#!/bin/bash
set -e -o pipefail

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

# Get a temporary directory, and unzip a gzipped file there.
#
# $1:       Path to a gzipped file.
#           Does not require a .gz suffix.
#
# stdout:   Path to the unzipped file.
#
unzip_to_temp() {
    param_count 1 $#
    local file_path; file_path="$1"

    local decompressed_path
    decompressed_path="${temp_dir}/$(basename "$file_path")"

    # Perform some checks
    if [[ "$file_path" == "$decompressed_path" ]]; then
        echo "Error: we are decompressing to the same path as we are reading from." >&2
        exit 1
    elif [[ -e "$decompressed_path" ]]; then
        echo "Warning: file already exists at this path, replacing it." >&2
    fi

    # Unzip to the temp location
    cat "$file_path" | gzip -d > "$decompressed_path"
    
    # Debug output: show size and location
    echo "$decompressed_path"
}

# Add a file to a tar archive.
#
# $1:       Path to the archive.
#           Must be an unzipped .tar archive.
#           Does not require .tar suffix.
# $2:       Path to the file to add.
# $3:       The path of the file, within the archive.
#           Includes file's name.
#           Should not include special character '|'.
#           Generally should not begin with '/', though tar autoremoves them.
#
# stdout:   Debug logs.
#
add_file_to_archive() {
    param_count 3 $#
    local archive_path; archive_path="$1"
    local file_path; file_path="$2"
    local file_dest_path; file_dest_path="$3"

    # Checks
    # shellcheck disable=SC2076 # We are actually trying to match literal pipe char
    if [[ "$file_dest_path" =~ '|' ]]; then
        echo "Error: destination file path cannot contain special character '|'." >&2
        exit 1
    fi
    if [[ ${file_dest_path:0:1} == '/' ]]; then
        echo "Warning: destination file path begins in '/'. " \
             "Files in tar archives are generally not absolute paths." >&2
    fi

    local sed_expression
    sed_expression="s|.*|${file_dest_path}|"
    sed_expression="${sed_expression}x" # for tar --transform,
                                        # x flag indicates we are using
                                        # extended regex (sed -E)

    echo "Adding to tar archive ${archive_path}"
    echo "File source: ${file_path}"
    echo "File destination: $(echo "$file_path" | sed -E "${sed_expression%x}")"
    echo "File contents (5 lines): "
    head -n 5 "${file_path}" | sed -e 's/^/| /'

    if ( tar -tf "${archive_path}" | grep "$file_dest_path" > /dev/null ); then # grep -q would break pipe & then tar would fail
        echo "Removing preexisting file at this path"
        tar --delete -vf "$archive_path" "$file_dest_path"
    fi

    # Note: tar --append does not remove an existing file with the same name.
    tar --owner=root --group=root --mode=0755 \
        -vf "$archive_path" \
        --append "$file_path" \
        --transform="$sed_expression" --show-transformed-names
    echo "Done"
}

# Rezip a file with gzip to a destination path.
#
# $1:       Path to an unzipped file.
# $2:       Path to rezip file to.
#           Does not require a .gz suffix.
#
# stdout:   Debug logs.
#
rezip_to_path() {
    param_count 2 $#
    local from_path; from_path="$1"
    local dest_path; dest_path="$2"

    # Perform some checks
    if [[ "$from_path" == "$dest_path" ]]; then
        echo "Error: we are compressing to the same path as we are reading from." >&2
        exit 1
    elif [[ -e "$dest_path" ]]; then
        echo "Warning: file already exists at rezipped archive's path, replacing it." >&2
    fi

    # Rezip
    cat "$from_path" | gzip --best > "$dest_path"
}

# Add files to a gzipped tar archive.
# 
# stdin:    JSON object.
#           Keys are filepaths on the current machine.
#           Values are filepaths when inside the archive.
#
# $1:       Path to the archive to add files to.
# $2:       Where to create the new archive, including filename.
#           Must be different from `archive_path`.
#           The file created here will be gzipped.
#
# stdout:   Debug logs.
#
main() {
    param_count 2 $#
    local files_json; files_json="$cmdline_stdin"
    local archive_path; archive_path="$1"
    local modified_archive_path; modified_archive_path="$2"

    # Unzip archive
    local unzipped_path
    echo "Unzipping default Ubuntu image..."
    unzipped_path="$( unzip_to_temp "$archive_path" )"

    # Add the files
    local -a keys vals; local count
    readarray -t keys < <(echo "$files_json" | jq --raw-output 'keys_unsorted[]')
    readarray -t vals < <(echo "$files_json" | jq --raw-output '.[]')
    count="${#keys[@]}"
    for (( i=0 ; i < count ; i++ )); do
        local file; file="${keys[$i]}"
        local path_in_archive; path_in_archive="${vals[$i]}"
        add_file_to_archive "$unzipped_path" "$file" "$path_in_archive"
    done

    # Rezip archive
    echo "Rezipping image..."
    rezip_to_path "$unzipped_path" "$modified_archive_path"
}

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