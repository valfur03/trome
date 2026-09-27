#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../shared-cache.sh"
state=$(mktemp -d)
cache="$state/cache"
failures=0
trap 'kill $(jobs -p) 2> /dev/null || true; rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

wait_for() {
    tries=0
    until eval "$1"; do
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || return 1
        sleep 0.1
    done
}

start_time() {
    ps -o lstart= -p "$1"
}

mark_clearing() {
    mkdir -p "$cache/clearing"
    printf '%s\n' "$2" > "$cache/clearing/$1"
}

expect "a build runs as the registered process" \
    "$("$script" use "$cache" sh -c '[ -f "$1/users/$$" ] && echo registered' _ "$cache")" "registered"

expect "a clear does not wait for a build that ended" \
    "$("$script" clear "$cache" 2> /dev/null)" "Deleted $cache/SDKExplicitPrecompiledModules"

"$script" use "$cache" sleep 30 &
build=$!
wait_for '[ -f "$cache/users/$build" ]'
"$script" clear "$cache" > "$state/clear.out" 2> "$state/clear.err" &
clear=$!
wait_for 'grep -q "Build processes: $build" "$state/clear.err"'
expect "a clear waits for a running build and names its process" \
    "$(grep -c "Build processes: $build" "$state/clear.err")" "1"
kill -9 "$build"
wait "$build" 2> /dev/null || true
wait "$clear"
expect "a clear goes on once the build process is killed" \
    "$(cat "$state/clear.out")" "Deleted $cache/SDKExplicitPrecompiledModules"

sleep 30 &
clearer=$!
mark_clearing "$clearer" "$(start_time "$clearer")"
"$script" use "$cache" echo built > "$state/build.out" 2> "$state/build.err" &
waiting_build=$!
wait_for 'grep -q "is being cleared" "$state/build.err"'
expect "a build waits while a live clear holds the mark" "$(cat "$state/build.out")" ""
expect "a clear refuses to start while another clear runs" \
    "$("$script" clear "$cache" > /dev/null 2>&1 && echo starts || echo refuses)" "refuses"
kill "$clearer"
wait "$clearer" 2> /dev/null || true
wait "$waiting_build"
expect "a build starts once the clear is gone" "$(cat "$state/build.out")" "built"
expect "the mark of a gone clear is removed" "$([ -e "$cache/clearing" ] && echo kept || echo removed)" "removed"

mark_clearing 99999 "Thu Jan  1 00:00:00 1970"
expect "a build does not wait for the mark of a dead clear" \
    "$("$script" use "$cache" echo built 2> /dev/null)" "built"

[ "$failures" -eq 0 ]
