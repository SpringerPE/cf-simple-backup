#!/usr/bin/env bash
#
# Script with common procedures and funtions for shell programming
# (c) 2014 Jose Riguera <jose.riguera@springer.com>
# Licensed under GPLv3

# LOAD with:
# _BASE_LIB="$PROGRAM_LIB/_lib.sh"
# if ! [ -f "$_BASE_LIB" ]; then
#     msg="$(date '+%Y-%m-%d %T'): Error $_BASE_LIB not found!"
#     logger -s -p local0.err -t ${PROGRAM} "$msg"
#     exit 1
# fi
# . $_BASE_LIB


# Global Variables
UUENCODE=${UUENCODE:-'uuencode'}
PERL=${PERL:-'perl'}
MAIL=${MAIL:-'mail'}
LOGGER=${LOGGER:-'logger'}
SSH=${SSH:-'ssh -n'}
SSH_OPTIONS=${SSH_OPTIONS:-'ConnectTimeout=30 BatchMode=yes'}

##############################
# Print a message
echo_log() {
   $LOGGER -p local0.notice -t ${PROGRAM} -- "$@"
   echo "--$PROGRAM $(date '+%Y-%m-%d %T'): $@" | tee -a $PROGRAM_LOG
}


##############################
# Print a message without \n at the end
echon_log() {
   $LOGGER -p local0.notice -t ${PROGRAM} -- "$@"
   echo -n "--$PROGRAM $(date '+%Y-%m-%d %T'): $@" | tee -a $PROGRAM_LOG
}


##############################
# error
error_log() {
    $LOGGER -p local0.err -t ${PROGRAM} -- "$@"
    echo "--$PROGRAM $(date '+%Y-%m-%d %T') ERROR: $@" | tee -a $PROGRAM_LOG
}


##############################
# DEBUG
debug_log() {
   $LOGGER -p local0.debug -t ${PROGRAM} -- "$@"
    if [ z"$DEBUG" == z"0" ]; then
        echo "--$PROGRAM $(date '+%Y-%m-%d %T'): $@" >> $PROGRAM_LOG
    else
        echo "--$PROGRAM $(date '+%Y-%m-%d %T'): $@" | tee -a $PROGRAM_LOG
    fi
}


##############################
# Print a message and exit with error
die() {
    error_log "$@"

    exit 1
}


##############################
# Appends a command to a trap
# from http://stackoverflow.com/questions/3338030/multiple-bash-traps-for-the-same-signal/7287873#7287873
# trap_add 'echo "in trap DEBUG"' DEBUG
trap_add() {
    local trap_add_cmd=$1
    shift || error_log "Unable to add to trap ${trap_add_name}"
    for trap_add_name in "$@"; do
        trap -- "$(
            # helper fn to get existing trap command from output
            # of trap -p
            extract_trap_cmd() { printf '%s\n' "$3"; }
            # print existing trap command with newline
            eval "extract_trap_cmd $(trap -p "${trap_add_name}")"
            # print the new trap command
            printf '%s\n' "${trap_add_cmd}"
        )" "${trap_add_name}" || error_log "Unable to add to trap ${trap_add_name}"
    done
}
# set the trace attribute for the above function.  this is
# required to modify DEBUG or RETURN traps because functions don't
# inherit them unless the trace attribute is set
declare -f -t trap_add


##############################
# Check if the running user is the correct user.
# If not rexecute the script with 'su $USER -c'
sudo_check() {
    local user=$1
    local fullname="$PROGRAM_DIR/$PROGRAM"

    if [ $(id -u -nr) != $user ]; then
        debug_log "Running: sudo -i -u $user -- $fullname $@"
        exec sudo -i -p "You are not $user, trying to change to that user with sudo ... type your password: " \
              -u $user -- $fullname $PROGRAM_OPTS
        rvalue=$?
        if [ "$rvalue" != "0" ]; then
            echo_log "You must be $user or have sudo permissions to run this script."
            return 1
        fi
    fi
    return 0
}


