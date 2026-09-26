#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
default=11111111-1111-1111-1111-111111111111
old=22222222-2222-2222-2222-222222222222
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock"
unset RATP_SIM_SIZE || true

mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch > /dev/null 2>&1 & echo $! > "$state/idle-watcher/pid")
idle_watcher=$(cat "$state/idle-watcher/pid")

cleanup() {
    kill "$idle_watcher" 2> /dev/null || true
    rm -rf "$state"
}
trap cleanup EXIT

pretend_a_watcher_runs() {
    echo "$idle_watcher" > "$RATP_SIM_LOCK.watcher"
}
pretend_a_watcher_runs

booted() {
    xcrun simctl list devices booted | sed -n -E 's/^    ([^ ]+) .*/\1/p' | tr '\n' ' '
}

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

small_open() {
    RATP_SIM_SIZE=small "$scripts/sim-lock.sh" open "$scripts/simulator.sh" boot > /dev/null
}

echo "RATP-Shared Booted" > "$state/device.$default"

small_open
small=$("$scripts/simulator.sh" booted)
expect "make run SMALL=1 shuts down RATP-Shared and boots only the small Simulator" "$(booted)" "RATP-Shared-Small "
expect "the small Simulator is an iPhone SE" "$(cat "$state/type.$small")" "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
expect "the lock keeps the small Simulator" "$(cat "$RATP_SIM_LOCK/udid")" "$small"

"$scripts/sim-lock.sh" open sh -c '"$1" boot && kill -0 "$(cat "$RATP_SIM_LOCK/pid")" && echo held > "$FAKE_SIM_STATE/switch"' \
    sh "$scripts/simulator.sh" > /dev/null
expect "make run after make run SMALL=1 in the same folder boots only RATP-Shared" "$(booted)" "RATP-Shared "
expect "a live job holds the lock while the session switches Simulator" "$(cat "$state/switch" 2> /dev/null || true)" "held"
expect "the session keeps the lock with no job after the switch" "$(test -e "$RATP_SIM_LOCK/pid" && echo job || true)" ""
expect "the lock follows the Simulator of the session" "$(cat "$RATP_SIM_LOCK/udid")" "$default"

small_open
"$scripts/sim-lock.sh" free
expect "make simulator-shutdown after make run SMALL=1 shuts down the small Simulator" "$(booted)" ""
expect "make simulator-shutdown frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

"$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null
expect "a job keeps RATP-Shared booted after it ends" "$(booted)" "RATP-Shared "

echo "RATP-Shared-Small Booted" > "$state/device.$small"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null
expect "a job shuts down a small Simulator left booted" "$(booted)" "RATP-Shared "

echo "RATP-Shared Shutdown" > "$state/device.$default"
echo "RATP-Shared-Small Booted" > "$state/device.$small"
FAKE_SHUTDOWN_FAILS=1 "$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null 2>&1 || true
expect "a job does not boot RATP-Shared when it cannot shut down the small Simulator" "$(booted)" "RATP-Shared-Small "
expect "a failed job frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

touch -t 202001010000 "$RATP_SIM_LOCK.last"
RATP_SIM_IDLE_MINUTES=1 "$scripts/sim-lock.sh" watch
pretend_a_watcher_runs
expect "the idle watcher shuts down every shared Simulator" "$(booted)" ""

echo "RATP-task-1-abc Shutdown" > "$state/device.$old"
"$scripts/simulator.sh" delete-old > /dev/null
expect "make simulator-delete-old keeps the small Simulator" "$(test -e "$state/device.$small" && echo kept || true)" "kept"
expect "make simulator-delete-old deletes an old Simulator" "$(test -e "$state/device.$old" && echo kept || true)" ""

"$scripts/simulator.sh" delete > /dev/null
expect "make simulator-delete deletes both shared Simulators" "$(xcrun simctl list devices | grep -c RATP-Shared || true)" "0"

[ "$failures" -eq 0 ]
