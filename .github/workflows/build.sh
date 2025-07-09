#!/bin/bash
set -e -o pipefail

SCRIPT_DIR="$(dirname "$0")"
GITHUB_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$GITHUB_DIR")"
if [[ ! -d "${REPO_DIR}/.git/" ]]; then
    echo "Error: REPO_DIR does not appear to be the base git repo directory." >&2
    exit 1
fi

BUILD_CONFIG_JSON="${REPO_DIR}/build_config.json"
BUILD_OUTPUT_DIR="${REPO_DIR}/build"
mkdir -p "$BUILD_OUTPUT_DIR"

ADD_ARCHIVE_FILE_SCRIPT="${GITHUB_DIR}/actions/add_archive_file/add_archive_file.sh"
GET_UBUNTU_IMAGES_SCRIPT="${GITHUB_DIR}/actions/get_ubuntu_images/get_ubuntu_images.sh"
if [[ ! -f "$ADD_ARCHIVE_FILE_SCRIPT" ]] || [[ ! -f "$GET_UBUNTU_IMAGES_SCRIPT" ]]; then
    echo "Error: A dependency was not found at its expected path." >&2
    echo "Expected paths:" >&2
    echo "ADD_ARCHIVE_FILE_SCRIPT: $ADD_ARCHIVE_FILE_SCRIPT" >&2
    echo "GET_UBUNTU_IMAGES_SCRIPT: $GET_UBUNTU_IMAGES_SCRIPT" >&2
    exit 1
fi

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

# Get the files to copy into each image.
#
# stdout:   A JSON object.
#
# shellcheck disable=SC2120 # param_count is 0
get_files_to_copy_json() {
    param_count 0 $#

    local json
    json="$(cat "${BUILD_CONFIG_JSON}" | jq '.copy_runtime_files')"
    # The value of `json` here is similar to the following:
    # {
    #     "/cloud-init/99a_uncc_itsc_3146.cfg": "/etc/cloud/cloud.cfg.d/99a_uncc_itsc_3146.cfg",
    #     "/cloud-init/vendor-data": "/etc/CCI/vendor-data"
    # }

    # add `REPO_DIR` before every key string
    json="$( \
                echo "$json" |
                jq  --arg repo_dir "$REPO_DIR" \
                    'with_entries({key:($repo_dir + .key),value:.value})' \
            )"
    # The value of `json` here is similar to the following:
    # {
    #     "$REPO_DIR/cloud-init/99a_uncc_itsc_3146.cfg": "/etc/cloud/cloud.cfg.d/99a_uncc_itsc_3146.cfg",
    #     "$REPO_DIR/cloud-init/vendor-data": "/etc/CCI/vendor-data"
    # }
    
    # remove any starting '/' before every value string
    json="$( \
                echo "$json" |
                jq  'map_values(select(startswith("/")) = .[1:])' \
            )"
    # The value of `json` here is similar to the following:
    # {
    #     "$REPO_DIR/cloud-init/99a_uncc_itsc_3146.cfg": "etc/cloud/cloud.cfg.d/99a_uncc_itsc_3146.cfg",
    #     "$REPO_DIR/cloud-init/vendor-data": "etc/CCI/vendor-data"
    # }

    # output
    echo "$json"
}

# Local build script.
# Should have identical results as build.yml,
# but may not work with certain features (e.g. upload a new release).
#
# stdout:   Debug logs.
#
# shellcheck disable=SC2120 # param_count is 0
main() {
    param_count 0 $#

    # Get the base images
    local output
    output="( $($GET_UBUNTU_IMAGES_SCRIPT main) )"
    declare -A base_images="$output"
    # `base_images` is an array with contents like:
    # "amd64": "/path/to/file"
    # "arm64": "/path/to/file"
    # Inject files into archive
    for key in "${!base_images[@]}"; do
        local image_name; image_name="$key"
        local base_image_path; base_image_path="${base_images["$key"]}"

        # Create a value for `final_image_path`
        local _filename _suffix final_image_path
        _filename="$(basename "$base_image_path")"
        _suffix="${_filename#*.}" # remove up to, and including, the first '.'
        final_image_path="${BUILD_OUTPUT_DIR}/${image_name}.${_suffix}"

        # Get the filenames to copy
        local files_json
        files_json="$(get_files_to_copy_json)"

        # Call helper script
        echo "$files_json" |
            "$ADD_ARCHIVE_FILE_SCRIPT" main "$base_image_path" "$final_image_path"
    done

    echo "Created images: " "${!base_images[@]}" # prints keys e.g. arm64
    echo "In directory: $BUILD_OUTPUT_DIR"
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