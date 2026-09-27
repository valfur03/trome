#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE ONLY RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID || true
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" RATP_SIM_POLL_SECONDS=1 RATP_MERGE_LOCK="$state/merge.lock" SCRIPTS="$scripts"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 & echo $! > "$state/idle-watcher/pid")
idle_watcher=$(cat "$state/idle-watcher/pid")
echo "$idle_watcher" > "$RATP_SIM_LOCK.slots-watcher"

cleanup() {
    kill "$idle_watcher" "$(cat "$RATP_SIM_LOCK.slots-watcher" 2> /dev/null)" 2> /dev/null || true
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

contains() {
    grep -qF "$2" "$1" && echo yes || echo no
}

commit() {
    echo "$3" > "$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "change $2"
}

new_task() {
    git -C "$repo" worktree add -q -b "task/$1" "$state/$1" main
}

advance_main() {
    commit "$repo" "$1" "$2"
}

rev() {
    git -C "$repo" rev-parse "$1"
}

step_recorder() {
    printf 'echo %s >> "$FAKE_SIM_STATE/steps" && test -e "$RATP_SIM_LOCK/pid" && echo %s-locked >> "$FAKE_SIM_STATE/steps"' "$1" "$1"
}

start_merge() {
    (cd "$state/$1" && { "$scripts/merge.sh" > "$state/$1.log" 2>&1 && echo 0 || echo $?; } > "$state/$1.new" && mv "$state/$1.new" "$state/$1.status") &
    eval "merge_$1=\$!"
}

finish_merge() {
    tries=0
    while [ ! -e "$state/$1.status" ] && [ "$tries" -lt 30 ]; do
        sleep 1
        tries=$((tries + 1))
    done
    eval "pid=\$merge_$1"
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    cat "$state/$1.status" 2> /dev/null || echo "still running"
}

merge() {
    : > "$state/steps"
    : > "$state/refs"
    start_merge "$1"
    status=$(finish_merge "$1")
}

lock_state() {
    test -e "$RATP_SIM_LOCK" && echo held || echo free
}

git init -q -b main "$repo"
commit "$repo" base base
cat > "$repo/.git/hooks/reference-transaction" << 'EOF'
#!/bin/sh
[ "$1" = committed ] || exit 0
while read -r old new ref; do
    case "$ref" in
        refs/heads/*)
            if [ -e "$RATP_SIM_LOCK/pid" ]; then held=locked; else held=free; fi
            echo "$ref $held" >> "$FAKE_SIM_STATE/refs"
            ;;
    esac
done
EOF
chmod +x "$repo/.git/hooks/reference-transaction"

passing_check="$(step_recorder check)"
passing_e2e="$(step_recorder e2e) && \"\$SCRIPTS/sim-lock.sh\" job sh -c 'echo nested-job >> \"\$FAKE_SIM_STATE/steps\"'"
export RATP_MERGE_CHECK="$passing_check" RATP_MERGE_E2E="$passing_e2e"

new_task ok
commit "$state/ok" ok ok
advance_main other other
before=$(rev main)
merge ok
expect "make merge succeeds" "$status" "0"
expect "make merge rebases the task, runs the gate, then the full E2E suite, all with the Simulator lock" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "
expect "make merge holds the lock from the rebase to the fast-forward" "$(tr '\n' ' ' < "$state/refs")" "refs/heads/task/ok locked refs/heads/main locked "
expect "main is now the rebased task branch" "$(rev main)" "$(rev task/ok)"
expect "the task branch was rebased onto the tip of main" "$(rev task/ok~1)" "$before"
expect "main has no merge commit" "$(git -C "$repo" rev-list --merges main)" ""
expect "make merge frees the Simulator lock when it succeeds" "$(lock_state)" "free"
expect "the folder where main is checked out has the files of the task" "$(cat "$repo/ok")" "ok"
expect "the folder where main is checked out has no change left" "$(git -C "$repo" status --porcelain)" ""

git -C "$repo" checkout -q --detach main
new_task detached
commit "$state/detached" detached detached
merge detached
git -C "$repo" checkout -q main
expect "make merge succeeds when main is checked out nowhere" "$status" "0"
expect "main is the task branch when main is checked out nowhere" "$(rev main)" "$(rev task/detached)"

new_task busy
commit "$state/busy" base "from the task"
echo "not committed" > "$repo/base"
before=$(rev main)
merge busy
git -C "$repo" checkout -q -- base
expect "make merge fails when the folder of main has changes on the files of the task" "$status" "1"
expect "make merge leaves main unchanged when it cannot update the folder of main" "$(rev main)" "$before"
expect "make merge says what to do with the changes of the folder of main" "$(contains "$state/busy.log" "Commit or stash the changes of that folder")" "yes"
expect "make merge frees the Simulator lock when it cannot update the folder of main" "$(lock_state)" "free"

new_task merged
commit "$state/merged" merged merged
advance_main before-merged before-merged
git -C "$state/merged" merge -q --no-edit main
git -C "$repo" config rebase.rebaseMerges true
merge merged
git -C "$repo" config --unset rebase.rebaseMerges
expect "make merge succeeds on a task branch with a merge commit" "$status" "0"
expect "make merge drops the merge commit of the task branch, even when git keeps merges by default" "$(git -C "$repo" rev-list --merges main)" ""

new_task docs
mkdir -p "$state/docs/docs"
commit "$state/docs" docs/page page
commit "$state/docs" README.md readme
merge docs
expect "make merge of a task that changes only docs succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only docs" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "
expect "make merge says why it skips the E2E suite" "$(contains "$state/docs.log" "changes no app code")" "yes"
expect "main is the task that changes only docs" "$(rev main)" "$(rev task/docs)"

advance_main app app
new_task moved
mkdir -p "$state/moved/docs"
git -C "$state/moved" mv app docs/app
git -C "$state/moved" commit -q -m "move app into docs"
merge moved
expect "make merge runs the E2E suite when the task moves app code into docs" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "

new_task gate
commit "$state/gate" gate gate
before=$(rev main)
RATP_MERGE_CHECK="$passing_check && exit 1"
merge gate
RATP_MERGE_CHECK=$passing_check
expect "make merge fails when the quality gate fails" "$status" "1"
expect "make merge does not run the E2E suite after a failed gate" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "
expect "make merge leaves main unchanged when the gate fails" "$(rev main)" "$before"
expect "make merge says that the gate failed" "$(contains "$state/gate.log" "the step 'quality gate' failed")" "yes"
expect "make merge frees the Simulator lock when the gate fails" "$(lock_state)" "free"

new_task e2e
commit "$state/e2e" e2e e2e
RATP_MERGE_E2E="$passing_e2e && exit 1"
merge e2e
RATP_MERGE_E2E=$passing_e2e
expect "make merge fails when the E2E suite fails" "$status" "1"
expect "make merge leaves main unchanged when the E2E suite fails" "$(rev main)" "$before"
expect "make merge says that the E2E suite failed" "$(contains "$state/e2e.log" "the step 'full E2E suite' failed")" "yes"
expect "make merge frees the Simulator lock when the E2E suite fails" "$(lock_state)" "free"

new_task conflict
commit "$state/conflict" shared "from the task"
advance_main shared "from main"
before=$(rev main)
merge conflict
expect "make merge fails on a rebase conflict" "$status" "1"
expect "make merge runs no gate after a rebase conflict" "$(cat "$state/steps")" ""
expect "make merge leaves main unchanged after a rebase conflict" "$(rev main)" "$before"
expect "make merge says that the rebase failed" "$(contains "$state/conflict.log" "the step 'rebase' failed")" "yes"
expect "make merge frees the Simulator lock after a rebase conflict" "$(lock_state)" "free"
git -C "$state/conflict" rebase --abort

new_task dirty
commit "$state/dirty" dirty dirty
echo change > "$state/dirty/dirty"
merge dirty
expect "make merge refuses a worktree with changes that are not committed" "$status" "1"
expect "make merge does not rebase a worktree with changes" "$(cat "$state/refs")" ""

new_task only
commit "$state/only" only only
ONLY=SnoozeTests
export ONLY
merge only
unset ONLY
expect "make merge refuses ONLY, so the E2E suite is always the full one" "$(contains "$state/only.log" "ONLY works only with 'make e2e'")" "yes"
expect "make merge with ONLY does not rebase" "$(cat "$state/refs")" ""

merge repo
expect "make merge refuses to run on main" "$(contains "$state/repo.log" "you are on 'main'")" "yes"

new_task empty
merge empty
expect "make merge refuses a branch with nothing to merge" "$(contains "$state/empty.log" "There is nothing to merge")" "yes"

new_task first
new_task second
commit "$state/first" first first
commit "$state/second" second second
before=$(rev main)
: > "$state/steps"
RATP_MERGE_CHECK="sleep 2 && $passing_check"
start_merge first
sleep 1
start_merge second
expect "the first of two merges started together succeeds" "$(finish_merge first)" "0"
expect "the second of two merges started together succeeds" "$(finish_merge second)" "0"
expect "the second merge waits for the first one" "$(contains "$state/second.log" "waiting for the merge of another worktree")" "yes"
expect "the second merge rebases onto main after the fast-forward of the first one" "$(rev main~1) $(rev main~2)" "$(rev task/first) $before"
expect "main is the second task branch" "$(rev main)" "$(rev task/second)"
expect "main has no merge commit after two merges" "$(git -C "$repo" rev-list --merges main)" ""

new_task slot1
new_task slot2
commit "$state/slot1" slot1 slot1
commit "$state/slot2" slot2 slot2
before=$(rev main)
export RATP_SIM_SLOTS=2 RATP_SIM_MIN_IDLE_PERCENT=0
start_merge slot1
sleep 1
start_merge slot2
expect "with two Simulator slots, the first of two merges succeeds" "$(finish_merge slot1)" "0"
expect "with two Simulator slots, the second merge succeeds" "$(finish_merge slot2)" "0"
expect "with two Simulator slots, the second merge still waits for the first one" "$(rev main~1) $(rev main~2)" "$(rev task/slot1) $before"
unset RATP_SIM_SLOTS RATP_SIM_MIN_IDLE_PERCENT

[ "$failures" -eq 0 ]
