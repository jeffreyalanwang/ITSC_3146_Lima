#!/bin/bash
set -e -o pipefail

temp_dir="/tmp"
if [[ -n "$RUNNER_TEMP" ]]; then
    temp_dir=$RUNNER_TEMP # use GitHub Actions' temp dir if available
fi
temp_dir="${temp_dir}/get_ubuntu_images"
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

    if [[ $expected -ne $actual ]]; then
        echo "Error: This function requires exactly $expected arguments, got $actual." >&2
        exit 1
    fi

    return 0
}

# For use with unit tests.
echo_args() {
    echo "$2"
}

# Get the most up-to-date Ubuntu WSL image file links + checksums.
#
# Output stored in shell variables:
# populated_links:  Whether the output variables can be used yet.
# amd64url:         str
# amd64sha256:      str
# arm64url:         str
# arm64sha256:      str
#
populated_links=false
# shellcheck disable=SC2120 # param_count is 0
get_lima_image_links() {
    param_count 0 $#

    # Ubuntu LTS (latest) Lima image links:
    # https://github.com/lima-vm/lima/blob/master/templates/_images/ubuntu-lts.yaml
    # (access using raw link: https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/_images/ubuntu-lts.yaml)

    # Ubuntu 24.04 Lima image links:
    # https://github.com/lima-vm/lima/blob/master/templates/_images/ubuntu-24.04.yaml
    # (raw: https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/_images/ubuntu-24.04.yaml)

    local all_ubuntu_image_options
    all_ubuntu_image_options="$(curl 'https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/_images/ubuntu-24.04.yaml' | yq '.images')"
    # # value of `all_ubuntu_image_options`, without some list items
    # - location: "https://cloud-images.ubuntu.com/releases/noble/release-20250516/ubuntu-24.04-server-cloudimg-amd64.img"
    #   arch: "x86_64"
    #   digest: "sha256:8d6161defd323d24d66f85dda40e64e2b9021aefa4ca879dcbc4ec775ad1bbc5"
    # - location: "https://cloud-images.ubuntu.com/releases/noble/release-20250516/ubuntu-24.04-server-cloudimg-arm64.img"
    #   arch: "aarch64"
    #   digest: "sha256:c933c6932615d26c15f6e408e4b4f8c43cb3e1f73b0a98c2efa916cc9ab9549c"
    # [...]
    # - location: https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img
    #   arch: x86_64
    # - location: https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64.img
    #   arch: aarch64

    local ubuntu_images_with_sha
    ubuntu_images_with_sha="$( echo "$all_ubuntu_image_options" | yq 'filter(has("digest"))' )"
    # This ends up using the daily stable builds, because only those seem to have a digest.
    # We could use the non-daily builds but it doesn't seem to matter anyways (only difference is probably up-to-date packages).
    #
    # # value of `ubuntu_images_with_sha`, without some list items
    # - location: "https://cloud-images.ubuntu.com/releases/noble/release-20250516/ubuntu-24.04-server-cloudimg-amd64.img"
    #   arch: "x86_64"
    #   digest: "sha256:8d6161defd323d24d66f85dda40e64e2b9021aefa4ca879dcbc4ec775ad1bbc5"
    # - location: "https://cloud-images.ubuntu.com/releases/noble/release-20250516/ubuntu-24.04-server-cloudimg-arm64.img"
    #   arch: "aarch64"
    #   digest: "sha256:c933c6932615d26c15f6e408e4b4f8c43cb3e1f73b0a98c2efa916cc9ab9549c"
    # [...]

    amd64url="$(echo "$ubuntu_images_with_sha" | yq 'filter(.arch == "x86_64") | .[0].location')"
    amd64sha256="$(echo "$ubuntu_images_with_sha" | yq 'filter(.arch == "x86_64") | .[0].digest')"
    arm64url="$(echo "$ubuntu_images_with_sha" | yq 'filter(.arch == "aarch64") | .[0].location')"
    arm64sha256="$(echo "$ubuntu_images_with_sha" | yq 'filter(.arch == "aarch64") | .[0].digest')"

    # Post-process digest strings: remove "sha256:" prefix
    amd64sha256="${amd64sha256#'sha256:'}"
    arm64sha256="${arm64sha256#'sha256:'}"

    populated_links=true
}

# Check a file against a SHA256 sum.
#
# $1: The file to check.
# $2: The expected checksum.
#
# returns:  0 (true) if file matches
#           1 (false) if not
#
check_file_sum() {
    param_count 2 $#
    local img; img="$1"
    local expected_sum; expected_sum="$2"

    local img_sum
    img_sum="$(sha256sum "$img" | awk '{print $1}')"

    if [[ "$img_sum" == "$expected_sum" ]]; then
        return 0
    else
        return 1
    fi
}

