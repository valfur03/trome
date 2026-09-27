#!/bin/sh
set -eu

base_lock=${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}
watcher="$base_lock.slots-watcher"
slots=${RATP_SIM_SLOTS:-1}
min_idle_percent=${RATP_SIM_MIN_IDLE_PERCENT:-25}
idle_minutes=${RATP_SIM_IDLE_MINUTES:-5}
poll_seconds=${RATP_SIM_POLL_SECONDS:-10}
scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/../.." && pwd)
simulator="$scripts/simulator.sh"
watch_seconds=30
held_slots=

case "$slots" in
    "" | *[!0-9]* | 0)
        echo "Unknown RATP_SIM_SLOTS: $slots (use 1 or more)" >&2
        exit 1
        ;;
esac

usage() {
    echo "Usage: $0 job <command...>   Run a Simulator job with the lock of a free Simulator slot" >&2
    echo "       $0 open <command...>  Open the Simulator with the lock of a free slot, and keep the lock" >&2
    echo "       $0 free               Remove the app from the Simulator and free the lock that this folder keeps after 'open'" >&2
    echo "       $0 all <command...>   Run a command with the locks of every slot (waits until no other job runs)" >&2
    echo "       $0 udid               Print the ID of the Simulator that this folder keeps after 'open', or of the Simulator of slot 1" >&2
    echo "       $0 watch              Shut down the shared Simulators of each slot after $idle_minutes minutes with no job" >&2
    echo "At most $slots Simulator jobs run at once (RATP_SIM_SLOTS). A job runs next to another one only when the CPU is at least $min_idle_percent% idle (RATP_SIM_MIN_IDLE_PERCENT)." >&2
    exit 1
}

all_slots() {
    seq 1 "$slots"
}

use_slot() {
    RATP_SIM_SLOT=$1
    export RATP_SIM_SLOT
    if [ "$1" -eq 1 ]; then
        lock=$base_lock
    else
        lock="$base_lock.$1"
    fi
    last_job="$lock.last"
}

holder() {
    cat "$lock/$1" 2> /dev/null || true
}

is_booted() {
    booted=$(xcrun simctl list devices booted) || return 0
    printf '%s\n' "$booted" | grep -qF "($1)"
}

is_stale() {
    pid=$(holder pid)
    udid=$(holder udid)
    if [ -n "$pid" ]; then
        ! kill -0 "$pid" 2> /dev/null
    elif [ -n "$udid" ]; then
        [ ! -d "$(holder worktree)" ] || ! is_booted "$udid"
    else
        return 1
    fi
}

describe_holder() {
    worktree=$(holder worktree)
    pid=$(holder pid)
    if [ -n "$pid" ]; then
        echo "a job in $worktree (PID $pid)"
    elif [ -n "$(holder udid)" ]; then
        echo "the open Simulator of $worktree (run 'make simulator-shutdown' there to free it)"
    else
        echo "an agent that took it by hand${worktree:+ ($worktree)}"
    fi
}

owns_session() {
    [ -z "$(holder pid)" ] && [ -n "$(holder udid)" ] && [ "$(holder worktree)" = "$root" ]
}

find_session() {
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if owns_session; then
            return 0
        fi
    done
    return 1
}

remove_if_stale() {
    find "$lock.reap" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2> /dev/null || true
    mkdir "$lock.reap" 2> /dev/null || return 1
    removed=1
    if is_stale; then
        echo "Removing a stale Simulator lock of $(holder worktree)" >&2
        touch "$last_job"
        rm -rf "$lock"
        removed=0
    fi
    rmdir "$lock.reap"
    return "$removed"
}

take() {
    echo "$$" > "$lock/pid"
    echo "$root" > "$lock/worktree"
    held_slots="$held_slots $RATP_SIM_SLOT"
}

join_session() {
    echo "$$" > "$lock/pid"
    held_slots="$held_slots $RATP_SIM_SLOT"
}

watcher_is_running() {
    watcher_pid=$(cat "$watcher" 2> /dev/null || true)
    [ -n "$watcher_pid" ] && ps -p "$watcher_pid" -o command= 2> /dev/null | grep -qF "sim-lock.sh watch"
}

start_watcher() {
    if ! watcher_is_running; then
        perl -MPOSIX -e 'setsid(); exec @ARGV' "$scripts/sim-lock.sh" watch < /dev/null > /dev/null 2>&1 &
    fi
}

cpu_idle_percent() {
    idle=$(top -l 2 -n 0 -s 1 2> /dev/null | sed -n -E 's/^CPU usage:.* ([0-9]+)(\.[0-9]*)?% idle.*/\1/p' | tail -n 1)
    echo "${idle:-0}"
}

