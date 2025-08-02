###
### lib_std.sh - Foundation library for Bash scripts
###              Requires Bash version 4.0 or higher.
###
### This library provides a standardized set of functions for common tasks,
### ensuring consistency and robustness across multiple scripts.
###
### Areas covered:
###     - PATH manipulation
###     - Logging (with levels and colors)
###     - Error handling and stack tracing
###     - Bash version checking
###     - Library importing
###     - Miscellaneous helpers
###

################################################# INITIALIZATION #######################################################

#
# Make sure we do nothing in case the library is sourced more than once in the same shell.
# This prevents functions from being redefined and initialization from running multiple times.
#
[[ -n "${__stdlib_sourced__-}" ]] && return
__stdlib_sourced__=1

#
# Memorize the original script arguments at the very beginning.
# This allows the library to parse global options before the main script does.
#
readonly __script_args__=("$@")
__new_args__=()
readonly __SCRIPT_DIR__=$(cd -- "$(dirname -- "${BASH_SOURCE[1]}" )" &>/dev/null && pwd -P)

############################################ BASH VERSION CHECKER #######################################################

#
# is_interactive - Checks if the current shell is interactive.
#
# An interactive shell is one where the user is typing commands directly.
# This is used to determine if we can safely prompt the user for input.
#
# Returns:
#   0 (true) if the shell is interactive.
#   1 (false) if the shell is not interactive (e.g., running in a cron job).
#
is_interactive() {
    [[ -t 0 ]]
}

#
# check_bash_version_and_upgrade - Verifies the Bash version and prompts for an upgrade if necessary.
#
# This function checks if the running Bash interpreter is version 4.0 or higher.
# If the version is too old and the shell is interactive, it will offer to
# install/upgrade Bash via Homebrew. If the shell is not interactive, or if the OSTYPE is not darwin,
# it will exit with an error.
#
# Note: This function is called before logging is initialized, so it uses `echo` to stderr.
#
check_bash_version_and_upgrade() {
    local -r major_version=${BASH_VERSINFO[0]}
    if ((major_version < 4)); then
        if ! is_interactive; then
            {
                echo "Error: This script requires Bash 4.0 or higher."
                echo "Your version ($BASH_VERSION) is not compatible."
                echo "Upgrade Bash manually or run the script in interactive mode for guided upgrade."
            } >&2
            exit 1
        fi

        # -- Interactive Upgrade Process --
        echo "Warning: This script requires Bash version 4.0 or higher to run correctly." >&2
        echo "Your current version is $BASH_VERSION." >&2

        local install_cmd
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &>/dev/null; then
                install_cmd="sudo apt-get update && sudo apt-get install bash"
            elif command -v yum &>/dev/null; then
                install_cmd="sudo yum install bash"
            fi

            echo "On your system, you can likely upgrade by running:" >&2
            echo "  $install_cmd" >&2
            exit 1
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            read -p "Would you like to attempt an upgrade using Homebrew? (y/n) " -n 1 -r
            echo >&2
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if ! command -v brew &>/dev/null; then
                    echo "Homebrew is not installed." >&2
                    read -p "May I install Homebrew for you? (y/n) " -n 1 -r
                    echo >&2
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo "Installing Homebrew..." >&2
                        if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                            echo "Error: Homebrew installation failed. Please install it manually and try again." >&2
                            exit 1
                        fi
                        echo "Homebrew installed successfully." >&2
                    else
                        echo "Aborting. Homebrew is required to proceed." >&2
                        exit 1
                    fi
                fi

                echo "Updating Homebrew and installing Bash..." >&2
                brew update && brew install bash
                if [[ $? -ne 0 ]]; then
                    echo "Error: Failed to install Bash via Homebrew." >&2
                    exit 1
                fi

                echo "Bash installed successfully." >&2

                local new_bash_path
                new_bash_path="$(brew --prefix)/bin/bash"
                if [[ -f "$new_bash_path" ]]; then
                    echo "Relaunching script with the new Bash from: $new_bash_path ${__script_args__[@]}" >&2
                    exec "$new_bash_path" "$0" "${__script_args__[@]}"
                else
                    echo "Error: Could not find the new Bash executable at '$new_bash_path'." >&2
                    exit 1
                fi
            else
                echo "Aborting. Please upgrade Bash to version 4.0 or higher to run this script." >&2
                exit 1
            fi
        else
            echo "Unsupported OSTYPE: [$OSTYPE]"
            exit 1
        fi
    fi
}

