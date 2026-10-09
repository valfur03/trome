#!/bin/sh
# The records of the Simulator jobs and of the build gate waits, and their sum-up (make simulator-times).
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
root=$(cd "$scripts/../.." && pwd)
state=$(mktemp -d)
default=11111111-1111-1111-1111-111111111111
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" RATP_SIM_POLL_SECONDS=1 \
    RATP_BUILD_GATE="$state/gate" TROME_LOGS="$state/logs"
unset RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_MERGE_QUEUE RATP_SIM_KIND \
    RATP_SIM_DETAIL RATP_BUILD_GATE_HELD || true
jobs_log="$state/logs/simulator-jobs.tsv"
waits_log="$state/logs/build-waits.tsv"

# A watcher of the current version seems to run, so the lock starts none.
mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 & echo $! > "$state/idle-watcher/pid")
idle_watcher=$(cat "$state/idle-watcher/pid")
echo "$idle_watcher" > "$RATP_SIM_LOCK.slots-watcher"
echo "RATP-Shared Booted" > "$state/device.$default"

cleanup() {
    kill "$idle_watcher" ${orphan:-} $(jobs -p) 2> /dev/null || true
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
    until eval "$1"; do
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || return 1
        sleep 0.1
    done
}

# The fields of the last record: line <n> from the end, columns by name.
field() {
    awk -F '\t' -v name="$1" -v back="${2:-1}" '
        NR == 1 { for (i = 1; i <= NF; i++) column[$i] = i; next }
        { line[NR] = $0 }
        END { split(line[NR - back + 1], fields, "\t"); print fields[column[name]] }' "$3"
}

records() {
    grep -cv '^asked' "$jobs_log" 2> /dev/null || true
}

mkdir -p "$state/logs"
printf 'asked\tkind\twait_s\thold_s\tgate_wait_s\tend\tworktree\tbranch\tdetail\twaited_for\n' > "$jobs_log"
printf '2026-09-27T10:00:00+0200\te2e\t60\t300\t0\t0\ttask-1\ttask/1\t\tbusy\n' >> "$jobs_log"

mkdir "$RATP_SIM_LOCK"
echo "$idle_watcher" > "$RATP_SIM_LOCK/pid"
echo /another/worktree > "$RATP_SIM_LOCK/worktree"
RATP_SIM_KIND=e2e RATP_SIM_DETAIL=SnoozeTests "$scripts/sim-lock.sh" job sh -c 'sleep 1; exit 3' 2> /dev/null &
job=$!
sleep 2
rm -rf "$RATP_SIM_LOCK"
wait "$job" || true
expect "a Simulator job adds one record when it frees the Simulator, and keeps the older records" "$(records)" "2"
expect "the record says the kind and the detail of the job" "$(field kind 1 "$jobs_log") $(field detail 1 "$jobs_log")" "e2e SnoozeTests"
expect "the record counts the wait for the Simulator, and why it waited" \
    "$([ "$(field wait_s 1 "$jobs_log")" -ge 1 ] && echo waited) $(field waited_for 1 "$jobs_log")" "waited busy"
expect "the record counts the hold of the Simulator, and the exit status of the job" \
    "$([ "$(field hold_s 1 "$jobs_log")" -ge 1 ] && echo held) $(field end 1 "$jobs_log")" "held 3"
expect "the record names the clone and its branch" "$(field worktree 1 "$jobs_log") $(field branch 1 "$jobs_log")" \
    "$(basename "$root") $(git -C "$root" rev-parse --abbrev-ref HEAD)"
expect "the record says when the job asked for the Simulator" \
    "$(field asked 1 "$jobs_log" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$')" "1"

"$scripts/sim-lock.sh" job sh -c '"$0" job true' "$scripts/sim-lock.sh"
expect "a job inside a job that holds the Simulator adds no record of its own" "$(records) $(field kind 1 "$jobs_log")" "3 job"

RATP_SIM_MERGE=1 RATP_SIM_KIND=e2e "$scripts/sim-lock.sh" job sh -c 'echo "task/1, task/2" > "$RATP_SIM_HELD_LOCK/detail"'
expect "a merge is recorded as a merge, with the detail that its job writes" "$(field kind 1 "$jobs_log") $(field detail 1 "$jobs_log")" "merge task/1, task/2"

RATP_SIM_KIND=run RATP_SIM_DETAIL="LIVE=1 SMALL=1" "$scripts/sim-lock.sh" open true
"$scripts/sim-lock.sh" open true
expect "make run adds no record while it keeps the Simulator, also when it runs again" "$(records)" "4"
sleep 1
"$scripts/sim-lock.sh" free
expect "make simulator-shutdown adds the one record of make run, from its first start" \
    "$(records) $(field kind 1 "$jobs_log") $(field end 1 "$jobs_log") $(field detail 1 "$jobs_log") $([ "$(field hold_s 1 "$jobs_log")" -ge 1 ] && echo held)" \
    "5 run freed LIVE=1 SMALL=1 held"

