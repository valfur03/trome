#!/bin/sh
# Writes the load of the Mac and its busiest processes to a file every 10 s, until the process that started it ends.
# make e2e runs it next to the tests, and a failed run keeps the file (e2e-keep.py): when iOS in the Simulator is
# slow, the file shows what kept the Mac busy at that moment, the Simulator itself or another job.
set -u

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file>" >&2
    echo "       Every TROME_LOAD_LOG_INTERVAL seconds (default 10), adds one line to the file: the time, the 1-minute load" >&2
    echo "       average, and the 5 processes of the Mac that use the most CPU. It stops when the process that started it ends." >&2
    exit 2
fi

file=$1
interval=${TROME_LOAD_LOG_INTERVAL:-10}
parent=$PPID
: > "$file"
while kill -0 "$parent" 2>/dev/null; do
    load=$(sysctl -n vm.loadavg | awk '{ print $2 }')
    busiest=$(ps -Ao pcpu=,ucomm= -r | head -5 | sed -E 's/^ *([0-9.]+) +(.*[^ ]) *$/\2 \1%/' | paste -sd ',' - | sed 's/,/, /g')
    echo "$(date +%H:%M:%S) load $load | $busiest" >> "$file"
    sleep "$interval"
done
