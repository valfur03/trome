#!/bin/sh
set -eu

poll_seconds=1

usage() {
    echo "Usage: $0 use <cache folder> <command...>  Run a build that uses the shared build cache" >&2
    echo "       $0 clear <cache folder>             Delete the shared build cache once no build uses it" >&2
    exit 1
}

[ $# -ge 2 ] && [ -n "$2" ] || usage
command=$1
cache=$2
shift 2

modules="$cache/SDKExplicitPrecompiledModules"
users="$cache/users"
clearing="$cache/clearing"

start_time() {
    ps -o lstart= -p "$1" 2> /dev/null || true
}

record() {
    start_time $$ > "$1/.$$" && mv -f "$1/.$$" "$1/$$"
}

is_alive() {
    recorded=$(cat "$1" 2> /dev/null || true)
    [ -n "$recorded" ] && [ "$(start_time "${1##*/}")" = "$recorded" ]
}

clearer_is_gone() {
    for clearer in "$clearing"/*; do
        [ -e "$clearer" ] || break
        ! is_alive "$clearer"
        return
    done
    [ -n "$(find "$clearing" -maxdepth 0 -mmin +1 2> /dev/null)" ]
}

register() {
    mkdir -p "$users"
    waiting=
    while :; do
        if [ ! -d "$clearing" ]; then
            record "$users"
            [ -d "$clearing" ] || return 0
            rm -f "$users/$$"
        elif clearer_is_gone; then
            rm -rf "$clearing"
            continue
        fi
        if [ -z "$waiting" ]; then
            echo "Waiting: the shared build cache ($cache) is being cleared" >&2
            waiting=1
        fi
        sleep "$poll_seconds"
    done
}

use() {
    [ $# -gt 0 ] || usage
    trap 'rm -f "$users/$$"' EXIT
    register
    "$@"
}

builds_running() {
    running=1
    for user in "$users"/*; do
        [ -e "$user" ] || continue
        if is_alive "$user"; then
            running=0
        else
            rm -f "$user"
        fi
    done
    return "$running"
}

clear_cache() {
    mkdir -p "$cache"
    until mkdir "$clearing" 2> /dev/null; do
        if clearer_is_gone; then
            rm -rf "$clearing"
        else
            echo "The shared build cache ($cache) is already being cleared" >&2
            exit 1
        fi
    done
    trap 'rm -rf "$clearing"' EXIT
    record "$clearing"
    waiting=
    while builds_running; do
        if [ -z "$waiting" ]; then
            echo "Waiting for the builds that use the shared build cache to end (new builds wait)" >&2
            waiting=1
        fi
        sleep "$poll_seconds"
    done
    rm -rf "$modules"
    echo "Deleted $modules"
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$command" in
    use) use "$@" ;;
    clear) [ $# -eq 0 ] || usage; clear_cache ;;
    *) usage ;;
esac
