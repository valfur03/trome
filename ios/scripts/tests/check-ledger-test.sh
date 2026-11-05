#!/bin/sh
# The check ledger: each check that runs as a Simulator job adds one JSON line to <git common dir>/factory-checks.jsonl,
# and a write that fails never changes the end of the job. No Simulator: a fake xcrun, a lock and a repo of the test.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" TROME_LOGS="$state/logs" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_SIM_KIND \
    FACTORY_CHECK_WHERE TROME_CHECK_LEDGER TROME_CHECK_RESULT || true

# A watcher that does nothing, so that no job starts the real one.
mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 &
    echo $! > "$state/idle-watcher/pid")
echo "$(cat "$state/idle-watcher/pid")" > "$RATP_SIM_LOCK.slots-watcher"

cleanup() {
    kill "$(cat "$state/idle-watcher/pid")" ${background:-} 2> /dev/null || true
    chmod -R u+w "$state" 2> /dev/null || true
    rm -rf "$state"
}
trap cleanup EXIT

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
    until "$@" || [ "$tries" -ge 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
}

# A repo with its main folder and a worktree named as the worktree of a task, each with the lock script.
repo="$state/repo"
git init -q -b main "$repo"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
git -C "$repo" worktree add -q -b task/77 "$state/worktrees/task-77"
task="$state/worktrees/task-77"
git -C "$task" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
for folder in "$repo" "$task"; do
    mkdir -p "$folder/ios/scripts"
    cp "$scripts/sim-lock.sh" "$scripts/simulator.sh" "$folder/ios/scripts/"
done
ledger="$repo/.git/factory-checks.jsonl"

# Prints the fields of line $1 of the ledger, or "invalid" when it is not a JSON object with every field.
field() {
    python3 -I - "$ledger" "$1" "$2" << 'PYTHON'
import json, re, sys
lines = open(sys.argv[1]).read().splitlines()
entry = json.loads(lines[int(sys.argv[2]) - 1])
keys = ["at", "check", "result", "seconds", "waited", "where", "commit", "task"]
if sorted(entry) != sorted(keys) or not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d", entry["at"]):
    print("invalid")
elif not isinstance(entry["seconds"], int) or not isinstance(entry["waited"], int):
    print("invalid")
else:
    print(entry[sys.argv[3]])
PYTHON
}

lines() {
    if [ -f "$ledger" ]; then wc -l < "$ledger" | tr -d ' '; else echo 0; fi
}

status=0
RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job true || status=$?
expect "a green job ends with its own exit status" "$status" "0"
expect "a job in a worktree writes the ledger of the common git folder" "$(lines)" "1"
expect "the line names the check" "$(field 1 check)" "e2e"
expect "a job that exits 0 is green" "$(field 1 result)" "green"
expect "with no FACTORY_CHECK_WHERE, the place is branch" "$(field 1 where)" "branch"
expect "the line has the commit of the worktree" "$(field 1 commit)" "$(git -C "$task" rev-parse HEAD)"
expect "the task comes from the folder name" "$(field 1 task)" "TASK-77"

status=0
FACTORY_CHECK_WHERE=main RATP_SIM_KIND=release-run "$task/ios/scripts/sim-lock.sh" job sh -c 'exit 3' || status=$?
expect "a red job ends with its own exit status" "$status" "3"
expect "a job that fails is red" "$(field 2 result)" "red"
expect "the place comes from FACTORY_CHECK_WHERE" "$(field 2 where)" "main"

RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job sh -c 'echo flaky > "$TROME_CHECK_RESULT"'
expect "a job that passed on a retry, and says so, is flaky" "$(field 3 result)" "flaky"

RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job sh -c 'echo flaky > "$TROME_CHECK_RESULT"; exit 1' || true
expect "a job that says flaky but fails is red" "$(field 4 result)" "red"

# The main folder: git gives the common folder as a relative path there.
(cd "$repo/ios" && RATP_SIM_KIND=e2e ./scripts/sim-lock.sh job true)
expect "a job in the main folder writes the same ledger" "$(lines)" "5"
expect "a folder that is not a task's has no task" "$(field 5 task)" "None"
expect "the line has the commit of the main folder" "$(field 5 commit)" "$(git -C "$repo" rev-parse HEAD)"

# The checks of a merge run inside its job: one line each, and none for the merge itself.
FACTORY_CHECK_WHERE=merge RATP_SIM_MERGE=1 "$task/ios/scripts/sim-lock.sh" job sh -c \
    'RATP_SIM_KIND=e2e "$0" job true && RATP_SIM_KIND=release-run "$0" job sh -c "exit 4"; exit 0' "$task/ios/scripts/sim-lock.sh"
expect "each check inside a held job writes its line, and the held job none" "$(lines)" "7"
expect "the first check inside names its kind" "$(field 6 check)-$(field 6 where)" "e2e-merge"
expect "the second check inside has its own result" "$(field 7 check)-$(field 7 result)" "release-run-red"

RATP_SIM_MERGE=1 "$task/ios/scripts/sim-lock.sh" job true
expect "a merge with no check inside writes its own line" "$(field 8 check)" "merge"

RATP_SIM_KIND=simulator-wallpaper "$task/ios/scripts/sim-lock.sh" job true
RATP_SIM_KIND=simulator-delete-old "$task/ios/scripts/sim-lock.sh" job true
expect "a job that checks nothing writes no line" "$(lines)" "8"

# A job stopped by a signal says nothing about its check.
RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job sh -c 'touch "$FAKE_SIM_STATE/started"; exec sleep 600' 2> /dev/null &
background=$!
wait_for test -e "$state/started"
kill -TERM "$background"
status=0
wait "$background" || status=$?
background=
expect "a stopped job ends as stopped" "$status" "143"
expect "a stopped job writes no line" "$(lines)" "8"

# A ledger that cannot be written: the job still ends with its own exit status, and says nothing of the ledger.
chmod a-w "$ledger"
status=0
RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job sh -c 'exit 5' > "$state/out" 2>&1 || status=$?
expect "a read-only ledger keeps the exit status of a red job" "$status" "5"
status=0
RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job true > "$state/out" 2>&1 || status=$?
expect "a read-only ledger keeps the exit status of a green job" "$status" "0"
expect "a read-only ledger prints nothing" "$(cat "$state/out")" ""
expect "a read-only ledger is left as it was" "$(lines)" "8"
status=0
TROME_CHECK_LEDGER="$state/no-folder/factory-checks.jsonl" RATP_SIM_KIND=e2e "$task/ios/scripts/sim-lock.sh" job sh -c 'exit 6' 2> /dev/null ||
    status=$?
expect "a ledger in a missing folder keeps the exit status of the job" "$status" "6"
expect "the lock is free after each job" "$([ -e "$RATP_SIM_LOCK" ] && echo held || echo free)" "free"

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "check-ledger-test: all checks passed"
