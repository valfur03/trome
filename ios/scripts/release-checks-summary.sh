#!/bin/sh
# The summary of the release checks workflow (.github/workflows/release-checks.yml): one row per check, with its
# outcome, its minutes and the last line that it printed, so a failed check shows at the top of the run, by its name.
set -u

usage() {
    echo "Usage: $0 run <check> <command...>    Run the command as it is, add the row of the check, exit with its status" >&2
    echo "       $0 end <check>=<outcome>...    Add a row for each check that did not run (outcome skipped or cancelled), then the minutes of the job" >&2
    echo "       The summary is the file of GITHUB_STEP_SUMMARY; the start of the job is in RUNNER_TEMP/release-checks-start (seconds since 1970)." >&2
    exit 2
}

summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
table_started="$temp/release-checks-table-started"
# The first step of the job writes it.
job_start="$temp/release-checks-start"

row() {
    if [ ! -f "$table_started" ]; then
        printf '\n| Check | Outcome | Minutes | Last line |\n|---|---|---|---|\n' >> "$summary"
        : > "$table_started"
    fi
    printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >> "$summary"
}

minutes() {
    awk -v seconds="$1" 'BEGIN { printf "%.1f", seconds / 60 }'
}

# A table cell is one line: no |, no backquote, at most 200 characters.
cell() {
    tr -d '\r`' | sed 's/|/\//g' | cut -c 1-200
}

[ $# -ge 1 ] || usage
mode=$1
shift

case "$mode" in
    run)
        [ $# -ge 2 ] || usage
        check=$1
        shift
        output=$(mktemp "$temp/release-check.XXXXXX")
        start=$(date +%s)
        { "$@"; echo "$?" > "$output.status"; } 2>&1 | tee "$output"
        status=$(cat "$output.status" 2> /dev/null || echo 1)
        seconds=$(($(date +%s) - start))
        last=$(grep -v '^[[:space:]]*$' "$output" | tail -n 1 | cell)
        rm -f "$output" "$output.status"
        if [ "$status" -eq 0 ]; then
            row "$check" "passed" "$(minutes "$seconds")" "$last"
        else
            row "$check" "**FAILED** (exit $status)" "$(minutes "$seconds")" "$last"
        fi
        exit "$status"
        ;;
    end)
        for pair in "$@"; do
            check=${pair%=*}
            case "${pair##*=}" in
                skipped | "") row "$check" "not run: a step above did not pass" "" "" ;;
                cancelled) row "$check" "**cancelled**" "" "" ;;
            esac
        done
        if [ -f "$job_start" ]; then
            printf '\nThe job took %s minutes, from its start on the runner to this line.\n' \
                "$(minutes $(($(date +%s) - $(cat "$job_start"))))" >> "$summary"
        fi
        ;;
    *)
        usage
        ;;
esac
