
# ================================================================================================
#                                            GLOBALS

declare -gA valid_flags
declare -gA valid_flag_names

declare -ga flag_schedule
declare -ga flag_unschedule

declare -ga builtin_targets

declare -g   current_target
declare -ga  target_arguments
declare -ga  target_arg_types
declare -ga  target_arg_descs

# ================================================================================================
#                                       CORE FUNCTIONALITY


#  1: flag (single character); 2: name; 3: description; 4: priority;
#  5: argument name; 6: argument type; 7: argument description
function add_flag {
    local flag="$1"
    local name="$2"
    local description="$3"
    local priority="$4"
    local argument="$5"
    local argument_type="$6"
    local arg_description="$7"

    # basic validations
    [[ -z "${flag}" ]]                  && error "Flag cannot be empty!"                                           60
    [[ ${#flag} -gt 1 ]]                && error "Flag '${flag}' is invalid! Flags must be a single character!"    61
    [[ -z "${description}" ]]           && error "Description for flag '${name}' cannot be empty!"                 62
    [[ -z "${priority}" ]]              && error "Must provide a priority for flag '${name}'!"                     63
    [[ ! ${priority} =~ ^[0-9]+$ ]]     && error "Priority <${priority}> for flag '${name}' is not a number!"      64
    if [[ -n "${argument}" && ! ${valid_arg_types[@]} =~ "${argument_type}" ]]; then
        error "Flag argument type for '${name}':'${argument}' (${argument_type}) is invalid!"                      65
    fi

    # more complex validations
    for key in "${!valid_flags[@]}"; do # iterate over keys
        [[ "${valid_flags[${key}]}" == "${flag}" ]]               && error "Flag <${flag}> already registered!"                      66
    done

    for flag_name in "${!valid_flag_names[@]}"; do
        [[ "${valid_flag_names[${flag_name}]}" == "${name}" ]]    && error "Flag name <${flag_name}> already registered!"            67
    done

    [[ -n "${argument}" && -z "${argument_type}" ]] && error "Argument type must be provided for flag '${name}':'${argument}'"       68

    # register information
    [[ "${flag}" != "-" ]] && valid_flags["${flag}"]="${name}"

    local packed="'${flag}' '${name}' '${description//\'/\\\'}' '${priority}' '${argument}' '${argument_type}' '${arg_description//\'/\\\'}'"
    valid_flag_names[${name}]="${packed}"
}

# (1: flag name (string))
function validate_flag {
    local flag_name="$1"
    local valid_flag_name_found=0

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
        local function_name="${flag_name//-/_}"

        local packed_flag_data="${valid_flag_names[${flag_name}]}"
        eval local unpacked_flag_data=(${packed_flag_data})

        #  0: flag (single character); 1: name; 2: description; 3: priority;
        #  4: argument name; 5: argument type; 6: argument description
        local flag_arg
        if [[ -n "${unpacked_flag_data[4]}" ]]; then
            [[ ${#arguments[@]} -eq 0 ]] \
                && error "flag '${flag_name}' requires argument '${unpacked_flag_data[4]}' but wasn't provided!" 255

            flag_arg="${arguments[0]}"
            arr_pop arguments 0

            local inferred_type=$(check_type "${flag_arg}")
            if [[ "${inferred_type}" != "${unpacked_flag_data[5]}" && ! "${valid_string_subtypes[@]}" =~ "${unpacked_flag_data[5]}" ]]; then
                local msg="Flag '${flag_name}' argument '${unpacked_flag_data[4]}' requires type '${unpacked_flag_data[5]}'. 
                    Inferred type of '${flag_arg}' is '${inferred_type}'"
                error "${msg}" 255
            fi
        fi
        flag_unschedule+=("'${unpacked_flag_data[3]}' 'flag_name_${function_name} ${flag_arg}'")
    fi
}

function validate_target {
    local target=${arguments[0]}
    local valid_target_found=0

    if [[ ${#arguments[@]} -eq 0 ]]; then
        print_help
        exit 0
    fi
    arr_pop arguments 0

    if [[ ! -f "${PROJECT_PATH}/targets/${target}.bash" ]] && ! is_builtin ${target}; then
        error "Target file '${PROJECT_PATH}/targets/${target}.bash' not found!" 255
    fi

    # DAG_TARGET_STACK+=("${target}")

    scrub_flags

    if ! is_builtin ${target}; then
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

    local target_arguments_provide=()
    for (( i=0; i<${#target_arguments[@]}; i++ )); do
        local arg_name="${target_arguments[i]}"
        local arg_type="${target_arg_types[i]}"

        local variadic=0
        [[ "${arg_type}" == *... ]] && variadic=1
        arg_type=${arg_type%%...}

        if [[ ${variadic} -eq 0 ]]; then
            if [[ ${#arguments[@]} -eq 0 ]]; then
                error "Target '${target}' requires argument '${arg_name}' but wasn't provided!" 255
            fi

            local arg="${arguments[0]}"
            arr_pop arguments 0

            # TYPE CHECKING
            if [[ "${arg_type}" != "any" && ! "${valid_string_subtypes[@]}" =~ "${unpacked_flag_data[5]}" ]]; then
                local inferred_type=$(check_type "${arg}")
                if [[ "${inferred_type}" != "${arg_type}" ]]; then
                    local msg="Target '${target}' argument '${arg_name}' requires type '${arg_type}'. \nInferred type of '${arg}' is '${inferred_type}'"
                    error "${msg}" 255
                fi
            fi
            target_arguments_provide+=("\"${arg}\"")
        else
            for arg in "${arguments[@]}"; do
                arr_pop arguments 0

                # TYPE CHECKING
                if [[ "${arg_type}" != "any" && ! "${valid_string_subtypes[@]}" =~ "${unpacked_flag_data[5]}" ]]; then
                    local inferred_type=$(check_type "${arg}")
                    # if not exact match, and (type was determined to be string, and provided type is a string subtype)
                    if [[ "${inferred_type}" != "${arg_type}" ]]; then
                        local msg="Target '${target}' argument '${arg_name}' requires type '${arg_type}'. \nInferred type of '${arg}' is '${inferred_type}'"
                        error "${msg}" 255
                    fi
                fi
                target_arguments_provide+=("\"${arg}\"")
            done
        fi
    done

    eval "target_${target}" ${target_arguments_provide[@]}
    # echo "target_${target} ${target_arguments_provide[@]}"
}

function scrub_arguments {
    unset -v target_arguments target_arg_types target_arg_descs
    declare -ga target_arguments target_arg_types target_arg_descs
}

function is_builtin {
    local target_check="$1"
    if [[ ${builtin_targets[@]} =~ ${target_check} ]]; then
        return 0
    else
        return 1
    fi
}

# (1: name; 2: type; 3: description)
function add_argument {
    local name=$1
    local type_=$2
    local desc=$3

    local detected_any=0

    if [[ -z "${type_}" ]]; then
        detected_any=1
        type_="any"
    fi

    local variadic=0
    [[ "${type_}" == *... ]] && variadic=1
    type_="${type_%%...}"

    if [[ "${name}" == "" || "${desc}" == "" || ! ${valid_arg_types[@]} =~ "${type_}" ]]; then
        local msg="\n\tadd_argument usage is: 'add_argument \"<name>\" \"<${valid_arg_types[*]}>\" \"<description>\"'\n"
        [[ ${detected_any} -eq 1 ]] && msg+="\t(auto-detected type as \"any\")\n"
        msg+="\tWhat you provided:\n"
        msg+="\tadd_argument \"${name}\" \"${type_}\" \"${desc}\"\n"
        error "${msg}" 255
    fi

    [[ ${variadic} -eq 1 ]] && type_="${type_}..."

    local count=${#target_arguments[@]}

    target_arguments[$count]="${name}"
    target_arg_types[$count]="${type_}"
    target_arg_descs[$count]="${desc}"
}

# ================================================================================================
#                                            BUILT-INS

builtin_targets+=("help")
function target_help_builtin {
    description="prints this menu"
}
function target_help {
    print_help
}

add_flag 'h' "help" "prints this menu" 0
function flag_name_help {
    if [[ -z ${current_target} ]]; then
        print_help
    else
        print_help ${current_target}
    fi
    exit 0
}

add_flag '-' "help-target" "prints help for a specific target" 0 "target" "string" "prints a target-specific help with more info"
function flag_name_help_target {
    print_help $1
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
    echo "error: $1"
    return $1
}

add_flag 'g' "global" "use the global install of ${APP_NAME}" 0
function flag_name_global {
    echo ${readonly_arguments}
}

function goose_autocomplete {
    return
    # TODO: add pseudo-parsing of supplied arguments so that suggestions can be made
}

add_flag '-' "register-autocompletion" "use this flag to enable autocompletion of ${APP_NAME}" 0
function flag_name_register_autocompletion {
    complete -F goose_autocomplete ${APP_NAME}
    exit 0
}
