#!/bin/sh
# Tests the choice of test-waits.py in throwaway repos: which unit tests it runs for the test files that a change
# touches, and the bound of the tests that run at once. It runs no test: the runs themselves are make test-waits.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
core="ios/Packages/TROMECore/Tests/TROMECoreTests"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

write() {
    mkdir -p "$(dirname "$repo/$1")"
    printf '%s\n' "$2" > "$repo/$1"
}

chosen() {
    (cd "$repo/ios" && "$scripts/test-waits.py" filter)
}

git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
write "$core/Trains/TrainTests.swift" "struct TrainTests {
    @Test func leaves() {}
}"
write "$core/Trains/StubProvider.swift" "final class StubProvider {}"
write "ios/App/View.swift" "struct View {}"
git -C "$repo" add -A
git -C "$repo" commit -q -m first
git -C "$repo" checkout -q -b task

expect "no changed test file: runs nothing" "$(chosen)" ""

write "ios/App/View.swift" "struct View { let changed = true }"
git -C "$repo" commit -q -am "feat: change the app"
expect "a change of the app only: runs nothing" "$(chosen)" ""

# The tests of a file, each under the type above it: a suite, an extension of another suite in the same file, a test
# with arguments over several lines.
write "$core/Trains/TrainTests.swift" "import Testing

@MainActor
struct TrainTests {
    @Test func leaves() {}

    @Test(.timeLimit(.minutes(1))) func arrives() async {}
}

extension StationTests {
    @Test(arguments: [
        1, 2
    ])
    func shows(count: Int) {}
}"
expect "a changed test file, committed or not: its tests" "$(chosen)" \
    '\.StationTests/shows\(|\.TrainTests/arrives\(|\.TrainTests/leaves\('

git -C "$repo" commit -q -am "test: change the train tests"
write "$core/Stations/StationTests+Map.swift" "extension StationTests {
    @Test func drawsTheMap() {}
}"
expect "a new test file, not added yet: its tests too" "$(chosen)" \
    '\.StationTests/drawsTheMap\(|\.StationTests/shows\(|\.TrainTests/arrives\(|\.TrainTests/leaves\('

rm "$repo/$core/Stations/StationTests+Map.swift"
git -C "$repo" rm -q "$core/Trains/TrainTests.swift"
expect "a deleted test file: runs nothing" "$(chosen)" ""

git -C "$repo" checkout -q -- .
git -C "$repo" reset -q --hard
write "$core/Trains/StubProvider.swift" "final class StubProvider { var calls = 0 }"
expect "a changed fake or helper, which any test may use: every test" "$(chosen)" "all"

# The unit tests of make test and make test-waits run at most as many tests at once as the Mac has cores: when Swift
# Testing starts them all at once, a wait runs out of time on a busy Mac (ios/Makefile).
printf 'show-width:\n\t@echo "$$SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH"\n' > "$state/width.mk"
width=$(cd "$scripts/.." && env -u SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH \
    make -s -f Makefile -f "$state/width.mk" show-width)
expect "the recipes of ios/Makefile run as many unit tests at once as the Mac has cores" "$width" \
    "$(sysctl -n hw.ncpu)"

if [ "$failures" -ne 0 ]; then
    echo "$failures failures"
    exit 1
fi