#################################
# Load script configuration
# Search for a suitable configuration file for this script.
# This function will check if the given script has an .conf file in the same
# path. If not, it will follow the symlink and try again.
# If there is no config file, it returns failure.
# It also prints the posible scripts names. Example:
# find_config_file $0 > /dev/null && [ -f $CONFIG_FILE ] && . $CONFIG_FILE || die "Can't find conf"
# @sets PROGRAM_CONF
find_config_file() {
    local program=$(basename $1)
    local program_dir=$(cd $(dirname "$1"); pwd)

    local fullname

    # Get config file
    PROGRAM_CONF=$program_dir/$(echo $program | sed 's/.sh$//;s/.ctl$//;s/^[SK][0-9]*//').conf
    debug_log "Looking for configuration file $PROGRAM_CONF ... "

    if [ -f "$PROGRAM_CONF" ]; then
	    debug_log "$PROGRAM_CONF: found!"
	    return 0
    else
  	    debug_log "$PROGRAM_CONF: not found!"
    fi
    # If not, check if script is a link and follow it
    fullname=${program_dir}/${program}
    if [ ! -h $fullname ]; then
        PROGRAM_CONF=''
        return 1
    fi
    find_config_file $(ls -l $fullname | sed 's/.*-> //')
}


#################################
# Internal function to control timeout of a command
_process_timeout() {
    echo -n "(subprocess: > kill -9 $1) "
    kill -9 $1
}


#################################
# Execute a command, displaying output only if there is a failure.
# It also mask some tipical errors
exec_launcher() {
    local logfile="/tmp/${PROGRAM%%.sh}_$$_$(date '+%Y%m%d%H%M%S').out"
    local rvalue=1
    local pid
    local counter
    local wait_time=$PROCESS_TIME_LIMIT
    local end=0

    echo >> $PROGRAM_LOG
    debug_log "Launching: '$@'"
    # Exec process
    (
        echo "* -- START -- PID=$$" >> $logfile
        (
            echo "* Process environment was:" >> $logfile
            env >> $logfile
            echo >> $logfile
            echo "* Command line of pid $$ was:" >> $logfile
            echo "$@" >> $logfile
            echo "* -- $(date) --" >> $logfile
            {
                exec time $@  2>&1;
            } >> $logfile
        ) &
        pid=$!
        trap "_process_timeout $pid" TERM
        wait $pid 2>/dev/null
        rvalue=$?
        echo "* -- END -- RC=$rvalue" >> $logfile
        return $rvalue
    ) &
    pid=$!
    counter=0
    rvalue=1
    for ((counter=0;counter<wait_time;counter++)); do
        if ps -p $pid >/dev/null 2>&1; then
            sleep 1
            [ $(expr $counter % $PROCESS_SECONDS_SHOW) == 0 ] && echo -n '.'
        else
            rvalue=$(tail -n 1 $logfile | sed -n 's/^\* \-\- END \-\- RC=\([0-9]*\)/\1/p')
            if [ -z "$rvalue" ]; then
                wait $pid 2>/dev/null
                rvalue=$?
            fi
            if grep -q "Stack trace : " $logfile; then
                if [ $rvalue == 0 ]; then
                    rvalue=1
                    debug_log "Finished with RC=0, but there are exceptions, RC=1"
                    echo "* -- END -- RC=$rvalue" >> $logfile
                fi
            fi
            break
        fi
    done
    if ps -p $pid >/dev/null 2>&1; then
        echo
        echo_log "Error launching '$@'."
        echo_log "Dumping log file:"
        cat $logfile | tee -a $PROGRAM_LOG
        echo_log "WARNING, after ${wait_time}s, the process '$pid' did not answer."
        echo_log "Maybe it is freezed. Wiping out with 'kill $pid'."
        while ps -p $pid >/dev/null 2>&1; do
            echon_log "> kill -9 $pid "
            kill $pid 2>&1 >> $PROGRAM_LOG
            rvalue=$?
            echo -n "Kill RC=$rvalue."
            wait $pid 2>/dev/null
            rvalue=$?
            echo "RC=$rvalue."
            end=1
            debug_log "Process $pid finished. RC=$rvalue."
            sleep 1
        done
        rvalue=1
    fi
    if [ "$rvalue" == "0" ]; then
        rm -f $logfile
    else
        [ "$end" == 0 ] && debug_log "Fail (RC=$rvalue)."
        echo_log "Details: '$logfile'."
    fi
    debug_log "Finished with RC=$rvalue"
    return $rvalue
}