"$scripts/sim-lock.sh" job sleep 30 &
killed=$!
wait_for '[ -e "$RATP_SIM_LOCK/job" ]'
orphan=$(pgrep -P "$killed" sleep || true)
kill -9 "$killed"
wait "$killed" 2> /dev/null || true
"$scripts/sim-lock.sh" job true 2> /dev/null
expect "a job that died without freeing the Simulator is recorded as stale, then the next job is recorded" \
    "$(records) $(field end 2 "$jobs_log") $(field end 1 "$jobs_log")" "7 stale 0"

mkdir "$RATP_SIM_LOCK"
sh -c 'echo $$' > "$RATP_SIM_LOCK/pid"
echo /another/worktree > "$RATP_SIM_LOCK/worktree"
printf '1\t2026-01-01T00:00:00+0000\te2e\t5\tother\ttask/other\tmerge\n' > "$RATP_SIM_LOCK/job"
"$scripts/sim-lock.sh" job true 2> /dev/null
expect "the job that removes a stale lock keeps its own asked time and wait reason in its record" \
    "$(field asked 2 "$jobs_log") $(field waited_for 2 "$jobs_log") $(field asked 1 "$jobs_log" | cut -c 1-10) [$(field waited_for 1 "$jobs_log")]" \
    "2026-01-01T00:00:00+0000 merge $(date +%Y-%m-%d) []"

"$scripts/build-gate.py" build sh -c 'touch "$0.started"; sleep 2' "$state/build" &
wait_for '[ -e "$state/build.started" ]'
"$scripts/sim-lock.sh" job "$scripts/build-gate.py" tests true 2> /dev/null
expect "a test run that waits for the builds counts that wait in the record of its Simulator job" \
    "$([ "$(field gate_wait_s 1 "$jobs_log")" -ge 1 ] && echo counted)" "counted"
expect "the build gate records the wait of the test run, and what it waited for" \
    "$(field gate 1 "$waits_log") $(field waited_for 1 "$waits_log")" "tests 1 builds"
wait

"$scripts/build-gate.py" tests sh -c 'touch "$0.started"; sleep 2' "$state/tests" &
wait_for '[ -e "$state/tests.started" ]'
"$scripts/build-gate.py" build true 2> /dev/null
expect "the build gate records the wait of a build for a test run, and the clone of the test run" \
    "$(field gate 1 "$waits_log") $([ "$(field wait_s 1 "$waits_log")" -ge 1 ] && echo waited) $(field waited_for 1 "$waits_log")" \
    "build waited a test run ($(basename "$root"))"
wait
"$scripts/build-gate.py" build true
expect "a build that does not wait adds no record" "$(grep -c '^20' "$waits_log")" "2"

summary="$state/logs/summary"
mkdir "$state/fixture"
{
    printf 'asked\tkind\twait_s\thold_s\tgate_wait_s\tend\tworktree\tbranch\tdetail\twaited_for\n'
    printf '2026-10-07T10:00:00+0200\tmerge\t600\t1200\t60\t0\ttask-1\ttask/1\ttask/1\tbusy\n'
    printf '2026-10-07T11:00:00+0200\te2e\t0\t600\t0\t0\ttask-2\ttask/2\tSnoozeTests\t\n'
    printf '2026-10-08T10:00:00+0200\trun\t30\t1800\t0\tfreed\tqa\tHEAD\tLIVE=1\tmerge\n'
    printf 'asked\tkind\twait_s\thold_s\tgate_wait_s\tend\tworktree\tbranch\tdetail\twaited_for\n'
    printf '2026-10-08T11:00:00+0200\tmerge\t0\t600\t0\t1\ttask-3\ttask/3\ttask/3, task/4\t\n'
} > "$state/fixture/simulator-jobs.tsv"
TROME_LOGS="$state/fixture" "$scripts/simulator-times.py" > "$summary"
expect "make simulator-times sums the hold of each kind, and its share of all the hold" \
    "$(grep -E '^(merge|run|e2e) ' "$summary" | awk '{print $1, $2, $3, $4, $5, $6, $7}' | tr '\n' ';')" \
    "merge 2 30 min 00 s 42%;run 1 30 min 00 s 42%;e2e 1 10 min 00 s 14%;"
expect "make simulator-times says how much of the span the Simulator was held" \
    "$(head -n 1 "$summary")" "Simulator jobs from 2026-10-07 10:00: 4 jobs held the Simulator 1 h 10 min of 25 h 10 min (4%)."
TROME_LOGS="$state/fixture" "$scripts/simulator-times.py" --since 2026-10-08 > "$summary"
expect "make simulator-times SINCE=<date> keeps the records from that date on" \
    "$(grep -E '^(merge|run|e2e) ' "$summary" | awk '{print $1, $2}' | tr '\n' ';')" "run 1;merge 1;"
expect "make simulator-times refuses a SINCE that is not a date" \
    "$(TROME_LOGS="$state/fixture" "$scripts/simulator-times.py" --since yesterday > /dev/null 2>&1 && echo ran || echo refused)" "refused"
expect "make simulator-times says when nothing is recorded yet" \
    "$(TROME_LOGS="$state/empty" "$scripts/simulator-times.py" | head -n 1)" "No Simulator job recorded in $state/empty/simulator-jobs.tsv."

[ "$failures" -eq 0 ]