# Download a file to a path where a file may already be present.
# If a file is present, it will be used, if it matches the desired checksum.
#
# $1:       The URL to download.
# $2:       The filepath to try to save to.
#           May be modified if a file is already present there.
# $3:       The expected SHA256 checksum.
#
# stdout:   The filepath to which the file was ultimately downloaded to.
#
download_or_keep() {
    param_count 3 $#
    local url; url="$1"
    local path; path="$2"
    local sha256sum; sha256sum="$3"

    local needs_download
    needs_download=false
    local loop_end # stop once we have a path where it's cached,
                   # or we have created an unused path to download anew
    while [[ "$loop_end" != 'true' ]]; do

        if [[ ! -e "$path" ]]; then # file doesn't exist yet

            needs_download=true
            loop_end=true

        elif { check_file_sum "$path" "$sha256sum"; }; then # file has the desired hash
            
            needs_download=false
            loop_end=true

        else # this file's hash does not match
        
            # create a new path, check that one
            path="${path}.1"
            loop_end=false

        fi

    done

    if [[ "$needs_download" == 'true' ]]; then
        if [[ -e "$path" ]]; then
            echo "Error: unreachable situation occurred." >&2
            exit 1
        fi
        curl "$url" > "$path"
    fi

    # output
    echo "$path"
}

# Download the Ubuntu images to a temporary directory.
# `get_lima_image_links` will be automatically called if needed.
#
# # Output stored in shell variables:
# populated_files:  Whether the output variables can be used yet.
# amd64img:         Path to the amd64 WSL image.
# arm64img:         Path to the arm64 WSL image.
#
# shellcheck disable=SC2120 # param_count is 0
download_lima_images() {
    param_count 0 $#
    if [[ "$populated_links" != 'true' ]]; then
        get_lima_image_links
    fi

    # These may not end up being the ultimate paths we use.
    local amd64img_path arm64img_path
    amd64img_path="${temp_dir}/amd64_base_img_${amd64sha256:0:5}.img"
    arm64img_path="${temp_dir}/arm64_base_img_${arm64sha256:0:5}.img"

    # Download
    amd64img_path="$(download_or_keep "$amd64url" "$amd64img_path" "$amd64sha256")"
    arm64img_path="$(download_or_keep "$arm64url" "$arm64img_path" "$arm64sha256")"

    # Output
    amd64img="$amd64img_path"
    arm64img="$arm64img_path"
    populated_files=true
}

# Check downloaded Ubuntu images against their provided SHA256 sums.
#
# Requires (from `get_lima_image_links` and `download_lima_images`):
#    `[[ "$populated_links" = 'true' ]]` \
# && `[[ "$populated_files" = 'true' ]]`
#
# No output, but exits script with failure code (`exit 1`) on failure.
#
# shellcheck disable=SC2120 # param_count is 0
check_images() {
    param_count 0 $#
    
    if [[ ! ("$populated_links" == 'true' && "$populated_files" == 'true') ]]; then
        echo "Required values not present (did you run get_lima_image_links and download_lima_images?)." >&2
        echo "populated_links: $populated_links" >&2
        echo "populated_files: $populated_files" >&2
        exit 1
    fi

    # Check amd64 image
    if ! { check_file_sum "$amd64img" "$amd64sha256"; }; then
        echo "amd64 image did not match expected checksum." >&2
        echo "File: $amd64img" >&2
        echo "Expected: $amd64sha256" >&2
        exit 1
    fi

    # Check arm64 image
    if ! { check_file_sum "$arm64img" "$arm64sha256"; }; then
        echo "amd64 image did not match expected checksum." >&2
        echo "File: $arm64img" >&2
        echo "Expected: $arm64sha256" >&2
        exit 1
    fi
}

# Download the most up-to-date Ubuntu WSL image files.
# 
# stdout:       Each line provides the path to one of the downloaded images.
#               Read into an array with:
#                   declare -A var_name="( $(main) )"
#               Format:
#                   [amd64]="/path/to/file"
#                   [arm64]="/path/to/file"
#
# shellcheck disable=SC2120 # param_count is 0
main() {
    param_count 0 $#

    get_lima_image_links
    download_lima_images
    check_images

    echo -n '[amd64]='
    echo -n '"'
    echo -n "$amd64img"
    echo '"'

    echo -n '[arm64]='
    echo -n '"'
    echo -n "$arm64img"
    echo '"'
}

# Call a function within this script:
#
# $ ./add_archive_file.sh function_name arg_1 arg_2 ...
# > [...]
#
fn_args=( "${@:2}" )
$1 "${fn_args[@]}"