#################################
# exec command via ssh
exec_sudo_host() {
    local user="$1"; shift
    local server="$1"; shift

    local logfile="/tmp/${PROGRAM%%.sh}_$$_$(date '+%Y%m%d%H%M%S').out"
    local sshoptions=""
    local rvalue

    for o in ${SSH_OPTIONS}; do
        sshoptions="${sshoptions} -o ${o}"
    done

    echo "* -- START -- PID=$$" >> $logfile
    echo "* -- $(date) --" >> $logfile
    if [ $(id -u -nr) != $user ]; then
        echo "* -- sudo -i -u $user -- ${SSH} $sshoptions ${user}@${server} $@ --" >> $logfile
        sudo -i -u "$user" -p "Your are not $user, type your password: " -- \
            $SSH ${sshoptions} ${user}@${server} $@ | tee -a $logfile
        rvalue=${PIPESTATUS[0]}
    else
        echo "* -- $SSH ${sshoptions} ${user}@${server} $@ --" >> $logfile
        $SSH ${sshoptions} ${user}@${server} $@ | tee -a $logfile
        rvalue=${PIPESTATUS[0]}
    fi
    echo "* -- END -- RC=$rvalue" >> $logfile
    if [ "$rvalue" != "0" ]; then
        echo_log "Error connecting through ssh:${user}@${server} $@"
        echo_log "Dumping log file:"
        cat $logfile | tee -a $PROGRAM_LOG
    else
        cat $logfile >> $PROGRAM_LOG
    fi
    rm -f $logfile
    return $rvalue
}


exec_host() {
    local user="$1"; shift
    local server="$1"; shift

    local logfile="/tmp/${PROGRAM%%.sh}_$$_$(date '+%Y%m%d%H%M%S').out"
    local sshoptions=""
    local rvalue

    for o in ${SSH_OPTIONS}; do
        sshoptions="${sshoptions} -o ${o}"
    done

    echo "* -- START -- PID=$$" >> $logfile
    echo "* -- $(date) --" >> $logfile
    echo "* -- ${SSH} ${sshoptions} ${user}@${server} $@ --" >> $logfile
    ${SSH} ${sshoptions} ${user}@${server} $@ | tee -a $logfile
    rvalue=${PIPESTATUS[0]}
    echo "* -- END -- RC=$rvalue" >> $logfile
    if [ "$rvalue" != "0" ]; then
        echo_log "Error connecting through ssh:${user}@${server} $@"
        echo_log "Dumping log file:"
        cat $logfile | tee -a $PROGRAM_LOG
    else
        cat $logfile >> $PROGRAM_LOG
    fi
    rm -f $logfile
    return $rvalue
}


#################################
# exec a process
launch() {
    local logfile="/tmp/${PROGRAM%%.sh}_$$_$(date '+%Y%m%d%H%M%S').out"
    local rvalue

    echo >> $PROGRAM_LOG
    debug_log "Launching: '$@'"
    # Exec process
    echo "* -- START -- PID=$$" >> $logfile
    (
        echo "* Process environment was:" >> $logfile
        env >> $logfile
        echo >> $logfile
        echo "* Command line of pid $$ was:" >> $logfile
        echo "$@" >> $logfile
        echo "* -- $(date) --" >> $logfile
        {
            exec time $@  2>&1;
        } >> $logfile
    ) &
    pid=$!
    wait $pid 2>/dev/null
    rvalue=$?
    echo "* -- END -- RC=$rvalue" >> $logfile
    if [ "$rvalue" != "0" ]; then
        echo_log "Error launching process: $@"
        echo_log "Dumping log file:"
        cat $logfile | tee -a $PROGRAM_LOG
    else
        cat $logfile >> $PROGRAM_LOG
    fi
    rm -f $logfile
    return $rvalue
}


