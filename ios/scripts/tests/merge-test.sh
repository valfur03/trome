#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE ONLY RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_MERGE_QUEUE || true
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
export TROME_MERGE_CHECK="$passing_check" TROME_MERGE_E2E="$passing_e2e"

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

mkfifo "$state/release-merge-lock"
lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
merge_lock_holder=$!
until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
new_task busy
commit "$state/busy" base "from the task"
commit "$state/busy" fresh "from the task"
commit "$state/busy" staged "from the task"
echo "not committed" > "$repo/base"
echo "not committed" > "$repo/fresh"
echo "not committed" > "$repo/staged"
git -C "$repo" add staged
before=$(rev main)
merge busy
echo release > "$state/release-merge-lock"
wait "$merge_lock_holder"
expect "make merge refuses at once, before the locks, when the folder of main has changes on the files of the task" "$status" "1"
expect "make merge does not wait for the locks when the folder of main has changes on the files of the task" "$(contains "$state/busy.log" "waiting for the merge of another worktree")" "no"
expect "make merge does not rebase when the folder of main has changes on the files of the task" "$(cat "$state/refs")" ""
expect "make merge runs no gate when the folder of main has changes on the files of the task" "$(cat "$state/steps")" ""
expect "make merge says in which folder main is checked out" "$(contains "$state/busy.log" "main is checked out in $(cd "$repo" && pwd -P),")" "yes"
expect "make merge names a changed file of the folder of main" "$(contains "$state/busy.log" "  base")" "yes"
expect "make merge names a file of the folder of main that git does not track" "$(contains "$state/busy.log" "  fresh")" "yes"
expect "make merge names a staged file of the folder of main" "$(contains "$state/busy.log" "  staged")" "yes"
expect "make merge says that the fast-forward would not be able to update these files" "$(contains "$state/busy.log" "The fast-forward would not be able to update these files.")" "yes"
expect "make merge says that the changes of the folder of main belong to the owner of that folder" "$(contains "$state/busy.log" "These changes belong to the owner of that folder. Ask the owner to commit, stash or drop them")" "yes"
expect "make merge leaves main unchanged when the folder of main has changes on the files of the task" "$(rev main)" "$before"
expect "make merge leaves the changes of the folder of main as they were" "$(cat "$repo/base") $(git -C "$repo" status --porcelain | tr '\n' ' ')" "not committed  M base A  staged ?? fresh "
git -C "$repo" rm -q --cached staged
rm "$repo/fresh" "$repo/staged"
git -C "$repo" checkout -q -- base

new_task elsewhere
commit "$state/elsewhere" elsewhere elsewhere
echo "not committed" > "$repo/base"
merge elsewhere
expect "make merge succeeds when the folder of main has changes only on files that the task does not change" "$status" "0"
expect "main is the task branch when the folder of main has changes on other files" "$(rev main)" "$(rev task/elsewhere)"
expect "make merge keeps the changes of the folder of main on other files" "$(cat "$repo/base")" "not committed"
git -C "$repo" checkout -q -- base

new_task late
commit "$state/late" late "from the task"
before=$(rev main)
TROME_MERGE_CHECK="$passing_check && echo 'not committed' > '$repo/late'"
merge late
TROME_MERGE_CHECK=$passing_check
rm "$repo/late"
expect "make merge fails when the folder of main gets changes on the files of the task during the run" "$status" "1"
expect "make merge leaves main unchanged when it cannot update the folder of main" "$(rev main)" "$before"
expect "make merge says that the fast-forward failed" "$(contains "$state/late.log" "the step 'fast-forward' failed")" "yes"
expect "make merge says that the changes of the folder of main during the run belong to the owner of that folder" "$(contains "$state/late.log" "These changes belong to the owner of that folder. Ask the owner to commit, stash or drop them")" "yes"
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

new_task server
mkdir -p "$state/server/server/src" "$state/server/contracts/prim"
commit "$state/server" server/src/worker.ts worker
commit "$state/server" contracts/prim/answer.json answer
merge server
expect "make merge of a task that changes only the server and the contracts succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only the server and the contracts" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "

new_task markdown
mkdir -p "$state/markdown/ios/guide" "$state/markdown/.claude/rules" "$state/markdown/ios/Packages/TROMECore/Tests/TROMECoreTests/Stations"
for file in CONTRIBUTING.md ARCHITECTURE.md NOTICE.md LICENSE ios/README.md ios/guide/stations.md ios/guide/page.mdx .claude/rules/docs.md .claude/settings.json ios/Packages/TROMECore/Tests/TROMECoreTests/Stations/StationTests.swift; do
    commit "$state/markdown" "$file" text
