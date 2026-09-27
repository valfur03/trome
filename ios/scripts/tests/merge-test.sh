#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID || true
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" RATP_SIM_POLL_SECONDS=1 SCRIPTS="$scripts"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch > /dev/null 2>&1 & echo $! > "$state/idle-watcher/pid")
idle_watcher=$(cat "$state/idle-watcher/pid")
echo "$idle_watcher" > "$RATP_SIM_LOCK.slots-watcher"

cleanup() {
    kill "$idle_watcher" 2> /dev/null || true
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
    git -C "$repo" worktree add -q -b "task/$1" "$state/$1" develop
}

advance_develop() {
    git -C "$state/helper" checkout -q --detach develop
    commit "$state/helper" "$1" "$2"
    git -C "$repo" update-ref refs/heads/develop "$(git -C "$state/helper" rev-parse HEAD)"
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
git -C "$repo" branch develop
git -C "$repo" worktree add -q --detach "$state/helper" develop
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
advance_develop other other
before=$(rev develop)
merge ok
expect "make merge succeeds" "$status" "0"
expect "make merge rebases the task, runs the gate, then the full E2E suite, all with the Simulator lock" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "
expect "make merge holds the lock from the rebase to the fast-forward" "$(tr '\n' ' ' < "$state/refs")" "refs/heads/task/ok locked refs/heads/develop locked "
expect "develop is now the rebased task branch" "$(rev develop)" "$(rev task/ok)"
expect "the task branch was rebased onto the tip of develop" "$(rev task/ok~1)" "$before"
expect "develop has no merge commit" "$(git -C "$repo" rev-list --merges develop)" ""
expect "make merge frees the Simulator lock when it succeeds" "$(lock_state)" "free"

new_task docs
mkdir -p "$state/docs/docs"
commit "$state/docs" docs/page page
commit "$state/docs" README.md readme
merge docs
expect "make merge of a task that changes only docs succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only docs" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "
expect "make merge says why it skips the E2E suite" "$(contains "$state/docs.log" "changes no app code")" "yes"
expect "develop is the task that changes only docs" "$(rev develop)" "$(rev task/docs)"

new_task gate
commit "$state/gate" gate gate
before=$(rev develop)
RATP_MERGE_CHECK="$passing_check && exit 1"
merge gate
RATP_MERGE_CHECK=$passing_check
expect "make merge fails when the quality gate fails" "$status" "1"
expect "make merge does not run the E2E suite after a failed gate" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "
expect "make merge leaves develop unchanged when the gate fails" "$(rev develop)" "$before"
expect "make merge says that the gate failed" "$(contains "$state/gate.log" "the step 'quality gate' failed")" "yes"
expect "make merge frees the Simulator lock when the gate fails" "$(lock_state)" "free"

new_task e2e
commit "$state/e2e" e2e e2e
RATP_MERGE_E2E="$passing_e2e && exit 1"
merge e2e
RATP_MERGE_E2E=$passing_e2e
expect "make merge fails when the E2E suite fails" "$status" "1"
expect "make merge leaves develop unchanged when the E2E suite fails" "$(rev develop)" "$before"
expect "make merge says that the E2E suite failed" "$(contains "$state/e2e.log" "the step 'full E2E suite' failed")" "yes"
expect "make merge frees the Simulator lock when the E2E suite fails" "$(lock_state)" "free"

new_task conflict
commit "$state/conflict" shared "from the task"
advance_develop shared "from develop"
before=$(rev develop)
merge conflict
expect "make merge fails on a rebase conflict" "$status" "1"
expect "make merge runs no gate after a rebase conflict" "$(cat "$state/steps")" ""
expect "make merge leaves develop unchanged after a rebase conflict" "$(rev develop)" "$before"
expect "make merge says that the rebase failed" "$(contains "$state/conflict.log" "the step 'rebase' failed")" "yes"
expect "make merge frees the Simulator lock after a rebase conflict" "$(lock_state)" "free"
git -C "$state/conflict" rebase --abort

new_task dirty
commit "$state/dirty" dirty dirty
echo change > "$state/dirty/dirty"
merge dirty
expect "make merge refuses a worktree with changes that are not committed" "$status" "1"
expect "make merge does not rebase a worktree with changes" "$(cat "$state/refs")" ""

new_task empty
merge empty
expect "make merge refuses a branch with nothing to merge" "$(contains "$state/empty.log" "There is nothing to merge")" "yes"

new_task first
new_task second
commit "$state/first" first first
commit "$state/second" second second
before=$(rev develop)
: > "$state/steps"
RATP_MERGE_CHECK="sleep 2 && $passing_check"
start_merge first
sleep 1
start_merge second
expect "the first of two merges started together succeeds" "$(finish_merge first)" "0"
expect "the second of two merges started together succeeds" "$(finish_merge second)" "0"
expect "the second merge waits for the Simulator lock of the first one" "$(contains "$state/second.log" "Waiting for the Simulator lock")" "yes"
expect "the second merge rebases onto develop after the fast-forward of the first one" "$(rev develop~1) $(rev develop~2)" "$(rev task/first) $before"
expect "develop is the second task branch" "$(rev develop)" "$(rev task/second)"
expect "develop has no merge commit after two merges" "$(git -C "$repo" rev-list --merges develop)" ""

[ "$failures" -eq 0 ]