launch_out() {
    local logfile="/tmp/${PROGRAM%%.sh}_$$_$(date '+%Y%m%d%H%M%S').log"
    local rvalue

    echo >> $PROGRAM_LOG
    debug_log "Launching: '$@'"
    # Exec process
    echo "* -- START -- PID=$$" >> $logfile
    (
        echo "* Process environment was:" >> $logfile
        env >> $logfile
        echo >> $logfile
        echo "* Command line of pid $$ was:" >> $logfile
        echo "$@" >> $logfile
        echo "* -- $(date) --" >> $logfile
        {
            exec time $@ ;
        } 2>> $logfile
    ) &
    pid=$!
    wait $pid 2>/dev/null
    rvalue=$?
    echo "* -- END -- RC=$rvalue" >> $logfile
    if [ $rvalue != 0 ]; then
        echo_log "Error launching process: $@"
        echo_log "Dumping log file:"
        cat $logfile | tee -a $PROGRAM_LOG
    else
        cat $logfile >> $PROGRAM_LOG
    fi
    rm -f $logfile
    return $rvalue
}


#################################
# Dumps the last 20 lines of a log file. For information.
dump_log() {
    local i

    for i in $@; do
        echo_log "DUMP $i:"
        tail -n 20 $i | tee -a $PROGRAM_LOG
    done
}


#################################
# Check if the pid in the given file is running
check_pid_in_file() {
    local i

    for i in $@; do
        [ -f "$i" ] && ps -p $(<$i) >/dev/null || return 1
    done
    return 0
}


#################################
# Get pids running in given path. It checks the /proc directory
get_pids_in_path() {
    local cwd=$(echo $1 | sed 's/\/\+/\//g')
    ls -l /proc/*/cwd | sed -n  "s|.*/proc/\(.*\)/cwd -> $dir\$|\1|p" | xargs
}


#################################
# Send a signal to a list of process in a path and wait
killall_by_path() {
    local running_path=$1
    local askfirst=$2

    local signal
    local pids
    local times

    cd /
    pids=$(get_pids_in_path $running_path)
    for signal in TERM KILL; do
        if [ "$pids" ]; then
            if [ "$askfirst" ]; then
                read -p "Kill $pids with signal $signal? (y/N)" a
                [ "$a" == "y" ] || return 1
            fi
            echon_log "Sending $signal signal to pids $pids : "
            times=10
            while [ $times -gt 0 ]; do
                pids=$(get_pids_in_path $running_path)
                [ "$pids" ] || break
                debug_log "Killing $pids ..."
                kill -$signal $pids 2>&1 >> $PROGRAM_LOG || true
                ((times--))
                echo -n "."
                sleep 1
            done
            echo "Ok."
        fi
    done
}


#################################
# Get a list of items.
# For example:
#
# MUREX_SERVICE_LIST() {
# cat <<EOF
# # Service                                 Primary server
# fileserver                                  localhost
# xmlserver                                   localhost
# #mxhibernate                                localhost
# launcherall                                 localhost
# #mandatory                                  localhost
# mxrepository                                localhost
# hubs                                        localhost
# #launcher:launchermxdealscanner_1.mxres     localhost
# launcher:launchermxdealscanner_2.mxres      localhost
# launchermxmlexchangemlcspaces               localhost
# mxmlexchange                                localhost
# EOF
# }
#
# get_list MUREX_SERVICE_LIST
#
get_list() {
    $1 | grep -v -e "^[ \t]*#"
}