done
merge markdown
expect "make merge of a task that changes only Markdown, LICENSE, .claude/ and the unit tests succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only Markdown or MDX files, LICENSE, .claude/ and the unit tests" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "

new_task github
mkdir -p "$state/github/.github/workflows" "$state/github/.github/ISSUE_TEMPLATE"
commit "$state/github" .github/workflows/docs-site.yml workflow
commit "$state/github" .github/ISSUE_TEMPLATE/bug.yml form
merge github
expect "make merge of a task that changes only .github/ succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only .github/, which no build and no test reads" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "

new_task github_app
mkdir -p "$state/github_app/.github/workflows" "$state/github_app/ios/App"
commit "$state/github_app" .github/workflows/docs-site.yml "new workflow"
commit "$state/github_app" ios/App/Feature.swift code
merge github_app
expect "make merge runs the E2E suite when the task changes .github/ and app code" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "

for folder in ios/App ios/Widget ios/UITests ios/DocsScreenshots ios/RenderCheck ios/Packages/TROMECore/Sources/TROMECore; do
    name=$(echo "$folder" | tr '/' '_')
    new_task "$name"
    mkdir -p "$state/$name/$folder"
    commit "$state/$name" "$folder/README.md" text
    merge "$name"
    expect "make merge runs the E2E suite when the task changes a Markdown file in $folder, which the build of the app reads" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "
done

new_task mixed
mkdir -p "$state/mixed/ios/guide"
commit "$state/mixed" ios/guide/trains.md text
commit "$state/mixed" NOTICE notice
merge mixed
expect "make merge runs the E2E suite when the task changes Markdown and one other file" "$(tr '\n' ' ' < "$state/steps")" "check check-locked e2e e2e-locked nested-job "

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
TROME_MERGE_CHECK="$passing_check && exit 1"
merge gate
TROME_MERGE_CHECK=$passing_check
expect "make merge fails when the quality gate fails" "$status" "1"
expect "make merge does not run the E2E suite after a failed gate" "$(tr '\n' ' ' < "$state/steps")" "check check-locked "
expect "make merge leaves main unchanged when the gate fails" "$(rev main)" "$before"
expect "make merge says that the gate failed" "$(contains "$state/gate.log" "the step 'quality gate' failed")" "yes"
expect "make merge frees the Simulator lock when the gate fails" "$(lock_state)" "free"

new_task e2e
commit "$state/e2e" e2e e2e
TROME_MERGE_E2E="$passing_e2e && echo /kept/2026-10-07-141744-task-e2e > \"\$TROME_E2E_EVIDENCE_NOTE\" && exit 1"
merge e2e
TROME_MERGE_E2E=$passing_e2e
expect "make merge fails when the E2E suite fails" "$status" "1"
expect "make merge leaves main unchanged when the E2E suite fails" "$(rev main)" "$before"
expect "make merge says that the E2E suite failed" "$(contains "$state/e2e.log" "the step 'full E2E suite' failed")" "yes"
expect "make merge says where the failed E2E run kept its log and its .xcresult" "$(tail -1 "$state/e2e.log")" "The log, the .xcresult and the Simulator log of the failed run are kept in /kept/2026-10-07-141744-task-e2e"
expect "make merge frees the Simulator lock when the E2E suite fails" "$(lock_state)" "free"

new_task bare
commit "$state/bare" bare bare
TROME_MERGE_E2E="$passing_e2e && exit 1"
merge bare
TROME_MERGE_E2E=$passing_e2e
expect "make merge says when the failed E2E run kept no evidence, as when it stopped at the build" "$(tail -1 "$state/bare.log")" "The failed run kept no evidence folder: it stopped before the tests ran, so its output above is all there is."

new_task conflict
commit "$state/conflict" shared "from the task"
advance_main shared "from main"
before=$(rev main)
conflict_head=$(rev task/conflict)
merge conflict
expect "make merge fails on a rebase conflict" "$status" "1"
expect "make merge runs no gate after a rebase conflict" "$(cat "$state/steps")" ""
expect "make merge leaves main unchanged after a rebase conflict" "$(rev main)" "$before"
expect "make merge says that the rebase failed" "$(contains "$state/conflict.log" "the step 'rebase' failed")" "yes"
expect "make merge frees the Simulator lock after a rebase conflict" "$(lock_state)" "free"
expect "make merge stops the rebase after a conflict" "$(test -d "$(git -C "$state/conflict" rev-parse --git-path rebase-merge)" && echo in-progress || echo stopped)" "stopped"
expect "make merge leaves the task branch as it was after a rebase conflict" "$(rev task/conflict)" "$conflict_head"
expect "make merge leaves the worktree clean after a rebase conflict" "$(git -C "$state/conflict" status --porcelain)" ""
expect "make merge names the files of the conflict" "$(contains "$state/conflict.log" "  shared")" "yes"

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
TROME_MERGE_CHECK="sleep 2 && $passing_check"
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

