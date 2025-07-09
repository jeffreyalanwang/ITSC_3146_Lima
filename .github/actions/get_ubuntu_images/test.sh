#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
export SCRIPT="${SCRIPT_DIR}/get_ubuntu_images.sh"

temp_dir="/tmp"
if [[ -n "$RUNNER_TEMP" ]]; then
    temp_dir=$RUNNER_TEMP # use GitHub Actions' temp dir if available
fi
temp_dir="${temp_dir}/test_get_ubuntu_images"
mkdir -p "$temp_dir"

rm -f -r "/tmp/fake_github_actions_tmp"
mkdir -p "/tmp/fake_github_actions_tmp"

test_param_count() {
    assertTrue "$SCRIPT param_count 1 1"
    assertTrue "$SCRIPT param_count 0 0"
    assertFalse "$SCRIPT param_count 1 0"
    assertFalse "$SCRIPT param_count 0 1"
    assertFalse "$SCRIPT param_count 2 3"
    assertFalse "$SCRIPT param_count 3 1"

    echo "" # Formatting between sections
}

test_get_wsl_image_links() {

    # Setup:
    # create a script in a separate shell,
    # in which we source the script so that we can
    # access global script vars

    local subshell_script
    subshell_script="${temp_dir}/tmp_script.sh"

    # Create new file
    echo '#!/bin/bash' > "$subshell_script"
    chmod +x "$subshell_script"
    
    # Do not source the following line (these options break shunit2):
    # set -e -o pipefail
    local _arg1 _arg2
    _arg1='"s/^set .*//"'
    # shellcheck disable=SC2016 # variable expansion can happen in subshell
    _arg2='"$SCRIPT"'
    # shellcheck disable=SC2129 # individual lines are clearer
    echo "source <(sed $_arg1 $_arg2)" >> "$subshell_script"

    # Test code
    echo 'test_above_in_subshell() {' >> "$subshell_script"
    cat <<- 'EOF' >> "$subshell_script"

        # Setup: make sure the variables start as unset

        assertSame 'false' "$populated_links"
        assertNull "$amd64url"
        assertNull "$amd64sha256"
        assertNull "$arm64url"
        assertNull "$arm64sha256"

        # Execute

        get_wsl_image_links

        # Assert outputs

        assertTrue "[[ $populated_links == 'true' ]]"
        assertContains "$amd64url" "https://"
        assertContains "$arm64url" "https://"
        assertEquals 64 "$(echo -n "$amd64sha256" | wc -m)"
        assertEquals 64 "$(echo -n "$arm64sha256" | wc -m)"

	EOF
    echo '}' >> "$subshell_script"

    # Run shunit2 in the subshell
    echo '. shunit2' >> "$subshell_script"

    # Tell the outer shell's instance of shunit2 if we failed
    "$subshell_script"
    assertTrue "See above message from subshell" $?
    
    # Clean up
    rm "$subshell_script"

    echo "" # Formatting between sections
}

