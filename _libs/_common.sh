#!/usr/bin/env bash
#
# Script with common procedures and funtions for shell programming 
# (c) 2013 Jose Riguera <jose.riguera@springer.com>
# Licensed under GPLv3

# LOAD with:
# _COMMON=_common.sh
# if ! [ -f "$_COMMON" ]; then
#     msg="$(date "+%Y-%m-%d %T"): Error $_COMMON not found!"
#     logger -s -p local0.err -t ${0} "$msg"
#     exit 1
# fi
# . $_COMMON

set -e

# Global Variables, If they are not defined, setup with the default values
EXEC_USER=${EXEC_USER:-$USER}
SSH_USER=${SSH_USER:-$USER}
SSH=${SSH:-'ssh -n'}
SSH_OPTIONS=${SSH_OPTIONS:-'ConnectTimeout=30 BatchMode=yes'}
DEBUG=${DEBUG:-'0'}
LOG_PATH=${LOG_PATH:-"/var/log/scripts"}
PROCESS_SECONDS_SHOW=${PROCESS_SECONDS_SHOW:-'10'}
PROCESS_TIME_LIMIT=${PROCESS_TIME_LIMIT:-'60'}

# If script name is not define take this one
PROGRAM=${PROGRAM:-$(basename $0)}
PROGRAM_DIR=$(cd $(dirname "$0"); pwd)
PROGRAM_OPTS=$@
PROGRAM_HOST=$(hostname -s)
PROGRAM_LOG="${LOG_PATH}/${PROGRAM}_${PROGRAM_HOST}_$(date '+%F-%H%M%S').log"
PROGRAM_CONF=""
PROGRAM_LIB="$PROGRAM_DIR/_libs"

# Load Springer base lib
REALPATH=${REALPATH:-$(dirname "$(readlink $PROGRAM)")}
[ ! -z "$REALPATH" ] && PROGRAM_LIB="$REALPATH/_libs" || PROGRAM_LIB="$PROGRAM_DIR/_libs"
_BASE_LIB="$PROGRAM_LIB/_lib.sh"
if ! [ -f "$_BASE_LIB" ]; then
    msg="$(date '+%Y-%m-%d %T'): Error $_BASE_LIB not found!"
    logger -s -p local0.err -t ${PROGRAM} "$msg"
    exit 1
fi
. $_BASE_LIB

# Starting the work ...
__start() {
    local hostfunction
    local programfunction
    local host

    local this=$(hostname -s)

    test -d $LOG_PATH || mkdir -p $LOG_PATH
    debug_log "($$): START, USER=$(id -u -nr)"
    debug_log "($$): PROGRAM=$PROGRAM, PROGRAM_DIR=$PROGRAM_DIR, PROGRAM_OPTS=$PROGRAM_OPTS"
    debug_log "($$): LOG=$PROGRAM_LOG"
    echo "--$PROGRAM $(date '+%Y-%m-%d %T'): ($$): ENV" >> $PROGRAM_LOG
    env >> $PROGRAM_LOG

    find_config_file "$PROGRAM_DIR/$PROGRAM" && . $PROGRAM_CONF
    debug_log "($$): CONF=$PROGRAM_CONF"

    # Runs again all the script with the correct user with sudo
    sudo_check $EXEC_USER
}

# ... and this is the function to finish a shell script automatically
__end() {
    local rc=$?

    if [ -z "$_ENDED" ]; then
        debug_log "($$): END RC=$rc"
        _ENDED=1
        exit $rc
    fi
}

__start
trap_add "__end" EXIT SIGHUP SIGINT SIGQUIT SIGTERM

# set +e

# END
