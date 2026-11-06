#!/bin/sh
# Runs every check of the app on the head of main, in a temporary worktree: the gate, the release archive, the full E2E
# suite (a failed test retried once), the run of the Release app and the render check. The Simulator checks take the
# Simulator lane as any job does, through their make commands. It prints one line per check and a verdict, and exits 1
# when a check is red.
# Why: a merge runs the checks of what it changed; this run catches what that choice can miss.
# After a pass of the gate, the release archive, the E2E suite and the Release app run, it pushes main and leaves on the
# commit the record that the release reads ('E2E on the Mac', e2e-proof.sh), with the counts of the render check (a report).
# The temporary worktree goes on every ending: a pass, a red check, or a stop (TERM, INT, HUP).
# The docs, server and film checks are not in it: each one reads only its own part, and make check runs it at every
# change of that part.
set -u

scripts=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$scripts/../.." && pwd)
base=main
logs=${TROME_LOGS:-$HOME/Library/Logs/TROME}/full-run
# A script test puts stand-ins for these commands: it runs no build and no Simulator.
checks="check release-archive-check e2e release-run-check live-activity-render"
command_of() {
    case $1 in
        check) echo "${TROME_FULL_RUN_CHECK:-make check}" ;;
        release-archive-check) echo "${TROME_FULL_RUN_ARCHIVE:-make release-archive-check}" ;;
        e2e) echo "${TROME_FULL_RUN_E2E:-make e2e}" ;;
        release-run-check) echo "${TROME_FULL_RUN_RELEASE_RUN:-make release-run-check}" ;;
        live-activity-render) echo "${TROME_FULL_RUN_RENDER:-make live-activity-render}" ;;
    esac
}

# The checks write the check ledger with this place, whoever started the run.
FACTORY_CHECK_WHERE=main
export FACTORY_CHECK_WHERE
# The record says that the full suite passed: no class list of the caller may narrow it.
unset ONLY

head=$(git -C "$repo" rev-parse --verify --quiet "$base^{commit}") || {
    echo "full-run: no branch $base in $repo" >&2
    exit 2
}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/trome-full-run.XXXXXX") || exit 2
work="$temporary/main"
child=
stopped=

remove_worktree() {
    git -C "$repo" worktree remove --force "$work" > /dev/null 2>&1 || true
    rm -rf "$temporary"
    git -C "$repo" worktree prune > /dev/null 2>&1 || true
}

# A check runs in its own process group: a stop reaches every process of the check (make, the lock, the test run),
# and the lock frees the Simulator only when its job has ended, so the worktree goes only after the check.
stop_check() {
    stopped=$1
    if [ -n "$child" ]; then
        kill -TERM -- "-$child" 2> /dev/null || kill -TERM "$child" 2> /dev/null || true
    fi
}

on_exit() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$child" ]; then
        while kill -0 -- "-$child" 2> /dev/null || kill -0 "$child" 2> /dev/null; do
            sleep 1
        done
    fi
    remove_worktree
    exit "$status"
}

trap on_exit EXIT
trap 'stop_check 129' HUP
trap 'stop_check 130' INT
trap 'stop_check 143' TERM

[ -z "$stopped" ] || exit "$stopped"
if ! git -C "$repo" worktree add --detach "$work" "$head" > /dev/null 2>&1; then
    echo "full-run: cannot create a worktree at $base ($head) in $temporary" >&2
    exit 2
fi
mkdir -p "$logs" || exit 2
echo "full-run: $base at $(git -C "$repo" rev-parse --short "$head"), in $work; the logs are in $logs"

red=
count=0
for name in $checks; do
    [ -z "$stopped" ] || exit "$stopped"
    started=$(date +%s)
    log="$logs/$name.log"
    # Only the E2E suite retries a failed test, and writes the names of the tests that passed only on their retry.
    (cd "$work" && { [ "$name" != e2e ] || export E2E_RETRY=1 TROME_E2E_FLAKY="$temporary/flaky"; } && exec perl -MPOSIX -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; setsid(); exec @ARGV' sh -c "$(command_of "$name")") \
        > "$log" 2>&1 < /dev/null &
    child=$!
    status=0
    while :; do
        status=0
        wait "$child" || status=$?
        # A signal ends the wait while the check still runs: wait again.
        kill -0 "$child" 2> /dev/null || break
    done
    while kill -0 -- "-$child" 2> /dev/null; do
        sleep 1
    done
    child=
    seconds=$(($(date +%s) - started))
    if [ -n "$stopped" ]; then
        echo "$name: STOPPED ($seconds s); the run stops here, and removes its worktree"
        exit "$stopped"
    fi
    count=$((count + 1))
    if [ "$status" -eq 0 ]; then
        echo "$name: OK ($seconds s)"
    else
        echo "$name: RED (exit $status, $seconds s); its whole output: $log"
        red="$red${red:+, }$name"
    fi
done

if [ -s "$temporary/flaky" ]; then
    echo "e2e: flaky tests (each failed, then passed on its retry): $(paste -s -d ',' "$temporary/flaky" | sed 's/,/, /g'). File a bug labelled flaky for each one, or add this run to its open bug (see 'Flaky tests' in CLAUDE.md); the log: $logs/e2e.log"
fi

# The record that the release reads. GitHub keeps a status only for a commit that it has, so the run pushes main first;
# a push that git refuses (main on GitHub is already past this commit) is fine. The render check is a report, as at a merge.
publish_record() {
    git -C "$repo" remote get-url origin > /dev/null 2>&1 || {
        echo "full-run: no remote 'origin', so no record for the release"
        return 0
    }
    perl -e 'alarm 120; exec @ARGV' git -C "$repo" push -q origin "$head:refs/heads/$base" > /dev/null 2>&1 || true
    render_counts=$("$scripts/e2e-proof.sh" render-counts "$logs/live-activity-render.log" 2> /dev/null || true)
    case " $red, " in *" live-activity-render,"*) render_counts= ;; esac
    if ! (cd "$repo" && "$scripts/e2e-proof.sh" publish "$head" "$render_counts") > "$temporary/publish.err" 2>&1; then
        echo "full-run: GitHub did not take the record of this pass, so a release refuses $(git -C "$repo" rev-parse --short "$head") until the next full run: $(tail -n 1 "$temporary/publish.err")"
        return 0
    fi
    echo "full-run: left on $(git -C "$repo" rev-parse --short "$head") the record that a release reads (the status 'E2E on the Mac' on GitHub), render: ${render_counts:-not drawn}"
}

case " $red, " in
    *" check,"* | *" release-archive-check,"* | *" e2e,"* | *" release-run-check,"*)
        echo "full-run: no record for the release: a check that it needs is red"
        ;;
    *) publish_record ;;
esac

if [ -n "$red" ]; then
    echo "full-run: RED on $base at $(git -C "$repo" rev-parse --short "$head"): $red ($count checks)"
    exit 1
fi
echo "full-run: OK on $base at $(git -C "$repo" rev-parse --short "$head") ($count checks)"
