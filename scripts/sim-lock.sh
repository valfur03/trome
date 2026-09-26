#!/bin/sh
set -eu

lock=${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}
scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/.." && pwd)
simulator="$scripts/simulator.sh"
poll_seconds=10

usage() {
    echo "Usage: $0 job <command...>   Run a Simulator job with the lock, then shut down the Simulator" >&2
    echo "       $0 open <command...>  Open the Simulator with the lock, and keep both" >&2
    echo "       $0 free               Shut down this folder's Simulator and free its lock" >&2
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
        rm -rf "$lock"
        removed=0
    fi
    rmdir "$lock.reap"
    return "$removed"
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
    echo "$$" > "$lock/pid"
    echo "$root" > "$lock/worktree"
    if [ -n "$waiting" ]; then
        echo "Got the Simulator lock" >&2
    fi
}

release() {
    if [ "$(holder pid)" = "$$" ] || owns_session; then
        rm -rf "$lock"
    fi
}

shut_down_and_release() {
    "$simulator" shutdown || true
    release
}

on_exit_always() {
    status=$?
    trap - EXIT
    shut_down_and_release
    exit "$status"
}

on_exit_if_failed() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        shut_down_and_release
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
        else
            acquire
        fi
        trap on_exit_always EXIT
        "$@"
        ;;
    open)
        [ $# -gt 0 ] || usage
        if owns_session; then
            "$@"
            exit
        fi
        acquire
        trap on_exit_if_failed EXIT
        "$@"
        "$simulator" udid > "$lock/udid"
        rm "$lock/pid"
        ;;
    free)
        shut_down_and_release
        ;;
    *)
        usage
        ;;
esac
