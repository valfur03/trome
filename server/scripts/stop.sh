#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
pid_file=.wrangler/dev.pid

if [ ! -f "$pid_file" ]; then
    echo "No server of this folder runs."
    exit 0
fi

pid=$(cat "$pid_file")
if ! ps -p "$pid" -o command= 2> /dev/null | grep -q wrangler; then
    rm -f "$pid_file"
    echo "No server of this folder runs."
    exit 0
fi

kill -INT "$pid"
tries=0
while kill -0 "$pid" 2> /dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -eq 50 ]; then
        kill -TERM "$pid" 2> /dev/null || true
    fi
    if [ "$tries" -gt 100 ]; then
        echo "The server (process $pid) did not stop." >&2
        exit 1
    fi
    sleep 0.1
done
rm -f "$pid_file"
echo "Stopped the server of this folder."