test_check_file_sum() {
    # Setup:
    # create a script in a separate shell,
    # in which we source the script so that we can
    # access global script vars

    local subshell_script
    subshell_script="${temp_dir}/tmp_script.sh"

    # Create new file
    echo '#!/bin/bash' > "$subshell_script"
    chmod +x "$subshell_script"
    
    # Do not source the following line (these options break shunit2):
    # set -e -o pipefail
    local _arg1 _arg2
    _arg1='"s/^set .*//"'
    # shellcheck disable=SC2016 # variable expansion can happen in subshell
    _arg2='"$SCRIPT"'
    # shellcheck disable=SC2129 # individual lines are clearer
    echo "source <(sed $_arg1 $_arg2)" >> "$subshell_script"

    # Test code
    echo 'test_above_in_subshell() {' >> "$subshell_script"
    cat <<- 'EOF' >> "$subshell_script"
        
        # Setup
        local filepath expected_sha256sum
        filepath="/bin/dash"
        expected_sha256sum="$(sha256sum "$filepath" | awk '{print $1}')"

        # Execute

        # Check behavior
        assertTrue 'check_file_sum "$filepath" "$expected_sha256sum"'
        assertFalse 'check_file_sum "$filepath" "${expected_sha256sum:1}"' # cut off first char
        assertFalse 'check_file_sum "/bin/bash" "$expected_sha256sum"' # different existing file
        
        # Check that it doesn't matter where pwd is
        local original_pwd
        original_pwd="$(pwd)"
        cd "$(dirname "$filepath")" || exit 1
        assertTrue 'check_file_sum "$(basename "$filepath")" "$expected_sha256sum"'
        cd "$original_pwd"
        
        # Check edge cases
        assertFalse '[[ -e /non_existent_file ]]'
        assertFalse 'check_file_sum "/non_existent_file" "$expected_sha256sum"'
        assertFalse 'check_file_sum "$expected_sha256sum" "$filepath"'
        assertFalse 'check_file_sum "$filepath"'
        assertFalse 'check_file_sum "$expected_sha256sum"'

	EOF
    echo '}' >> "$subshell_script"

    # Run shunit2 in the subshell
    echo '. shunit2' >> "$subshell_script"

    # Tell the outer shell's instance of shunit2 if we failed
    "$subshell_script"
    assertTrue "See above message from subshell" $?
    
    # Clean up
    rm "$subshell_script"

    echo "" # Formatting between sections
}

test_download_or_keep() {
    
    # Setup

    # ensure files we use do not exist yet
    rm -f "/tmp/myfile"
    rm -f "/tmp/myfile.1"
    rm -f "/tmp/myfile.1.1"

    # get an example online file
    local url
    url="cheat.sh/ls"
    # get the sha256 for our file
    local expected_sha256sum
    expected_sha256sum="$(curl "$url" | sha256sum - | awk '{print $1}')"

    # Execute
    local requested_path actual_path
    requested_path="/tmp/myfile"

    echo "= Case 1: Download a file to a test dir"
    # setup: none
    # execute
    actual_path="$("$SCRIPT" download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the path we asked for
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path" | awk '{print $1}')"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    echo "= Case 2: Download the file again (same file contents)"
    # setup: none
    # execute
    actual_path="$("$SCRIPT" download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the same path
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path" | awk '{print $1}')"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    echo "= Case 3: Download the file to a destination which has a different file value"
    # setup
    rm -r "${requested_path}"
    touch "${requested_path}"
    echo "contents" > "${requested_path}.1"
    # execute
    actual_path="$("$SCRIPT" download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the expected path
    assertEquals "${requested_path}.1.1" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path" | awk '{print $1}')"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    echo "" # Formatting between sections
}

test_download_wsl_images() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r /tmp/get_ubuntu_images/
    rm -f -r /tmp/fake_github_actions_tmp/get_ubuntu_images/

    # Execute

    echo "= Case 1: make sure GitHub Actions temp variable not set"
    # setup
    export RUNNER_TEMP=""
    # execute
    "$SCRIPT" download_wsl_images
    # assert it worked
    assertTrue $?
    # assert we downloaded to the correct temp dir
    assertTrue "[[ -d /tmp/get_ubuntu_images ]]"
    assertEquals 2 "$(find /tmp/get_ubuntu_images -type f | wc -l)"

    echo "= Case 2: set GitHub Actions temp variable"
    # setup
    export RUNNER_TEMP="/tmp/fake_github_actions_tmp"
    # execute
    "$SCRIPT" download_wsl_images
    # assert it worked
    assertTrue $?
    # assert we downloaded to the correct temp dir
    assertTrue "[[ -d /tmp/fake_github_actions_tmp/get_ubuntu_images ]]"
    assertEquals 2 "$(find /tmp/fake_github_actions_tmp/get_ubuntu_images -type f | wc -l)"
    
    # Clean up
    export RUNNER_TEMP=""

    echo "" # Formatting between sections
}

