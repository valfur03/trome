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

repo="$state/repo"
mkdir -p "$repo/server/scripts" "$repo/contracts/prim" "$repo/ios"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
cp "$scripts/server-changed.sh" "$repo/server/scripts/"
echo a > "$repo/contracts/prim/a.json"
echo a > "$repo/ios/a.swift"
git -C "$repo" add -A
git -C "$repo" commit -q -m init
git -C "$repo" switch -q -c task/1

changed() {
    "$repo/server/scripts/server-changed.sh" main 2> /dev/null && echo "changed" || echo "unchanged"
}

expect "a branch with no change" "$(changed)" "unchanged"

echo b > "$repo/ios/a.swift"
git -C "$repo" commit -q -am ios
expect "a change of the app only" "$(changed)" "unchanged"

echo b > "$repo/contracts/prim/a.json"
expect "a change of contracts/ that is not committed" "$(changed)" "changed"
git -C "$repo" commit -q -am contracts
expect "a committed change of contracts/" "$(changed)" "changed"

git -C "$repo" switch -q main
git -C "$repo" switch -q -c task/2
echo x > "$repo/server/new.ts"
expect "a new file in server/" "$(changed)" "changed"

[ "$failures" -eq 0 ]
