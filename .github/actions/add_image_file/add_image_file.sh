#!/usr/bin/env bash
# ^ Equivalent to /bin/bash or whatever `PATH` would choose,
#   for Mac systems which require Homebrew-installed bash (see below regarding readarray).
set -e -o pipefail

# Ensure our bash supports readarray.
{ echo "" | readarray ; } || {
    echo "Error: this version of bash does not support readarray." >&2
    echo "This may be because the default version of bash provided on Mac systems is outdated." >&2
    echo "Try: brew install bash" >&2
    exit 1
}

# At the moment, this script actually shouldn't be run on Mac (despite the above check for readarray),
# because Macs have no support for mounting ext4
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Error: this script is not supported on Mac systems." >&2
    echo "If you are using a Mac, please use a Linux VM or Docker container instead." >&2
    exit 1
fi

temp_dir="/tmp"
if [[ -n "$RUNNER_TEMP" ]]; then
    temp_dir=$RUNNER_TEMP # use GitHub Actions' temp dir if available
fi
temp_dir="${temp_dir}/add_archive_file"
mkdir -p "$temp_dir"

# Ensure a function is provided the correct number of arguments.
#
# $1:       Expected number of arguments.
# $2:       Actual number of arguments.
#
param_count() {
    local expected; expected=$1;
    local actual; actual=$2;

    if [[ -z $1 ]] || [[ -z $2 ]] || [[ -n $3 ]]; then
        echo "Error: param_count requires exactly 2 arguments." >&2
        exit 1
    fi

    if [[ "$expected" != "$actual" ]]; then
        echo "Error: This function requires exactly $expected arguments, got $actual." >&2
        exit 1
    fi

    return 0
}

# For use with unit tests.
echo_args() {
    echo "$2"
}

# Get a temporary directory, and mount an .img file there.
#
# $1:       Path to a image file.
#
# stdout:   Path to the root directory.
#
mount_to_temp() {
    param_count 1 $#
    local file_path; file_path="$1"

    local mount_path
    mount_path="${temp_dir}/$(basename "$file_path")"

    # Perform some checks
    if [[ ! -f "$file_path" ]]; then
        echo "Error: specified image path is not a file." >&2
        exit 1
    fi

    # Mount at the temp location
    mkdir -p "$mount_path"
    guestmount -a "$file_path" -i --rw "$mount_path"
    
    # Output
    echo "$mount_path"
}

# Copy a file into a mounted image.
#
# $1:       Path to the image mount directory.
# $2:       Path to the file to copy.
# $3:       The path of the file, within the filesystem.
#           Includes file's name.
#           Does not need to begin with a /.
#
# stdout:   Debug logs.
#
add_file() {
    param_count 3 $#
    local mount_root; mount_root="$1"
    local file_path; file_path="$2"
    local file_dest_path; file_dest_path="$3"

    # Checks
    if [[ ! -d "$mount_root" ]]; then
        echo "Error: directory does not exist at path: $mount_root" >&2
        exit 1
    fi
    if [[ ! -d "${mount_root}/usr" ]]; then
        echo "Warning: mount point does not appear to be a Linux filesystem root" >&2
    fi

    # Remove any trailing slash '/'
    mount_root="${mount_root%/}"
    # Remove any preceding slash '/'
    file_dest_path="${file_dest_path#/}"

    echo "Adding to filesystem root mounted at dir: ${mount_root}"
    echo "File source: ${file_path}"
    echo "File destination: /${file_dest_path}"
    echo "File contents (5 lines): "
    head -n 5 "${file_path}" | sed -e 's/^/| /'

    # Determine destination + ensure parent dir
    local host_fs_file_dest_path
    host_fs_file_dest_path="${mount_root}/${file_dest_path}"
    mkdir -p "$(dirname "$host_fs_file_dest_path")"

    if [[ -f "$host_fs_file_dest_path" ]]; then
        echo "Replacing preexisting file at this path"
    fi
    cp "$file_path" "$host_fs_file_dest_path"
    # these permissions are also set in the WSL image's build script
    chmod 0755 "$host_fs_file_dest_path"
    chown root:root "$host_fs_file_dest_path"

    echo "Done"
}

# Unmount an image.
#
# $1:       Path to the image mount directory.
#
# stdout:   Debug logs.
#
unmount() {
    param_count 1 $#
    local mount_path; mount_path="$1"

    # Rezip
    guestunmount "$mount_path"
}

# Add files to an .img image's filesystem (as a copy, not in-place).
# 
# stdin:    JSON object.
#           Keys are filepaths on the current machine.
#           Values are filepaths when inside the image.
#
# $1:       Path to the image to add files to.
# $2:       New path for the modified image.
#
# stdout:   Debug logs.
#
main() {
    param_count 2 $#
    local files_json; files_json="$cmdline_stdin"
    local image_path; image_path="$1"
    local dest_path; dest_path="$2"

    # Copy to a new path
    if [[ -e "$dest_path" ]]; then
        echo "Warning: file already exists at this path, replacing it." >&2
    fi
    mkdir -p "$(dirname "$dest_path")"
    cp "$image_path" "$dest_path"

    # Mount archive
    local mount_path
    echo "Mounting image for modification..."
    mount_path="$( mount_to_temp "$dest_path" )"

    # Add the files
    local -a keys vals; local count
    readarray -t keys < <(echo "$files_json" | jq --raw-output 'keys_unsorted[]')
    readarray -t vals < <(echo "$files_json" | jq --raw-output '.[]')
    count="${#keys[@]}"
    for (( i=0 ; i < count ; i++ )); do
        local file; file="${keys[$i]}"
        local path_in_archive; path_in_archive="${vals[$i]}"
        add_file "$mount_path" "$file" "$path_in_archive"
    done

    # Unmount archive
    echo "Unmounting image..."
    unmount "$mount_path"
}

# TODO check for guestmount

# Call a function within this script:
#
# $ ./add_archive_file.sh function_name arg_1 arg_2 ...
# > [...]
#
if [[ ! -t 0 ]]; then
    cmdline_stdin="$(cat -)"
fi
fn_args=( "${@:2}" )
$1 "${fn_args[@]}"