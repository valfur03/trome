#!/bin/sh
set -u

if [ $# -lt 3 ]; then
    echo "Usage: $0 <log file> <summary pattern> <command...>" >&2
    echo "       Runs the command with all of its output in the log file." >&2
    echo "       On a pass, it prints one line: the step (the name of the log file), the time, and the lines of the log that match the pattern (grep -E; empty: none)." >&2
    echo "       On a failure, it prints the whole log, then a last line that names the step and the log file." >&2
    echo "       VERBOSE=1 runs the command with its output as it comes, as if this script was not there." >&2
    exit 2
fi

log=$1
pattern=$2
shift 2

if [ "${VERBOSE:-}" = 1 ]; then
    exec "$@"
fi

step=$(basename "$log" .log)
case "$log" in
    /*) shown=$log ;;
    *) shown="$(git rev-parse --show-prefix 2> /dev/null)$log" ;;
esac
mkdir -p "$(dirname "$log")"
start=$(date +%s)
"$@" > "$log" 2>&1
status=$?
seconds=$(($(date +%s) - start))

if [ "$status" -ne 0 ]; then
    cat "$log"
    echo "$step: FAILED (exit $status, $seconds s). The whole output is above, and in $shown; VERBOSE=1 prints it as it runs."
    exit "$status"
fi

summary=""
if [ -n "$pattern" ]; then
    summary=$(grep -E -- "$pattern" "$log" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g' | awk 'NR > 1 { printf "; " } { printf "%s", $0 }')
fi
echo "$step: OK ($seconds s)${summary:+: $summary}"
