#!/usr/bin/env bash

# This script is meant to be sourced by BATS test files.
# It ensures that BATS helper libraries are available for the test run
# by cloning them into a temporary directory if they don't already exist.
# This avoids polluting your project's source tree.

# Define a consistent directory for our test dependencies within BATS's temp space.
export BATS_LIBS_DIR="${BATS_TMPDIR}/libs"
mkdir -p "$BATS_LIBS_DIR"

# Define paths for helper libraries. These will be used by the main test script.
export BATS_SUPPORT_DIR="${BATS_LIBS_DIR}/bats-support"
export BATS_ASSERT_DIR="${BATS_LIBS_DIR}/bats-assert"
export BATS_FILE_DIR="${BATS_LIBS_DIR}/bats-file" # Re-added this line

# --- On-Demand Cloning ---
# Check if the libraries exist and clone them if they don't.
# The --depth 1 flag makes the clone much faster.
if [[ ! -d "$BATS_SUPPORT_DIR" ]]; then
    git clone --depth 1 https://github.com/bats-core/bats-support.git "$BATS_SUPPORT_DIR"
fi
if [[ ! -d "$BATS_ASSERT_DIR" ]]; then
    git clone --depth 1 https://github.com/bats-core/bats-assert.git "$BATS_ASSERT_DIR"
fi
# Add the clone command for bats-file
if [[ ! -d "$BATS_FILE_DIR" ]]; then
    git clone --depth 1 https://github.com/bats-core/bats-file.git "$BATS_FILE_DIR"
fi
