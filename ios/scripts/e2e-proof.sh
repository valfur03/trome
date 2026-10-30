#!/bin/sh
# The record that make merge leaves on a commit of main when the full E2E suite passed on its tree, and its reader.
#
# The full E2E suite runs only on the Mac, at make merge: GitHub's Mac is too slow for the Live Activity buttons.
# So the release reads this record before it cuts a commit, and refuses a commit with none.
# The record is a commit status of GitHub, named "E2E on the Mac", on the commit of main that make merge pushed.
# Its text names the tree that the suite ran on, and the counts of the render check when make merge drew the views.
# A status is public and holds no secret; GitHub shows it next to the commit.
#
# Who can write it: only a token of the owner of the repo. The reader keeps only the statuses whose author is the owner,
# so a status that a workflow writes with its own token (author github-actions[bot]) never counts,
# and a pushed branch, which writes no status, cannot make one.
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
. "$scripts/code-paths.sh"

context="E2E on the Mac"
# The reader looks this many commits back at most, for a commit of main whose record covers the one that it reads.
max_walk=${TROME_E2E_PROOF_MAX_WALK:-50}

usage() {
    echo "Usage: $0 read [<commit>]    Say whether the commit (default HEAD) has a record of a full E2E pass on the Mac, and its render counts:" >&2
    echo "                             exit 0 when the record is found, 1 when it is missing, 2 when GitHub cannot be read." >&2
    echo "                             A commit with no record of its own is covered by the record of an older commit of main" >&2
    echo "                             when no commit since changes app code (the rule of make merge for skipping the suite)." >&2
    echo "                             The lines go to GITHUB_STEP_SUMMARY too, when it is set." >&2
    echo "       $0 publish <commit> [<render counts>]    Write the record on the commit, which must be on GitHub (make merge only)" >&2
    echo "       $0 render-counts <file>    Print the counts of the output of make live-activity-render, or nothing" >&2
    exit 2
}

short() {
    git rev-parse --short "$1"
}

# Runs a command, and stops it after $1 seconds: a hung network call must not hold the merge.
timed() {
    perl -e '$seconds = shift; alarm $seconds; exec @ARGV or die "cannot run $ARGV[0]: $!\n"' "$@"
}

# "too tall 0, cut texts 3, breaches 1" from the output of the render check, added up over its languages (fr and en),
# or nothing when a language misses a count (its text recognition failed): a count of one language only would hide a cut.
render_counts() {
    awk '
        function count(text) { sub(/^[^:]*: /, "", text); return text + 0 }
        /^== Language: / { languages++ }
        /^Too tall for their text size, in [a-z]+: [0-9]+/ { tall += count($0); n_tall++ }
        /^Cut texts in the images[^:]*: [0-9]+/ { cut += count($0); n_cut++ }
        /^Breaches of the cut rules[^:]*: [0-9]+/ { breaches += count($0); n_breaches++ }
        END {
            if (languages < 1) languages = 1
            if (n_tall == languages && n_cut == languages && n_breaches == languages)
                printf "too tall %d, cut texts %d, breaches %d\n", tall, cut, breaches
        }' "$1"
}

# The text of the record of the tree of $1, written by publish and checked by read.
record_text() {
    echo "Full E2E passed on tree $(git rev-parse "$1^{tree}"). Render: ${2:-not drawn}."
}

publish() {
    commit=$(git rev-parse --verify "$1^{commit}")
    timed 30 gh api -X POST "repos/{owner}/{repo}/statuses/$commit" -f state=success -f "context=$context" \
        -f "description=$(record_text "$commit" "${2:-}")" > /dev/null
}

# Prints the render counts of the record of the commit $1 ("not drawn" when the merge did not draw), or nothing when
# the commit has no record. Exits 1 when GitHub cannot be read.
record_of() {
    tree=$(git rev-parse "$1^{tree}")
    statuses=$(timed 30 gh api "repos/{owner}/{repo}/commits/$1/statuses?per_page=100" \
        --jq ".[] | select(.context == \"$context\" and .state == \"success\") | [.creator.login, .description] | @tsv" 2>&1) || {
        echo "$statuses" | tail -n 1
        return 1
    }
    # The newest first: the first record of the owner on this tree.
    printf '%s\n' "$statuses" | awk -F '\t' -v owner="$owner" -v tree="$tree" '
        $1 == owner && index($2, "on tree " tree ".") {
            if (match($2, /Render: too tall [0-9]+, cut texts [0-9]+, breaches [0-9]+/)) {
                print substr($2, RSTART + 8, RLENGTH - 8)
            } else {
                print "not drawn"
            }
            exit
        }'
}

# Exits 0 when the commit $1 changes a file for which the rule $2 is true. A first commit changes every file.
changes() {
    parent=$(git rev-parse -q --verify "$1^") || return 0
    diff_touches "$parent" "$1" "$2"
}

say() {
    echo "$1"
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "- $1" >> "$GITHUB_STEP_SUMMARY"
}

read_proof() {
    commit=$(git rev-parse --verify "$1^{commit}")
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '## E2E proof of %s\n\n' "$(short "$commit")" >> "$GITHUB_STEP_SUMMARY"
    if ! owner=$(timed 30 gh api "repos/{owner}/{repo}" --jq .owner.login 2>&1); then
        say "E2E proof: missing (GitHub could not be read: $(echo "$owner" | tail -n 1))"
        say "render counts: missing"
        return 2
    fi
    e2e=
    render=
    unreadable=0
    walked=0
    at=$commit
    while [ -z "$e2e" ] || [ -z "$render" ]; do
        if ! record=$(record_of "$at"); then
            [ -n "$e2e" ] || { e2e="missing (GitHub could not be read: $record)"; unreadable=1; }
            [ -n "$render" ] || render=missing
            break
        fi
        if [ -n "$record" ] && [ -z "$e2e" ]; then
            if [ "$at" = "$commit" ]; then
                e2e="found (the full E2E suite passed on the Mac on this tree)"
            else
                e2e="found (the full E2E suite passed on the Mac on $(short "$at"); the $walked commits since change no app code)"
            fi
        fi
        if [ -n "$record" ] && [ "$record" != "not drawn" ] && [ -z "$render" ]; then
            render="$record (drawn on the Mac on $(short "$at"))"
        fi
        if [ -z "$e2e" ] && changes "$at" is_app_code; then
            e2e="missing ($(short "$at") changes app code, and has no record of a full E2E pass on the Mac)"
        fi
        if [ -z "$render" ] && changes "$at" is_render_input; then
            render=missing
        fi
        walked=$((walked + 1))
        if [ -z "$e2e" ] || [ -z "$render" ]; then
            if [ "$walked" -ge "$max_walk" ]; then
                [ -n "$e2e" ] || e2e="missing (no record in the last $max_walk commits)"
                [ -n "$render" ] || render=missing
            else
                at=$(git rev-parse "$at^")
            fi
        fi
    done
    say "E2E proof: $e2e"
    say "render counts: $render"
    case "$render" in
        missing) ;;
        *) say "The render counts are shown, not compared: the first release sets the baseline." ;;
    esac
    case "$e2e" in
        found*) return 0 ;;
    esac
    return $((1 + unreadable))
}

[ $# -ge 1 ] || usage
case "$1" in
    read)
        [ $# -le 2 ] || usage
        read_proof "${2:-HEAD}"
        ;;
    publish)
        [ $# -ge 2 ] && [ $# -le 3 ] || usage
        publish "$2" "${3:-}"
        ;;
    render-counts)
        [ $# -eq 2 ] || usage
        render_counts "$2"
        ;;
    *)
        usage
        ;;
esac
