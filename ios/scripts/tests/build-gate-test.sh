#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../build-gate.py"
state=$(mktemp -d)
export RATP_BUILD_GATE="$state/gate" TROME_LOGS="$state/logs"
unset RATP_BUILD_GATE_HELD
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

# Runs a job (build or tests) whose command marks <name>.started, then waits for <name>.go, then marks <name>.done.
job() {
    "$script" "$1" sh -c 'touch "$0.started"; until [ -e "$0.go" ]; do sleep 0.05; done; touch "$0.done"' "$state/$2" \
        2> "$state/$2.err" &
}

started() { [ -e "$state/$1.started" ] && echo started || echo waiting; }

expect "a build passes the exit status of its command" \
    "$("$script" build sh -c 'exit 3' && echo 0 || echo $?)" "3"

job build a
job build b
wait_for '[ -e "$state/a.started" ] && [ -e "$state/b.started" ]' || true
expect "two builds run at once" "$(started a) $(started b)" "started started"

job tests t
wait_for 'grep -q "Waiting for the builds" "$state/t.err"' || true
expect "a test run waits for the builds that run" "$(started t)" "waiting"
expect "the test run names the builds that it waits for" \
    "$(grep -c "(process [0-9]*).*(process [0-9]*)" "$state/t.err")" "1"

job build c
wait_for 'grep -q "needs a quiet Mac" "$state/c.err"' || true
expect "a new build waits for a test run that waits, so a stream of builds never keeps it waiting" "$(started c)" "waiting"

touch "$state/a.go"
wait_for '[ -e "$state/a.done" ]' || true
sleep 0.3
expect "the test run still waits while one build runs" "$(started t)" "waiting"
touch "$state/b.go"
wait_for '[ -e "$state/t.started" ]' || true
expect "the test run starts when the last build ends" "$(started t)" "started"
sleep 0.3
expect "the new build still waits while the test run runs" "$(started c)" "waiting"
expect "it names the folder of the test run" "$(grep -c "test run ($(pwd))" "$state/c.err")" "1"

expect "a build inside a test run runs at once" \
    "$(RATP_BUILD_GATE_HELD=tests "$script" build echo built)" "built"

touch "$state/t.go"
wait_for '[ -e "$state/c.started" ]' || true
expect "the new build starts when the test run ends" "$(started c)" "started"
touch "$state/c.go"
wait

"$script" build sh -c 'echo $$ > "$0"; exec sleep 30' "$state/killed.pid" 2> /dev/null &
killed=$!
wait_for '[ -e "$state/gate.builds/$killed" ] && [ -s "$state/killed.pid" ]' || true
kill -9 "$killed"
kill "$(cat "$state/killed.pid")"
wait "$killed" 2> /dev/null || true
expect "a test run does not wait for a killed build" "$("$script" tests echo ran 2> "$state/killed.err")" "ran"
expect "the killed build left no wait" "$(cat "$state/killed.err")" ""

"$script" tests sleep 30 &
stopped=$!
wait_for '[ -s "$state/gate.turn" ]' || true
kill -TERM "$stopped"
status=0
wait "$stopped" || status=$?
expect "a stopped test run stops its command and passes its status" "$status" "143"
expect "a build does not wait for a stopped test run" "$("$script" build echo built 2> "$state/stopped.err")" "built"
expect "the stopped test run left no wait" "$(cat "$state/stopped.err")" ""

"$script" build sh -c 'touch "$0"; exec sleep 30' "$state/hung-build.started" 2> /dev/null &
hung=$!
wait_for '[ -e "$state/hung-build.started" ]' || true
expect "a test run waits for a hung build only up to its limit, then runs" \
    "$(RATP_BUILD_GATE_TESTS_WAIT=1 "$script" tests echo ran 2> "$state/hung-build.err")" "ran"
expect "it says that it runs next to the build" "$(grep -c "the tests run next to them" "$state/hung-build.err")" "1"
kill "$hung" 2> /dev/null || true
wait "$hung" 2> /dev/null || true

"$script" tests sh -c 'touch "$0"; exec sleep 30' "$state/hung-tests.started" 2> /dev/null &
hung=$!
wait_for '[ -e "$state/hung-tests.started" ]' || true
expect "a build waits for a hung test run only up to its limit, then runs" \
    "$(RATP_BUILD_GATE_BUILD_WAIT=1 "$script" build echo built 2> "$state/hung-tests.err")" "built"
expect "it says that it runs next to the test run" "$(grep -c "this build runs next to it" "$state/hung-tests.err")" "1"
kill "$hung" 2> /dev/null || true
wait "$hung" 2> /dev/null || true

makefile="$tests/../../Makefile"
expect "every Simulator test run of ios/Makefile goes through the gate" \
    "$(grep -F '$(SIM_LOCK) job' "$makefile" | grep -F ' reset ' | grep -cvF '$(SIM_LOCK) job $(TEST_RUN_GATE) ')" "0"
expect "every build of ios/Makefile goes through the gate" \
    "$(grep -E '^XCODEBUILD :=|swift test|build-for-testing|\$\(QUIET\) \$\(LOGS\)/build\.log|EXPORT_STRINGS\)$' "$makefile" \
        | grep -cvE '^XCODEBUILD := \$\(BUILD_GATE\) |^	@\$\(BUILD_GATE\) ')" "0"

# A script that runs 'swift <file>' or 'swiftc' compiles, itself or through a script that it runs, so it loads the Mac as a build does.
compiles_swift() {
    grep -qE '(^|[[:space:]|(;&])(xcrun )?swiftc? ' "$1" && return 0
    for called in $(grep -oE '"\$scripts/[A-Za-z0-9_.-]+"' "$1" | tr -d '"' | sed 's|^\$scripts/||' | sort -u); do
        [ "$tests/../$called" != "$1" ] && [ -f "$tests/../$called" ] && compiles_swift "$tests/../$called" && return 0
    done
    return 1
}
ungated=""
# Each command of a recipe, with its continuation lines joined, that runs such a script outside both gates.
for called in $(awk '/\\$/ { sub(/\\$/, ""); line = line $0; next } { print line $0; line = "" }' "$makefile" \
    | grep -E '^	' | grep -vF '$(BUILD_GATE)' | grep -vF '$(TEST_RUN_GATE)' \
    | grep -oE '\./scripts/[A-Za-z0-9_.-]+' | sed 's|^\./scripts/||' | sort -u); do
    [ -f "$tests/../$called" ] && compiles_swift "$tests/../$called" && ungated="$ungated $called"
done
expect "every script of ios/Makefile that compiles Swift goes through a gate" "$ungated" ""

[ "$failures" -eq 0 ]
