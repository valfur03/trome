#!/bin/sh
# make full-run: every check on the head of main, in a temporary worktree that goes on every ending (pass, red, stop).
# The checks are stand-ins: no build and no Simulator.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null TMPDIR="$state/tmp" TROME_LOGS="$state/logs" STATE="$state"
unset FACTORY_CHECK_WHERE TROME_FULL_RUN_CHECK TROME_FULL_RUN_ARCHIVE TROME_FULL_RUN_E2E TROME_FULL_RUN_RELEASE_RUN \
    TROME_FULL_RUN_RENDER E2E_RETRY TROME_E2E_FLAKY GITHUB_STEP_SUMMARY || true
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir "$state/tmp"

cleanup() {
    kill ${background:-} 2> /dev/null || true
    [ ! -f "$state/check.pid" ] || kill "$(cat "$state/check.pid")" 2> /dev/null || true
    rm -rf "$state"
}
trap cleanup EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

wait_for() {
    tries=0
    until "$@" || [ "$tries" -ge 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
}

# A repo whose main folder has another branch checked out: the run takes the head of main, not the folder's.
repo="$state/repo"
git init -q -b main "$repo"
mkdir -p "$repo/ios/scripts"
cp "$scripts/full-run.sh" "$scripts/e2e-proof.sh" "$scripts/code-paths.sh" "$repo/ios/scripts/"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m main
main_head=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q -b task/9
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m branch

# Each stand-in writes its name, the commit of its folder, its place in the ledger, whether make e2e would retry a failed
# test, and the E2E classes that a caller asked for, then passes.
record='echo "$0 $(git rev-parse HEAD) $FACTORY_CHECK_WHERE ${E2E_RETRY:-no-retry} ${ONLY:-all}" >> "$STATE/ran"'
export TROME_FULL_RUN_CHECK="sh -c '$record' check" TROME_FULL_RUN_ARCHIVE="sh -c '$record' archive" \
    TROME_FULL_RUN_E2E="sh -c '$record' e2e" TROME_FULL_RUN_RELEASE_RUN="sh -c '$record' release-run" \
    TROME_FULL_RUN_RENDER="sh -c '$record' render"

worktrees() {
    git -C "$repo" worktree list --porcelain | grep -c '^worktree '
}

leftovers() {
    ls -A "$state/tmp" | wc -l | tr -d ' '
}

status=0
"$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
expect "a run where every check passes exits 0" "$status" "0"
expect "it runs each check once, in that order" "$(cut -d ' ' -f 1 "$state/ran" | tr '\n' ' ')" "check archive e2e release-run render "
expect "each check runs at the head of main, not of the folder's branch" "$(cut -d ' ' -f 2 "$state/ran" | sort -u)" "$main_head"
expect "each check writes the ledger with the place main" "$(cut -d ' ' -f 3 "$state/ran" | sort -u)" "main"
expect "only the E2E suite retries a failed test" "$(cut -d ' ' -f 1,4 "$state/ran" | tr '\n' ' ')" \
    "check no-retry archive no-retry e2e 1 release-run no-retry render no-retry "
expect "with no remote, it says that it leaves no record for the release" "$(grep -c "^full-run: no remote 'origin', so no record for the release$" "$state/out")" "1"
expect "it prints one line per check" "$(grep -c ': OK (' "$state/out")" "5"
expect "it ends with a verdict" "$(tail -n 1 "$state/out" | sed -E 's/ at [0-9a-f]+ / at <commit> /')" "full-run: OK on main at <commit> (5 checks)"
expect "a pass removes the temporary worktree" "$(worktrees) $(leftovers)" "1 0"

rm "$state/ran"
status=0
TROME_FULL_RUN_E2E="sh -c '$record; exit 2' e2e" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
expect "a red check makes the run exit 1" "$status" "1"
expect "a red check names its log" "$(grep '^e2e: ' "$state/out" | sed -E 's/, [0-9]+ s\)/)/')" \
    "e2e: RED (exit 2); its whole output: $state/logs/full-run/e2e.log"
expect "the checks after a red one still run" "$(cut -d ' ' -f 1 "$state/ran" | tr '\n' ' ')" "check archive e2e release-run render "
expect "the verdict names the red checks" "$(tail -n 1 "$state/out" | sed -E 's/ at [0-9a-f]+:/ at <commit>:/')" \
    "full-run: RED on main at <commit>: e2e (5 checks)"
expect "a red run removes the temporary worktree" "$(worktrees) $(leftovers)" "1 0"

rm "$state/ran"
ONLY=SnoozeTests "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || true
expect "a list of E2E classes of the caller does not narrow the full suite" "$(grep '^e2e ' "$state/ran" | cut -d ' ' -f 5)" "all"

# The record that the release reads: after a pass, the run pushes main and leaves the status 'E2E on the Mac' on its commit
# (a fake gh, as in e2e-proof-test.sh); merge-test.sh shows that a merge leaves none.
export PATH="$tests/bin:$PATH" FAKE_GH_STATE="$state/gh"
mkdir -p "$FAKE_GH_STATE/statuses"
git init -q --bare "$state/origin.git"
git -C "$repo" remote add origin "$state/origin.git"
record_of() {
    jq -r '.[0].description' "$FAKE_GH_STATE/statuses/$1.json" 2> /dev/null || echo "no record"
}
render_counts='echo "Too tall for their text size, in fr: 0"; echo "Cut texts in the images (OCR): 5"; echo "Breaches of the cut rules (texts cut too much): 1"'
TROME_FULL_RUN_RENDER="sh -c '$render_counts'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
tree=$(git -C "$repo" rev-parse "$main_head^{tree}")
expect "a pass pushes main to origin" "$(git -C "$state/origin.git" rev-parse main)" "$main_head"
expect "a pass leaves on the commit of main the record of the full run, with its render counts" "$(record_of "$main_head")" \
    "Full E2E passed on tree $tree. Render: too tall 0, cut texts 5, breaches 1. Release run: passed."
expect "it says so, before its verdict" "$(tail -n 2 "$state/out" | head -n 1 | sed -E 's/ on [0-9a-f]+ / on <commit> /')" \
    "full-run: left on <commit> the record that a release reads (the status 'E2E on the Mac' on GitHub), render: too tall 0, cut texts 5, breaches 1"
expect "the release then accepts that commit" "$(cd "$repo" && ios/scripts/e2e-proof.sh read "$main_head" > /dev/null 2>&1 && echo accepted || echo refused)" "accepted"

rm "$FAKE_GH_STATE/statuses/$main_head.json"
TROME_FULL_RUN_E2E="sh -c 'exit 2'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || true
expect "a red E2E suite leaves no record, and says why" "$(record_of "$main_head") $(grep -c '^full-run: no record for the release: a check that it needs is red$' "$state/out")" "no record 1"
TROME_FULL_RUN_RELEASE_RUN="sh -c 'exit 2'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || true
expect "a red Release app run leaves no record" "$(record_of "$main_head")" "no record"
TROME_FULL_RUN_CHECK="sh -c 'exit 2'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || true
expect "a red gate leaves no record" "$(record_of "$main_head")" "no record"

status=0
TROME_FULL_RUN_RENDER="sh -c 'exit 2'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
expect "a red render check is a report: the run is red, but it leaves the record, which says 'not drawn'" "$status $(record_of "$main_head")" \
    "1 Full E2E passed on tree $tree. Render: not drawn. Release run: passed."

# A test that failed, then passed on its retry: make e2e writes its name in TROME_E2E_FLAKY (e2e-failures.py).
rm "$FAKE_GH_STATE/statuses/$main_head.json"
status=0
TROME_FULL_RUN_E2E="sh -c 'echo SnoozeTests/testSnooze\(\) >> \"\$TROME_E2E_FLAKY\"'" "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
expect "a flaky test is a pass of the run, and of the record" "$status $(record_of "$main_head" | cut -c1-15)" "0 Full E2E passed"
expect "the run names the flaky test, and says to file a bug for it" "$(grep '^e2e: flaky' "$state/out")" \
    "e2e: flaky tests (each failed, then passed on its retry): SnoozeTests/testSnooze(). File a bug labelled flaky for each one, or add this run to its open bug (see 'Flaky tests' in CLAUDE.md); the log: $state/logs/full-run/e2e.log"

touch "$FAKE_GH_STATE/fail"
rm "$FAKE_GH_STATE/statuses/$main_head.json"
status=0
"$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 || status=$?
rm "$FAKE_GH_STATE/fail"
expect "when GitHub does not take the record, the run still passes, and says that a release refuses the commit" \
    "$status $(grep -c '^full-run: GitHub did not take the record of this pass, so a release refuses ' "$state/out")" "0 1"
git -C "$repo" remote remove origin

# A stop while a check runs: the check gets it too, and the worktree goes once it has ended.
for signal in TERM INT HUP; do
    rm -f "$state/ran" "$state/started" "$state/check.pid"
    # A command started in the background ignores INT; perl puts it back, as a terminal would send it.
    TROME_FULL_RUN_E2E="sh -c 'echo \$\$ > \"\$STATE/check.pid\"; touch \"\$STATE/started\"; exec sleep 600'" \
        perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$repo/ios/scripts/full-run.sh" > "$state/out" 2>&1 &
    background=$!
    wait_for test -e "$state/started"
    kill "-$signal" "$background"
    status=0
    wait "$background" || status=$?
    background=
    case $signal in TERM) code=143 ;; INT) code=130 ;; HUP) code=129 ;; esac
    expect "a run stopped by $signal exits as stopped" "$status" "$code"
    expect "a run stopped by $signal stops its running check" \
        "$(kill -0 "$(cat "$state/check.pid")" 2> /dev/null && echo running || echo stopped)" "stopped"
    expect "a run stopped by $signal runs no check after it" "$(cut -d ' ' -f 1 "$state/ran" | tr '\n' ' ')" "check archive "
    expect "a run stopped by $signal removes the temporary worktree" "$(worktrees) $(leftovers)" "1 0"
done

expect "the run itself starts no Simulator command: its checks go through make and the lock" \
    "$(grep -cE 'xcrun|simctl|xcodebuild|simulator\.sh|sim-lock\.sh' "$scripts/full-run.sh" || true)" "0"

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "full-run-test: all checks passed"
