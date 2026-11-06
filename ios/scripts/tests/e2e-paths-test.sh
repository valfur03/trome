#!/bin/sh
# The path map of the E2E tests (e2e_classes in code-paths.sh, and e2e-paths.txt): which E2E test classes a merge runs.
# It guards a merge that skips the test of a flow that it changed: a changed file of app code with no line in the map
# runs the full suite, and the core checks run at every merge of app code.
# Each case replays the files of a real commit of main (named by its hash) in a throwaway repo, with the real map,
# so the test needs no history; when this clone has the commit, the test checks that the list is the real one.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
root=$(cd "$scripts/../.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
unset TROME_E2E_PATHS || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
. "$scripts/code-paths.sh"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

repo="$state/repo"
git init -q -b main "$repo"
git -C "$repo" commit -q --allow-empty -m base

# Commits a change to each file of $2 (one per line) in the throwaway repo, and prints the classes that a merge of it runs.
# $1 is the real commit whose files these are: when this clone has it, its real list must be the same.
classes_of() {
    if git -C "$root" cat-file -e "$1^{commit}" 2> /dev/null; then
        real=$(git -C "$root" diff --name-only --no-renames "$1^" "$1")
        [ "$real" = "$2" ] || { echo "the files of $1 are not the ones of the test"; return 0; }
    fi
    before=$(git -C "$repo" rev-parse HEAD)
    printf '%s\n' "$2" | while IFS= read -r file; do
        mkdir -p "$repo/$(dirname "$file")"
        echo "$1" >> "$repo/$file"
    done
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$1"
    (cd "$repo" && e2e_classes "$before" HEAD)
}

core="LiveActivityTests AutoLiveActivityTests SnoozeTests"

expect "a docs page alone runs no E2E test (424a6a85)" "$(classes_of 424a6a85 \
'docs/src/content/docs/en/maintain/release-on-the-app-store.mdx')" ""

expect "unit tests alone run no E2E test (5d03577f)" "$(classes_of 5d03577f \
'ios/Packages/TROMECore/Tests/TROMECoreTests/AutoLiveActivity/AutoLiveActivityWakeLogTests.swift
ios/Packages/TROMECore/Tests/TROMECoreTests/AutoLiveActivity/RegionCrossingTimeTests.swift
ios/Packages/TROMECore/Tests/TROMECoreTests/AutoLiveActivity/RegionEventTests.swift')" ""

expect "the widget alone, with its guide page, runs the core checks: the map gives the widget no other class (baadcc5c)" \
    "$(classes_of baadcc5c \
'ios/Widget/PanamStripsHeader.swift
ios/Widget/PanamStripsView.swift
ios/Widget/SielRowsView.swift
ios/guide/live-activity.md')" "$core"

expect "the rules of the automatic Live Activity run the core checks and the tests in the background (97ac29ee)" \
    "$(classes_of 97ac29ee \
'ios/Packages/TROMECore/Sources/TROMECore/AutoLiveActivity/AutoLiveActivityModel.swift
ios/Packages/TROMECore/Tests/TROMECoreTests/AutoLiveActivity/AutoLiveActivityNotificationPermissionTests.swift
ios/guide/auto-live-activity.md')" "$core BackgroundArrivalTests BackgroundPositionTests SwipeAwayTests"

expect "a Makefile, which no line maps, runs the full suite (e63c32db)" "$(classes_of e63c32db \
'.claude/rules/ios-code.md
ios/Makefile
ios/README.md')" "all"

expect "a file that every E2E test shares runs the full suite, even beside a mapped test class (e186c00a)" \
    "$(classes_of e186c00a \
'ios/UITests/E2ETestCase+WakeLog.swift
ios/UITests/SwipeAwayTests.swift')" "all"

expect "a new E2E test class, which has no line yet, runs the full suite" \
    "$(classes_of new-test 'ios/UITests/NewFlowTests.swift')" "all"

expect "a class named by two changed files runs once" "$(classes_of two-files \
'ios/App/TestingTools/WakeLogScreen.swift
ios/UITests/WakeLogClearTests.swift')" "$core BackgroundArrivalTests BackgroundPositionTests SwipeAwayTests WakeLogClearTests"

expect "a diff that git cannot make runs the full suite" "$(cd "$repo" && e2e_classes not-a-commit HEAD 2> /dev/null)" "all"
expect "a map that cannot be read runs the full suite" \
    "$(cd "$repo" && TROME_E2E_PATHS="$state/no-map.txt" e2e_classes HEAD~1 HEAD)" "all"

# A class of the map that no file of ios/UITests/ holds would fail make e2e ONLY=... at each merge that runs it.
unknown=
for class in $core $(sed -e 's/#.*//' "$scripts/e2e-paths.txt" | awk 'NF > 1 { for (i = 2; i <= NF; i++) if ($i != "-") print $i }' | sort -u); do
    grep -qw "class $class: E2ETestCase" "$root/ios/UITests/$class.swift" 2> /dev/null || unknown="$unknown $class"
done
expect "each class of the map and of the core checks is an E2E test class of ios/UITests/" "$unknown" ""

expect "each test class of ios/UITests/ has its own line in the map" \
    "$(for file in "$root"/ios/UITests/*Tests.swift; do grep -q "^ios/UITests/$(basename "$file") " "$scripts/e2e-paths.txt" || echo "$(basename "$file")"; done)" ""

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "e2e-paths-test: all checks passed"
