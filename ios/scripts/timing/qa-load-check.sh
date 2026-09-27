#!/bin/sh
set -u
if [ $# -ne 2 ] || { [ "$2" != cold ] && [ "$2" != warm ]; }; then
    echo "Usage: $0 <label> cold|warm" >&2
    echo "Measures the load of the Mac while a full make e2e runs on the shared Simulator and a QA session runs on its own Simulator (RATP-Shared-QA)." >&2
    echo "cold: the QA Simulator boots 20 s after the e2e job gets the Simulator lock. warm: the QA Simulator and the app are open before the e2e job starts." >&2
    echo "The logs go to ios/.build/timing/<label>/. When the 1-minute load goes above 200 or the free memory below 10%, it shuts down the QA Simulator at once." >&2
    echo "Delete RATP-Shared-QA when you are done: xcrun simctl delete <its ID>" >&2
    exit 1
fi
label=$1
mode=$2
dir=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$dir/../.." && pwd)
root=$(cd "$ios/.." && pwd)
out="$ios/.build/timing/$label"
app="$ios/.build/DerivedData/Build/Products/Debug-iphonesimulator/RATPActivity.app"
qa_name=RATP-Shared-QA
mkdir -p "$out"
cd "$ios"

qa_udid=$(xcrun simctl list devices available | grep -F "    $qa_name (" | head -n 1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$qa_udid" ]; then
    runtime=$(xcrun simctl list runtimes available | grep '^iOS ' | tail -n 1 | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+).*/\1/')
    qa_udid=$(xcrun simctl create "$qa_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")

stamp() { date +%H:%M:%S; }
note() { echo "$(stamp) $*" >> "$out/summary.txt"; }

qa_start() {
    note "qa boot start"
    xcrun simctl bootstatus "$qa_udid" -b > /dev/null
    note "qa booted"
    open -a Simulator --args -CurrentDeviceUDID "$qa_udid" 2> /dev/null || true
    xcrun simctl install "$qa_udid" "$app"
    xcrun simctl launch "$qa_udid" "$bundle_id" > /dev/null
    note "qa app open"
}

( top -l 0 -s 5 -n 0 | grep --line-buffered '^CPU usage' | while read -r line; do
    idle=$(printf '%s\n' "$line" | sed -n -E 's/.* ([0-9.]+)% idle.*/\1/p')
    load=$(uptime | sed 's/.*load averages*: //')
    swap=$(sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+M).*/\1/')
    free=$(memory_pressure 2> /dev/null | sed -n -E 's/.*free percentage: ([0-9]+)%.*/\1/p')
    booted=$(xcrun simctl list devices booted | grep -c Booted)
    echo "$(stamp) load $load idle $idle% swap $swap free $free% booted $booted"
    load1=$(printf '%s\n' "$load" | awk '{ print int($1) }')
    if [ "$load1" -gt 200 ] || [ "${free:-100}" -lt 10 ]; then
        echo "$(stamp) GUARD: load $load1, free $free%: shutting down the QA Simulator"
        xcrun simctl shutdown "$qa_udid" 2> /dev/null || true
    fi
done ) > "$out/load.log" 2>&1 &
logger=$!
trap 'kill $logger 2> /dev/null; pkill -f "top -l 0 -s 5 -n 0" 2> /dev/null' EXIT

note "start ($mode)"
if [ "$mode" = warm ]; then
    qa_start
fi
make e2e 2>&1 | "$dir/ts.pl" > "$out/e2e.log" &
e2e=$!
if [ "$mode" = cold ]; then
    until [ "$(cat /tmp/ratp-sim.lock/worktree 2> /dev/null)" = "$root" ] && [ -n "$(cat /tmp/ratp-sim.lock/pid 2> /dev/null)" ]; do
        sleep 2
    done
    note "e2e got the lock"
    sleep 20
    qa_start
fi
( n=0; while kill -0 "$e2e" 2> /dev/null; do
    n=$((n + 1))
    xcrun simctl io "$qa_udid" screenshot "$out/qa-$n.png" > /dev/null 2>&1 || true
    sleep 15
done ) &
wait "$e2e"
status=$?
note "e2e end, status $status"
sleep 10
exit "$status"
