#!/usr/bin/env bash

# ================================================================================================
#                                            GLOBALS

declare -gA valid_flags
declare -gA valid_flag_names

declare -ga flag_schedule
declare -ga flag_unschedule

declare -ga arguments
declare -ga readonly_arguments

declare -ga builtin_targets

declare -g   current_target
declare -ga  target_arguments
declare -ga  target_arg_types
declare -ga  target_arg_descs

declare -ga valid_arg_types

declare -g IGNORE_DEPENDENCIES
declare -ga BUILTIN_DEPENDENCIES
declare -g PRESERVE_FLAGS

arguments=($@)
readonly_arguments=($@)
valid_arg_types=("any" "int" "float" "string")
IGNORE_DEPENDENCIES=0
BUILTIN_DEPENDENCIES=("tput")
PRESERVE_FLAGS=0

readonly readonly_arguments

# ================================================================================================
#                                              UTILS

# Prints a formatted call stack trace.
# Arguments: None.
# Return: None.
function call_stack {
    local i
    local stack_size
    local stack_func
    local stack_file
    local stack_line
    
    stack_size=${#FUNCNAME[@]}
    echo "Call stack:"
    for (( i=stack_size-1; i > 0; i-- )); do
        stack_func="${FUNCNAME[$i]}"
        stack_file="${BASH_SOURCE[$i]}"
        stack_line="${BASH_LINENO[$i-1]}"

        echo " -> ${stack_func}@${stack_file}:${stack_line}"
    done
}

# Prints an error message to stderr, prints a call stack trace, outputs an error message, and exits.
# Arguments:
#   $1 - Error message.
#   $2 - Exit code (optional, defaults to 255).
# Return: None.
function error {
    local message
    local code

    message="$1"
    code="${2:-255}"

    call_stack >&2
    echo -e "\n[ERROR][${code}]: ${message}"
    exit "${code}"
}
# trap 'error "An unknown error has occurred" 255' ERR

# Prints a warning message to stderr (including the caller's function, source file, and line number).
# Arguments:
#   $1 - Warning message.
# Return: None.
function warn {
    local message
    local stack_size
    local warn_func
    local warn_file
    local warn_line

    message="$1"
    stack_size=${#FUNCNAME[@]}
    warn_func="${FUNCNAME[$stack_size-2]}"
    warn_file="${BASH_SOURCE[$stack_size-2]}"
    warn_line="${BASH_LINENO[$stack_size-3]}"

    echo "[WARN] ${warn_func}@${warn_file}:${warn_line}" >&2
    echo " => ${message}" >&2
    echo >&2
}

# Removes an element from a global array at a specified index.
# Arguments:
#   $1 - Name of the array variable.
#   $2 - Index of the element to pop.
# Return: None.
function arr_pop {
    local arr_name
    local arr_index
    local arr_declare

    arr_name="$1"
    arr_index="$2"

    [[ -z "${arr_name}" ]]              && error "Array name is empty!"                         90
    [[ -z "${arr_index}" ]]             && error "No provided index!"                           91
    [[ ! ${arr_index} =~ ^[0-9]+$ ]]    && error "Index '${arr_index}' is not a valid number!"  92

    arr_declare="$(declare -p "${arr_name}" 2>/dev/null)"

    if [[ -z "${!arr_name+x}" || "${arr_declare}" != "declare"* ]]; then
        error "Variable '${arr_name}' does not exist or is empty!" 93
    fi

    if [[ ! -v "${arr_name}" || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]; then
        error "Variable '${arr_name}' is not an array!" 94
    fi

    [[ ! -v ${!1[$arr_index]} ]] && error "Array element at index ${arr_index} does not exist!" 95

    eval "$1=(\${$1[@]:0:$2} \${$1[@]:$2+1})"
}

# ================================================================================================
#                                       CORE FUNCTIONALITY

# Checks that required dependencies (defined in `BUILTIN_DEPENDENCIES` and `BUILTIN_DEPENDENCIES`)
# are present in the current PATH and reports any missing ones, erroring if any are missing.
# Arguments: None.
# Return: None.
function validate_dependencies {
    local all_deps
    local -a missing_deps
    local current_dep

    all_deps=(${BUILTIN_DEPENDENCIES[@]} ${DEPENDENCIES[@]})

    for (( i=0; i<${#all_deps[@]}; i++ )); do
        current_dep="${all_deps[i]}"
        if ! which "${current_dep}" &> /dev/null; then
            missing_deps+=("\n\t${current_dep}")
        fi
    done

    if [[ ${#missing_deps} -ne 0 ]]; then
        error "Please install missing dependencies:${missing_deps[*]}\n" 255
    fi
}

# Add a flag to the current context (irrespective of being in common or target). Implementation
# MUST be in a function with the name `flag_name_<long flag name>`, in the same context
# (preferably immediately following the call to `add_flag`).
#
# Short flag names are optional. For flags without a short name, use '-'.
#
# Flags are executed based on their registered priority score, NOT in the provided order.
#
# Some flags have an argument, some do not. For those that don't, arguments 5, 6, and 7 should
# be ignored. For those that do, all 3 of arguments 5, 6, and 7 must *ALL* be provided.
# Arguments:
#   $1 - flag name (short) (single character)
#   $2 - flag name (long)
#   $3 - description
#   $4 - priority (integer)
#   $5 - (OPTIONAL) argument name
#   $6 - (OPTIONAL-DEPENDENT) argument type
#   $7 - (OPTIONAL-DEPENDENT) argument description
# Return: None.
function add_flag {
    local flag
    local name
    local description
    local priority
    local argument
    local argument_type
    local arg_description
    local packed

    flag="$1"
    name="$2"
    description="$3"
    priority="$4"
    argument="$5"
    argument_type="$6"
    arg_description="$7"

    # basic validations
    [[ -z "${flag}" ]]                  && error "Flag cannot be empty!"                                           60
    [[ ${#flag} -gt 1 ]]                && error "Flag '${flag}' is invalid! Flags must be a single character!"    61
    [[ -z "${description}" ]]           && error "Description for flag '${name}' cannot be empty!"                 62
    [[ -z "${priority}" ]]              && error "Must provide a priority for flag '${name}'!"                     63
    [[ ! ${priority} =~ ^[0-9]+$ ]]     && error "Priority <${priority}> for flag '${name}' is not a number!"      64

    if [[ -n "${argument}" && ! ${valid_arg_types[*]} =~ ${argument_type} ]]; then
        error "Flag argument type for '${name}':'${argument}' (${argument_type}) is invalid!" 65
    fi

    # more complex validations
    for key in "${!valid_flags[@]}"; do # iterate over keys
    
        if [[ "${valid_flags[$key]}" == "${flag}" ]]; then
            error "Flag <${flag}> already registered!" 66
        fi
    done

    for flag_name in "${!valid_flag_names[@]}"; do
        if [[ "${valid_flag_names[$flag_name]}" == "${name}" ]]; then
            error "Flag name <${flag_name}> already registered!" 67
        fi
    done

    if [[ -n "${argument}" && -z "${argument_type}" ]]; then
        error "Argument type must be provided for flag '${name}':'${argument}'" 68
    fi

    # register information
    [[ "${flag}" != "-" ]] && valid_flags["${flag}"]="${name}"

    packed="'${flag}' '${name}' '${description//\'/\\\'}' '${priority}' '${argument}' '${argument_type}' '${arg_description//\'/\\\'}'"
    valid_flag_names[${name}]="${packed}"
}

# Pass a value to this function to try and determine its type.
# Arguments:
#   $1 - variable value
# Return: "int" | "float" | "string" | <error>
function check_type {
    local arg
    local inferred_type

    arg=$1

    if [[ "${arg}" =~ ^[0-9]+$ ]]; then
        inferred_type="int"
    elif [[ "${arg}" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
        inferred_type="float"
    elif [[ "$(declare -p arg)" =~ "declare -- arg=\""* ]]; then
        inferred_type="string"
    else
        error "failed to determine type of '${arg}'" 255
    fi

    echo "${inferred_type}"
}

# Validate the use of a short flag during runtime
# Arguments:
#   $1 - flag short name (single character)
# Return: None.
function validate_short_flag {
    local flag
    local valid_flag_found
    local flag_name
    local function_name
    local packed_flag_data
    local -a unpacked_flag_data
    local flag_arg
    local inferred_type
    local msg

    flag="$1"
    valid_flag_found=0

    # check if the supplied flag is valid
    for value in "${!valid_flags[@]}"; do
        if [[ "${flag}" != "-" && "${value}" == "${flag}" ]]; then
            valid_flag_found=1
            break
        fi
    done

    # if no valid flag matching the supplied flag is found, error
    if [[ ${valid_flag_found} -eq 0 ]]; then
        error "'-${flag}' is not a valid flag.\n\n$(print_help)" 255
    else
        flag_name="${valid_flags[$flag]}"
        function_name="${flag_name//-/_}"

        packed_flag_data="${valid_flag_names[$flag_name]}"
        eval "unpacked_flag_data=(${packed_flag_data})"

        #  0: flag (single character); 1: name; 2: description; 3: priority;
        #  4: argument name; 5: argument type; 6: argument description
        if [[ -n "${unpacked_flag_data[4]}" ]]; then
            flag_arg=" ${arguments[0]}"
            arr_pop arguments 0

            inferred_type=$(check_type "${flag_arg}")
            if [[ "${inferred_type}" != "${unpacked_flag_data[5]}" ]]; then
                msg="Flag '${flag_name}' argument '${unpacked_flag_data[4]}' requires type '${unpacked_flag_data[5]}'. "
                msg+="Inferred type of '${flag_arg}' is '${inferred_type}'"
                error "${msg}" 255
            fi
        fi
        flag_unschedule+=("'${unpacked_flag_data[3]}' 'flag_name_${function_name}${flag_arg}'")
    fi
}

# Validate the use of a long flag during runtime
# Arguments:
#   $1 - flag long name
# Return: None.
function validate_flag_long {
    local flag_name
    local valid_flag_name_found
    local function_name
    local packed_flag_data
    local unpacked_flag_data
    local flag_arg
    local inferred_type
    local msg

    flag_name="$1"
    valid_flag_name_found=0

    # check if the supplied flag is valid
    for value in "${!valid_flag_names[@]}"; do
        if [[ "${value}" == "${flag_name}" || "${value}" == "${flag//-/_}" ]]; then
            valid_flag_name_found=1
            break
        fi
    done

    # if no valid flag matching the supplied flag is found, error
    if [[ ${valid_flag_name_found} -eq 0 ]]; then
        error "'--${flag_name}' is not a valid flag name.\n\n$(print_help)" 255
    else
        function_name="${flag_name//-/_}"

        packed_flag_data="${valid_flag_names[$flag_name]}"
        eval "unpacked_flag_data=(${packed_flag_data})"

        #  0: flag (single character); 1: name; 2: description; 3: priority;
        #  4: argument name; 5: argument type; 6: argument description
        if [[ -n "${unpacked_flag_data[4]}" ]]; then
            [[ ${#arguments[@]} -eq 0 ]] \
                && error "flag '${flag_name}' requires argument '${unpacked_flag_data[4]}' but wasn't provided!" 255

            flag_arg="${arguments[0]}"
            arr_pop arguments 0

            inferred_type=$(check_type "${flag_arg}")
            if [[ "${inferred_type}" != "${unpacked_flag_data[5]}" ]]; then
                msg="Flag '${flag_name}' argument '${unpacked_flag_data[4]}' requires type '${unpacked_flag_data[5]}'. 
                    Inferred type of '${flag_arg}' is '${inferred_type}'"
                error "${msg}" 255
            fi
        fi
        flag_unschedule+=("'${unpacked_flag_data[3]}' 'flag_name_${function_name} ${flag_arg}'")
    fi
}

# Consume, validate, and process cli arguments beginning with a dash ('-')
# Arguments: None.
# Return: None.
function validate_flags {
    local arg
    local flags
    local unpacked_item

    arg="${arguments[0]}"

    if [[ "${arg:0:1}" != "-" ]]; then
        return
    fi

    arr_pop arguments 0

    if [[ "${arg:1:1}" != "-" ]]; then
        flags=${arg}
        for (( i=1; i<${#flags}; i++ )); do
            validate_short_flag "${flags:$i:1}"
        done
    else
        validate_flag_long "${arg:2}"
    fi

    # TODO: do not recursion
    validate_flags
}

# Consume, validate, and process remaining arguments
# Arguments: None.
# Return: None.
function execute_flags {
    for (( i=0; i<10; i++ )); do
        for packed_item in "${flag_unschedule[@]}"; do
            eval "unpacked_item=(${packed_item})"
            [[ ${unpacked_item[0]} -eq $i ]] && flag_schedule+=("${unpacked_item[1]}")
        done
    done

    for (( i=0; i<${#flag_schedule[@]}; i++ )); do
        eval "${flag_schedule[i]}"
    done
}

# Reset global state related to flags
# Arguments: None.
# Return: None.
function scrub_flags {
    local FORCE
    
    FORCE="$1"

    unset -v flag_schedule flag_unschedule

    declare -ga flag_schedule
    declare -ga flag_unschedule

    if [[ ${PRESERVE_FLAGS} -eq 0 || "${FORCE}" == "force" ]]; then
        unset -v valid_flags valid_flag_names

        declare -gA valid_flags
        declare -gA valid_flag_names
    fi
}

# Consume, validate, and process cli arguments not beginning with a dash ('-')
# Arguments: None.
# Return: None.
function validate_target {
    local target
    local target_arguments_provide
    local arg_name
    local arg_type
    local variadic
    local arg
    local msg
    local inferred_type

    target=${arguments[0]}

    if [[ ${#arguments[@]} -eq 0 ]]; then
        print_help
        exit 0
    fi
    arr_pop arguments 0

    if [[ ! -f "${PROJECT_PATH}/targets/${target}.bash" ]] && ! is_builtin "${target}"; then
        error "Target file '${PROJECT_PATH}/targets/${target}.bash' not found!" 255
    fi

    scrub_flags

    if ! is_builtin "${target}"; then
        source "${PROJECT_PATH}/targets/${target}.bash"
    else
        eval "target_${target}_builtin"
    fi

    target="${target//-/_}"

    if [[ $(type -t "target_${target}") != "function" ]]; then
        error "Target function 'target_${target}' was not found in '${PROJECT_PATH}/targets/${target}.bash'!" 255
    fi

    current_target=${target}
    add_flag 'h' "help" "print this help screen" 0
    validate_flags
    execute_flags

    target_arguments_provide=()
    for (( i=0; i<${#target_arguments[@]}; i++ )); do
        arg_name="${target_arguments[i]}"
        arg_type="${target_arg_types[i]}"

        variadic=0
        [[ "${arg_type}" == *... ]] && variadic=1
        arg_type=${arg_type%%...}

        if [[ ${variadic} -eq 0 ]]; then
            if [[ ${#arguments[@]} -eq 0 ]]; then
                error "Target '${target}' requires argument '${arg_name}' but wasn't provided!" 255
            fi

            arg="${arguments[0]}"
            arr_pop arguments 0

            # TYPE CHECKING
            if [[ "${arg_type}" != "any" && "${arg_type}" != "string" ]]; then
                inferred_type=$(check_type "${arg}")
                if [[ "${inferred_type}" != "${arg_type}" ]]; then
                    msg="Target '${target}' argument '${arg_name}' requires type '${arg_type}'. \nInferred type of '${arg}' is '${inferred_type}'"
                    error "${msg}" 255
                fi
            fi
            target_arguments_provide+=("\"${arg}\"")
        else
            for arg in "${arguments[@]}"; do
                arr_pop arguments 0

                # TYPE CHECKING
                if [[ "${arg_type}" != "any" && "${arg_type}" != "string" ]]; then
                    inferred_type=$(check_type "${arg}")
                    if [[ "${inferred_type}" != "${arg_type}" ]]; then
                        msg="Target '${target}' argument '${arg_name}' requires type '${arg_type}'. \nInferred type of '${arg}' is '${inferred_type}'"
                        error "${msg}" 255
                    fi
                fi
                target_arguments_provide+=("\"${arg}\"")
            done
        fi
    done

    eval "target_${target}" ${target_arguments_provide[@]}
}

# Reset global state related to target arguments
# Arguments: None.
# Return: None.
function scrub_arguments {
    unset -v target_arguments target_arg_types target_arg_descs
    declare -ga target_arguments target_arg_types target_arg_descs
}

# Checks if a target is builtin by goose
# Arguments:
#   $1 - target name
# Return: 0 | 1
function is_builtin {
    local target_check
    target_check="$1"
    if [[ ${builtin_targets[*]} =~ ${target_check} ]]; then
        return 0
    else
        return 1
    fi
}

# Add an argument to a target
# Arguments:
#   $1 - argument name
#   $2 - argument type
#   $3 - argument description
function add_argument {
    local name
    local type_
    local desc
    local detected_any
    local variadic
    local msg
    local count

    name=$1
    type_=$2
    desc=$3

    detected_any=0

    if [[ -z "${type_}" ]]; then
        detected_any=1
        type_="any"
    fi

    variadic=0
    [[ "${type_}" == *... ]] && variadic=1
    type_="${type_%%...}"

    if [[ "${name}" == "" || "${desc}" == "" || ! ${valid_arg_types[*]} =~ ${type_} ]]; then
        msg="\n\tadd_argument usage is: 'add_argument \"<name>\" \"<${valid_arg_types[*]}>\" \"<description>\"'\n"
        [[ ${detected_any} -eq 1 ]] && msg+="\t(auto-detected type as \"any\")\n"
        msg+="\tWhat you provided:\n"
        msg+="\tadd_argument \"${name}\" \"${type_}\" \"${desc}\"\n"
        error "${msg}" 255
    fi

    [[ ${variadic} -eq 1 ]] && type_="${type_}..."

    count=${#target_arguments[@]}

    target_arguments[$count]="${name}"
    target_arg_types[$count]="${type_}"
    target_arg_descs[$count]="${desc}"
}

# ================================================================================================
#                                            BUILT-INS

# print the help text associated with a target if provided, else print help text listing targets
# and global flags.
# Arguments:
#   $1 - target name (optional)
#   $2 - is flag (optional)
function print_help {
    local cols
    local flag_help
    local is_flag
    local current_target
    local arg_count
    local packed_flag_data
    local flag_data
    local flag
    local name
    local description
    local priority
    local argument
    local argument_type
    local arg_description
    local flag_count

    cols=$(tput cols)
    cols=$(( cols > 22 ? cols - 1 : 20 ))

    flag_help="$1"
    is_flag="$2"

    if [[ -n "${is_flag}" ]]; then
        return
    fi

    # print help for targets
    if [[ $# -gt 0 ]]; then
        if [[ ! -f "${PROJECT_PATH}/targets/${flag_help}.bash" ]] && ! is_builtin "${flag_help}"; then
            error "No such command '${flag_help}'" 255

        elif is_builtin "${flag_help}"; then
            current_target="${flag_help}"
            scrub_flags
            eval "target_${current_target}_builtin"
            arg_count=${#target_arguments[@]}

            {
                echo ";name;priority;argument name;argument type   ;description"
                echo ";;;;;"
                for flag_name in "${!valid_flag_names[@]}"; do

                    packed_flag_data="${valid_flag_names[$flag_name]}"
                    eval "flag_data=(${packed_flag_data})"

                    #  1: flag (single character); 2: name; 3: description; 4: priority;
                    #  5: argument name; 6: argument type; 7: argument description
                    flag="${flag_data[0]}"
                    name="${flag_name}"
                    description="${flag_data[2]}"
                    priority="${flag_data[3]}"
                    argument="${flag_data[4]}"
                    argument_type="${flag_data[5]}"
                    arg_description="${flag_data[6]}"

                    [[ "${flag}" == "-" ]] && flag="" || flag="-${flag}"

                    echo "${flag};--${name};${priority};;;${description}"
                    [[ -n "${argument}" ]] && echo ";;;${argument};${argument_type};${arg_description}"
                    echo ";;;;;"

                done
            } | column  --separator ';'                                                                             \
                        --table                                                                                     \
                        --output-width ${cols}                                                                      \
                        --table-noheadings                                                                          \
                        --table-columns "short name,long name,priority,argument name,argument type,description"     \
                        --table-right "short name,priority"                                                         \
                        --table-wrap description

            {
                echo "target: ${current_target};description:;${description}"
                echo ";;"
                echo "argument name |;argument type |;description"
                echo ";;"

                for (( i=0; i<arg_count; i++ )); do
                    echo "${target_arguments[i]};${target_arg_types[i]};${target_arg_descs[i]}"
                done
            } | column                                      \
                    --separator ';'                         \
                    --table                                 \
                    --output-width ${cols}                  \
                    --table-noheadings                      \
                    --table-columns "argument name,argument type,description"  \
                    --table-wrap description

        else
            current_target="${flag_help}"

            scrub_flags
            scrub_arguments
            source "${PROJECT_PATH}/targets/${current_target}.bash"

            arg_count=${#target_arguments[@]}

            {
                echo "target: ${current_target};description:;${description}"
                echo ";;"
                echo "argument name |;argument type |;description"
                echo ";;"

                for (( i=0; i<arg_count; i++ )); do
                    echo "${target_arguments[i]};${target_arg_types[i]};${target_arg_descs[i]}"
                done
            } | column                                      \
                    --separator ';'                         \
                    --table                                 \
                    --output-width ${cols}                  \
                    --table-noheadings                      \
                    --table-columns "argument name,argument type,description"  \
                    --table-wrap description

            printf "%${cols}s\n" | tr " " "="

            {
                echo ";name;priority;argument name;argument type   ;description"
                echo ";;;;;"
                for flag_name in "${!valid_flag_names[@]}"; do

                    packed_flag_data="${valid_flag_names[$flag_name]}"
                    eval "flag_data=(${packed_flag_data})"

                    #  1: flag (single character); 2: name; 3: description; 4: priority;
                    #  5: argument name; 6: argument type; 7: argument description
                    flag="${flag_data[0]}"
                    name="${flag_name}"
                    description="${flag_data[2]}"
                    priority="${flag_data[3]}"
                    argument="${flag_data[4]}"
                    argument_type="${flag_data[5]}"
                    arg_description="${flag_data[6]}"

                    if [[ "${flag}" == "-" ]]; then
                        flag=""
                    else
                        flag="-${flag}"
                    fi

                    echo "${flag};--${name};${priority};;;${description}"
                    [[ -n "${argument}" ]] && echo ";;;${argument};${argument_type};${arg_description}"
                    echo ";;;;;"

                done
            } | column  --separator ';'                                                                             \
                        --table                                                                                     \
                        --output-width ${cols}                                                                      \
                        --table-noheadings                                                                          \
                        --table-columns "short name,long name,priority,argument name,argument type,description"     \
                        --table-right "short name,priority"                                                         \
                        --table-wrap description

        fi
    else # iterate through targets and collect info ; `$0 -h` or `$0 --help`
        echo "Main usage:"
        echo "    ${APP_NAME} [common-flag [flag-argument]]... <target> [target-flag [flag-argument]]... [target argument]..."
        echo
        echo "Help aliases:"
        echo "    ${APP_NAME}"
        echo "    ${APP_NAME}  -h"
        echo "    ${APP_NAME} --help"
        echo "    ${APP_NAME}   help"
        echo
        echo "More detailed help aliases:"
        echo "    ${APP_NAME} --help-target <target>"
        echo

        echo "Common Flags:"
        {
            echo ";name;priority;argument name;argument type   ;description"
            echo ";;;;;"
            for flag_name in "${!valid_flag_names[@]}"; do

                packed_flag_data="${valid_flag_names[$flag_name]}"
                eval "flag_data=(${packed_flag_data})"

                #  1: flag (single character); 2: name; 3: description; 4: priority;
                #  5: argument name; 6: argument type; 7: argument description
                flag="${flag_data[0]}"
                name="${flag_name}"
                description="${flag_data[2]}"
                priority="${flag_data[3]}"
                argument="${flag_data[4]}"
                argument_type="${flag_data[5]}"
                arg_description="${flag_data[6]}"

                if [[ "${flag}" == "-" ]]; then
                    flag=""
                else
                    flag="-${flag}"
                fi

                echo "${flag};--${name};${priority};;;${description}"
                [[ -n "${argument}" ]] && echo ";;;${argument};${argument_type};${arg_description}"
                echo ";;;;;"

            done
        } | column  --separator ';'                                                                             \
                    --table                                                                                     \
                    --output-width ${cols}                                                                      \
                    --table-noheadings                                                                          \
                    --table-columns "short name,long name,priority,argument name,argument type,description"     \
                    --table-right "short name,priority"                                                         \
                    --table-wrap description

        echo "Targets:"
        {
            echo ";;;"
            for file in "${PROJECT_PATH}"/targets/*.bash; do
                current_target="${file##*/}"
                current_target="${current_target%.bash}"

                [[ "${current_target}" == "common" ]] && continue

                target_arguments=()
                target_arg_types=()
                target_arg_descs=()

                scrub_flags "force"
                source "${file}"

                flag_count=${#valid_flag_names[@]}
                arg_count=${#target_arguments[@]}

                echo "${current_target};${flag_count};${arg_count};${description}"
                echo ";;;"
            done
        } | column                                                              \
                --separator ';'                                                 \
                --table                                                         \
                --output-width ${cols}                                          \
                --table-columns "subcommand,flag count,arg count,description"   \
                --table-wrap description
    fi
}

add_flag 'h' "help" "prints this menu" 0
function flag_name_help {
    if [[ -z ${current_target} ]]; then
        print_help
    else
        print_help "${current_target}"
    fi
    exit 0
}

add_flag '-' "help-target" "prints help for a specific target" 0 "target" "string" "prints a target-specific help with more info"
function flag_name_help_target {
    local help_target

    help_target="$1"

    print_help "${help_target}"
    exit 0
}

add_flag '-' "debug--ignore-dependencies" "bypass the check for dependencies" 0
function flag_name_debug__ignore_dependencies {
    IGNORE_DEPENDENCIES=1
}

add_flag '-' "debug--preserve-flags" "prevents unsetting flags before loading targets" 0
function flag_name_debug__preserve_flags {
    PRESERVE_FLAGS=1
}

add_flag '-' "error" "simulates an error" 1 "exit code" "int" "exit code"
function flag_name_error {
    local exit_code

    exit_code="$1"

    echo "error: ${exit_code}"
    return "${exit_code}"
}

add_flag 'g' "global" "use the global install of ${APP_NAME}" 0
function flag_name_global {
    echo "${readonly_arguments}"
}

function goose_autocomplete {
    return
    # TODO: add pseudo-parsing of supplied arguments so that suggestions can be made
}

add_flag '-' "register-autocompletion" "use this flag to enable autocompletion of ${APP_NAME}" 0
function flag_name_register_autocompletion {
    complete -F goose_autocomplete "${APP_NAME}"
    exit 0
}

builtin_targets+=("help")
function target_help_builtin {
    description="prints this menu"
}
function target_help {
    print_help
}

