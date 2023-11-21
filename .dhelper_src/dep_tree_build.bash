

# ================================================================================================
#                                            GLOBALS

dependency_types=("target" "file")
provider_types=("file")

GENERATE_DAG=0


# ================================================================================================
#                                             FLAGS

add_flag "-" "debug--export-dag" "generates an image of the dependency dag, given the CLI inputs" 0 "dag name" "string" "the filename of the output image"
function flag_name_debug__export_dag () {
    GENERATE_DAG=1
}


# ================================================================================================
#                                             UTILS

# (1: dependency type; 2: dependency name)
function depends () {
    local _type="$1"
    local name="$2"

    [[ x"${_type}" == x"" ]] && caller >&2 && error $(eval echo "${ERR_INFO}") "dependency type not provided!" 255
    [[ ! "${dependency_types[@]}" =~ "${_type}" ]] && {
        caller >&2
        IFS=','
        local __types="(${dependency_types[*]})"
        unset IFS
        error $(eval echo "${ERR_INFO}") "dependency type provided: '${_type}'\nvalid types are: ${__types}" 255
    }
    [[ x"${name}" == x"" ]]  && caller >&2 && error $(eval echo "${ERR_INFO}") "dependency name not provided!" 255

    if [[ "${_type}" == "target" ]]; then # shallow implementation ; TODO: needs deep implementation
        [[ ! -f "targets/${target}.bash" && "$(is_builtin ${target})" == "n" ]] && \
            error $(eval echo "${ERR_INFO}") "Target file 'targets/${target}.bash' not found!" 255

        source "targets/${target}.bash"
    fi

    scrub_flags
}


# (1: provider type; 2: provider name)
function provides () {
    local _type="$1"
    local name="$2"

    [[ x"${_type}" == x"" ]] && caller >&2 && error $(eval echo "${ERR_INFO}") "dependency type not provided!" 255
    [[ ! "${provider_types[@]}" =~ "${_type}" ]] && {
        caller >&2
        IFS=','
        local __types="(${provider_types[*]})"
        unset IFS
        error $(eval echo "${ERR_INFO}") "dependency type provided: '${_type}'\nvalid types are: ${__types}" 255
    }
    [[ x"${name}" == x"" ]]  && caller >&2 && error $(eval echo "${ERR_INFO}") "dependency name not provided!" 255

    # ...

    scrub_flags
}

# recursively loads through target dependencies to check non-target dependencies and constructs a graph
# of the targets to run, and how, to perform the desired behaviour and generate the desired files
# (1: target)
function evaluate_target () {
    return
}
