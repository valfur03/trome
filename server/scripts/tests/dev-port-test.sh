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

main="$state/ratp-activity-ios"
mkdir -p "$main/server/scripts"
git -C "$main" init -q -b main
git -C "$main" config user.email test@example.com
git -C "$main" config user.name test
cp "$scripts/dev-port.sh" "$main/server/scripts/"
git -C "$main" add -A
git -C "$main" commit -q -m init

port_in() {
    "$1/server/scripts/dev-port.sh"
}

worktree() {
    git -C "$main" worktree add -q -b "branch-$1" "$state/worktrees/$1"
    port_in "$state/worktrees/$1"
}

expect "the main folder uses 8787" "$(port_in "$main")" "8787"
expect "the worktree of a task adds its number" "$(worktree task-187)" "8974"
expect "two worktrees get two ports" "$(worktree task-12)" "8799"
expect "a leading zero is not read as octal" "$(worktree task-019)" "8806"

qa=$(worktree qa)
expect "a worktree with no number at its end does not use 8787" "$([ "$qa" != 8787 ] && echo yes || echo no)" "yes"
expect "it gets a port above the ports of the task numbers" "$([ "$qa" -ge 9800 ] && [ "$qa" -lt 9900 ] && echo yes || echo no)" "yes"
expect "it gets the same port each time" "$(port_in "$state/worktrees/qa")" "$qa"
expect "a worktree that ends with 0 does not use 8787" "$([ "$(worktree task-0)" != 8787 ] && echo yes || echo no)" "yes"

mv "$main" "$state/ratp-activity-ios2"
git -C "$state/ratp-activity-ios2" worktree repair > /dev/null 2>&1 || true
expect "a main folder whose name ends with a number still uses 8787" "$(port_in "$state/ratp-activity-ios2")" "8787"

[ "$failures" -eq 0 ]
