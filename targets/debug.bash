
description="for debugging dhelper and/or the environment"

PRINT_FLAGS=0

add_flag "h" "help" "prints this menu" 0
function flag_name_help () {
    print_help debug
}

add_flag "-" "print-flags" "print registered flags" 1
function flag_name_print_flags () {
    PRINT_FLAGS=1
}

add_argument "test" "string..." "a test argument"

# declare -A valid_flags
# declare -A valid_flag_names

# declare -a flag_schedule
# declare -a flag_unschedule

function target_debug () {
    [[ ${PRINT_FLAGS} -eq 1 ]] && {
        IFS=';' echo "valid_flags: ${valid_flags[*]}"
        IFS=';' echo "!valid_flags: ${!valid_flags[*]}"
        echo
        IFS=';' echo "valid_flag_names: ${valid_flag_names[*]}"
        IFS=';' echo "!valid_flag_names: ${!valid_flag_names[*]}"
        echo
        IFS=';' echo "flag_schedule: ${flag_schedule[*]}"
        IFS=';' echo "flag_unschedule: ${flag_unschedule[*]}"
    }
    
    error $(eval echo "${ERR_INFO}") "I have oopsed!" 255
}
