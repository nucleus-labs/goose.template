#!/usr/bin/env bash

# ================================================================================================
#                                            GLOBALS

declare -ga GOOSE_PATH

declare -ga arguments=($@) arguments_readonly=($@)
readonly arguments_readonly

declare -ga valid_arg_types=("any" "int" "float" "string" "path" "file" "directory")
declare -ga valid_string_subtypes=("string" "path" "file" "directory")

IGNORE_DEPENDENCIES=0
BUILTIN_DEPENDENCIES=("tput")
PRESERVE_FLAGS=0

# ================================================================================================
#                                              UTILS
function call_stack {
    local i
    local stack_size=${#FUNCNAME[@]}
    echo "Call stack:"
    for (( i=stack_size-1; i > 0; i-- )); do
        echo " -> ${FUNCNAME[$i]}@${BASH_SOURCE[$i]}:${BASH_LINENO[$i-1]}"
    done
}

# (1: error message; 2: exit code)
function error {
    local message="$1"
    local code="${2:-255}"
    call_stack >&2
    echo -e "\n[ERROR][${code}]: ${message}"
    exit ${code}
}
alias  ERR_TRAP_ENABLE="trap 'error \"An unknown error has occurred\" 255' ERR"
alias ERR_TRAP_DISABLE="trap '' ERR"

# (1: warn message)
function warn {
    local message="$1"
    local stack_size=${#FUNCNAME[@]}
    echo -e "[WARN] ${FUNCNAME[$stack_size-2]}@${BASH_SOURCE[$stack_size-2]}:${BASH_LINENO[$stack_size-3]}\n => ${message}\n" >&2
}

# (1: array name (global))
function arr_max_value {
    [[ -z "$1" ]] && error "Array name is empty!" 80

    local arr_declare="$(declare -p "$1" 2>/dev/null)"
    if [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]]; then
        error "Variable '$1' does not exist!" 81
    fi

    if [[ ! -v "$1" || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]; then
        error "Variable '$1' is not an array!" 82
    fi
    local -n arr="$1"
    local max_value=${arr[0]}

    [[ ! $2 =~ ^[0-9]+$ ]] && error "value '$2' is not a valid number!" 83

    for item in "${arr[@]}"; do
        max_value=$(( ${item} > ${max_value} ? ${item} : ${max_value} ))
    done
    echo ${max_value}
}

# (1: array name (global); 2: index to pop)
function arr_pop {
    [[ -z "$1" ]] && error "Array name is empty!" 90
    [[ -z "$2" ]] && error "No provided index!" 91
    [[ ! $2 =~ ^[0-9]+$ ]] && error "Index '$2' is not a valid number!" 92

    local arr_declare="$(declare -p "$1" 2>/dev/null)"

    if [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]]; then
        error "Variable '$1' does not exist or is empty!" 93
    fi

    if [[ ! -v "$1" || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]; then
        error "Variable '$1' is not an array!" 94
    fi

    [[ ! -v $1[$2] ]] && error "Array element at index $2 does not exist!" 95

    eval "$1=(\${$1[@]:0:$2} \${$1[@]:$2+1})"
}

# ================================================================================================
#                                       CORE FUNCTIONALITY
function validate_dependencies {
    local all_deps=(${BUILTIN_DEPENDENCIES[@]} ${DEPENDENCIES[@]})
    local -a missing_deps

    for (( i=0; i<${#all_deps[@]}; i++ )); do
        if ! which "${all_deps[i]}" &> /dev/null; then
            missing_deps+=("\n\t${all_deps[i]}")
        fi
    done

    if [[ ${#missing_deps} -ne 0 ]]; then
        error "Please install missing dependencies:${missing_deps[*]}\n" 255
    fi
}

# (1: variable)
function check_type {
    local arg=$1

    local inferred_type

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

function validate_flags {
    local arg="${arguments[0]}"

    if [[ "${arg:0:1}" != "-" ]]; then
        return
    fi

    arr_pop arguments 0

    # flag is --<flag name> rather than -<short flag...>
    if [[ "${arg:0:2}" == "--" ]]; then
        validate_flag ${arg:2}
    else
        for (( i=1; i<${#arg}-1; i++ )); do
            local flag="${arg:$i:1}"
            validate_flag ${valid_flags[${flag}]}
        done
    fi

    # TODO: do not recursion
    validate_flags
}

function execute_flags {
    for (( i=0; i<10; i++ )); do
        for packed_item in "${flag_unschedule[@]}"; do
            eval local unpacked_item=(${packed_item})
            [[ ${unpacked_item[0]} -eq $i ]] && flag_schedule+=("${unpacked_item[1]}")
        done
    done

    for (( i=0; i<${#flag_schedule[@]}; i++ )); do
        eval ${flag_schedule[i]}
    done
}

function scrub_flags {
    local FORCE="$1"

    unset -v flag_schedule flag_unschedule

    declare -ga flag_schedule
    declare -ga flag_unschedule

    if [[ ${PRESERVE_FLAGS} -eq 0 || "${FORCE}" == "force" ]]; then
        unset -v valid_flags valid_flag_names

        declare -gA valid_flags
        declare -gA valid_flag_names
    fi
}

function find_namespace_from {
    return
}

function find_root_namespace {
    return
}

function run_namespace {
    validate_flags
    execute_flags

    [[ ${IGNORE_DEPENDENCIES} -eq 0 ]] && validate_dependencies
    validate_target
}

# ================================================================================================
#                                            BUILT-INS

# (1: target (optional); 2: is flag)
function print_help {
    local cols=$(tput cols)
    cols=$(( $cols > 22 ? $cols - 1 : 20 ))

    local flag_help="$1"
    local is_flag="$2"

    if [[ -n "${is_flag}" ]]; then
        return
    fi

    # print help for targets
    if [[ $# -gt 0 ]]; then
        if [[ ! -f "${PROJECT_PATH}/targets/${flag_help}.bash" ]] && ! is_builtin "${flag_help}"; then
            error "No such command '${flag_help}'" 255

        elif is_builtin "${flag_help}"; then
            local current_target="${flag_help}"
            scrub_flags
            eval "target_${current_target}_builtin"
            local arg_count=${#target_arguments[@]}

            {
                echo ";name;priority;argument name;argument type   ;description"
                echo ";;;;;"
                for flag_name in "${!valid_flag_names[@]}"; do

                    local packed_flag_data="${valid_flag_names[${flag_name}]}"
                    eval local flag_data=(${packed_flag_data})

                    #  1: flag (single character); 2: name; 3: description; 4: priority;
                    #  5: argument name; 6: argument type; 7: argument description
                    local flag="${flag_data[0]}"
                    local name="${flag_name}"
                    local description="${flag_data[2]}"
                    local priority="${flag_data[3]}"
                    local argument="${flag_data[4]}"
                    local argument_type="${flag_data[5]}"
                    local arg_description="${flag_data[6]}"

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

                for (( i=0; i<${arg_count}; i++ )); do
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
            local current_target="${flag_help}"

            scrub_flags
            scrub_arguments
            source "${PROJECT_PATH}/targets/${current_target}.bash"

            local arg_count=${#target_arguments[@]}

            {
                echo "target: ${current_target};description:;${description}"
                echo ";;"
                echo "argument name |;argument type |;description"
                echo ";;"

                for (( i=0; i<${arg_count}; i++ )); do
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

                    # echo "${flag_name}"
                    local packed_flag_data="${valid_flag_names[${flag_name}]}"
                    # echo "${packed_flag_data}"
                    eval local flag_data=(${packed_flag_data})

                    #  1: flag (single character); 2: name; 3: description; 4: priority;
                    #  5: argument name; 6: argument type; 7: argument description
                    local flag="${flag_data[0]}"
                    local name="${flag_name}"
                    local description="${flag_data[2]}"
                    local priority="${flag_data[3]}"
                    local argument="${flag_data[4]}"
                    local argument_type="${flag_data[5]}"
                    local arg_description="${flag_data[6]}"

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

                # echo "${flag_name}"
                local packed_flag_data="${valid_flag_names[${flag_name}]}"
                # echo "${packed_flag_data}"
                eval local flag_data=(${packed_flag_data})

                #  1: flag (single character); 2: name; 3: description; 4: priority;
                #  5: argument name; 6: argument type; 7: argument description
                local flag="${flag_data[0]}"
                local name="${flag_name}"
                local description="${flag_data[2]}"
                local priority="${flag_data[3]}"
                local argument="${flag_data[4]}"
                local argument_type="${flag_data[5]}"
                local arg_description="${flag_data[6]}"

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

        echo "Targets:"
        {
            echo ";;;"
            for file in ${PROJECT_PATH}/targets/*.bash; do
                current_target="${file##*/}"
                current_target="${current_target%.bash}"

                [[ "${current_target}" == "common" ]] && continue

                # echo "${current_target}" >&2

                target_arguments=()
                target_arg_types=()
                target_arg_descs=()

                scrub_flags "force"
                source ${file}

                local flag_count=${#valid_flag_names[@]}
                local arg_count=${#target_arguments[@]}

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


