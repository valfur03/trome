#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
ios=$(cd "$scripts/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
# The make commands below go through the build gate. The gate of the Mac is shared with every worktree: a test run or a
# build of another worktree would add its wait line to the output, and a test run here would stop their builds.
# Its waits go to a log folder of its own: a made-up wait in the log of the Mac would make its wait measures look busier.
export RATP_BUILD_GATE="$state/gate" TROME_LOGS="$state/trome-logs"
unset RATP_BUILD_GATE_HELD

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

quiet() {
    (cd "$state" && "$scripts/quiet.sh" "$@") > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

lines() {
    wc -l < "$state/out" | tr -d ' '
}

has() {
    grep -c -F -- "$1" "$state/out" || true
}

cat > "$state/step.sh" << 'EOF'
#!/bin/sh
noise() {
    i=0
    while [ "$i" -lt 2000 ]; do
        echo "noise line $i"
        i=$((i + 1))
    done
}
noise
echo "Test run with 653 tests in 45 suites passed after 5.5 seconds."
if [ "$1" = fail ]; then
    echo "App/Foo.swift:12:5: error: cannot find 'bar' in scope" >&2
    noise
    exit 65
fi
EOF
chmod +x "$state/step.sh"

expect "a pass succeeds" "$(quiet logs/unit-tests.log 'Test run with' ./step.sh pass)" "exit 0"
expect "a pass prints one line: the step, the time and the counts" \
    "$(lines) $(sed -E 's/\([0-9]+ s\)/(N s)/' "$state/out")" "1 unit-tests: OK (N s): Test run with 653 tests in 45 suites passed after 5.5 seconds."
expect "a pass keeps the whole output in the log file" "$(wc -l < "$state/logs/unit-tests.log" | tr -d ' ')" "2001"
quiet logs/lint.log '' ./step.sh pass > /dev/null
expect "a pass with no pattern prints only the step, the result and the time" "$(sed -E 's/\([0-9]+ s\)/(N s)/' "$state/out")" "lint: OK (N s)"

expect "a failure keeps the exit status of the command" "$(quiet logs/build.log '' ./step.sh fail)" "exit 65"
expect "a failure prints the line that explains it, even in the middle of a long output on stderr" \
    "$(has "App/Foo.swift:12:5: error: cannot find 'bar' in scope")" "1"
expect "a failure prints the whole output of the command, cut nowhere" "$(lines)" "4003"
expect "the last line of a failure names the step, the log file and VERBOSE=1" \
    "$(tail -1 "$state/out" | sed -E 's/, [0-9]+ s\)/, N s)/')" \
    "build: FAILED (exit 65, N s). The whole output is above, and in logs/build.log; VERBOSE=1 prints it as it runs."

expect "VERBOSE=1 keeps the exit status" "$(VERBOSE=1 quiet logs/build.log '' ./step.sh fail)" "exit 65"
expect "VERBOSE=1 prints the output of the command as it is, with no line of its own" "$(lines) $(has 'FAILED')" "4002 0"

mkdir "$state/bin" "$state/cache"
cat > "$state/bin/swiftlint" << 'EOF'
#!/bin/sh
[ "${FAKE:-}" = fail ] || exit 0
echo "/x/App/Foo.swift:3:1: error: Line Length Violation: Line should be 120 characters or less (line_length)"
exit 2
EOF
cat > "$state/bin/swift" << 'EOF'
#!/bin/sh
echo "Building for debugging..."
echo "◇ Test run started."
if [ "${FAKE:-}" = fail ]; then
    echo "✘ Test \"the snooze ends at the next train\" recorded an issue at SnoozeTests.swift:42:9: Expectation failed: (minutes → 3) == 4"
    echo "✘ Test run with 653 tests in 45 suites failed after 5.5 seconds with 1 issue."
    exit 1
fi
echo "✔ Test run with 653 tests in 45 suites passed after 5.5 seconds."
EOF
cat > "$state/bin/xcodebuild" << 'EOF'
#!/bin/sh
result=""
previous=""
for argument in "$@"; do
    [ "$previous" != -resultBundlePath ] || result=$argument
    previous=$argument
done
[ -z "$result" ] || mkdir -p "$result"
echo "2026-10-04 18:23:26.414 xcodebuild[1:2] [MT] IDELaunchParametersSnapshot: no debugger version"
case "${FAKE:-}" in
    fail-build)
        echo "/x/App/Foo.swift:12:5: error: cannot find 'bar' in scope"
        exit 65 ;;
    fail-e2e)
        [ "$previous" != build-for-testing ] || exit 0
        printf 'Failing tests:\n\tSnoozeTests.testSnooze()\n\n** TEST EXECUTE FAILED **\n'
        exit 65 ;;
esac
EOF
cat > "$state/bin/xcrun" << 'EOF'
#!/bin/sh
case "$*" in
    "xcresulttool get build-results"*) echo '{"warnings": [], "analyzerWarnings": []}' ;;
    "xcresulttool get test-results summary"*)
        if [ "${FAKE:-}" = fail-e2e ]; then
            echo '{"result": "Failed", "totalTestCount": 3, "passedTests": 2, "failedTests": 1, "skippedTests": 0, "startTime": 100.0, "finishTime": 340.0}'
        else
            echo '{"result": "Passed", "totalTestCount": 3, "passedTests": 3, "failedTests": 0, "skippedTests": 0, "startTime": 100.0, "finishTime": 340.0}'
        fi ;;
    "xcresulttool get test-results tests"*)
        if [ "${FAKE:-}" = fail-e2e ]; then
            echo '{"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "SnoozeTests/testSnooze()", "children": [{"nodeType": "Failure Message", "name": "The next lines did not show.", "sourceLocation": {"filePath": "/x/UITests/SnoozeTests.swift", "lineNumber": 42}}]}]}'
        else
            echo '{"testNodes": []}'
        fi ;;
    *) exit 1 ;;
