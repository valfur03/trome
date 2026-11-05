#!/bin/sh
# The commit that a build writes in the Info.plist of the app, for the record of a walk: the short hash of HEAD, with
# -dirty when the app folder has changes that are not committed (a change elsewhere in the repo does not count), and
# no commit at all with no git history. A throwaway repo stands in for the clone.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../build-commit.sh"
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

# run <app folder>: a build of the app of that folder; prints the commit that the Info.plist names, or "none".
run() {
    mkdir -p "$state/build/TROME.app"
    plutil -create xml1 "$state/build/TROME.app/Info.plist"
    env -i PATH="$PATH" HOME="$state" SRCROOT="$1" TARGET_BUILD_DIR="$state/build" INFOPLIST_PATH=TROME.app/Info.plist \
        "$script" > "$state/out" 2>&1
    plutil -extract TROMECommit raw -o - "$state/build/TROME.app/Info.plist" 2>/dev/null || echo none
}

repo="$state/repo"
mkdir -p "$repo/ios/App" "$repo/docs"
echo app > "$repo/ios/App/File.swift"
echo page > "$repo/docs/page.md"
printf '.build/\n' > "$repo/.gitignore"
git -C "$repo" init -q
git -C "$repo" -c user.name=test -c user.email=test@example.com add -A
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm first
head=$(git -C "$repo" rev-parse --short=7 HEAD)

expect "a clean clone names its short hash" "$(run "$repo/ios")" "$head"
mkdir -p "$repo/ios/.build" && echo built > "$repo/ios/.build/out"
expect "an ignored build output is no change" "$(run "$repo/ios")" "$head"
echo other > "$repo/docs/page.md"
expect "a change outside the app folder is no change of the app" "$(run "$repo/ios")" "$head"
echo changed > "$repo/ios/App/File.swift"
expect "a change of the app not committed is told" "$(run "$repo/ios")" "$head-dirty"
git -C "$repo" checkout -q -- ios
echo new > "$repo/ios/App/New.swift"
expect "a new file of the app not committed is told" "$(run "$repo/ios")" "$head-dirty"
rm "$repo/ios/App/New.swift"

worktree="$state/worktree"
git -C "$repo" worktree add -q "$worktree" HEAD
expect "a git worktree names its short hash" "$(run "$worktree/ios")" "$head"

mkdir -p "$state/zip/ios"
expect "a folder with no git history names no commit" "$(run "$state/zip/ios")" none
expect "and the build says so" "$(grep -c 'no git history' "$state/out")" 1

[ "$failures" -eq 0 ] || exit 1
echo "build-commit-test: OK"
