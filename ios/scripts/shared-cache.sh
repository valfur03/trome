#!/bin/sh
set -eu

# Xcode keys each SDK module of the cache by a hash of the SDK and the compiler flags, and writes each file
# in one step, so many builds can use the cache at once. Only a clear must wait for the builds that use it.
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
    for clearer in "$1"/*; do
        [ -e "$clearer" ] || break
        ! is_alive "$clearer"
        return
    done
    [ -n "$(find "$1" -maxdepth 0 -mmin +1 2> /dev/null)" ]
}

remove_mark_of_gone_clearer() {
    taken="$cache/.clearing.$$"
    rm -rf "$taken"
    mv "$clearing" "$taken" 2> /dev/null || return 0
    if clearer_is_gone "$taken"; then
        rm -rf "$taken"
    elif mkdir "$clearing" 2> /dev/null; then
        mv "$taken"/* "$clearing"/ 2> /dev/null || true
        rm -rf "$taken"
    else
        rm -rf "$taken"
    fi
}

prune_gone_users() {
    for user in "$users"/*; do
        [ -e "$user" ] || continue
        is_alive "$user" || rm -f "$user"
    done
}

register() {
    mkdir -p "$users"
    waiting=
    while :; do
        if [ ! -d "$clearing" ]; then
            record "$users"
            [ -d "$clearing" ] || return 0
            rm -f "$users/$$"
        elif clearer_is_gone "$clearing"; then
            remove_mark_of_gone_clearer
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
    prune_gone_users 2> /dev/null || true
    register
    exec "$@"
}

running_builds() {
    prune_gone_users
    for user in "$users"/*; do
        [ ! -e "$user" ] || printf ' %s' "${user##*/}"
    done
}

release_mark() {
    [ "$(cat "$clearing/$$" 2> /dev/null || true)" = "$(start_time $$)" ] && rm -rf "$clearing"
}

clear_cache() {
    mkdir -p "$cache"
    until mkdir "$clearing" 2> /dev/null; do
        if clearer_is_gone "$clearing"; then
            remove_mark_of_gone_clearer
        else
            echo "The shared build cache ($cache) is already being cleared" >&2
            exit 1
        fi
    done
    record "$clearing"
    trap 'release_mark || true' EXIT
    waiting=
    while builds=$(running_builds) && [ -n "$builds" ]; do
        if [ "$waiting" != "$builds" ]; then
            echo "Waiting for the builds that use the shared build cache to end (new builds wait). Build processes:$builds" >&2
            waiting=$builds
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
