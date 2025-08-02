#!/usr/bin/env bats

# --- SETUP ---

# First, source our new helper script. This will run the git clone commands
# to ensure the helper libraries are available in a temporary directory.
source "$BATS_TEST_DIRNAME/test_helper.sh"

# Now that the helper has run, we can load the libraries at the top level,
# as recommended by the BATS documentation.
load "${BATS_SUPPORT_DIR}/load.bash"
load "${BATS_ASSERT_DIR}/load.bash"
load "${BATS_FILE_DIR}/load.bash" # Load the file assertion library

# Silence BATS version warnings by declaring the minimum version we need.
bats_require_minimum_version 1.5.0


# The setup() function runs before each individual test.
setup() {
    # Get the absolute path to the library from the test script's location.
    local lib_path
    lib_path="$(cd "$BATS_TEST_DIRNAME/../" && pwd)/lib/lib_std.sh"

    # Create a wrapper script that sources our library.
    # It uses 'eval "$@"' and then explicitly exits with the last command's
    # status, ensuring BATS sees the correct result.
    cat > main.sh <<EOF
#!/usr/bin/env bash
source "$lib_path"
eval "\$@"
exit \$?
EOF
    chmod +x main.sh
}

# --- LOGGING TESTS ---

@test "Logging: log_info should produce output" {
    run ./main.sh 'log_info "test message"'
    assert_success
    assert_output --partial "INFO"
    assert_output --partial "test message"
}

@test "Logging: DEBUG messages should be hidden by default" {
    run ./main.sh 'log_debug "you should not see this"'
    assert_success
    refute_output --partial "DEBUG"
}

@test "Logging: set_log_level DEBUG should show DEBUG messages" {
    run ./main.sh 'set_log_level DEBUG; log_debug "you should see this"'
    assert_success
    assert_output --partial "DEBUG"
}

@test "Logging: set_log_level WARN should hide INFO messages" {
    # Create a separate script to avoid the command-line log interference.
    local test_script="${BATS_TMPDIR}/log_test.sh"
    local lib_path
    lib_path="$(cd "$BATS_TEST_DIRNAME/../" && pwd)/lib/lib_std.sh"

    # To prevent the initial "Command line" log, we can pass a dummy argument
    # that the library's argument parser will consume.
    cat > "$test_script" <<EOF
#!/usr/bin/env bash
source "$lib_path" --no-init-log
set_log_level WARN
log_info "this message should be hidden"
EOF
    chmod +x "$test_script"

    run "$test_script"
    assert_success
    refute_output --partial "this message should be hidden"
}

@test "Logging: print_tty should produce no output in a non-interactive script" {
    run ./main.sh 'print_tty "should not see this"'
    assert_success
    refute_output "should not see this"
}


# --- ERROR HANDLING TESTS ---

@test "Error Handling: exit_if_error should exit on non-zero code" {
    run -1 ./main.sh 'exit_if_error 1 "this fails"'
    assert_failure
    assert_output --partial "FATAL"
    assert_output --partial "at exit_if_error"
}

@test "Error Handling: exit_if_error should not exit on zero code" {
    run ./main.sh 'exit_if_error 0 "this succeeds"'
    assert_success
}

@test "Error Handling: fatal_error should exit immediately" {
    run -1 ./main.sh 'false || fatal_error "forced failure"'
    assert_failure
    assert_output --partial "forced failure"
}


# --- COMMAND EXECUTION (run) TESTS ---

@test "run: should execute a successful command" {
    run ./main.sh 'run true'
    assert_success
}

@test "run: should exit on a failed command by default" {
    run -1 ./main.sh 'run false'
    assert_failure
    assert_output --partial "Command failed with exit code 1"
}

@test "run: --no-exit should prevent exit on failure" {
    run -1 ./main.sh 'run --no-exit false'
    assert_failure
    assert_output --partial "Command failed with exit code 1 (continuing)"
}

@test "run: DRY_RUN mode should print the command instead of executing" {
    local test_file="${BATS_TMPDIR}/dry_run_test.txt"
    run ./main.sh "DRY_RUN=true; run touch '$test_file'"
    assert_success
    assert_output --partial "[DRY-RUN] Would run: touch"
    if [ -f "$test_file" ]; then
        echo "File '$test_file' should not exist but it does." >&2
        return 1
    fi
}


# --- FILE & DIRECTORY HANDLING ---

