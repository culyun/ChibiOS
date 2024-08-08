#!/usr/bin/env bash

set -e

# Curry file name into target and call the main helper script

cd "${0%/*}" ; SCRIPT_PATH="$PWD" ; cd - > /dev/null
SCRIPT_NAME="${0##*/}"
MCU_TARGET="${SCRIPT_NAME##*_}"; MCU_TARGET="${MCU_TARGET%.*}"

exec "${SCRIPT_PATH}/update_mcuconf.sh" "$MCU_TARGET" "$@"