esac
EOF
cat > "$state/bin/pmset" << 'EOF'
#!/bin/sh
exit 1
EOF
cat > "$state/fake-simulator" << 'EOF'
#!/bin/sh
case "$1" in
    job) echo "Waiting for the Simulator lock: another job holds it (fake)" >&2; shift; exec "$@" ;;
    reset | wait-for-wallpaper-update | wait-for-widget-host) shift; exec "$@" ;;
    grant-location) shift 2; exec "$@" ;;
    with-destination) shift; exec "$@" -destination "platform=iOS Simulator,id=FAKE" ;;
esac
exit 1
EOF
chmod +x "$state/bin/"* "$state/fake-simulator"

run_make() {
    PATH="$state/bin:$PATH" make --no-print-directory -C "$ios" -o project \
        BUILD_DIR="$state/build" USE_SHARED_CACHE= SIM_LOCK="$state/fake-simulator" SIMULATOR="$state/fake-simulator" \
        TROME_E2E_EVIDENCE="$state/kept" "$@" > "$state/out" 2>&1 && echo "exit 0" || echo "exit 1"
}

expect "make lint passes quietly" "$(FAKE=pass run_make lint) $(lines)" "exit 0 1"
expect "make lint fails on a violation" "$(FAKE=fail run_make lint)" "exit 1"
expect "it prints every lint violation with its file and line" "$(has '/x/App/Foo.swift:3:1: error: Line Length Violation')" "1"

expect "make test passes with the count of the unit tests" "$(FAKE=pass run_make test) $(lines) $(has 'Test run with 653 tests in 45 suites passed')" "exit 0 1 1"
expect "the make commands of this test use a gate of their own, never the gate of the Mac" "$(test -e "$state/gate.lock" && echo yes || echo no)" "yes"

wait_for() {
    tries=0
    until "$@"; do
        tries=$((tries + 1))
        [ "$tries" -lt 300 ] || return 1
        sleep 0.1
    done
}
# A fake test run holds the gate of this test: make test waits, says why on one line, then passes as usual.
"$scripts/build-gate.py" tests sh -c 'touch "$1/held"; until [ -f "$1/release" ]; do sleep 0.1; done' sh "$state" &
holder=$!
wait_for test -f "$state/held" || true
(FAKE=pass run_make test > "$state/busy-status") &
busy=$!
wait_for grep -q '^Waiting: a Simulator test run' "$state/out" || true
touch "$state/release"
wait "$busy"
wait "$holder"
expect "while a Simulator test run holds the gate, make test passes with the wait line, then the count of the unit tests" \
    "$(cat "$state/busy-status") $(lines) $(sed -n 1p "$state/out" | cut -c1-29) $(sed -n 2p "$state/out" | grep -c 'unit-tests: OK .*Test run with 653 tests in 45 suites passed')" \
    "exit 0 2 Waiting: a Simulator test run 1"
expect "the wait of that made-up test run goes to the log folder of this test, never to the log of the Mac" \
    "$(grep -c 'a test run' "$state/trome-logs/build-waits.tsv" 2>/dev/null || echo 0)" "1"

expect "make test fails on a failing unit test" "$(FAKE=fail run_make test)" "exit 1"
expect "it prints the failing unit test with its name and message" \
    "$(has '✘ Test "the snooze ends at the next train" recorded an issue at SnoozeTests.swift:42:9: Expectation failed')" "1"

expect "make build passes quietly" "$(FAKE=pass run_make build) $(lines)" "exit 0 1"
expect "make build fails on a compiler error" "$(FAKE=fail-build run_make build)" "exit 1"
expect "it prints the compiler error with its file and line, and names the step" \
    "$(has "/x/App/Foo.swift:12:5: error: cannot find 'bar' in scope") $(has 'build: FAILED (exit 65')" "1 1"

expect "make e2e passes" "$(FAKE=pass run_make e2e)" "exit 0"
expect "a pass of make e2e prints the lock message, the counts and the time, in a few lines" \
    "$(has 'Waiting for the Simulator lock') $(has 'E2E tests: 3 passed, 0 failed, 0 skipped (of 3) in 240 s') $(lines)" "1 1 3"
expect "make e2e fails on a failing test" "$(FAKE=fail-e2e run_make e2e)" "exit 1"
expect "it prints the failing tests of xcodebuild and of scripts/e2e-failures.py" \
    "$(has '** TEST EXECUTE FAILED **') $(has 'SnoozeTests.swift:42: SnoozeTests/testSnooze(): The next lines did not show.')" "1 1"
expect "its last line of output names the step and the log file" \
    "$(grep -c "^e2e: FAILED (exit 65, [0-9]* s). The whole output is above, and in $state/build/logs/e2e.log" "$state/out")" "1"
expect "a failed make e2e keeps its log in a folder of the evidence of failed runs, and a pass keeps nothing" \
    "$(ls "$state/kept" | wc -l | tr -d ' ') $(ls "$state/kept"/*/e2e.log | wc -l | tr -d ' ')" "1 1"

[ "$failures" -eq 0 ]