@test "File Handling: safe_mkdir should create a directory" {
    local test_dir="${BATS_TMPDIR}/new_dir"
    rm -rf "$test_dir"
    run ./main.sh "safe_mkdir '$test_dir'"
    assert_success
    assert_dir_exists "$test_dir"
}

@test "File Handling: safe_mkdir -p should create nested directories" {
    local test_dir="${BATS_TMPDIR}/nested/new_dir"
    rm -rf "${BATS_TMPDIR}/nested"
    run ./main.sh "safe_mkdir -p '$test_dir'"
    assert_success
    assert_dir_exists "$test_dir"
}

@test "File Handling: safe_mkdir should fail if a directory cannot be created" {
    local read_only_dir="${BATS_TMPDIR}/read_only"
    rm -rf "$read_only_dir"
    mkdir "$read_only_dir"
    chmod 444 "$read_only_dir"
    run -1 ./main.sh "safe_mkdir '${read_only_dir}/cannot_create'"
    assert_failure
    assert_output --partial "Failed to create directories"
    chmod 755 "$read_only_dir" # cleanup
}

@test "File Handling: safe_touch should create a file" {
    local test_file="${BATS_TMPDIR}/new_file.txt"
    rm -f "$test_file"
    run ./main.sh "safe_touch '$test_file'"
    assert_success
    assert_file_exists "$test_file"
}

@test "File Handling: safe_truncate should empty a file" {
    local test_file="${BATS_TMPDIR}/file_to_empty.txt"
    echo "some content" > "$test_file"
    run ./main.sh "safe_truncate '$test_file'"
    assert_success
    assert_file_empty "$test_file"
}


# --- ASSERTION TESTS ---

@test "Assertions: assert_not_null should pass for set variables" {
    run ./main.sh 'MY_VAR="value"; assert_not_null MY_VAR'
    assert_success
}

@test "Assertions: assert_not_null should fail for empty variables" {
    run -1 ./main.sh 'MY_VAR=""; assert_not_null MY_VAR'
    assert_failure
    assert_output --partial "required variables are not set or are empty: MY_VAR"
}

@test "Assertions: assert_command_exists should fail for non-existent commands" {
    run -1 ./main.sh 'assert_command_exists this_cmd_does_not_exist_123'
    assert_failure
    assert_output --partial "required commands were not found"
}

@test "Assertions: assert_file_exists should pass for files and fail for directories" {
    mkdir -p "${BATS_TMPDIR}/test_dir"
    touch "${BATS_TMPDIR}/test_dir/file.txt"
    run ./main.sh "assert_file_exists '${BATS_TMPDIR}/test_dir/file.txt'"
    assert_success
    run -1 ./main.sh "assert_file_exists '${BATS_TMPDIR}/test_dir'"
    assert_failure
    rm -rf "${BATS_TMPDIR}/test_dir"
}

@test "Assertions: assert_dir_exists should pass for directories" {
    local test_dir="${BATS_TMPDIR}/another_dir"
    mkdir -p "$test_dir"
    run ./main.sh "assert_dir_exists '$test_dir'"
    assert_success
}

@test "Assertions: assert_integer should pass for valid integers" {
    run ./main.sh 'MY_INT=123; NEG_INT=-45; assert_integer MY_INT NEG_INT'
    assert_success
}

@test "Assertions: assert_integer should fail for non-integers" {
    run -1 ./main.sh 'NOT_AN_INT="abc"; assert_integer NOT_AN_INT'
    assert_failure
    assert_output --partial "is not a valid integer"
}

@test "Assertions: assert_integer_range should pass for value in range" {
    run ./main.sh 'VAL=50; assert_integer_range VAL 10 100'
    assert_success
}

@test "Assertions: assert_integer_range should fail for value out of range" {
    run -1 ./main.sh 'VAL=5; assert_integer_range VAL 10 100'
    assert_failure
    assert_output --partial "is not in range"
}

@test "Assertions: assert_arg_count should pass for exact match" {
    run ./main.sh 'assert_arg_count 2 2'
    assert_success
}

@test "Assertions: assert_arg_count should fail for exact mismatch" {
    run -1 ./main.sh 'assert_arg_count 3 2'
    assert_failure
    assert_output --partial "Argument count mismatch: expected 2 but got 3 arguments"
}

@test "Assertions: assert_arg_count should pass for value in range" {
    run ./main.sh 'assert_arg_count 2 1 3'
    assert_success
}

@test "Assertions: assert_arg_count should fail for value outside range" {
    run -1 ./main.sh 'assert_arg_count 4 1 3'
    assert_failure
    assert_output --partial "Argument count mismatch: expected between 1 and 3 arguments, but got 4"
}


