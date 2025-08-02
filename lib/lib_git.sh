#
# lib_git.sh: Git operations
#

#
# Safely updates a Git repository and its submodules after checking if the current branch is 'master'.
#
# @param $1 git_repo        The path to the local git repository.
#
git_update_repo() {
    local git_repo="$1"
    if [[ -z "$git_repo" ]]; then
        log_error "No git repository path provided."
        log_info "Usage: update_repo /path/to/repo"
        return 1
    fi

    if [[ ! -d "$git_repo" ]]; then
        log_error "Git repo not found at '$git_repo'"
        return 1
    fi

    git_log=$(mktemp -p /tmp)
    if ! pushd "$git_repo" > /dev/null; then
        # If cd fails, we can't proceed.
        return 1
    fi

    # Check if it's a valid git repo
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        log_error "'$git_repo' is not a Git repository."
        popd > /dev/null
        return 1
    fi

    # Make sure the current branch is master
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "master" ]]; then
        log_debug "Current branch of '$git_repo' is '${current_branch}', not 'master'. Skipping update."
        popd > /dev/null
        return 1
    fi

    # sometimes git pull throws warnings and we need a second git pull to address it
    { git pull || git pull; } >"$git_log" 2>&1
    if (($? != 0)); then
        log_error "git pull failed on repo '$git_repo'"
        [[ -s "$git_log" ]] && log_info_file "$git_log"
        popd > /dev/null
        return 1
    fi

    # it is safe to run submodule commands even if the repo has no submodules
    { git submodule init && git submodule sync && git submodule update; } >/dev/null
    if (($? != 0)); then
        log_error "git submodule update failed on repo '$git_repo'"
        [[ -s "$git_log" ]] && log_info_file "$git_log"
        popd > /dev/null
        return 1
    fi

    log_debug "Git repo '$git_repo' updated to latest master"
    popd > /dev/null
    return 0
}

#
# Gets the currently checked-out branch of a Git repository without using a subshell.
#
# This function safely checks a directory, determines if it's a Git repository,
# and returns the current branch name via a name reference (nameref).
#
# @param $1 target_dir     The path to the directory to check.
# @param $2 result_var_name The name of the variable in the calling scope
#                          that will receive the output.
#
# Returns:
#   - The branch name (e.g., "master", "feature/login") is stored in the result variable.
#   - "detached head" if the repository is in a detached HEAD state.
#   - An empty string "" if the directory doesn't exist or is not a Git repo.
#   - The function itself returns an exit code of 0 on success, 1 on invalid usage.
#
git_get_current_branch() {
    local target_dir="$1"
    # Create a name reference to the variable name passed as the second argument.
    local -n result_var="$2"
    result_var=""

    # --- Argument Validation ---
    if [[ -z "$target_dir" || -z "$2" ]]; then
        log_error "Usage: get_git_branch <directory> <result_variable_name>"
        return 1
    fi

    if [[ ! -d "$target_dir" ]]; then
        return 1
    fi

    # --- Core Logic without Subshell ---
    # Use pushd to change directory and add the current dir to a stack.
    # Redirect output to /dev/null to keep it clean.
    if ! pushd "$target_dir" > /dev/null; then
        # If cd fails, we can't proceed.
        return 1
    fi

    # Check if we are inside a Git repository.
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        # Not a Git repo, result is already an empty string.
        popd > /dev/null
        return 0
    fi

    # Use 'git symbolic-ref' to get the branch name.
    # It's the most reliable way to distinguish a branch from a detached HEAD.
    # -q (--quiet) suppresses errors and returns a non-zero exit code on failure.
    local branch_name
    if branch_name=$(git symbolic-ref --short -q HEAD); then
        # Success: We are on a named branch.
        result_var="$branch_name"
    else
        # Failure: We are in a detached HEAD state.
        result_var="detached head"
    fi

    popd > /dev/null
    return 0
}
