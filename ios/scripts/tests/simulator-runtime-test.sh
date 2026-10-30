#!/bin/sh
# Tests how 'simulator.sh' creates the shared Simulator and names its runtime, with a fake xcrun (no Simulator).
# The newest runtime of a Mac may run only one new device: the shared iPhone must still be created, on a runtime that runs
# it, and the summary of the release checks must name that runtime, not the newest one.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH"
unset RATP_SIM_SIZE RATP_SIM_SLOT || true
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

status=0
udid=$("$scripts/simulator.sh" udid 2> "$state/errors") || status=$?
expect "with a newer runtime for another device only, it creates the shared iPhone" \
    "$status $(cat "$state/type.$udid" 2> /dev/null)" "0 com.apple.CoreSimulator.SimDeviceType.iPhone-17"
expect "it creates one shared Simulator" "$(ls "$state" | grep -c '^device\.')" "1"

status=0
runtime=$("$scripts/simulator.sh" runtime 2>> "$state/errors") || status=$?
expect "it names the runtime of the shared Simulator, not the newest runtime of the Mac" \
    "$status $runtime" "0 iOS 27.0 (27.0 - 24A434)"
expect "it prints no error" "$(cat "$state/errors")" ""

[ "$failures" -eq 0 ]
