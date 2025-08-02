#!/usr/bin/env bats

# --- SETUP ---

# Source our generic helper to download BATS dependencies.
source "$BATS_TEST_DIRNAME/test_helper.sh"

# Load the required helper libraries.
load "${BATS_SUPPORT_DIR}/load.bash"
load "${BATS_ASSERT_DIR}/load.bash"
load "${BATS_FILE_DIR}/load.bash"

# Silence BATS version warnings.
bats_require_minimum_version 1.5.0


# The setup() function runs before each individual test.
setup() {
    # Get the absolute paths to the libraries.
    local std_lib_path
    std_lib_path="$(cd "$BATS_TEST_DIRNAME/../" && pwd)/lib/lib_std.sh"
    local file_lib_path
    file_lib_path="$(cd "$BATS_TEST_DIRNAME/../" && pwd)/lib/lib_file.sh"

    # Create a wrapper script that sources both required libraries.
    cat > main.sh <<EOF
#!/usr/bin/env bash
source "$std_lib_path"
source "$file_lib_path"
eval "\$@"
exit \$?
EOF
    chmod +x main.sh
}

# --- update_file_section TESTS ---

@test "update_file_section: should add a new section to a file" {
    local test_file="${BATS_TMPDIR}/test.conf"
    echo "initial content" > "$test_file"

    run ./main.sh 'update_file_section "'"$test_file"'" "# START" "# END" "new line 1" "new line 2"'
    assert_success

    assert_file_contains "$test_file" "# START"
    assert_file_contains "$test_file" "new line 1"
    assert_file_contains "$test_file" "new line 2"
    assert_file_contains "$test_file" "# END"
}

@test "update_file_section: should update an existing section" {
    local test_file="${BATS_TMPDIR}/test.conf"
    cat > "$test_file" <<EOF
initial content
# START
old line 1
# END
final content
EOF

    run ./main.sh 'update_file_section "'"$test_file"'" "# START" "# END" "updated line"'
    assert_success

    # FIX: Use standard shell commands for refuting.
    # The test fails if grep finds the string.
    if grep -q "old line 1" "$test_file"; then return 1; fi
    assert_file_contains "$test_file" "updated line"
}

@test "update_file_section: should remove an existing section with -r flag" {
    local test_file="${BATS_TMPDIR}/test.conf"
    cat > "$test_file" <<EOF
initial content
# START
content to be removed
# END
final content
EOF

    run ./main.sh 'update_file_section -r "'"$test_file"'" "# START" "# END"'
    assert_success

    # FIX: Use standard shell commands for refuting.
    if grep -q "# START" "$test_file"; then return 1; fi
    if grep -q "content to be removed" "$test_file"; then return 1; fi
    if grep -q "# END" "$test_file"; then return 1; fi
    assert_file_contains "$test_file" "initial content"
    assert_file_contains "$test_file" "final content"
}

@test "update_file_section: should handle empty content correctly (effectively removing content)" {
    local test_file="${BATS_TMPDIR}/test.conf"
    cat > "$test_file" <<EOF
# START
old line
# END
EOF

    run ./main.sh 'update_file_section "'"$test_file"'" "# START" "# END"'
    assert_success

    # FIX: Use standard shell commands for refuting.
    if grep -q "old line" "$test_file"; then return 1; fi
}

@test "update_file_section: should only update the first of multiple matching sections" {
    local test_file="${BATS_TMPDIR}/test.conf"
    cat > "$test_file" <<EOF
# START
section 1
# END
# START
section 2
# END
EOF

    run ./main.sh 'update_file_section "'"$test_file"'" "# START" "# END" "updated section"'
    assert_success

    assert_file_contains "$test_file" "updated section"
    assert_file_contains "$test_file" "section 2"
}

@test "update_file_section: should do nothing if removing a non-existent section" {
    local test_file="${BATS_TMPDIR}/test.conf"
    local original_content="initial content"
    echo "$original_content" > "$test_file"

    run ./main.sh 'update_file_section -r "'"$test_file"'" "# START" "# END"'
    assert_success
    
    # FIX: Use standard diff command to compare files.
    # It will exit with 0 if they are the same.
    diff "$test_file" <(echo "$original_content")
}

@test "update_file_section: should fail if not enough arguments are provided" {
    run -1 ./main.sh 'update_file_section "somefile.txt" "# START"'
    assert_failure
    assert_output --partial "Insufficient arguments"
}