#################################
# Get a list in reserve order
get_reverse_list() {
    $1 | grep -v -e "^[ \t]*#" | awk '{ line[NR] = $0 } END { for (i=NR;i>0;i--) print line[i] }'
}


#################################
# time difference between dates: days, hours, min, seconds
diff_dates() {
	local date1=$1
	local date2=$2

	$PERL -e '
		use Time::Local;

		$min = substr($ARGV[0], 10, 2);
		$hour = substr($ARGV[0], 8, 2);
		$mday = substr($ARGV[0], 6, 2);
		$mon =  substr($ARGV[0], 4 ,2);
		$year = substr($ARGV[0], 0 ,4);
		$min = 0 if (not defined $min);
		$hour = 0 if (not defined $hour);
		$time1 = timelocal(0, $min, $hour, $mday, $mon - 1, $year -1900);
		if ($ARGV[1]) {
		    $min = substr($ARGV[1], 10, 2);
		    $hour = substr($ARGV[1], 8, 2);
		    $mday = substr($ARGV[1], 6, 2);
		    $mon =  substr($ARGV[1], 4 ,2);
		    $year = substr($ARGV[1], 0 ,4);
		    $min = 0 if (not defined $min);
		    $hour = 0 if (not defined $hour);
		    $time2 = timelocal(0, $min, $hour, $mday, $mon - 1, $year -1900);
		} else {
		    $time2=time;
		}
		$diff = $time2 - $time1;
		$diff_sec = $diff;
		$diff_min = $diff / 60;
		$diff_hours = $diff_min / 60;
		$diff_days = $diff_hours / 24;
		print "$diff_days $diff_hours $diff_min $diff_sec";
		' "$date1" "$date2"
}


##############################
# send-mail
# For example:
#
# MAIL_MSG() {
# 	cat <<EOF
# Estimado usuario,
#
# Se adjuntan las estadisticas del EOD de Murex solicitadas.
# Informacion de proceso:
#
# EOF
# }
#
# send_mail jriguera@gmail.com Info MAIL_MSG file.bin
#
# or you can use a simple variable:
#
# content="Hola amigo que tal estas ..."
# send_mail jriguera@gmail.com "Personal Subject" $content
#
send_mail() {
    local mailto="$1"
    local subject="$2"
    local msg="$3"
    local bin="$4"

    local rvalue
    (
	type -t $msg > /dev/null && $msg || echo $msg
        echo "--"
        echo "Report from $PROGRAM on $(hostname)"
        echo "--"
        echo "Program Log:"
        cat $PROGRAM_LOG
        [ -z $bin ] || $UUENCODE $bin $bin
    ) | $MAIL -s "$subject" $mailto
    rvalue=$?
    debug_log "Mail sent to $1 (RC=$rvalue)"
    return $rvalue
}


# Misc functions
get_real_path() {
    local f="$1"
    local last

    while [ -n "$f" ]; do
        last=$f;
        f=$(ls -l $f | sed -n 's/.* -> //p');
    done;
    echo $last
}


# Wait until the predicate is true (returns 0)
wait_until() {
    local test="$1"
    local times="$2"
    local wait="$3"

    local counter=0
    debug_log "Waiting until [ $test ] ..."
    for ((counter=0;counter<times;counter++)); do
	    $test 2>&1 >> $PROGRAM_LOG && return 0
	    [ $(expr $counter % $PROCESS_SECONDS_SHOW) == 0 ] && echo -n '.'
        sleep $wait
    done
    debug_log "[ $test ] failed after $times ($wait s. each time)"
    return 1
}


# get a random string
random_str() {
     local chars=$1

     [ -z "$chars" ] && chars=10
     tr -cd '[:alnum:]' < /dev/urandom | head -c${chars}
}


# Self destruction
kill_me() {
   debug_log "Killing me! ..."
   local parent=${PPID}
   kill -9 $parent
   kill -9 $$
}


# EOF

