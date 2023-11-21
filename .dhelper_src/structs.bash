

# (1: array name (global))
function arr_max_value () {
    [[ -z "$1" ]]           && error $(eval echo "${ERR_INFO}") "Array name is empty!" 80
    local arr_declare="$(declare -p "$1" 2>/dev/null)"
    [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]]                                            \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' does not exist!" 81
    [[ ! -v "$1"    || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]    \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' is not an array!" 82
    local -n arr="$1"
    local max_value=${arr[0]}

    for item in "${arr[@]}"; do
        [[ ! $2 =~ ^-?[0-9]+$ ]]  && error $(eval echo "${ERR_INFO}") "value '$2' is not a valid number!" 83
        max_value=$(( ${item} > ${max_value} ? ${item} : ${max_value} ))
    done
    echo ${max_value}
}

# (1: array name (global); 2: index to pop)
function arr_pop () {
    [[ -z "$1" ]] && error $(eval echo "${ERR_INFO}") "Array name is empty!" 90

    local arr_declare="$(declare -p "$1" 2>/dev/null)"

    [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]] && \
        error $(eval echo "${ERR_INFO}") "Variable '$1' does not exist or is empty!" 91

    [[ ! -v "$1"    || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]] && \
        error $(eval echo "${ERR_INFO}") "Variable '$1' is not an array!" 92

    [[ ! $2 =~ ^[0-9]+$ ]]  && \
        error $(eval echo "${ERR_INFO}") "Index '$2' is not a valid number!" 93

    [[ ! -v $1[$2] ]]       && \
        error $(eval echo "${ERR_INFO}") "Array element at index $2 does not exist!" 94

    eval "$1=(\${$1[@]:0:$2} \${$1[@]:$2+1})"
}

# (1: array name (global); 2: value to push)
function buffer_push () {
    [[ x"$1" == x"" ]]      && error $(eval echo "${ERR_INFO}") "Array name is empty!" 80
    local arr_declare="$(declare -p "$1" 2>/dev/null)"
    [[ "${arr_declare}" != "declare"* ]]                                            \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' does not exist!" 81
    [[ "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]    \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' is not an array!" 82

    local buffer=($(eval "echo $1[@]"))
    eval "$1=($2 ${buffer[@]})"
}

# (1: array name (global))
function stack_pop () {
    [[ -z "$1" ]]           && error $(eval echo "${ERR_INFO}") "Array name is empty!" 80
    local arr_declare="$(declare -p "$1" 2>/dev/null)"
    [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]]                                            \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' does not exist!" 81
    [[ ! -v "$1"    || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]    \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' is not an array!" 82

    local pop_val=$(eval "$1[0]")
    arr_pop $1 0
    echo "${pop_val}"
}

# (1: array name (global))
function queue_pop () {
    [[ -z "$1" ]]           && error $(eval echo "${ERR_INFO}") "Array name is empty!" 80
    local arr_declare="$(declare -p "$1" 2>/dev/null)"
    [[ -z "${!1+x}" || "${arr_declare}" != "declare"* ]]                                            \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' does not exist!" 81
    [[ ! -v "$1"    || "${arr_declare}" != "declare -a"* && "${arr_declare}" != "declare -A"* ]]    \
                            && error $(eval echo "${ERR_INFO}") "Variable '$1' is not an array!" 82

    local buffer=($(eval "$1[@]"))
    local buffer_len=$(( ${#buffer[@]} - 1 ))
    local pop_val="${buffer[buffer_len]}"
    arr_pop $1 ${buffer_len}
    echo "${pop_val}"
}
