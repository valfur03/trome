#!/bin/sh
set -eu

lock=${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}
last_job="$lock.last"
watcher="$lock.watcher"
idle_minutes=${RATP_SIM_IDLE_MINUTES:-5}
scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/../.." && pwd)
simulator="$scripts/simulator.sh"
poll_seconds=10
watch_seconds=30

usage() {
    echo "Usage: $0 job <command...>   Run a Simulator job with the lock" >&2
    echo "       $0 open <command...>  Open the Simulator with the lock, and keep the lock" >&2
    echo "       $0 free               Remove the app from the Simulator and free the lock that this folder keeps after 'open'" >&2
    echo "       $0 watch              Shut down the shared Simulators after $idle_minutes minutes with no job" >&2
    exit 1
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

acquire() {
    waiting=
    until mkdir "$lock" 2> /dev/null; do
        if [ ! -e "$lock" ]; then
            sleep 1
            continue
        fi
        if remove_if_stale; then
            continue
        fi
        if [ -z "$waiting" ]; then
            echo "Waiting for the Simulator lock ($lock), held by $(describe_holder)" >&2
            waiting=1
        fi
        sleep "$poll_seconds"
    done
    take
    start_watcher
    if [ -n "$waiting" ]; then
        echo "Got the Simulator lock" >&2
    fi
}

release() {
    if [ "$(holder pid)" = "$$" ] || owns_session; then
        touch "$last_job"
        rm -rf "$lock"
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
        if [ -e "$lock" ]; then
            remove_if_stale 2> /dev/null || touch "$last_job"
        elif ! booted_shared=$("$simulator" booted 2> /dev/null); then
            :
        elif [ -z "$booted_shared" ] || shut_down_if_idle "$booted_shared"; then
            break
        fi
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
        if owns_session; then
            echo "$$" > "$lock/pid"
            start_watcher
        else
            acquire
        fi
        trap on_exit EXIT
        "$@"
        ;;
    open)
        [ $# -gt 0 ] || usage
        if owns_session; then
            echo "$$" > "$lock/pid"
            start_watcher
        else
            acquire
        fi
        trap on_exit_if_failed EXIT
        "$@"
        "$simulator" udid > "$lock/udid"
        rm "$lock/pid"
        ;;
    free)
        if owns_session; then
            session_udid=$(holder udid)
            "$simulator" uninstall "$session_udid" || true
            "$simulator" shutdown-if-not-default "$session_udid" || true
        fi
        release
        ;;
    watch)
        watch
        ;;
    *)
        usage
        ;;
esac
