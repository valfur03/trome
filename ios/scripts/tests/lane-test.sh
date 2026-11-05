#!/bin/sh
# make lane: one line on the Simulator lane, read from the lock and the line of sim-lock.sh, with no lock taken and
# nothing changed. No Simulator: a fake xcrun, and a lock of the test.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" TROME_LOGS="$state/logs" \
    TROME_CHECK_LEDGER="$state/factory-checks.jsonl"
unset RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_SIM_KIND || true
lock=$RATP_SIM_LOCK
line="$lock.line"
sleepers=

# A watcher that does nothing, so that no job starts the real one.
mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 &
    echo $! > "$state/idle-watcher/pid")
watcher=$(cat "$state/idle-watcher/pid")
echo "$watcher" > "$lock.slots-watcher"

cleanup() {
    kill "$watcher" $sleepers ${background:-} 2> /dev/null || true
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

lane() {
    "$scripts/sim-lock.sh" lane
}

# A process that lives for the whole test: the holder or a waiter of the lock.
sleeper() {
    sleep 600 &
    sleeper=$!
    sleepers="$sleepers $sleeper"
}

started_at() {
    LC_ALL=C ps -p "$1" -o lstart= | sed -E 's/ +/ /g; s/^ //; s/ $//'
}

# A waiter as sim-lock.sh writes it: $1 when it asked (microseconds), $2 its PID, $3 job or merge, $4 its folder, $5 its kind.
waiter() {
    mkdir -p "$line"
    printf '%s\n%s\n%s\n' "$3" "$(started_at "$2")" "$4" > "$line/$1.$2"
    [ -z "${5:-}" ] || echo "$5" > "$line/.kind.$1.$2"
}

snapshot() {
    find "$state" -path "$state/logs" -prune -o -path "$state/idle-watcher" -prune -o -print | sort | while read -r file; do
        if [ -f "$file" ]; then echo "$file $(cat "$file")"; else echo "$file"; fi
    done
}

expect "no job: the lane is free" "$(lane)" "Simulator lane: free, no job waits."
expect "make lane prints the lane and exits 0" "$(make --no-print-directory -C "$scripts/.." lane && echo "exit 0")" \
    "Simulator lane: free, no job waits.
exit 0"

sleeper
holder=$sleeper
mkdir "$lock"
echo "$holder" > "$lock/pid"
echo /worktrees/qa > "$lock/worktree"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(($(date +%s) - 180))" 2026-11-04T10:00:00+0100 e2e 4 qa detached "" > "$lock/job"
expect "one job: its kind, its folder and how long it has held the lane" "$(lane)" \
    "Simulator lane: 1 running (e2e, qa, 3 min), 0 waiting."

sleeper
waiter 1000 "$sleeper" job /worktrees/docs docs-screenshots
sleeper
waiter 2000 "$sleeper" merge /worktrees/merging merge
sleeper
dead=$sleeper
waiter 500 "$dead" job /worktrees/ended e2e
kill "$dead"
wait "$dead" 2> /dev/null || true
before=$(snapshot)
expect "one job and two waiting: the merge first, then the jobs in the order they asked; an ended waiter is not counted" \
    "$(lane)" "Simulator lane: 1 running (e2e, qa, 3 min), 2 waiting (merge, merging; docs-screenshots, docs)."
expect "make lane changes nothing in the lock and the line" "$(snapshot)" "$before"

kill "$holder"
wait "$holder" 2> /dev/null || true
expect "a holder that has ended shows as stale, and stays for the jobs to remove" "$(lane)" \
    "Simulator lane: 1 running (e2e, qa, 3 min, stale), 2 waiting (merge, merging; docs-screenshots, docs)."
rm -rf "$lock" "$line"

# A real waiter writes its kind for the lane, and removes it when it leaves the line.
sleeper
holder=$sleeper
mkdir "$lock"
echo "$holder" > "$lock/pid"
echo /worktrees/qa > "$lock/worktree"
RATP_SIM_KIND=live-activity-render RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job true > "$state/waiter.log" 2>&1 &
background=$!
wait_for grep -q "Waiting for the Simulator lock" "$state/waiter.log"
expect "a job that waits shows with its kind and its folder" "$(lane)" \
    "Simulator lane: 1 running (job, qa), 1 waiting (live-activity-render, $(basename "$(cd "$scripts/../.." && pwd)"))."
kill "$holder"
wait "$background"
background=
expect "a job that took the lane leaves no kind file in the line" "$(ls -A "$line" | grep -c '^\.kind\.' || true)" "0"
expect "after the job, the lane is free" "$(lane)" "Simulator lane: free, no job waits."

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "lane-test: all checks passed"
