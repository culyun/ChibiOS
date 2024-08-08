#!/usr/bin/env bash

set -e
#set -x

cd "${0%/*}" ; SCRIPT_PATH="$PWD" ; cd - > /dev/null
SCRIPT_NAME="${0##*/}"
CALLERS_WD="$PWD"
LOGGING_ENABLED="TRUE"

###############################################################################

function find_tmp_dir()
{
  local tmpdir

  for tmpdir in "$TMPDIR" "$TMP" /tmp /var/tmp "$PWD" ; do
    test -d "$tmpdir" && break
  done

  echo "$tmpdir"
}

###############################################################################

function print_help()
{
  cat <<- EOF >&2

$SCRIPT_NAME updates Chibios mcuconf.h to the latest schema.

  Usage: $SCRIPT_NAME rootpath <root path>
         $SCRIPT_NAME <configuration file>

EOF
}

###############################################################################

function log() {
  if [[ -z "$LOGGING_ENABLED" ]] ; then
    return
  fi

  declare -a messages
  messages+=("$@")
  cat <<- EOF >&2
$(for message in "${messages[@]}" ; do printf "\e[92m#####    ${message}\n\e[39m"; done)
EOF
}

###############################################################################

function log_error() {
  declare -a messages
  local headline="Error: ${1}"
  shift 1
  messages+=("$headline" "$@")
  cat <<- EOF >&2
$(for message in "${messages[@]}" ; do printf "\e[91m!!!!!    ${message}\n\e[39m"; done)
EOF
}

###############################################################################

function main()
{
  SCRIPT_TMPDIR="$(find_tmp_dir)/${SCRIPT_NAME}"

  trap "clean_up ;" EXIT

  if [[ "$#" < 2 || "$1" == '-h' || "$1" == '--help' ]] ; then
    print_help
    exit 42
  fi

  # 0. Deduce Target IDs
  #
  #    The target name is extracted from the script name and massaged into:
  #      (a) The C preprocessor #define <TARGET>_MCUCONF expected in the mcucconf.h supplied in the script args
  #      (b) The ftl transformation script mcuconf_<target>

  #target="${SCRIPT_NAME##*_}"; target="${target%.*}"
  target="$1"
  shift 1

  target_base="${target%%x*}"

  target_cpp_base="${target_base^^}"
  target_cpp="${target_cpp_base}_MCUCONF"
  target_cpp_sfx="${target##${target_base}}"
  target_cpp_sfx_len=${#target_cpp_sfx}
  target_cpp_alt="${target_cpp_base:0:-${target_cpp_sfx_len}}${target_cpp_sfx}_MCUCONF"

  target_ftl="mcuconf_${target,,}"

  # 1. Parse args

  if [ $# -eq 2 ] ; then

    if [ "$1" != "rootpath" -o ! -d "$2" ] ; then
      exit 2
    fi

    shift 1

  fi

  if [ -d "$1" ] ; then
    conffile=$(find $1 -name "mcuconf.h")
  else
    conffile="$1"
  fi

  # 2. Make sure conffile is readable

  if [ ! -r "$conffile" ] ; then
    log_error "Supplied MCU configuration directory / file \"$1\" does not exist.\n"
    exit 3
  fi

  # 3. Determine absolute conffile path

  cd "${conffile%/*}" ; confdir="$PWD" ; cd - > /dev/null
  conffile="${confdir}/${conffile##*/}"

  # 4. Check that target_cpp is defined in mcuconf.h

  if ! grep -E -q -e "$target_cpp" -e "$target_cpp_alt" "$conffile" ; then

    log_error "Supplied / inferred mcuconf.h does not #define ${target_cpp} OR ${target_cpp_alt}" \
              "Check contents of \"$conffile\""
    exit 4
  fi

  # 5. Setup for processing

  mkdir -p "$SCRIPT_TMPDIR"

  log "Processing: \"$conffile\" ..."

  grep -E -e "#define\s+[a-zA-Z0-9_()]*\s+[^\s]" <<< "$conffile" \
    | sed -r 's/\#define\s+([a-zA-Z0-9_]*)(\([^)]*\))?\s+/\1=/g' > "${SCRIPT_TMPDIR}/values.txt"

  TOOLS_PATH="${SCRIPT_PATH%/*}"

cat <<-EOF > "${SCRIPT_TMPDIR}/conf.fmpp"

outputRoot: ${SCRIPT_TMPDIR}
dataRoot: ${SCRIPT_PATH}

freemarkerLinks: {
    lib: ${TOOLS_PATH}/ftl/libs
}

data : {
  doc:properties (${SCRIPT_TMPDIR}/values.txt)
}

EOF

  set +e

  fmpp -q -C "${SCRIPT_TMPDIR}/conf.fmpp" -S "${TOOLS_PATH}/ftl/processors/conf/${target_ftl}"
  fmpp_result=$?

  set -e

  if [ $fmpp_result -ne 0 ]; then
    log_error "Freemarker transformation failed with $fmpp_result"
    exit 1
  fi

  cp "${SCRIPT_TMPDIR}/mcuconf.h" "$conffile"

  log "Finished ${SCRIPT_NAME} ${target} \"${conffile}\""
}

###############################################################################

function clean_up()
{
  rm -rf "$SCRIPT_TMPDIR"
  cd "$CALLERS_WD" &> /dev/null;
}

###############################################################################

main "$@"
