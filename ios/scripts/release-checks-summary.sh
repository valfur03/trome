#!/bin/sh
# The summary of the release checks workflow (.github/workflows/release-checks.yml): one row per check, with its
# outcome, its minutes and the last line that it printed, so a failed check shows at the top of the run, with its cause.
set -u

usage() {
    echo "Usage: $0 run <check> <command...>    Run the command as it is, add the row of the check, exit with its status" >&2
    echo "       $0 report <check> <pattern> <command...>    The same, for a check that is a report: it fails only when it cannot run;" >&2
    echo "                                                  its row says so, and gives its lines that match the pattern (grep -E), not its last line" >&2
    echo "       $0 report <check> <pattern> --mac-only <failure> <detail> <command...>    The same, for a report whose last part cannot run here:" >&2
    echo "                                                  when it fails with a last line that matches <failure>, the step passes, and its row" >&2
    echo "                                                  says that it ran in part, with its counts and <detail>, a fixed text, never a pass" >&2
    echo "       $0 end <check>=<outcome>...    Add a row for each check that did not run (outcome skipped or cancelled)," >&2
    echo "                                      the row of the E2E suite, which never runs here, then the minutes of the job" >&2
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
        printf '\n| Check | Outcome | Minutes | Detail |\n|---|---|---|---|\n' >> "$summary"
        : > "$table_started"
    fi
    printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >> "$summary"
    # The row in the log too: the summary page needs a login to GitHub, the log is read with gh run view --log.
    [ "$summary" = /dev/stdout ] || printf 'Summary row: | %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4"
}

minutes() {
    awk -v seconds="$1" 'BEGIN { printf "%.1f", seconds / 60 }'
}

esc=$(printf '\033')

# The lines of the output, with no colour code (Node tools print them on GitHub), and with no line of make itself:
# each check is a root make that runs make again in its part, so on a failure the last line is always
# "make: *** [check] Error 2", never the cause.
lines() {
    sed -e "s/$esc\\[[0-9;?]*[A-Za-z]//g" -e "s/$esc//g" "$1" | tr -d '\r' \
        | grep -v -E '^[[:space:]]*$|^g?make(\[[0-9]+\])?: '
}

# A table cell is one line: no |, no backquote, at most 300 characters.
cell() {
    tr -d '`' | sed 's/|/\//g' | cut -c 1-300
}

[ $# -ge 1 ] || usage
mode=$1
shift

case "$mode" in
    run | report)
        [ $# -ge 2 ] || usage
        check=$1
        shift
        mac_only=""
        if [ "$mode" = report ]; then
            [ $# -ge 2 ] || usage
            pattern=$1
            shift
            if [ "$1" = --mac-only ]; then
                [ $# -ge 4 ] || usage
                mac_only=$2
                mac_only_detail=$3
                shift 3
            fi
        fi
        output=$(mktemp "$temp/release-check.XXXXXX")
        start=$(date +%s)
        { "$@"; echo "$?" > "$output.status"; } 2>&1 | tee "$output"
        status=$(cat "$output.status" 2> /dev/null || echo 1)
        seconds=$(($(date +%s) - start))
        counts() {
            lines "$output" | grep -E -- "$pattern" | sed -E 's/ \(list: [^)]*\)//' \
                | awk 'NR > 1 { printf "; " } { printf "%s", $0 }'
        }
        if [ "$status" -eq 0 ] && [ "$mode" = report ]; then
            outcome="ran: a report, not a gate"
            last=$(counts | cell)
        elif [ -n "$mac_only" ] && lines "$output" | tail -n 1 | grep -q -E -- "$mac_only"; then
            # The named failure of a part that only the Mac can run: the step passes, and the row says so, never a pass.
            status=0
            outcome="ran in part: a report, not a gate"
            last=$(printf '%s; %s' "$(counts)" "$mac_only_detail" | cell)
        else
            outcome="passed"
            [ "$status" -eq 0 ] || outcome="**FAILED** (exit $status)"
            last=$(lines "$output" | tail -n 1 | cell)
        fi
        rm -f "$output" "$output.status"
        row "$check" "$outcome" "$(minutes "$seconds")" "$last"
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
        # A fixed row, never a pass: the E2E suite runs on the Mac at make merge, as GitHub's Mac is too slow for it.
        row "make e2e" "not run here: runs on the Mac at make merge" "" \
            "too slow on GitHub's Mac for the Live Activity buttons: iOS stops their code at 30 s"
        if [ -f "$job_start" ]; then
            printf '\nThe job took %s minutes, from its start on the runner to this line.\n' \
                "$(minutes $(($(date +%s) - $(cat "$job_start"))))" >> "$summary"
        fi
        ;;
    *)
        usage
        ;;
esac
