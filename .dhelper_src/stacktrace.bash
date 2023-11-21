
source '.dhelper_src/preexec.bash'
install_preexec

source '.dhelper_src/structs.bash'

# ================================================================================================
#                                            GLOBALS

CALL_STACK=()
CURRENT_FUNCTION=""


# ================================================================================================
#                                              UTILS

function preexec () { # used by '.dhelper_src/preexec.bash'
    CURRENT_FUNCTION=$1
    echo ${CURRENT_FUNCTION}
    buffer_push CALL_STACK "${*@Q}"
}

function postexec () {
    if [[ x"$1" != x"${CURRENT_FUNCTION}" ]]; then
        echo "Houston, we have a problem! postexec:in does not match CURRENT_FUNCTION. '$1' != '${CURRENT_FUNCTION}'" >&2
        exit 255
    fi

    stack_pop CALL_STACK
}

function print_stacktrace () {
    for call in "${CALL_STACK[@]}"; do
        echo "    -> ${call}"
    done
}

