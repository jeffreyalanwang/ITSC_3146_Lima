#! /bin/bash
## Run as root. Observe cautions commented throughout script.
set -eux -o pipefail

# apt install libguestfs-tools qemu-utils systemd-container

REPO_DIR="$(dirname "$(realpath "$0")")"
cd "$REPO_DIR"

BUILD_DIR="$REPO_DIR/build"		 ; mkdir -p "$BUILD_DIR"
CACHE_DIR="$REPO_DIR/build/cache"; mkdir -p "$CACHE_DIR"
TMP_DIR="$REPO_DIR/build/tmp"	 ; mkdir -p "$TMP_DIR"

# Ensure a function is provided the correct number of arguments.
#
# $1:       Expected number of arguments.
# $2:       Actual number of arguments.
#
param_count() {
    local expected; expected=$1;
    local actual; actual=$2;

	set +u
    if [[ -z $1 ]] || [[ -z $2 ]] || [[ -n $3 ]]; then
        echo "Error: param_count requires exactly 2 arguments." >&2
        exit 1
    fi
	set -u

    if [[ "$expected" != "$actual" ]]; then
        echo "Error: This function requires exactly $expected arguments, got $actual." >&2
        exit 1
    fi

    return 0
}

# Download the base Ubuntu 24.02 QCOW2 image used by Lima.
#
# Caches download and does not reattempt if the file exists.
#
# stdout: Location of downloaded image.
#
download_image() {
	cd "$CACHE_DIR"

	local IMAGE_URL; local MD5SUMS;
	# Based on values in file: https://github.com/lima-vm/lima/blob/master/templates/_images/ubuntu-24.04.yaml
	if [[ "$(uname -m)" = "aarch64" ]]; then
		IMAGE_URL="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64.img"
	elif [[ "$(uname -m)" = "x86_64" ]]; then
		IMAGE_URL="https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
	else
		echo "Unrecognized CPU architecture $(uname -m)" >&2
		exit 1
	fi
	MD5SUMS="https://cloud-images.ubuntu.com/releases/noble/release/MD5SUMS"

	if [[ ! -f "$(basename $IMAGE_URL)" ]]; then
		wget "$IMAGE_URL"
	fi
	md5sum --status --check 								\
		<(curl "$MD5SUMS" | grep "$(basename "$IMAGE_URL")")

	echo "$CACHE_DIR/$(basename "$IMAGE_URL")"
	cd "$REPO_DIR"
}

# Create a larger copy of a QCOW2 image.
#
# Note: this operation will reorder partitions.
# (Here, we move the rootfs from sda1 to sda3 or sda4
# --there are 4 total partitions on the Intel image, 
# but 3 for ARM.)
#
# $1: Path of original image.
# $2: Path to place enlarged copy.
#
expand_image() {
	param_count 2 $#
	local src; src="$1"
	local dest; dest="$2"

	qemu-img create -f qcow2 -o preallocation=metadata		\
		"$dest" 6G
	virt-resize --expand /dev/sda1 							\
		"$src" "$dest"
}

# Mount a QCOW2 image.
#
# Caution: /dev/nbd0 must not yet be taken.
#
# $1: Path to image.
# $2: Path to desired mount point (directory or nonexistent).
#
mount_image() {
	param_count 2 $#
	local img; img="$1"
	local mnt; mnt="$2"

	modprobe nbd max_part=16
	qemu-nbd --connect=/dev/nbd0 "$img"
	sleep 3 							# qemu-nbd has some delay: https://gitlab.com/qemu-project/qemu/-/work_items/1413

	mkdir -p "$mnt"
	mount --label "cloudimg-rootfs" /dev/nbd0p4 "$mnt"
}

# Perform modifications on image as a live system.
#
# Technically uses systemd-nspawn, which is our best
# option if we want to init Docker inside the guest.
#
# Returns after cleaning up its environment modifications.
#
# $1: Root directory of unpacked system.
# $2: Host path to a shell script to run in guest system.
#
chroot_ops() {
	param_count 2 $#
	local fs_root; fs_root="$1"
	local script; script="$2"

	# Prepare to chroot into image
	systemctl start systemd-networkd		# works with guest systemd-networkd to set up NAT for guest internet
	systemd-nspawn --machine build -D "$fs_root" --boot --console=read-only --network-veth &
	sleep 15

	# Perform modifications requiring chroot (see chroot_operations.sh for implicated features)
	systemd-run --machine build --pipe /bin/bash < "$script"

	# Clean up: Done with chroot
	machinectl stop build
	wait									# End bg bash job `systemd-nspawn` above; by now, we have already stopped the machine
}

