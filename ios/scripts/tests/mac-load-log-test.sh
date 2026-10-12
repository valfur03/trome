#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

"$scripts/mac-load-log.sh" > "$state/usage" 2>&1 && status=0 || status=$?
expect "with no file, it prints its usage and fails" "$status $(head -c 7 "$state/usage")" "2 Usage: "

echo "a line of an older run" > "$state/load.log"
# The parent, as the shell of make e2e: it starts the log next to its work, then ends without stopping it.
TROME_LOAD_LOG_INTERVAL=1 sh -c '"$1" "$2" & echo $! > "$3"; sleep 2' parent "$scripts/mac-load-log.sh" "$state/load.log" "$state/pid"
pid=$(cat "$state/pid")
for _ in $(seq 1 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
done
expect "it stops by itself once the process that started it ends" "$(kill -0 "$pid" 2>/dev/null && echo running || echo stopped)" "stopped"
expect "it starts a new file, with no line of an older run" "$(grep -c 'older run' "$state/load.log")" "0"
expect "it writes samples while the process that started it runs" "$([ "$(wc -l < "$state/load.log")" -ge 1 ] && echo yes || echo no)" "yes"
expect "each sample has the time, the 1-minute load and the 5 busiest processes with their CPU" \
    "$(grep -cvE '^[0-9]{2}:[0-9]{2}:[0-9]{2} load [0-9.]+ \| ([^,]+ [0-9.]+%, ){4}[^,]+ [0-9.]+%$' "$state/load.log")" "0"

[ "$failures" -eq 0 ]
