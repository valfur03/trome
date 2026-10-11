#!/bin/sh
# Tests 'simulator.sh status-bar', the status bar of the pictures, with a fake xcrun (no Simulator).
# iOS writes the time of the override with the clock that the Simulator had when it booted (the fake does the same).
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
udid=11111111-1111-1111-1111-111111111111
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH"
unset RATP_SIM_SIZE RATP_SIM_SLOT FAKE_BOOT_CLOCK_24 || true
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# Boots the shared Simulator in a language, then sets English, as a job does before its pictures.
boot_in() {
    echo "RATP-Shared Shutdown" > "$state/device.$udid"
    rm -f "$state"/global.* "$state/calls"
    echo "$1" > "$state/global.$udid.AppleLocale"
    xcrun simctl bootstatus "$udid" -b
    echo en_US > "$state/global.$udid.AppleLocale"
}

status_bar() {
    status=0
    "$scripts/simulator.sh" status-bar > "$state/output" 2>&1 || status=$?
    echo "$status" > "$state/status"
}

time_shown() {
    xcrun simctl status_bar "$udid" list | sed -n 's/^Time: //p'
}

boots() {
    grep -c "^simctl shutdown $udid" "$state/calls" || true
}

twelve_hour=$(printf '9:41\342\200\257')

boot_in en_US
status_bar
expect "booted in English, it sets 9:41" "$(cat "$state/status") $(time_shown)" "0 $twelve_hour"
expect "booted in English, it does not boot the Simulator again" "$(boots)" "0"

boot_in fr_FR
status_bar
expect "booted in French, it boots the Simulator again once and sets 9:41" \
    "$(cat "$state/status") $(boots) $(time_shown)" "0 1 $twelve_hour"
expect "booted in French, it says why it boots the Simulator again" \
    "$(grep -c '^The Simulator booted with a 24-hour clock' "$state/output")" "1"

boot_in fr_FR
export FAKE_BOOT_CLOCK_24=1
status_bar
unset FAKE_BOOT_CLOCK_24
expect "when a new boot still gives 09:41, it fails after one new boot" "$(cat "$state/status") $(boots)" "1 1"
expect "when a new boot still gives 09:41, it says what to check" \
    "$(grep -c '^The status bar still shows 09:41 after a new boot' "$state/output")" "1"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