# Copy the basic files into the image 
# (i.e. modifications which do not require chroot).
#
# Sources files from $REPO_DIR.
#
# $1: Root directory of unpacked system.
#
file_ops() {
	param_count 1 $#
	local fs_root; fs_root="$1"

	## Copy system config files

	# Samba config to access guest fs from host
	mkdir -p "$fs_root/etc/samba/smb.conf.d/"
	cp "$REPO_DIR/guest/smb.conf" "$fs_root/etc/samba/smb.conf.d/96_share_to_host.conf"
	# chown not needed: already root
	chmod 644 "$fs_root/etc/samba/smb.conf.d/96_share_to_host.conf"

	# Enable overlay2 in Docker
	mkdir -p "$fs_root/etc/docker/"
	cp "$REPO_DIR/guest/docker_daemon.conf" "$fs_root/etc/docker/daemon.json"
	# chown not needed: already root
	chmod 644 "$fs_root/etc/docker/daemon.json"

	## Copy user directory files

	# Clipboard interop
	cp "$REPO_DIR/guest/Xdefaults" "$fs_root/home/itsc/.Xdefaults"
	chown 1000:1000 "$fs_root/home/itsc/.Xdefaults"
	ln -s "$fs_root/home/itsc/.Xdefaults" "$fs_root/root/.Xdefaults"

	# Modify .profile (see /guest/profile in repo for implicated features)
	echo >> "$fs_root/home/itsc/.profile"						# Add a newline
	tail -n +3 "$REPO_DIR/guest/profile" |						# Remove first 2 lines (shellcheck directive)
		cat - >> "$fs_root/home/itsc/.profile"				# Append retains correct ownership

	# Ensure users have something to see when they test VS Code functionality
	echo "EXAMPLE BASH HISTORY" >> "$fs_root/home/itsc/.bash_history"
	chown 1000:1000 "$fs_root/home/itsc/.bash_history"

	# Include IMUNES templates in home directory
	git clone https://github.com/imunes/imunes-examples.git "$fs_root/home/itsc/imunes-examples"
	# chown not needed: `sudo` needed for IMUNES anyway
	git -C "$fs_root/home/itsc/imunes-examples" checkout 8715a48a6ebc2257704e244e6b408f85352765d5
}

# Unmount the QCOW2 image
# (allowing interaction with its file,
# rather than through its mounted FS).
#
# Assumes `mount_image` used device path /dev/nbd0.
#
# $1: Mount point directory.
#
unmount_image() {
	param_count 1 $#
	local mnt; mnt="$1"

	umount "$mnt"
	rmdir "$mnt"
	qemu-nbd --disconnect /dev/nbd0
}

# gzip our result, move + rename it.
#
# $1:	  Path to existing image
# $2:	  Path to final image location
# stdout: Message notifying user of parameter $2 value.
#
package_image() {
	param_count 2 $#
	local src; src="$1"
	local dest; dest="$2"

	gzip --stdout --best "$src" > "$dest"
	echo "Built image at: $dest"
}

# Clean up after ourselves.
#
delete_tmp() {	
	rm -r "$TMP_DIR"
}

main() {
	base_image="$(download_image)"
	echo "Base image at $base_image"

	tmp_image="$TMP_DIR/$(basename "$base_image")"
	expand_image  "$base_image" "$tmp_image"
	echo "Working-copy image at $tmp_image"

	image_mnt="$TMP_DIR/mnt"
	echo 		  "Mounting image to $image_mnt"
	mount_image   "$tmp_image" "$image_mnt"

	chroot_ops    "$image_mnt" "$REPO_DIR/guest/chroot_operations.sh"
	file_ops      "$image_mnt"  # See function def for target files
	
	unmount_image "$image_mnt"

	package_image "$tmp_image" "$(uname -m).img.gz" 		# Ubuntu: either x86_64 or aarch64 (filename passed on and used by limayaml)
	delete_tmp	   # Removes anything still in $TMP_DIR
}

# Call a function within this script:
#
# $ ./build.sh function_name arg_1 arg_2 ...
# > [...]
#
if [[ $# == 0 ]]; then # script was not called asking for any specific function
    main
else
    fn_args=( "${@:2}" )
    $1 "${fn_args[@]}"
fi