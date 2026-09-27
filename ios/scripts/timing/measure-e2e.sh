#!/bin/sh
# Usage: measure-e2e.sh <label> [make args...]
label=$1; shift
dir=$(cd "$(dirname "$0")" && pwd)
cd "$dir/../.."
out="$dir/../../.build/timing/$label"
mkdir -p "$out"
( while :; do echo "$(date +%H:%M:%S) $(uptime | sed 's/.*load averages: //')"; sleep 15; done ) > "$out/load.log" 2>&1 &
loadpid=$!
start=$(date +%s)
echo "start $(date +%H:%M:%S)" > "$out/summary.txt"
make e2e SIMULATOR="$dir/tsim.sh" "$@" 2>&1 | "$dir/ts.pl" > "$out/e2e.log"
status=$?
end=$(date +%s)
kill $loadpid
echo "end $(date +%H:%M:%S) total $((end - start)) s" >> "$out/summary.txt"
xcrun xcresulttool get test-results tests --path .build/e2e.xcresult > "$out/tests.json" 2>/dev/null
cp -R .build/e2e.xcresult "$out/" 2>/dev/null
exit $status
