#!/usr/bin/env bash

if [ -z "${BASH}" ]; then
    echo "This script can only run in bash. Exiting..." >&2
    exit 255
fi

declare -g APP_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
declare -g APP_NAME="${0##${APP_PATH}/}"
declare -g PROJECT_PATH="$(pwd)"

[[ "${APP_PATH}" == "${PROJECT_PATH}" && "$1" == "-g" ]] && shift

if [[ "${APP_PATH}" != "${PROJECT_PATH}" && ! -f "${PROJECT_PATH}/${APP_NAME}" ]]; then
    PROJECT_PATH="${APP_PATH}"
fi

if [[ "${APP_PATH}" != "${PROJECT_PATH}" && "$1" == "-g" ]]; then
    echo "Using external ${APP_NAME}..."
    shift
    PROJECT_PATH="${APP_PATH}"
elif [[ "${APP_PATH}" != "${PROJECT_PATH}" && -f "${PROJECT_PATH}/${APP_NAME}" ]]; then
    echo "Using local ${APP_NAME}..."
    ${PROJECT_PATH}/${APP_NAME} $@
    exit $?
fi

if [[ ! -d "${APP_PATH}/.goose" || ! -f "${APP_PATH}/.goose/core.bash" ]]; then
    echo "${PROJECT_PATH}/.goose/core.bash is missing! Critical dependency! Exiting..." >&2
    exit 255
fi
source ${APP_PATH}/.goose/core.bash

if [[ ! -f "${APP_PATH}/.goose/namespace.bash" ]]; then
    echo "${PROJECT_PATH}/.goose/namespace.bash is missing! Critical dependency! Exiting..." >&2
    exit 255
fi
source ${APP_PATH}/.goose/namespace.bash

function init () {
    [[ -f ${PROJECT_PATH}/.env ]] && source ${PROJECT_PATH}/.env
}

function cleanup () {
    return
}

# ================================================================================================
#                                               MAIN
function main () {
    init

    find_root_namespace
    run_namespace

    cleanup
}

main
