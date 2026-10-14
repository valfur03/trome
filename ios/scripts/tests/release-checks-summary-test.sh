#!/bin/sh
# The summary of the release checks workflow: a failed check is red by its name, and no later step hides it.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-checks-summary.sh"
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
export RUNNER_TEMP="$state" GITHUB_STEP_SUMMARY="$state/summary.md"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

step() {
    "$script" "$@" > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

row() {
    grep -F "| $1 |" "$GITHUB_STEP_SUMMARY" || echo "no row"
}

expect "a check that passes passes" "$(step run "make check" sh -c 'echo "build: OK (3 s)"; echo; echo "check: OK (2 checks)"')" "exit 0"
expect "its output shows in the log of the step" "$(grep -c 'build: OK' "$state/out")" "1"
expect "its row says passed, with its last line" "$(row "make check" | sed -E 's/\| [0-9.]+ \|/| M |/')" \
    "| make check | passed | M | check: OK (2 checks) |"
expect "the table has its head once" "$(grep -c '^| Check | Outcome' "$GITHUB_STEP_SUMMARY")" "1"

expect "a check that fails fails with its own status" "$(step run "make e2e" sh -c 'echo "e2e: FAILED | see ios/.build/logs/e2e.log \`x\`"; exit 3')" "exit 3"
expect "its row says FAILED, with a last line that stays in its cell" "$(row "make e2e" | sed -E 's/\| [0-9.]+ \|/| M |/')" \
    "| make e2e | **FAILED** (exit 3) | M | e2e: FAILED / see ios/.build/logs/e2e.log x |"
expect "a command that does not exist fails the check" "$(step run "make nothing" "$state/no-such-command")" "exit 127"

echo 100 > "$state/release-checks-start"
expect "the end of the job passes" "$(step end "make check=success" "make server-check=failure" "make e2e=skipped" "make live-activity-render=cancelled" "make release-archive-check=")" "exit 0"
expect "a check that ran gets no second row" "$(grep -c '| make check |' "$GITHUB_STEP_SUMMARY")" "1"
expect "a failed check gets no second row: its own row says it" "$(row "make server-check")" "no row"
expect "a skipped check is not run" "$(row "make e2e" | tail -n 1)" "| make e2e | not run: a step above did not pass |  |  |"
expect "a check with no outcome is not run" "$(row "make release-archive-check")" "| make release-archive-check | not run: a step above did not pass |  |  |"
expect "a cancelled check says it" "$(row "make live-activity-render")" "| make live-activity-render | **cancelled** |  |  |"
expect "the end gives the minutes of the job" "$(grep -c '^The job took [0-9.]* minutes' "$GITHUB_STEP_SUMMARY")" "1"
expect "the table has still one head" "$(grep -c '^| Check | Outcome' "$GITHUB_STEP_SUMMARY")" "1"

expect "a run with no command is refused" "$(step run "make check")" "exit 2"
expect "an unknown mode is refused" "$(step skip "make check")" "exit 2"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "release-checks-summary: all tests passed"
