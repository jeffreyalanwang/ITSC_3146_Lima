#! /bin/bash
## Assumes root privilege. Run by build.sh inside chroot environment.
set -eux -o pipefail

## Set up user
useradd --create-home --uid 1000 itsc
test "1000" -eq "$(id -g itsc)"

## Install packages

debconf-set-selections <<-EOF
	docker.io docker.io/restart boolean true
	wireshark-common wireshark-common/install-setuid boolean true
EOF
apt update && apt install -y \
	g++ git make tcl tcllib jq tk imagemagick xterm \
	wireshark socat docker.io samba

# Allow non-root Docker access, just in case
usermod itsc -aG docker

# Configure samba
echo 'include = /etc/samba/smb.conf.d/96_share_to_host.conf' >> /etc/samba/smb.conf
# Provide blank samba password
{ echo                      # New password:
  echo                      # Confirm new password:
} | smbpasswd -a -s itsc    # -s allows smbpasswd to read prompts from stdin

# Install IMUNES
git clone https://github.com/jeffreyalanwang/imunes.git /tmp/imunes_temp/
cd /tmp/imunes_temp
make install
cd /
rm -rf /tmp/imunes_temp
imunes -p                   # note: supposedly, this requires
                            # restart after installing docker.io