###################################################### INIT ############################################################

#
# __stdlib_init__ - The main initialization function for this library.
#
# This is the only function that executes when the library is sourced.
# It sets up the environment by:
#   1. Checking the Bash version.
#   2. Initializing the logging system.
#   3. Parsing global command-line options like --debug, --verbose, --color.
#
__stdlib_init__() {
    check_bash_version_and_upgrade
    __log_init__

    # Processe global arguments and then remove them from the argument list that the main script will see.
    local arg
    __color__=0
    __strict_log_info__=0
    for arg in "${__script_args__[@]}"; do
        case "$arg" in
            --debug)
                set_log_level DEBUG
                ;;
            --verbose)
                set_log_level VERBOSE
                ;;
            --color)
                __color__=1
                ;;
            *)
                __new_args__+=("$arg")
                ;;
        esac
    done
    __init_colors__
    log_info_strict "Command line: $0 ${__script_args__[*]}"
    return 0
}

################################################# LIBRARY IMPORTER #####################################################

#
# import - Sources one or more other library files.
#
# This function provides a robust way to include other shell libraries. It handles
# both absolute and relative paths. Relative paths are resolved from the directory
# of the main script that sourced this library.
#
# Usage:
#   import /path/to/absolute/lib.sh
#   import relative/path/to/lib2.sh
#
# IMPORTANT NOTE: If your library has global variables declared with 'declare',
# you must add the -g flag (e.g., `declare -gA my_map`). Since the library is
# sourced inside this function, globals declared without -g would become local
# to the function and be unavailable to other functions.
#
import() {
    local lib
    local push=0
    for lib; do
        # Unless an absolute library path is given, make it relative to the script's location
        if [[ "$lib" != /* ]]; then
           [[ $__SCRIPT_DIR__ ]] || { printf '%s\n' "ERROR: __SCRIPT_DIR__ not set; import functionality needs it" >&2; exit 1; }
           pushd "$__SCRIPT_DIR__" >/dev/null
           push=1
        fi
        if [[ -f "$lib" ]]; then
            source "$lib"
            exit_if_error $? "Import of library '$lib' not successful."
            ((push)) && popd >/dev/null
        else
            exit_if_error 1 "Library '$lib' does not exist"
        fi
    done
    return 0
}

################################################# PATH MANIPULATION ####################################################

#
# add_to_path - Adds one or more directories to the system PATH.
#
# This function safely adds directories to the PATH, avoiding duplicates.
#
# Usage:
#   add_to_path [options] /path/to/dir1 /path/to/dir2 ...
#
# Options:
#   -p : Prepend the directory to the PATH instead of appending.
#   -n : Do not check if the directory exists before adding it.
#
add_to_path() {
    local dir re prepend=0 opt strict=1 in_path=0
    local -a path_dirs
    OPTIND=1
    while getopts sp opt; do
        case "$opt" in
            n)  strict=0  ;;  # don't care if directory exists or not before adding it to PATH
            p)  prepend=1 ;;  # prepend the directory to PATH instead of appending
            *)  log_error "add_to_path: invalid option '$opt'"
                return 1
                ;;
        esac
    done

    shift $((OPTIND-1))

    for dir; do
        ((strict)) && [[ ! -d $dir ]] && continue
        IFS=: read -ra path_dirs <<< "$PATH"
        for path_dir in "${path_dirs[@]}"; do
            if [[ "$path_dir" == "$dir" ]]; then
                in_path=1
                break
            fi
        done

        if ((! in_path)); then
            ((prepend)) && PATH="$dir:$PATH" || PATH="$PATH:$dir"
        fi
    done

    # It's good practice to de-duplicate the path after adding to it
    dedupe_path
    return 0
}

#
# dedupe_path - Removes duplicate entries from the PATH variable.
#
dedupe_path() {
    local -A seen
    local new_path dir
    IFS=:
    for dir in $PATH; do
        if [[ -n "$dir" && -z "${seen[$dir]}" ]]; then
            new_path="${new_path:+$new_path:}$dir"
            seen["$dir"]=1
        fi
    done
    PATH="$new_path"
}

#
# print_path - Prints each directory in the PATH on a new line.
#
print_path() {
    local -a dirs; local dir
    IFS=: read -ra dirs <<< "$PATH"
    for dir in "${dirs[@]}"; do printf '%s\n' "$dir"; done
}

#################################################### LOGGING ###########################################################

#
# __log_init__ - Initializes the logging system.
#
# Sets up colors for interactive terminals and defines the log level hierarchy.
# This is called automatically by __stdlib_init__.
#
__log_init__() {
    # Map log level strings (FATAL, ERROR, etc.) to numeric values.
    # Note the '-g' option passed to declare is essential for global scope.
    unset _log_levels _loggers_level_map
    declare -gA _log_levels _loggers_level_map
    _log_levels=([FATAL]=0 [ERROR]=1 [WARN]=2 [INFO]=3 [DEBUG]=4 [VERBOSE]=5)

    # Hash to map loggers to their log levels.
    # The default logger "default" has INFO as its default log level.
    _loggers_level_map["default"]=3
}

#
# __init_colors__ - Initialize colors used for logging
# This is called from __stdlib_init__
#
__init_colors__() {
    # If --color was not passed, or if the output is not a terminal, disable colors.
    if [[ -z "$__color__" || ! -t 1 ]]; then
        COLOR_BOLD=""
        COLOR_RED=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_BLUE=""
        COLOR_OFF=""
    else
        # colors for logging in interactive mode
        COLOR_BOLD="\033[1m"
        COLOR_RED="\033[0;31m"
        COLOR_GREEN="\033[0;32m"
        COLOR_YELLOW="\033[0;33m"
        COLOR_BLUE="\033[0;36m"
        COLOR_OFF="\033[0m"
    fi
    readonly COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_OFF
}

#
# set_log_level - Sets the logging verbosity for a given logger.
#
# Usage:
#   set_log_level [level]
#   set_log_level -l [logger_name] [level]
#
# Arguments:
#   level: One of FATAL, ERROR, WARN, INFO, DEBUG, VERBOSE. Default is INFO.
#   -l logger_name: (Optional) Specify a named logger. Default is 'default'.
#
set_log_level() {
    local logger=default in_level l
    [[ $1 = "-l" ]] && { logger=$2; shift 2 2>/dev/null; }
    in_level="${1:-INFO}"
    if [[ $logger ]]; then
        l="${_log_levels[$in_level]}"
        if [[ $l ]]; then
            _loggers_level_map[$logger]=$l
        else
            printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
                "${BASH_SOURCE[1]}:${BASH_LINENO[0]} Unknown log level '$in_level' for logger '$logger'; setting to INFO"
            _loggers_level_map[$logger]=3
        fi
    else
        printf '%(%Y-%m-%d:%H:%M:%S)T %-7s %s\n' -1 WARN \
            "${BASH_SOURCE[1]}:${BASH_LINENO[0]} Option '-l' needs an argument" >&2
    fi
}

#
# _print_log - Core and private log printing logic.
#
# This is the internal engine for the logging functions. It formats the log
# message with a timestamp, log level, and source location. It should not
# be called directly; use the `log_*` helper functions instead.
#
_print_log() {
    local in_level=$1; shift
    local logger=default log_level_set log_level color
    [[ $1 = "-l" ]] && { logger=$2; shift 2; }
    log_level="${_log_levels[$in_level]}"
    log_level_set="${_loggers_level_map[$logger]:-3}"

    if ((log_level_set >= log_level)); then
        # Select color based on log level
        case "$in_level" in
            FATAL|ERROR) color="$COLOR_RED";;
            WARN)        color="$COLOR_YELLOW";;
            INFO)        color="$COLOR_GREEN";;
            DEBUG)       color="$COLOR_BLUE";;
            *)           color="";; # No color for VERBOSE or others
        esac

        local source_path="${BASH_SOURCE[2]}"
        source_path="${source_path#"$__SCRIPT_DIR__"/}"
        source_path="${source_path#./}"
        
        printf "${color}%(%Y-%m-%d %H:%M:%S)T %-7s %s " -1 "$in_level" "${source_path}:${BASH_LINENO[1]}"
        printf '%s' "$@"
        printf "${COLOR_OFF}\n"
    fi
}

#
# _print_log_file - Core function for logging the contents of a file.
#
# Internal helper to be called by `log_info_file`, etc.
#
_print_log_file()   {
    local in_level=$1; shift
    local logger=default log_level_set log_level file
    [[ $1 = "-l" ]] && { logger=$2; shift 2; }
    file=$1
    log_level="${_log_levels[$in_level]}"
    log_level_set="${_loggers_level_map[$logger]}"
    if [[ $log_level_set ]]; then
        if ((log_level_set >= log_level)) && [[ -f $file ]]; then
            log_debug "Contents of file '$1':" 
            cat -- "$1"
        fi
    else
        printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 "WARN ${BASH_SOURCE[2]}:${BASH_LINENO[1]} Unknown logger '$logger'"
    fi
}

#
# Public logging functions.
# These are the primary functions scripts should use for logging.
#
log_fatal()   { _print_log FATAL   "$@"; }
log_error()   { _print_log ERROR   "$@"; }
log_warn()    { _print_log WARN    "$@"; }
log_info()    { _print_log INFO    "$@"; }
log_debug()   { _print_log DEBUG   "$@"; }
log_verbose() { _print_log VERBOSE "$@"; }

#
# log_info_strict is a special case for logging - we log the message as DEBUG or INFO based on
# user selection.
#
log_info_strict()     { ((__strict_log_info__)) && _print_log DEBUG "$@" || _print_log INFO "$@"; }
use_strict_log_info() { __strict_log_info__=1; }

#
# Public functions for logging the content of a file.
#
log_info_file()    { _print_log_file INFO    "$@"; }
log_debug_file()   { _print_log_file DEBUG   "$@"; }
log_verbose_file() { _print_log_file VERBOSE "$@"; }

#
# Public functions for logging function entry and exit points.
#
log_info_enter()    { _print_log INFO    "Entering function ${FUNCNAME[1]}"; }
log_debug_enter()   { _print_log DEBUG   "Entering function ${FUNCNAME[1]}"; }
log_verbose_enter() { _print_log VERBOSE "Entering function ${FUNCNAME[1]}"; }
log_info_leave()    { _print_log INFO    "Leaving function ${FUNCNAME[1]}";  }
log_debug_leave()   { _print_log DEBUG   "Leaving function ${FUNCNAME[1]}";  }
log_verbose_leave() { _print_log VERBOSE "Leaving function ${FUNCNAME[1]}";  }

#
# Simple print routines that do not prefix messages with timestamps or levels.
#
print_error()   { { printf "${COLOR_RED}ERROR: ";     printf '%s\n' "$@"; printf "$COLOR_OFF"; } >&2; }
print_warn()    { { printf "${COLOR_YELLOW}WARN: ";   printf '%s\n' "$@"; printf "$COLOR_OFF"; } >&2; }
print_info()    { { printf "$COLOR_GREEN";            printf '%s\n' "$@"; printf "$COLOR_OFF"; } >&2; }
print_success() { { printf "${COLOR_GREEN}SUCCESS: "; printf '%s\n' "$@"; printf "$COLOR_OFF"; } >&2; }
print_bold()    { printf '%b\n' "$COLOR_BOLD$@$COLOR_OFF"; }
print_message() { printf '%s\n' "$@"; }

#
# print_tty - Prints a message only if the output is going to a terminal.
#
print_tty() {
    if [[ -t 1 ]]; then
        printf '%s\n' "$@"
    fi
}

################################################## ERROR HANDLING ######################################################

#
# dump_trace - Prints a stack trace of the Bash function calls.
#
# This is useful for debugging to see the sequence of function calls
# that led to an error.
#
dump_trace() {
    local frame=0 line func source n=0
    while caller "$frame"; do
        ((frame++))
    done | while read line func source; do
        ((n++ == 0)) && {
            printf 'Encountered a fatal error\n'
        }
        printf '%4s at %s\n' " " "$func ($source:$line)"
    done
}

#
# exit_if_error - Exits the script if the provided exit code is non-zero.
#
# This is the primary error handling function. It checks a command's exit
# code and, if it indicates failure, logs a fatal message, dumps a stack
# trace, and exits the script.
#
# Usage:
#   command_that_might_fail
#   exit_if_error $? "A descriptive error message."
#
# Arguments:
#   $1: The exit code to check (typically $?).
#   $@: The error message to log if the exit code is non-zero.
#
exit_if_error() {
    (($#)) || return
    local num_re='^[0-9]+'
    local rc=$1; shift
    local message="${@:-No message specified}"
    if ! [[ $rc =~ $num_re ]]; then
        log_error "'$rc' is not a valid exit code; it needs to be a number greater than zero. Treating it as 1."
        rc=1
    fi
    ((rc)) && {
        log_fatal "$message"
        dump_trace "$@"
        exit $rc
    }
    return 0
}

#
# fatal_error - A convenience wrapper around exit_if_error.
#
# This function immediately triggers a fatal error, using the exit code
# of the last command if it was non-zero, or 1 otherwise.
#
# Usage:
#   [[ -f "$my_file" ]] || fatal_error "Required file '$my_file' not found."
#
fatal_error() {
    local ec=$?                # grab the current exit code
    ((ec == 0)) && ec=1        # if it is zero, set exit code to 1
    exit_if_error "$ec" "$@"
}

#################################################### COMMAND EXECUTION #################################################

#
# run - Safely executes a simple command with its arguments.
#
# This function is designed to be a secure and robust replacement for using
# `eval` or simple command execution. It correctly handles arguments with
# spaces and special characters.
#
# Features:
#   - Secure: Does not use `eval`, preventing arbitrary code execution.
#   - Argument Safe: Correctly handles spaces and special characters in arguments.
#   - Dry-Run Mode: If the global variable DRY_RUN (or dry_run) is true, it prints the
#     command instead of running it.
#   - Exit on Failure: By default, it will exit the script if the command
#     returns a non-zero exit code.
#   - Optional No-Exit: If the first argument is `--no-exit`, the function
#     will not exit on failure, allowing the calling script to handle the error.
#
# Usage:
#   run [options] command [arg1] [arg2] ...
#
# Options:
#   --no-exit   If provided as the very first argument, the script will not
#               exit if the command fails. The function will return the
#               command's original exit code.
#
# Examples:
#   # Run a simple command. Exits if `ls` fails.
#   run ls -l /tmp
#
#   # Run a command with spaces in an argument.
#   run touch "a file with spaces.txt"
#
#   # Run a command but don't exit the script on failure.
#   if ! run --no-exit grep "not_found" /etc/hosts; then
#       log "INFO" "The text was not found, but we are continuing."
#   fi
#
#   # In a script where DRY_RUN=true, this will only print the command.
#   DRY_RUN=true
#   run rm -rf /some/important/path
#
################################################################################
run() {
    local exit_on_failure=1

    # Check for the optional --no-exit flag.
    if [[ "$1" == "--no-exit" ]]; then
        exit_on_failure=0
        shift # Remove the --no-exit flag from the arguments list.
    fi

    # Check if the command is empty.
    if [[ $# -eq 0 ]]; then
        log_error "run: No command provided."
        return 1
    fi

    # --- Dry-Run Handling ---
    if [[ "$DRY_RUN" = true || "$dry_run" = true ]]; then
        # Use printf with the %q format specifier. This is the safest way to
        # print a command and its arguments in a way that is unambiguous and
        # could be copied and pasted back into a shell.
        local formatted_command
        printf -v formatted_command "%q " "$@"
        log_info "[DRY-RUN] Would run: ${formatted_command}"
        return 0
    fi

    # --- Execution ---
    # Execute the command. Using "$@" is the key. It expands each argument
    # as a separate, quoted string, preserving spaces and special characters.
    # This is the safe, modern alternative to using `eval`.
    "$@"
    local exit_code=$?
    if ((exit_code)); then
        if ((exit_on_failure)); then
            fatal_error "Command failed with exit code $exit_code. Exiting."
        else
            log_warn "Command failed with exit code $exit_code (continuing)."
            return $exit_code
        fi
    fi

    return 0
}

############################################## FILE AND DIRECTORY HANDLING ############################################

#
# safe_mkdir: Attempt to create directories and exit on failure.
#             Creates as many directories as possible.
#
# Usaage: safe_mkdir [-p] dir1 dir2 ...
#
safe_mkdir() {
    local p dir failed_dirs=()
    if [[ $1 = "-p" ]]; then
        shift
        p="-p"
    fi
    for dir; do
        [[ -d "$dir" ]] && continue
        mkdir $p -- "$dir"
        (($?)) && failed_dirs+=("$dir")
    done
    ((${#failed_dirs[@]} > 0)) && exit_if_error 1 "Failed to create directories: ${failed_dirs[*]}"
    return 0
}

#
# safe_touch - Creates or updates the timestamp of one or more files.
#
# This function iterates through all provided file paths. It attempts to
# 'touch' each file. If any operation fails (e.g., due to permissions),
# it collects the names of the failed files and reports them all in a
# single fatal error at the end.
#
# Usage:
#   safe_touch "/tmp/file1.log" "/var/run/app.pid"
#
# Arguments:
#   $@: One or more file paths to touch.
#
safe_touch() {
    local failed_files=()
    local file

    if (($# == 0)); then
        log_warn "safe_touch: No files provided to touch."
        return 0
    fi

    for file; do
        if ! touch "$file" 2>/dev/null; then
            failed_files+=("$file")
        fi
    done

    if ((${#failed_files[@]} > 0)); then
        fatal_error "Failed to touch the following files: ${failed_files[*]}"
    fi

    return 0
}

#
# safe_truncate - Truncates one or more files to zero bytes.
#
# This function iterates through all provided file paths. It attempts to
# truncate each file. If any operation fails (e.g., due to permissions),
# it collects the names of the failed files and reports them all in a
# single fatal error at the end.
#
# Usage:
#   safe_truncate "/var/log/app.log" "/tmp/data.tmp"
#
# Arguments:
#   $@: One or more file paths to truncate.
#
safe_truncate() {
    local failed_files=()
    local file

    if (($# == 0)); then
        log_warn "safe_truncate: No files provided to truncate."
        return 0
    fi

    for file; do
        # The > redirection is the simplest way to truncate a file.
        # We redirect stderr to /dev/null to suppress system error messages,
        # as we will provide our own comprehensive error message.
        if ! > "$file" 2>/dev/null; then
            failed_files+=("$file")
        fi
    done

    if ((${#failed_files[@]} > 0)); then
        fatal_error "Failed to truncate the following files: ${failed_files[*]}"
    fi

    return 0
}

####################################################### ASSERTIONS ####################################################

#
# assert_not_null - Checks that one or more variables are not empty.
#
# This function takes the *name* of one or more variables and checks that
# each one has a non-empty value. It is useful for validating required
# script inputs or configuration variables. Unlike other assertions, it
# checks all provided variables and reports all failures at once.
#
# Usage:
#   USER="admin"
#   TOKEN=""
#   assert_not_null USER       # This will succeed.
#   assert_not_null USER TOKEN # This will fail, listing TOKEN as empty.
#
# Arguments:
#   $@: One or more variable names to check.
#
assert_not_null() {
    local unset_vars=() var_name
    if (($# == 0)); then
        fatal_error "assert_not_null: No variable names provided for validation."
    fi

    for var_name in "$@"; do
        # Use indirection to get the value of the variable whose name is stored in var_name.
        # The -v check is for unset variables, -z is for empty strings.
        # We check for empty string as per the request.
        if [[ -z "${!var_name}" ]]; then
            unset_vars+=("$var_name")
        fi
    done

    if ((${#unset_vars[@]} > 0)); then
        fatal_error "These required variables are not set or are empty: ${unset_vars[*]}"
    fi

    return 0
}

#
# assert_integer - Checks if the values of one or more variables are valid integers.
#
assert_integer() {
    local var_name int_re='^[-+]?[0-9]+$'
    (($# == 0)) && fatal_error "assert_integer: No variable names provided."
    for var_name in "$@"; do
        local value="${!var_name}"
        ! [[ "$value" =~ $int_re ]] && fatal_error "Variable '$var_name' with value '$value' is not a valid integer."
    done
    return 0
}

#
# assert_integer_range - Checks if a variable's value is an integer within a specified range.
#
# Arguments:
#   $1: The NAME of the variable to check.
#   $2: The minimum value.
#   $3: The maximum value.
#
assert_integer_range() {
    local var_name="$1" min="$2" max="$3"
    (($# != 3)) && fatal_error "assert_integer_range: Expected 3 arguments, got $#."
    local value="${!var_name}"
    assert_integer "$var_name" min max
    ((value < min || value > max)) && fatal_error "Variable '$var_name' ($value) is not in range $min <= $max."
    return 0
}

#
# assert_arg_count - Checks that the number of arguments falls within a given range.
#
# Usage:
#   assert_arg_count $# 2      # Fails if arg count is not exactly 2
#   assert_arg_count $# 1 3    # Fails if arg count is not between 1 and 3 (inclusive)
#
# Arguments:
#   $1: The actual number of arguments (typically $#).
#   $2: The exact expected count, or the minimum count for a range.
#   $3: (Optional) The maximum count for a range.
#
assert_arg_count() {
    local arg_count="$1" count1="$2" count2="$3" argc=$#

    # Check the number of arguments passed to this function itself.
    if ((argc < 2 || argc > 3)); then
        fatal_error "assert_arg_count: Incorrect usage. Expected 2 or 3 arguments, but got $argc."
    fi

    # Create temporary named variables for assert_integer to check
    local __assert_arg_count_val="$arg_count" __assert_count1_val="$count1"
    assert_integer __assert_arg_count_val __assert_count1_val

    if [[ -n "$count2" ]]; then
        local __assert_count2_val="$count2"
        assert_integer __assert_count2_val
    fi

    if [[ -z "$count2" ]]; then
        # Exact match case
        if ((arg_count != count1)); then
            fatal_error "Argument count mismatch: expected $count1 but got $arg_count arguments"
        fi
    else
        # Range match case
        if ((arg_count < count1 || arg_count > count2)); then
            fatal_error "Argument count mismatch: expected between $count1 and $count2 arguments, but got $arg_count"
        fi
    fi
    return 0
}

#
# assert_command_exists - Checks that one or more commands are available in the system's PATH.
#
# This function iterates through all provided command names and uses 'command -v'
# to verify their existence. If any command is not found, it collects the names
# and reports them all in a single fatal error.
#
# Usage:
#   assert_command_exists git curl jq
#
# Arguments:
#   $@: One or more command names to check.
#
assert_command_exists() {
    local missing_commands=()
    local cmd

    if (($# == 0)); then
        log_warn "assert_command_exists: No commands provided to check."
        return 0
    fi

    for cmd; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if ((${#missing_commands[@]} > 0)); then
        fatal_error "These required commands were not found in your PATH: ${missing_commands[*]}"
    fi

    return 0
}

#
# assert_file_exists - Checks that one or more paths exist and are regular files.
#
# This function iterates through all provided paths. If any path does not
# exist or is not a regular file (e.g., it's a directory or a symlink to
# a non-file), it collects the names and reports them all in a single fatal error.
#
# Usage:
#   assert_file_exists "/etc/hosts" "./my_script.sh"
#
# Arguments:
#   $@: One or more file paths to check.
#
assert_file_exists() {
    local missing_files=()
    local file

    if (($# == 0)); then
        log_warn "assert_file_exists: No files provided to check."
        return 0
    fi

    for file; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if ((${#missing_files[@]} > 0)); then
        fatal_error "These required files do not exist or are not regular files: ${missing_files[*]}"
    fi

    return 0
}

#
# assert_dir_exists - Checks that one or more paths exist and are directories.
#
# This function iterates through all provided paths. If any path does not
# exist or is not a directory, it collects the names and reports them all
# in a single fatal error.
#
# Usage:
#   assert_dir_exists "/tmp" "/var/log"
#
# Arguments:
#   $@: One or more directory paths to check.
#
assert_dir_exists() {
    local missing_dirs=()
    local dir

    if (($# == 0)); then
        log_warn "assert_dir_exists: No directories provided to check."
        return 0
    fi

    for dir;  do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if ((${#missing_dirs[@]} > 0)); then
        fatal_error "These required directories do not exist: ${missing_dirs[*]}"
    fi

    return 0
}

################################################# MISC FUNCTIONS #######################################################

#
# base_cd - A safe version of the 'cd' command that exits on failure.
#
base_cd() {
    local dir=$1
    [[ $dir ]]   || fatal_error "No arguments or an empty string passed to base_cd"
    cd -- "$dir" || fatal_error "Can't cd to '$dir'"
}

#
# base_cd_nonfatal - A safe version of 'cd' that does not exit on failure.
#
# Returns:
#   0 on success, 1 on failure.
#
base_cd_nonfatal() {
    local dir=$1
    [[ $dir ]] || return 1
    cd -- "$dir" || return 1
    return 0
}

#
# safe_unalias - Safely unaliases a command, without erroring if it doesn't exist.
#
safe_unalias() {
    # Ref: https://stackoverflow.com/a/61471333/6862601
    local alias_name
    for alias_name; do
        [[ ${BASH_ALIASES[$alias_name]} ]] && unalias "$alias_name"
    done
    return 0
}

#
# get_my_source_dir - Returns the absolute path to the directory of the calling script through the passed variable name.
#
# Usage:
#   get_my_source_dir var_name
#
get_my_source_dir() {
    local -n result=$1
    # Reference: https://stackoverflow.com/a/246128/6862601
    result="$(cd "$(dirname "${BASH_SOURCE[1]}")" >/dev/null 2>&1 && pwd -P)"
}

#
# ask_yes_no - Get user's confirmation
#
# Prompts the user with a given message for a yes/no answer and returns 0 or 1
# based on user's choice of yes or no. It reads a single character without
# requiring the user to press Enter.
#
# Arguments:
#   $1: The message string to display as the prompt.
#
# Usage:
#
#   if ask_yes_no "Do you want to continue?"; then
#       echo "User chose to continue."
#   else
#       echo "User chose not to continue."
#   fi
#
ask_yes_no() {
    if (("$#" != 1)); then
        log_error "ask_yes_no: invalid arguments"
        log_info "Usage: ask_yes_no <prompt_message>"
        return 1
    fi

    local message=$1 user_input
    while true; do
        # Prompt the user for input.
        # -n 1: Reads only one character.
        # -r: Prevents backslash from acting as an escape character.
        # -p: Displays the prompt string.
        # The text "[y/N]" suggests that 'N' is the default choice.
        read -r -n 1 -p "$message [y/N]: " user_input
        
        # Add a newline since the user won't press Enter.
        echo

        case "$user_input" in
            [yY]) return 0;;
            [nN]) return 1;;
            *) echo "Invalid input. Please enter 'y' or 'n'.";;
        esac
    done
}

#
# wait_for_enter - Pauses the script and waits for the user to press the Enter key.
#
# Arguments:
#   $1: (Optional) The prompt to display. Defaults to "Press Enter to continue".
#
wait_for_enter() {
    local prompt=${1:-"Press Enter to continue"}
    read -r -n1 -s -p "$prompt" </dev/tty
}

#################################################### END OF FUNCTIONS ##################################################

#
# The only function that would be called upon sourcing of the library
#
__stdlib_init__

# This is the crucial step: it resets the positional parameters ($@, $1, etc.)
# of the *calling script* to the new, filtered list of arguments.
set -- "${__new_args__[@]}"
