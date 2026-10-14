#!/bin/sh
# The summary of the release checks workflow: a failed check is red by its name, and no later step hides it.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-checks-summary.sh"
root=$(cd "$tests/../../.." && pwd)
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

# The real path of the workflow: each step is the root make, which runs make again in ios/ (or server/).
# Its parts here print what their real recipes print on a failure, and the root Makefile is the real one.
mkdir -p "$state/repo/ios" "$state/repo/server"
cp "$root/Makefile" "$state/repo/Makefile"
esc=$(printf '\033')
cat > "$state/repo/ios/Makefile" << 'EOF2'
check:
	@echo "lint: OK (1 s)"
	@echo "unit-tests: FAILED: LineBadgeViewTests, run make test"
	@exit 1
live-activity-render:
	@echo "Renders: 120 (every station and page). Images: 240, in /tmp/render/fr"
	@echo "Too tall for their text size: 3 (list: /tmp/render/fr/too-tall.csv)"
	@echo "  4 sp p1 (limit 160 pt)"
	@echo "Cut texts in the images (OCR, for a person to read): 12 (list: /tmp/render/fr/cut-texts.txt)"
	@echo "Breaches of the cut rules (texts cut too much), in the images of 40 stations: 2 (list: /tmp/render/fr/breaches.txt)"
	@echo "  Destination: Porte de ... | 1 p1 lock 375 | a.png"
	@echo "Simulator time of the render: 12 s"
EOF2
printf 'server-check:\n\t@printf "%s[31mFAIL%s[39m test/core/time/paris-time.test.ts > parisDay\\n"\n\t@exit 1\n' "$esc" "$esc" > "$state/repo/server/Makefile"
in_repo() {
    (cd "$state/repo" && "$script" "$@") > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

expect "the root make check fails" "$(in_repo run "root check" make check)" "exit 2"
expect "its row gives the line that says what failed, not the error line of make" \
    "$(row "root check" | sed -E 's/\| [0-9.]+ \|/| M |/')" \
    "| root check | **FAILED** (exit 2) | M | unit-tests: FAILED: LineBadgeViewTests, run make test |"
expect "the root make server-check fails" "$(in_repo run "root server-check" make server-check)" "exit 2"
expect "its row has no colour code" "$(row "root server-check" | sed -E 's/\| [0-9.]+ \|/| M |/')" \
    "| root server-check | **FAILED** (exit 2) | M | FAIL test/core/time/paris-time.test.ts > parisDay |"
expect "a report that runs passes" "$(in_repo report "root render" '^(Too tall|Cut texts|Breaches)' make live-activity-render)" "exit 0"
expect "its row says it ran as a report, with its counts" "$(row "root render" | sed -E 's/\| [0-9.]+ \|/| M |/')" \
    "| root render | ran: a report, not a gate | M | Too tall for their text size: 3; Cut texts in the images (OCR, for a person to read): 12; Breaches of the cut rules (texts cut too much), in the images of 40 stations: 2 |"
expect "a report that cannot run fails, with its cause" "$(in_repo report "root render, no target" '^Too tall' make no-such-target)" "exit 2"
expect "its row says FAILED" "$(row "root render, no target" | cut -d '|' -f 3)" " **FAILED** (exit 2) "

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