# --- LIBRARY & PATH TESTS ---

@test "Library: import should source a library file" {
    echo 'my_imported_func() { echo "imported successfully"; }' > "${BATS_TMPDIR}/dummy_lib.sh"
    run ./main.sh 'import "'"${BATS_TMPDIR}/dummy_lib.sh"'"; my_imported_func'
    assert_success
    assert_output --partial "imported successfully"
}

@test "Library: import should fail for a non-existent library" {
    run -1 ./main.sh 'import "non_existent_lib.sh"'
    assert_failure
    assert_output --partial "Library 'non_existent_lib.sh' does not exist"
}

@test "PATH: print_path should print PATH entries on new lines" {
    run ./main.sh "PATH='/usr/bin:/bin'; print_path"
    assert_success
    assert_output --partial $'/usr/bin\n/bin'
}

@test "PATH: add_to_path should add a directory" {
    local test_dir="${BATS_TMPDIR}/path_test"
    mkdir -p "$test_dir"
    run ./main.sh "PATH='/usr/bin'; add_to_path '$test_dir'; echo \"\$PATH\""
    assert_success
    assert_output --partial "/usr/bin:$test_dir"
    rm -rf "$test_dir"
}

@test "PATH: dedupe_path should remove duplicates" {
    run ./main.sh "PATH='/bin:/usr/bin:/bin'; dedupe_path; echo \"\$PATH\""
    assert_success
    assert_output --partial "/bin:/usr/bin"
}


# --- MISC FUNCTION TESTS ---

@test "Misc: is_interactive should return false in a non-interactive script" {
    # Pipe stdin to ensure it's not a TTY, forcing a non-interactive state.
    run -1 bash -c "echo '' | ./main.sh is_interactive"
    assert_failure # It returns 1 (false) in non-interactive shells
}

@test "Misc: get_my_source_dir should return the calling script's directory" {
    # This test is rewritten to be more robust and avoid eval/BASH_SOURCE issues.
    # Create a test script in a subdirectory to make the test robust
    mkdir -p "${BATS_TMPDIR}/subdir"
    local test_script="${BATS_TMPDIR}/subdir/test_script.sh"
    local lib_path
    lib_path="$(cd "$BATS_TEST_DIRNAME/../" && pwd)/lib/lib_std.sh"

    cat > "$test_script" <<EOF
#!/usr/bin/env bash
# Source the library with a dummy arg to prevent the command-line log
source "$lib_path" --no-init-log
get_my_source_dir MY_OWN_DIR
echo "\$MY_OWN_DIR"
EOF
    chmod +x "$test_script"

    run "$test_script"
    assert_success
    # Compare against the physical path to handle symlinks on macOS
    local expected_dir
    expected_dir="$(cd "${BATS_TMPDIR}/subdir" && pwd -P)"
    assert_output --partial "$expected_dir"
}

@test "Misc: base_cd should change to a directory" {
    local new_dir="${BATS_TMPDIR}/cd_test"
    mkdir -p "$new_dir"
    run ./main.sh "base_cd '$new_dir'; pwd"
    assert_success
    assert_output --partial "$new_dir"
}

@test "Misc: base_cd should fail for a non-existent directory" {
    run -1 ./main.sh "base_cd '/non/existent/dir'"
    assert_failure
    assert_output --partial "Can't cd to"
}

@test "Misc: base_cd_nonfatal should change directory and return 0" {
    local new_dir="${BATS_TMPDIR}/cd_test_nonfatal"
    mkdir -p "$new_dir"
    run ./main.sh "base_cd_nonfatal '$new_dir' && pwd"
    assert_success
    assert_output --partial "$new_dir"
}

@test "Misc: base_cd_nonfatal should not exit and return 1 on failure" {
    run ./main.sh "base_cd_nonfatal '/non/existent/dir' || echo 'Failed as expected'"
    assert_success
    assert_output --partial "Failed as expected"
}

@test "Misc: ask_yes_no should return success for 'y'" {
    # Test non-interactively by piping 'y' into the function
    run bash -c "echo 'y' | ./main.sh 'ask_yes_no \"Continue?\"'"
    assert_success
}

@test "Misc: ask_yes_no should return failure for 'n'" {
    # Test non-interactively by piping 'n' into the function
    run -1 bash -c "echo 'n' | ./main.sh 'ask_yes_no \"Continue?\"'"
    assert_failure
}