try_to_take_a_slot() {
    free_slots=
    busy=
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if [ ! -e "$lock" ] || remove_if_stale; then
            free_slots="$free_slots $candidate"
        else
            busy="$busy${busy:+; }slot $candidate: $(describe_holder)"
        fi
    done
    if [ -z "$free_slots" ]; then
        wait_kind=busy
        wait_reason="every Simulator slot is busy ($busy)"
        return 1
    fi
    if [ -n "$busy" ]; then
        idle=$(cpu_idle_percent)
        if [ "$idle" -lt "$min_idle_percent" ]; then
            wait_kind=cpu
            wait_reason="a Simulator slot is free, but the CPU is only $idle% idle, and a job next to another one needs $min_idle_percent% ($busy)"
            return 1
        fi
    fi
    set -- $free_slots
    use_slot "$1"
    if mkdir "$lock" 2> /dev/null; then
        return 0
    fi
    wait_kind=race
    return 1
}

acquire() {
    said=
    until try_to_take_a_slot; do
        if [ "$wait_kind" = race ]; then
            sleep 1
            continue
        fi
        if [ "$wait_kind" != "$said" ]; then
            echo "Waiting for the Simulator lock: $wait_reason" >&2
            said=$wait_kind
        fi
        sleep "$poll_seconds"
    done
    take
    start_watcher
    if [ -n "$said" ]; then
        echo "Got the Simulator lock (slot $RATP_SIM_SLOT)" >&2
    fi
}

acquire_slot() {
    said=
    until mkdir "$lock" 2> /dev/null; do
        if [ ! -e "$lock" ]; then
            sleep 1
            continue
        fi
        if remove_if_stale; then
            continue
        fi
        if [ -z "$said" ]; then
            echo "Waiting for the Simulator lock of slot $RATP_SIM_SLOT, held by $(describe_holder)" >&2
            said=1
        fi
        sleep "$poll_seconds"
    done
    take
}

enter() {
    if find_session; then
        join_session
        start_watcher
    else
        acquire
    fi
}

release() {
    released=
    for held in $held_slots; do
        use_slot "$held"
        if [ "$(holder pid)" = "$$" ] || owns_session; then
            touch "$last_job"
            rm -rf "$lock"
            released=1
        fi
    done
    held_slots=
    if [ -n "$released" ]; then
        start_watcher
    fi
}

is_idle() {
    if [ ! -e "$last_job" ]; then
        touch "$last_job"
    fi
    [ -n "$(find "$last_job" -mmin +"$idle_minutes" 2> /dev/null)" ]
}

shut_down_if_idle() {
    is_idle && mkdir "$lock" 2> /dev/null || return 1
    take
    for booted_udid in $1; do
        xcrun simctl shutdown "$booted_udid" 2> /dev/null || true
    done
    rm -rf "$lock"
}

watch() {
    echo "$$" > "$watcher"
    trap 'if [ "$(cat "$watcher" 2> /dev/null)" = "$$" ]; then rm -f "$watcher"; fi' EXIT
    while :; do
        active=
        for candidate in $(all_slots); do
            use_slot "$candidate"
            if [ -e "$lock" ]; then
                remove_if_stale 2> /dev/null || touch "$last_job"
                active=1
            elif ! booted_shared=$("$simulator" booted 2> /dev/null); then
                active=1
            elif [ -n "$booted_shared" ] && ! shut_down_if_idle "$booted_shared"; then
                active=1
            fi
        done
        [ -n "$active" ] || break
        sleep "$watch_seconds"
    done
}

on_exit() {
    status=$?
    trap - EXIT
    release
    exit "$status"
}

on_exit_if_failed() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        release
    fi
    exit "$status"
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

command=${1:-}
[ $# -gt 0 ] && shift

case "$command" in
    job)
        [ $# -gt 0 ] || usage
        enter
        trap on_exit EXIT
        "$@"
        ;;
    open)
        [ $# -gt 0 ] || usage
        enter
        trap on_exit_if_failed EXIT
        "$@"
        "$simulator" udid > "$lock/udid"
        rm "$lock/pid"
        ;;
    free)
        if find_session; then
            held_slots=$RATP_SIM_SLOT
            session_udid=$(holder udid)
            "$simulator" uninstall "$session_udid" || true
            "$simulator" shutdown-if-not-default "$session_udid" || true
            release
        fi
        ;;
    all)
        [ $# -gt 0 ] || usage
        trap on_exit EXIT
        for candidate in $(all_slots); do
            use_slot "$candidate"
            if owns_session; then
                join_session
            else
                acquire_slot
            fi
        done
        start_watcher
        "$@"
        ;;
    udid)
        if find_session; then
            holder udid
        else
            use_slot 1
            "$simulator" udid
        fi
        ;;
    watch)
        watch
        ;;
    *)
        usage
        ;;
esac
