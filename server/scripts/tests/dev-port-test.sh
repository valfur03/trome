#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

port_in() {
    mkdir -p "$state/$1/server/scripts"
    git -C "$state/$1" init -q
    cp "$scripts/dev-port.sh" "$state/$1/server/scripts/"
    "$state/$1/server/scripts/dev-port.sh"
}

expect "the main folder uses 8787" "$(port_in ratp-activity-ios)" "8787"
expect "the worktree of a task adds its number" "$(port_in task-187)" "8974"
expect "two worktrees get two ports" "$(port_in task-12)" "8799"
expect "a leading zero is not read as octal" "$(port_in task-019)" "8806"

[ "$failures" -eq 0 ]
