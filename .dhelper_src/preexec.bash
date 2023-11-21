

[[ ${PREEXEC_INSTALLED} -eq 1 ]] && return

declare -a preexec_functions=("preexec")
declare -a postexec_functions=("postexec")

declare -g IN_PREEXEC=0

function debug_handler () {
    local preexec_opts=(${BASH_COMMAND@Q})

    [[ x"$(type -t $1)" != x"function" || ${IN_PREEXEC} -eq 1 ]] && return

    IN_PREEXEC=1

    local calls_good=1
    for preexec_func in "${preexec_functions[@]}"; do
        [[ x"$(type -t ${preexec_func})" != x"function" ]] && continue

        ${preexec_func} ${preexec_opts[@]} || calls_good=0
    done

    if [[ ${calls_good} -eq 1 ]]; then
        IN_PREEXEC=0
        $( ${preexec_opts[@]} )
        IN_PREEXEC=1
    fi

    for postexec_func in "${postexec_functions[@]}"; do
        [[ x"$(type -t ${postexec_func})" != x"function" ]] && continue

        ${postexec_func} ${preexec_opts[@]}
    done

    return 1
}

function install_preexec () {
    shopt -sq extdebug
    trap 'debug_handler' DEBUG
    declare -g PREEXEC_INSTALLED=1
}