test_check_images() {
    # Setup:
    # create a script in a separate shell,
    # in which we source the script so that we can
    # access global script vars

    local subshell_script
    subshell_script="${temp_dir}/tmp_script.sh"

    # Create new file
    echo '#!/bin/bash' > "$subshell_script"
    chmod +x "$subshell_script"
    
    # Do not source the following line (these options break shunit2):
    # set -e -o pipefail
    local _arg1 _arg2
    _arg1='"s/^set .*//"'
    # shellcheck disable=SC2016 # variable expansion can happen in subshell
    _arg2='"$SCRIPT"'
    # shellcheck disable=SC2129 # individual lines are clearer
    echo "source <(sed $_arg1 $_arg2)" >> "$subshell_script"

    # Test code
    echo 'test_above_in_subshell() {' >> "$subshell_script"
    cat <<- 'EOF' >> "$subshell_script"
        
        # Setup
        amd64img="/bin/dash"
        arm64img="/bin/bash"

        # Execute

        echo "= Case 1: populated_links == ''"
        # setup
        populated_links=''
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute (in subshell because function should exit)
        (
            check_images
        )
        # assert that we failed
        assertFalse $?

        echo "= Case 2: populated_links == 'false'"
        populated_links='false'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute (in subshell because function should exit)
        (
            check_images
        )
        # assert that we failed
        assertFalse $?

        echo "= Case 3: wrong hash for amd64img"
        populated_links='true'
        populated_files='true'
        amd64sha256="some extra text, plus $(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute (in subshell because function should exit)
        (
            check_images
        )
        # assert that we failed
        assertFalse $?

        echo "= Case 4: wrong hash for arm64img"
        populated_links='true'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}') plus some extra text"
        # execute (in subshell because function should exit)
        (
            check_images
        )
        # assert that we failed
        assertFalse $?

        echo "= Case 5: Success state"
        populated_links='true'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute (in subshell, just in case)
        (
            check_images
        )
        # assert no error
        assertTrue $?

	EOF
    echo '}' >> "$subshell_script"

    # Run shunit2 in the subshell
    echo '. shunit2' >> "$subshell_script"

    # Execute
    "$subshell_script"
    # Tell the outer shell's instance of shunit2 if we failed
    assertTrue "See above message from subshell" $?
    
    # Clean up
    rm "$subshell_script"

    echo "" # Formatting between sections
}

test_main() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r "/tmp/get_ubuntu_images/"

    # Execute
    local output

    echo "= Case 1"
    # setup: none
    # execute
    output="( $("$SCRIPT" main) )"
    declare -A paths="$output"
    # assert array contains 2 keys
    assertEquals 2 "${#paths[@]}"
    # assert we downloaded WSL images
    assertContains "${paths[amd64]}" ".wsl"
    assertContains "${paths[arm64]}" ".wsl"
    # assert the right keys match the right files
    assertContains "${paths[amd64]}" "amd64"
    assertContains "${paths[arm64]}" "arm64"
    # assert we downloaded Ubuntu images
    assertNotNull "$(tar -tzf "${paths[amd64]}" | grep "^etc/cloud/cloud.cfg.d/")"
    assertNotNull "$(tar -tzf "${paths[arm64]}" | grep "^etc/cloud/cloud.cfg.d/")"

    echo "" # Formatting between sections
}

test_cmdline() {
    # test that we can quote files with spaces in them
    # setup
    local arg1 arg2
    arg1="/tmp/directory with space/archive without extension"
    arg2="/tmp/directory with space/new archive"
    # execute
    output="$("$SCRIPT" echo_args "$arg1" "$arg2")"
    # assert
    assertSame "$arg2" "$output"

    echo "" # Formatting between sections
}

# Load shellcheck.
if ! { which shellcheck; }; then
    echo "shellcheck not installed. Try a command like the following:" >&2
    echo "sudo apt install shellcheck" >&2
    exit 1
fi
shellcheck "$0"
echo "" # Formatting between sections
shellcheck "$SCRIPT"
echo "" # Formatting between sections

# Load shUnit2.
if ! { which shunit2; }; then
    echo "shunit2 not installed. Try a command like the following:" >&2
    echo "sudo apt install shunit2" >&2
    exit 1
fi
# shellcheck disable=SC1091 # shunit2 may not be available on this system, dont't lint against
. shunit2