queue="$RATP_SIM_LOCK.merge-queue"

queued() {
    ls "$queue"/*.task 2> /dev/null | wc -l | tr -d ' '
}

wait_until() {
    tries=0
    until "$@" || [ "$tries" -ge 100 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
}

has_queued() {
    [ "$(queued)" -ge "$1" ]
}

# Starts the merges of the tasks one after another while another merge holds the merge lock, so that they wait together.
merge_together() {
    lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
    merge_lock_holder=$!
    until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
    : > "$state/steps"
    : > "$state/refs"
    count=0
    for task; do
        start_merge "$task"
        count=$((count + 1))
        wait_until has_queued "$count"
    done
    echo release > "$state/release-merge-lock"
    wait "$merge_lock_holder"
}

e2e_runs() {
    grep -c '^e2e$' "$state/steps" || true
}

steps_line() {
    tr '\n' ' ' < "$state/steps"
}

app_task() {
    new_task "$1"
    mkdir -p "$state/$1/ios/App"
    commit "$state/$1" "ios/App/$1.swift" "$1"
}

failing_e2e="$passing_e2e && test ! -e fails-e2e"

mkfifo "$state/release-qa"
new_task queue_a
new_task queue_b
commit "$state/queue_a" queue_a queue_a
commit "$state/queue_b" queue_b queue_b
before=$(rev main)
: > "$state/steps"
"$scripts/sim-lock.sh" job sh -c 'read -r line < "$0"; echo qa-end >> "$FAKE_SIM_STATE/steps"' "$state/release-qa" > "$state/qa.log" 2>&1 &
qa=$!
wait_until test -e "$RATP_SIM_LOCK/pid"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo review >> "$FAKE_SIM_STATE/steps"' > "$state/review.log" 2>&1 &
review=$!
wait_until grep -q "Waiting for the Simulator lock" "$state/review.log"
start_merge queue_a
wait_until has_queued 1
start_merge queue_b
wait_until has_queued 2
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo late >> "$FAKE_SIM_STATE/steps"' > "$state/late-job.log" 2>&1 &
late_job=$!
wait_until grep -q "Waiting for the Simulator lock" "$state/late-job.log"
expect "a merge does not cut off the job that holds the Simulator" "$(cat "$state/steps")" ""
echo release > "$state/release-qa"
wait "$qa"
expect "the first merge of a train lands" "$(finish_merge queue_a)" "0"
expect "the second merge of a train lands" "$(finish_merge queue_b)" "0"
wait "$review" "$late_job"
expect "merges go before the jobs that wait, also the ones that came first, and two merges that wait together share one gate and one E2E run" "$(steps_line | cut -d ' ' -f 1-6)" "qa-end check check-locked e2e e2e-locked nested-job"
expect "the jobs that wait run after the merges" "$(steps_line | cut -d ' ' -f 7- | tr ' ' '\n' | sort | tr '\n' ' ')" " late review "
expect "a job that waits says that a merge goes first" "$(contains "$state/review.log" "a merge goes first")" "yes"
expect "a train lands its tasks in the order they came, each one rebased onto the one before it" "$(rev main) $(rev main~1) $(rev main~2)" "$(rev task/queue_b) $(rev task/queue_a) $before"
expect "a task of a train says that it landed in the train" "$(contains "$state/queue_b.log" "task/queue_b landed in a train of 2 tasks, which shared one gate and one E2E run.")" "yes"
expect "a task of a train says where the steps of its train are" "$(contains "$state/queue_b.log" "this task went in the train of the make merge of")" "yes"
expect "main has no merge commit after a train" "$(git -C "$repo" rev-list --merges main)" ""
expect "a train frees the Simulator lock" "$(lock_state)" "free"
expect "a train leaves no task in the queue" "$(queued)" "0"

for task in docs_a docs_b docs_c; do
    new_task "$task"
    commit "$state/$task" "$task.md" "$task"
done
before=$(rev main)
merge_together docs_a docs_b docs_c
expect "three merges that wait together land" "$(finish_merge docs_a) $(finish_merge docs_b) $(finish_merge docs_c)" "0 0 0"
expect "a train of three tasks runs one gate, and no E2E run when no task changes app code" "$(steps_line)" "check check-locked "
expect "a train of three lands the three tasks in order" "$(rev main) $(rev main~1) $(rev main~2) $(rev main~3)" "$(rev task/docs_c) $(rev task/docs_b) $(rev task/docs_a) $before"

app_task second_ok
app_task second_bad
commit "$state/second_bad" fails-e2e bad
before=$(rev main)
bad_head=$(rev task/second_bad)
TROME_MERGE_E2E=$failing_e2e
merge_together second_ok second_bad
expect "when the second task of a train fails, the first one still lands" "$(finish_merge second_ok)" "0"
expect "when the second task of a train fails, it does not land" "$(finish_merge second_bad)" "1"
expect "when the second task of a train fails, main is the first task, which passed alone" "$(rev main) $(rev main~1)" "$(rev task/second_ok) $before"
expect "when a train fails, its tasks land one by one: one E2E run for the train, then one for each task" "$(e2e_runs)" "3"
expect "the failed task says which step failed" "$(contains "$state/second_bad.log" "the step 'full E2E suite' failed for task/second_bad")" "yes"
expect "the train says which step failed" "$(contains "$state/second_ok.log" "the train of task/second_ok, task/second_bad failed at the step 'full E2E suite'")" "yes"
expect "a train that fails for a task is not called flaky" "$(contains "$state/second_bad.log" "flaky")" "no"
expect "the failed task keeps its own commits, on top of main" "$(git -C "$repo" rev-list --count main..task/second_bad) $(git -C "$repo" merge-base --is-ancestor main task/second_bad && echo on-main)" "2 on-main"

app_task first_bad
commit "$state/first_bad" fails-e2e bad
app_task first_ok
before=$(rev main)
first_bad_head=$(rev task/first_bad)
merge_together first_bad first_ok
TROME_MERGE_E2E=$passing_e2e
expect "when the first task of a train fails, it does not land" "$(finish_merge first_bad)" "1"
expect "when the first task of a train fails, the second one still lands" "$(finish_merge first_ok)" "0"
expect "when the first task of a train fails, main is the second task alone" "$(rev main~1)" "$before"
expect "the second task does not keep the commits of the first one" "$(git -C "$repo" merge-base --is-ancestor "$first_bad_head" task/first_ok && echo mixed || echo apart)" "apart"
expect "the first task is back on its own commits" "$(rev task/first_bad)" "$first_bad_head"
expect "the first task says which step failed" "$(contains "$state/first_bad.log" "the step 'full E2E suite' failed for task/first_bad")" "yes"
expect "main has no merge commit after a failed train" "$(git -C "$repo" rev-list --merges main)" ""
expect "a failed train frees the Simulator lock" "$(lock_state)" "free"

app_task flaky_a
app_task flaky_b
before=$(rev main)
TROME_MERGE_E2E="$passing_e2e && if [ ! -e \"\$FAKE_SIM_STATE/flaked\" ]; then touch \"\$FAKE_SIM_STATE/flaked\"; echo /kept/flaky > \"\$TROME_E2E_EVIDENCE_NOTE\"; exit 1; fi"
merge_together flaky_a flaky_b
TROME_MERGE_E2E=$passing_e2e
expect "when a train fails once with a flaky test, both tasks land" "$(finish_merge flaky_a) $(finish_merge flaky_b)" "0 0"
expect "after a flaky train, main has both tasks in order" "$(rev main) $(rev main~1) $(rev main~2)" "$(rev task/flaky_b) $(rev task/flaky_a) $before"
expect "make merge says that the failure of the train is flaky" "$(contains "$state/flaky_b.log" "that failure is flaky. Create a bug task")" "yes"
expect "make merge gives the evidence of the flaky run" "$(tail -1 "$state/flaky_b.log")" "The log, the .xcresult and the Simulator log of the failed run are kept in /kept/flaky"

new_task clash_a
new_task clash_b
commit "$state/clash_a" clash "from a"
commit "$state/clash_b" clash "from b"
clash_head=$(rev task/clash_b)
before=$(rev main)
merge_together clash_a clash_b
expect "when the second task of a train conflicts with the first one, the first one lands" "$(finish_merge clash_a)" "0"
expect "the task that conflicts with the one before it does not land" "$(finish_merge clash_b)" "1"
expect "the train runs the gate and the E2E suite once, without the task that conflicts" "$(steps_line)" "check check-locked e2e e2e-locked nested-job "
expect "main is the first task, after a conflict in the train" "$(rev main~1)" "$before"
expect "the task that conflicts says that its rebase failed" "$(contains "$state/clash_b.log" "the step 'rebase' failed for task/clash_b")" "yes"
expect "the task that conflicts is as it was before" "$(rev task/clash_b) $(git -C "$state/clash_b" status --porcelain)" "$clash_head "

app_task stop_a
app_task stop_b
stop_b_head=$(rev task/stop_b)
before=$(rev main)
TROME_MERGE_CHECK="$passing_check && sleep 2"
merge_together stop_a stop_b
wait_until grep -q '^check$' "$state/steps"
stopped=$(grep -l '^branch=task/stop_b$' "$queue"/*.task | xargs sed -n 's/^pid=//p')
pkill -TERM -P "$stopped" || true
kill "$stopped" 2> /dev/null || true
TROME_MERGE_CHECK=$passing_check
expect "when the make merge of a task of a train is stopped, the other task still lands" "$(finish_merge stop_a)" "0"
finish_merge stop_b > /dev/null
expect "a task whose make merge was stopped during its train does not land" "$(rev main) $(rev main~1)" "$(rev task/stop_a) $before"
expect "a task whose make merge was stopped during its train is back on its own commits" "$(rev task/stop_b)" "$stop_b_head"
expect "a stopped make merge leaves no task in the queue" "$(queued)" "0"

mkdir -p "$queue"
sh -c 'exit 0' &
dead=$!
wait "$dead"
printf 'pid=%s\nroot=/gone\nbranch=task/gone\nnode=\n' "$dead" > "$queue/0000000001.000000.$dead.task"
: > "$state/steps"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo after-dead-merge >> "$FAKE_SIM_STATE/steps"' > "$state/dead.log" 2>&1
expect "a job does not wait for a merge whose make merge has ended" "$(steps_line)" "after-dead-merge "
rm -f "$queue/0000000001.000000.$dead.task"

fake_node() {
    mkdir -p "$1"
    printf '#!/bin/sh\ncase "$1" in -v) echo v%s.0.0 ;; *) echo %s ;; esac\n' "$2" "$2" > "$1/node"
    chmod +x "$1/node"
}
fake_node "$state/old-node" 20
fake_node "$state/nvm/versions/node/v24.0.0/bin" 24
mkdir "$state/nvm-without-24"
printf 'nvm() { [ "$1" = which ] && [ -x "$NVM_DIR/versions/node/v$2.0.0/bin/node" ] && echo "$NVM_DIR/versions/node/v$2.0.0/bin/node"; }\n' > "$state/nvm/nvm.sh"
cp "$state/nvm/nvm.sh" "$state/nvm-without-24/nvm.sh"
advance_main .nvmrc 24
path_before_node=$PATH
export PATH="$state/old-node:$PATH" NVM_DIR="$state/nvm"
TROME_MERGE_CHECK="$passing_check && node -v >> \"\$FAKE_SIM_STATE/steps\""

new_task docsnode
mkdir -p "$state/docsnode/docs"
commit "$state/docsnode" docs/page.md "page"
merge docsnode
expect "with an old Node active, make merge of a docs change succeeds when nvm has the Node of .nvmrc" "$status" "0"
expect "the gate of that merge runs with the Node of .nvmrc" "$(tr '\n' ' ' < "$state/steps")" "check check-locked v24.0.0 "

export NVM_DIR="$state/nvm-without-24"
lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
merge_lock_holder=$!
until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
new_task docsnonode
mkdir -p "$state/docsnonode/docs"
commit "$state/docsnonode" docs/other.md "other"
before=$(rev main)
merge docsnonode
echo release > "$state/release-merge-lock"
wait "$merge_lock_holder"
expect "with an old Node and no Node of .nvmrc in nvm, make merge of a docs change fails" "$status" "1"
expect "it fails before it waits for a lock" "$(contains "$state/docsnonode.log" "waiting for the merge")" "no"
expect "it runs no gate" "$(cat "$state/steps")" ""
expect "it says what to run" "$(contains "$state/docsnonode.log" "but the active Node is v20.0.0, and nvm has no Node 24. Run 'nvm install' in ")" "yes"
expect "main is unchanged when Node is missing" "$(rev main)" "$before"

new_task appnonode
commit "$state/appnonode" app "app"
merge appnonode
expect "with an old Node and no Node of .nvmrc in nvm, make merge of a change with no docs, server or contracts succeeds" "$status" "0"
export PATH="$path_before_node"
unset NVM_DIR
TROME_MERGE_CHECK=$passing_check

[ "$failures" -eq 0 ]
