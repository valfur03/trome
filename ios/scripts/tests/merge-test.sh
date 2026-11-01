#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d "${TMPDIR:-/tmp}/merge-test.XXXXXX")
repo="$state/repo"
failures=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE ONLY RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_MERGE_QUEUE || true
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" RATP_SIM_POLL_SECONDS=1 RATP_MERGE_LOCK="$state/merge.lock" SCRIPTS="$scripts" TROME_LOGS="$state/logs"
# The work folders of make merge go in the folder of this run, so that the cleanup removes them too.
mkdir "$state/tmp"
export TMPDIR="$state/tmp"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

mkdir "$state/idle-watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/idle-watcher/sim-lock.sh"
(/bin/sh "$state/idle-watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 & echo $! > "$state/idle-watcher/pid")
idle_watcher=$(cat "$state/idle-watcher/pid")
echo "$idle_watcher" > "$RATP_SIM_LOCK.slots-watcher"

# Sets 'left' to the processes that this run started and that still run: its children, their children, and so on.
# Only these: another run of this test, or a real make merge, may run the same scripts at the same time.
# It runs in this shell, not in a subshell, so that it does not find itself.
find_started() {
    table=$(ps -A -o pid= -o ppid=)
    found=$(printf '%s\n' "$table" | awk -v root="$$" '
        { parent[$1] = $2 }
        END {
            found[root] = 1
            do {
                more = 0
                for (p in parent) if (!(p in found) && (parent[p] in found)) { found[p] = 1; more = 1 }
            } while (more)
            for (p in found) if (p != root) print p
        }')
    left=
    for p in $found; do
        if kill -0 "$p" 2> /dev/null; then
            left="$left $p"
        fi
    done
}

# A run that is stopped, or that ends early, still has merges running, which write in its folder:
# they are stopped first, or the folder is removed while they write in it, and stays.
# A process stays on the list until it has ended, also once its parent has ended and it is no longer found.
# It keeps the exit status of the run: a run that stops on an error must not pass.
cleanup() {
    status=$?
    kill "$idle_watcher" "$(cat "$RATP_SIM_LOCK.slots-watcher" 2> /dev/null)" 2> /dev/null || true
    find_started
    kill -TERM $left 2> /dev/null || true
    tracked=$left
    tries=0
    while [ -n "$tracked" ] && [ "$tries" -lt 200 ]; do
        sleep 0.1
        tries=$((tries + 1))
        find_started
        still=
        for p in $tracked $left; do
            case " $still " in *" $p "*) continue ;; esac
            if kill -0 "$p" 2> /dev/null; then
                still="$still $p"
            fi
        done
        tracked=$still
    done
    [ -z "$tracked" ] || kill -KILL $tracked 2> /dev/null || true
    rm -rf "$state"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

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

# Its title says "no rider change", so that make merge does not refuse a task of app code for its note (see notes_task).
commit() {
    titled_commit "$1" "$2" "$3" "change $2 (no rider change)"
}

titled_commit() {
    echo "$3" > "$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "$4"
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

# Writes the step, then "<step>-locked" when it runs inside the Simulator job that holds the lock (not when another job holds it).
step_recorder() {
    printf 'echo %s >> "$FAKE_SIM_STATE/steps" && if test -n "${RATP_SIM_HELD_PID:-}" && test "$(cat "$RATP_SIM_LOCK/pid" 2> /dev/null)" = "$RATP_SIM_HELD_PID"; then echo %s-locked >> "$FAKE_SIM_STATE/steps"; fi' "$1" "$1"
}

start_merge() {
    (cd "$state/$1" && { "$scripts/merge.sh" > "$state/$1.log" 2>&1 && echo 0 || echo $?; } > "$state/$1.new" && mv "$state/$1.new" "$state/$1.status") &
    eval "merge_$1=\$!"
}

# What the merges write as they go: their logs, the steps of the fake checks, the records of the Simulator jobs, the queue.
progress() {
    ls -lnT "$state" "$state/logs" "$RATP_SIM_LOCK.merge-queue" 2> /dev/null | cksum
}

# Waits for the end of the merge, however long it takes: a busy Mac makes each step slower, so a bound on the whole merge
# fails a merge that works (a failed train runs its checks three times). Only a merge that writes nothing for
# $stall_seconds is stuck: it reads "stuck", and it is stopped with the jobs that it started.
stall_seconds=120
finish_merge() {
    eval "pid=\$merge_$1"
    last=$(progress)
    still=0
    while [ ! -e "$state/$1.status" ] && kill -0 "$pid" 2> /dev/null && [ "$still" -lt "$stall_seconds" ]; do
        sleep 1
        now=$(progress)
        if [ "$now" = "$last" ]; then
            still=$((still + 1))
        else
            still=0
            last=$now
        fi
    done
    # A stuck merge.sh, and the jobs that it started, would keep their locks after the end of their wrapper:
    # each later merge would wait behind them for its own stall bound.
    kill $(descendants "$pid") "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    cat "$state/$1.status" 2> /dev/null || echo "stuck"
}

# The processes under $1: its children, their children, and so on.
descendants() {
    ps -A -o pid= -o ppid= | awk -v root="$1" '
        { parent[$1] = $2 }
        END {
            found[root] = 1
            do {
                more = 0
                for (p in parent) if (!(p in found) && (parent[p] in found)) { found[p] = 1; more = 1 }
            } while (more)
            for (p in found) if (p != root) print p
        }'
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
            if [ -n "${RATP_SIM_HELD_PID:-}" ] && [ "$(cat "$RATP_SIM_LOCK/pid" 2> /dev/null)" = "$RATP_SIM_HELD_PID" ]; then held=locked; else held=free; fi
            echo "$ref $held" >> "$FAKE_SIM_STATE/refs"
            ;;
    esac
done
EOF
chmod +x "$repo/.git/hooks/reference-transaction"

passing_check="$(step_recorder check)"
passing_e2e="$(step_recorder e2e) && \"\$SCRIPTS/sim-lock.sh\" job sh -c 'echo nested-job >> \"\$FAKE_SIM_STATE/steps\"'"
passing_release_run="$(step_recorder release-run)"
passing_build="$(step_recorder build)"
export TROME_MERGE_CHECK="$passing_check" TROME_MERGE_E2E="$passing_e2e" TROME_MERGE_RELEASE_RUN="$passing_release_run" \
    TROME_MERGE_BUILD="$passing_build" TROME_MERGE_RENDER_BUILD="$(step_recorder render-build)"

new_task ok
commit "$state/ok" ok ok
advance_main other other
before=$(rev main)
merge ok
expect "make merge succeeds" "$status" "0"
expect "make merge rebases the task, runs the gate and the test builds with no Simulator lock, then the full E2E suite and the Release app run with it" "$(tr '\n' ' ' < "$state/steps")" "check build e2e e2e-locked nested-job release-run release-run-locked "
expect "make merge holds the lock neither for the rebase nor for the fast-forward" "$(tr '\n' ' ' < "$state/refs")" "refs/heads/task/ok free refs/heads/main free "
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
expect "make merge skips the E2E suite, and takes no Simulator lock, when the task changes only docs" "$(tr '\n' ' ' < "$state/steps")" "check "
expect "make merge says why it skips the E2E suite" "$(contains "$state/docs.log" "changes no app code")" "yes"
expect "main is the task that changes only docs" "$(rev main)" "$(rev task/docs)"

new_task server
mkdir -p "$state/server/server/src" "$state/server/contracts/prim"
commit "$state/server" server/src/worker.ts worker
commit "$state/server" contracts/prim/answer.json answer
merge server
expect "make merge of a task that changes only the server and the contracts succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only the server and the contracts" "$(tr '\n' ' ' < "$state/steps")" "check "

new_task video
mkdir -p "$state/video/video/src"
commit "$state/video" video/src/Film.tsx film
commit "$state/video" video/Makefile makefile
merge video
expect "make merge of a task that changes only the film source succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only the film source" "$(tr '\n' ' ' < "$state/steps")" "check "

new_task markdown
mkdir -p "$state/markdown/ios/guide" "$state/markdown/.claude/rules" "$state/markdown/ios/Packages/TROMECore/Tests/TROMECoreTests/Stations"
for file in CONTRIBUTING.md ARCHITECTURE.md NOTICE.md LICENSE ios/README.md ios/guide/stations.md ios/guide/page.mdx .claude/rules/docs.md .claude/settings.json ios/Packages/TROMECore/Tests/TROMECoreTests/Stations/StationTests.swift; do
    commit "$state/markdown" "$file" text
done
merge markdown
expect "make merge of a task that changes only Markdown, LICENSE, .claude/ and the unit tests succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only Markdown or MDX files, LICENSE, .claude/ and the unit tests" "$(tr '\n' ' ' < "$state/steps")" "check "

new_task github
mkdir -p "$state/github/.github/workflows" "$state/github/.github/ISSUE_TEMPLATE"
commit "$state/github" .github/workflows/docs-site.yml workflow
commit "$state/github" .github/ISSUE_TEMPLATE/bug.yml form
merge github
expect "make merge of a task that changes only .github/ succeeds" "$status" "0"
expect "make merge skips the E2E suite when the task changes only .github/, which no build and no test reads" "$(tr '\n' ' ' < "$state/steps")" "check "

new_task github_app
mkdir -p "$state/github_app/.github/workflows" "$state/github_app/ios/App"
commit "$state/github_app" .github/workflows/docs-site.yml "new workflow"
commit "$state/github_app" ios/App/Feature.swift code
merge github_app
expect "make merge runs the E2E suite when the task changes .github/ and app code" "$(tr '\n' ' ' < "$state/steps")" "check build e2e e2e-locked nested-job release-run release-run-locked "

for folder in ios/App ios/Widget ios/UITests ios/DocsScreenshots ios/RenderCheck ios/Packages/TROMECore/Sources/TROMECore; do
    name=$(echo "$folder" | tr '/' '_')
    new_task "$name"
    mkdir -p "$state/$name/$folder"
    commit "$state/$name" "$folder/README.md" text
    merge "$name"
    expect "make merge runs the E2E suite when the task changes a Markdown file in $folder, which the build of the app reads" "$(tr '\n' ' ' < "$state/steps")" "check build e2e e2e-locked nested-job release-run release-run-locked "
done

new_task mixed
mkdir -p "$state/mixed/ios/guide"
commit "$state/mixed" ios/guide/trains.md text
commit "$state/mixed" NOTICE notice
merge mixed
expect "make merge runs the E2E suite when the task changes Markdown and one other file" "$(tr '\n' ' ' < "$state/steps")" "check build e2e e2e-locked nested-job release-run release-run-locked "

advance_main app app
new_task moved
mkdir -p "$state/moved/docs"
git -C "$state/moved" mv app docs/app
git -C "$state/moved" commit -q -m "move app into docs"
merge moved
expect "make merge runs the E2E suite when the task moves app code into docs" "$(tr '\n' ' ' < "$state/steps")" "check build e2e e2e-locked nested-job release-run release-run-locked "

new_task gate
commit "$state/gate" gate gate
before=$(rev main)
TROME_MERGE_CHECK="$passing_check && exit 1"
merge gate
TROME_MERGE_CHECK=$passing_check
expect "make merge fails when the quality gate fails" "$status" "1"
expect "make merge does not build or run the E2E suite after a failed gate, and runs the gate with no Simulator lock" "$(tr '\n' ' ' < "$state/steps")" "check "
expect "a failed gate never takes the Simulator lock: it leaves no record of a Simulator job" "$(awk -F '\t' '$9 == "task/gate"' "$state/logs/simulator-jobs.tsv" 2> /dev/null | wc -l | tr -d ' ')" "0"
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
"$scripts/sim-lock.sh" job sh -c 'read -r line < "$0"; echo qa-end >> "$FAKE_SIM_STATE/steps"' "$state/release-qa" > "$state/qa.log" 2>&1 &
qa=$!
wait_until test -e "$RATP_SIM_LOCK/pid"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo review >> "$FAKE_SIM_STATE/steps"' > "$state/review.log" 2>&1 &
review=$!
wait_until grep -q "Waiting for the Simulator lock" "$state/review.log"
merge_together queue_a queue_b
wait_until grep -qs "Waiting for the Simulator lock" "$state/queue_a.log" "$state/queue_b.log"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo late >> "$FAKE_SIM_STATE/steps"' > "$state/late-job.log" 2>&1 &
late_job=$!
wait_until grep -q "a merge goes first" "$state/late-job.log"
expect "a merge runs its gate and its test builds while another job holds the Simulator, and does not cut that job off" "$(steps_line)" "check build "
expect "the merge then waits for the job that holds the Simulator, and its message names that job" \
    "$(cat "$state/queue_a.log" "$state/queue_b.log" | grep -c "Waiting for the Simulator lock: 1st in line, held by a job in .* (PID $qa)")" "1"
echo release > "$state/release-qa"
wait "$qa"
expect "the first merge of a train lands" "$(finish_merge queue_a)" "0"
expect "the second merge of a train lands" "$(finish_merge queue_b)" "0"
wait "$review" "$late_job"
expect "merges that ask for the Simulator go before the jobs that wait, also the ones that came first, and two merges that wait together share one gate and one E2E run" "$(steps_line | cut -d ' ' -f 1-8)" "check build qa-end e2e e2e-locked nested-job release-run release-run-locked"
expect "the jobs that wait run after the merges" "$(steps_line | cut -d ' ' -f 9- | tr ' ' '\n' | sort | tr '\n' ' ')" " late review "
expect "a job that waits says that a merge goes first" "$(contains "$state/review.log" "a merge goes first")" "yes"
expect "a train lands its tasks in the order they came, each one rebased onto the one before it" "$(rev main) $(rev main~1) $(rev main~2)" "$(rev task/queue_b) $(rev task/queue_a) $before"
expect "a task of a train says that it landed in the train" "$(contains "$state/queue_b.log" "task/queue_b landed in a train of 2 tasks, which shared one gate and one E2E run.")" "yes"
expect "a task of a train says where the steps of its train are" "$(cat "$state/queue_a.log" "$state/queue_b.log" | grep -c "this task went in the train of the make merge of")" "1"
expect "main has no merge commit after a train" "$(git -C "$repo" rev-list --merges main)" ""
expect "a train frees the Simulator lock" "$(lock_state)" "free"
expect "the record of the Simulator job of a train is a merge, and names the tasks of the train" \
    "$(awk -F '\t' '$2 == "merge" && $9 ~ /queue/ { print $9 }' "$state/logs/simulator-jobs.tsv")" "task/queue_a, task/queue_b"
expect "the records of the jobs that waited behind the merges say that they waited for a merge" \
    "$(awk -F '\t' '$2 == "job" && $10 ~ /merge/' "$state/logs/simulator-jobs.tsv" | wc -l | tr -d ' ')" "2"
expect "a train leaves no task in the queue" "$(queued)" "0"

for task in docs_a docs_b docs_c; do
    new_task "$task"
    commit "$state/$task" "$task.md" "$task"
done
before=$(rev main)
merge_together docs_a docs_b docs_c
expect "three merges that wait together land" "$(finish_merge docs_a) $(finish_merge docs_b) $(finish_merge docs_c)" "0 0 0"
expect "a train of three tasks runs one gate, and no E2E run and no Simulator lock when no task changes app code" "$(steps_line)" "check "
expect "a train of three lands the three tasks in order" "$(rev main) $(rev main~1) $(rev main~2) $(rev main~3)" "$(rev task/docs_c) $(rev task/docs_b) $(rev task/docs_a) $before"

# A merge with no app code holds no Simulator: it lands while another job holds the lock, and no job waits for it.
# The job that holds the Simulator ends when a file appears, so that a test that fails never blocks on it.
hold_simulator() {
    rm -f "$state/release-holder"
    "$scripts/sim-lock.sh" job sh -c 'until [ -e "$0" ]; do sleep 0.1; done' "$state/release-holder" > /dev/null 2>&1 &
    holder=$!
    wait_until test -e "$RATP_SIM_LOCK/pid"
}

lock_is_free() {
    [ ! -e "$RATP_SIM_LOCK" ]
}

hold_simulator
new_task nolock
commit "$state/nolock" nolock.md nolock
merge nolock
expect "a merge with no app code lands while another job holds the Simulator lock" "$status $(rev main)" "0 $(rev task/nolock)"
expect "it runs the gate and moves main with no Simulator lock" "$(steps_line)$(contains "$state/refs" locked)" "check no"
expect "it says that it takes no Simulator lock" "$(contains "$state/nolock.log" "no Simulator lock: task/nolock changes no app code")" "yes"
expect "it leaves no record of a Simulator job" "$(awk -F '\t' '$9 ~ /nolock/' "$state/logs/simulator-jobs.tsv" | wc -l | tr -d ' ')" "0"

# A merge of app code that waits in the queue, for the merge lock, does not hold back a job that waits for the Simulator:
# only a merge that asks for the Simulator does.
new_task queued_docs
commit "$state/queued_docs" queued_docs.md queued_docs
app_task queued_app
before=$(rev main)
lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
merge_lock_holder=$!
until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
: > "$state/steps"
: > "$state/refs"
start_merge queued_app
wait_until has_queued 1
start_merge queued_docs
wait_until has_queued 2
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo qa-after-queued >> "$FAKE_SIM_STATE/steps"' > "$state/qa-queued.log" 2>&1 &
qa_queued=$!
wait_until grep -q "Waiting for the Simulator lock" "$state/qa-queued.log"
touch "$state/release-holder"
wait "$holder"
wait_until grep -q qa-after-queued "$state/steps"
expect "a job that waits takes the free Simulator while a merge of app code waits in the queue" "$(steps_line)$(contains "$state/qa-queued.log" "a merge goes first")" "qa-after-queued no"
: > "$state/steps"
echo release > "$state/release-merge-lock"
wait "$merge_lock_holder" "$qa_queued"
expect "a train that mixes a task of app code and a task with no app code lands both" "$(finish_merge queued_docs) $(finish_merge queued_app)" "0 0"
expect "it runs one gate, then the E2E suite with the Simulator lock" "$(steps_line)" "check build e2e e2e-locked nested-job release-run release-run-locked "
expect "it moves main with no Simulator lock" "$(contains "$state/refs" "refs/heads/main free")" "yes"
expect "main has both tasks" "$(rev main~2)" "$before"

# A merge asks for the Simulator only after its gate and its test builds: a QA job that asks during the gate takes it,
# and the merge then waits for it, names it, and lands after it.
app_task during_gate
before=$(rev main)
rm -f "$state/gate-go" "$state/release-gate-qa"
: > "$state/steps"
TROME_MERGE_CHECK="$passing_check && until [ -e \"\$FAKE_SIM_STATE/gate-go\" ]; do sleep 0.1; done"
start_merge during_gate
wait_until grep -q '^check$' "$state/steps"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo qa-start >> "$FAKE_SIM_STATE/steps"; until [ -e "$0" ]; do sleep 0.1; done; echo qa-end >> "$FAKE_SIM_STATE/steps"' \
    "$state/release-gate-qa" > "$state/qa-gate.log" 2>&1 &
qa_gate=$!
wait_until grep -q qa-start "$state/steps"
expect "a QA job takes the free Simulator during the gate of a merge of app code" "$(steps_line)$(contains "$state/qa-gate.log" "a merge goes first")" "check qa-start no"
touch "$state/gate-go"
wait_until grep -q "Waiting for the Simulator lock" "$state/during_gate.log"
TROME_MERGE_CHECK=$passing_check
expect "after its gate, the merge waits for the QA job, and does not stop it" "$(steps_line)" "check qa-start build "
expect "its message names the job that holds the Simulator" "$(contains "$state/during_gate.log" "Waiting for the Simulator lock: 1st in line, held by a job in $(cd "$scripts/../.." && pwd) (PID $qa_gate)")" "yes"
touch "$state/release-gate-qa"
wait "$qa_gate"
expect "the merge lands after the QA job" "$(finish_merge during_gate) $(rev main~1)" "0 $before"
expect "it runs its E2E suite and its Release app run once the QA job has ended" "$(steps_line)" "check qa-start build qa-end e2e e2e-locked nested-job release-run release-run-locked "

# A failed test build never takes the Simulator lock.
app_task build_fails
before=$(rev main)
: > "$state/steps"
TROME_MERGE_BUILD="$passing_build && exit 1"
merge build_fails
TROME_MERGE_BUILD=$passing_build
expect "a merge whose test build fails does not land" "$status $(rev main)" "1 $before"
expect "it says that the test build failed" "$(contains "$state/build_fails.log" "the step 'test build' failed for task/build_fails")" "yes"
expect "it runs no test, and never takes the Simulator lock" "$(steps_line)$(awk -F '\t' '$9 == "task/build_fails"' "$state/logs/simulator-jobs.tsv" | wc -l | tr -d ' ')" "check build 0"

# A merge asks for the Simulator by joining the line of the jobs that wait for it (sim-lock.sh).
merge_asks() {
    ls "$RATP_SIM_LOCK.line" 2> /dev/null | grep -c '^[0-9]*\.[0-9]*$' || true
}

# A make merge stopped while it waits for the Simulator leaves no entry in the queue and no ask for the Simulator,
# and the next merge and the next job go on.
hold_simulator
app_task stopped_wait
before=$(rev main)
: > "$state/steps"
start_merge stopped_wait
wait_until grep -q "Waiting for the Simulator lock" "$state/stopped_wait.log"
expect "a merge that waits for the Simulator asks for it" "$(merge_asks)" "1"
# By PID, never by name, as a stop of make merge does: its lockf, then itself; the train sees that no make merge of its tasks is left.
stopped=$(grep -l '^branch=task/stopped_wait$' "$queue"/*.task | xargs sed -n 's/^pid=//p')
pkill -TERM -P "$stopped" lockf || true
kill -TERM "$stopped" 2> /dev/null || true
wait_until test -e "$state/stopped_wait.status"
asks_none() {
    [ "$(merge_asks)" = 0 ]
}
wait_until asks_none
expect "a merge stopped while it waits for the Simulator leaves no entry in the queue and no ask for the Simulator" "$(queued) $(merge_asks)" "0 0"
expect "it did not land" "$(rev main)" "$before"
RATP_SIM_POLL_SECONDS=1 "$scripts/sim-lock.sh" job sh -c 'echo after-stopped >> "$FAKE_SIM_STATE/steps"' > "$state/after-stopped.log" 2>&1 &
after_stopped=$!
wait_until grep -q "Waiting for the Simulator lock" "$state/after-stopped.log"
touch "$state/release-holder"
wait "$holder" "$after_stopped"
expect "the next job takes the Simulator, and no merge goes before it" "$(steps_line)$(contains "$state/after-stopped.log" "a merge goes first")" "check build after-stopped no"
: > "$state/steps"
rm -f "$state/stopped_wait.status"
merge stopped_wait
expect "the next make merge lands" "$status $(rev main)" "0 $(rev task/stopped_wait)"

# Two merges of app code queued one after the other land one after the other: the second one waits for the merge lock
# while the first one waits for the Simulator, and then runs its own gate and its own E2E suite.
hold_simulator
app_task line_a
app_task line_b
before=$(rev main)
: > "$state/steps"
start_merge line_a
wait_until grep -q "Waiting for the Simulator lock" "$state/line_a.log"
start_merge line_b
wait_until has_queued 2
wait_until grep -q "waiting for the merge of another worktree" "$state/line_b.log"
expect "the second merge waits for the merge lock while the first one waits for the Simulator" "$(steps_line)$(contains "$state/line_b.log" "waiting for the merge of another worktree")" "check build yes"
touch "$state/release-holder"
wait "$holder"
expect "two merges queued one after the other land" "$(finish_merge line_a) $(finish_merge line_b)" "0 0"
expect "they land one after the other" "$(rev main) $(rev main~1) $(rev main~2)" "$(rev task/line_b) $(rev task/line_a) $before"
expect "each one runs its own gate and its own E2E suite" "$(steps_line)" \
    "check build e2e e2e-locked nested-job release-run release-run-locked check build e2e e2e-locked nested-job release-run release-run-locked "
expect "they leave no entry in the queue, no ask for the Simulator, and the lock free" "$(queued) $(merge_asks) $(lock_state)" "0 0 free"

# The second guard: the task changes no app code from where it left main, but its rebase does. Its first commit,
# which adds a file of the app, is already on main, so the rebase drops it, and the commit that removes that file stays.
new_task undo
mkdir -p "$state/undo/ios/App"
commit "$state/undo" ios/App/Undo.swift undo
# main moves first, so that the copy is a new commit: in the same second, a copy on the same parent would be the same commit.
advance_main undo-before undo-before
git -C "$repo" cherry-pick "$(rev task/undo)" > /dev/null
git -C "$state/undo" rm -q ios/App/Undo.swift
git -C "$state/undo" commit -q -m "remove ios/App/Undo.swift (no rider change)"
commit "$state/undo" undo.md undo
merge undo
expect "a task whose rebase changes app code lands, its gate with no Simulator lock, then its E2E suite with it" "$status $(steps_line)" \
    "0 check build e2e e2e-locked nested-job release-run release-run-locked "
expect "main no longer has the file of the app" "$(git -C "$repo" ls-tree --name-only main ios/App/Undo.swift) $(rev main)" " $(rev task/undo)"
expect "the record of its Simulator job is a merge, and names the task" \
    "$(awk -F '\t' '$2 == "merge" && $9 == "task/undo" { print $9 }' "$state/logs/simulator-jobs.tsv")" "task/undo"
expect "the merges with no app code leave no task in the queue" "$(queued)" "0"

# The gate of a train sees the commits of all its tasks: a task of the app with no note must not pass on the note of another.
notes_task() {
    new_task "$1"
    mkdir -p "$state/$1/ios/App" "$state/$1/ios/changes"
    titled_commit "$state/$1" "ios/App/$1.swift" "$1" "feat: $1"
}
notes_task noted
titled_commit "$state/noted" ios/changes/noted.txt "kind: item
fr: Une ligne.
en: One line." "docs: the note of noted"
notes_task unnoted
unnoted_head=$(rev task/unnoted)
before=$(rev main)
merge_together noted unnoted
expect "a task of a train with a note lands" "$(finish_merge noted)" "0"
expect "a task of a train that changes the app with no note and no \"(no rider change)\" title does not land on the note of another task" "$(finish_merge unnoted)" "1"
expect "the task with no note says why, with the message of change-notes-check" "$(contains "$state/unnoted.log" "change-notes-check: the commits since main change the code of the app (ios/App/unnoted.swift)")" "yes"
expect "the task with no note is refused before its rebase" "$(rev task/unnoted)" "$unnoted_head"
expect "main gets only the task with a note" "$(rev main) $(rev main~2)" "$(rev task/noted) $before"

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

app_task release_flaky_a
app_task release_flaky_b
before=$(rev main)
TROME_MERGE_RELEASE_RUN="$passing_release_run && if [ ! -e \"\$FAKE_SIM_STATE/release-flaked\" ]; then touch \"\$FAKE_SIM_STATE/release-flaked\"; exit 1; fi"
merge_together release_flaky_a release_flaky_b
TROME_MERGE_RELEASE_RUN=$passing_release_run
expect "when a train fails once at the Release app run, both tasks land" "$(finish_merge release_flaky_a) $(finish_merge release_flaky_b)" "0 0"
expect "make merge says that this failure of the train is flaky" "$(contains "$state/release_flaky_b.log" "the train failed at the step 'Release app run', but each of its tasks passed it alone: that failure is flaky")" "yes"

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
expect "the train runs the gate and the E2E suite once, without the task that conflicts" "$(steps_line)" "check build e2e e2e-locked nested-job release-run release-run-locked "
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

# A stale train.pid whose PID the system gave again to a process that is not a train: the next train does not wait for it.
# The lockf of a make merge that waits for the merge lock names 'merge.sh drive' too, and a make merge names 'merge.sh'.
lockf -k "$state/not-a-train.lock" sh -c 'sleep 600; :' merge.sh drive stale > /dev/null 2>&1 &
not_train=$!
echo "$not_train" > "$queue/train.pid"
app_task stale_lockf
merge stale_lockf
expect "a train does not wait for a stale train.pid that now names the lockf of a make merge" \
    "$status $(contains "$state/stale_lockf.log" "waiting for the train of a stopped make merge")" "0 no"
pkill -P "$not_train" sleep 2> /dev/null || true
kill "$not_train" 2> /dev/null || true
wait "$not_train" 2> /dev/null || true
sh -c 'sleep 600; :' merge.sh > /dev/null 2>&1 &
not_train=$!
echo "$not_train" > "$queue/train.pid"
app_task stale_outer
merge stale_outer
expect "a train does not wait for a stale train.pid that now names a make merge" \
    "$status $(contains "$state/stale_outer.log" "waiting for the train of a stopped make merge")" "0 no"
pkill -P "$not_train" sleep 2> /dev/null || true
kill "$not_train" 2> /dev/null || true
wait "$not_train" 2> /dev/null || true
# The train itself, when the stale PID went to it: it takes the merge lock as make merge does, with no task to land.
lockf -k "$RATP_MERGE_LOCK" sh -c 'cd "$3" && echo "$$" > "$1/train.pid" && exec "$2/merge.sh" drive none' sh "$queue" "$scripts" "$repo" \
    > "$state/own-train.log" 2>&1 &
own=$!
tries=0
while kill -0 "$own" 2> /dev/null && [ "$tries" -lt 60 ]; do
    sleep 1
    tries=$((tries + 1))
done
kill "$own" 2> /dev/null || true
wait "$own" 2> /dev/null || true
expect "a train does not wait for a stale train.pid that has its own PID" \
    "$([ "$tries" -lt 60 ] && echo ended || echo hung) $(contains "$state/own-train.log" "waiting for the train of a stopped make merge")" "ended no"
expect "a train whose own PID was in a stale train.pid ends and leaves no train.pid" "$(test -e "$queue/train.pid" && echo left || echo none)" "none"

# The train is stopped while it rebases its third task: the second task, already rebased onto the first one, goes back too.
app_task kill_a
app_task kill_b
app_task kill_c
for task in kill_a kill_b kill_c; do
    eval "${task}_head=\$(rev task/$task)"
done
before=$(rev main)
cat > "$repo/.git/hooks/pre-rebase" << EOF
#!/bin/sh
case "\$(git rev-parse --show-toplevel)" in
    */kill_c) touch "$state/rebasing-kill-c"; sleep 2 ;;
esac
EOF
chmod +x "$repo/.git/hooks/pre-rebase"
merge_together kill_a kill_b kill_c
wait_until test -e "$state/rebasing-kill-c"
# By PID, never by name: another run of this test, or a real make merge, may run a train of the same scripts.
# The train runs under the merge lock: it is the child of the lockf of the make merge that drives it, any of the three.
stopped=
for task in kill_a kill_b kill_c; do
    task_pid=$(grep -l "^branch=task/$task\$" "$queue"/*.task | xargs sed -n 's/^pid=//p')
    train=$(pgrep -P "$(pgrep -P "$task_pid" lockf)" || true)
    if [ -n "$train" ]; then
        stopped=$task
        break
    fi
done
kill -TERM $train
pkill -KILL -P "$task_pid" lockf
wait_until test -e "$state/$stopped.status"
landed=
for task in kill_a kill_b kill_c; do
    [ "$task" = "$stopped" ] || landed="$landed $(finish_merge "$task")"
done
expect "after a train stopped during a rebase, the other tasks land" "$landed" " 0 0"
expect "a train stopped during a rebase puts back the branches it rebased: main gets no commit of the stopped task" "$(rev main~2)" "$before"
expect "the task of the stopped train is back on its own commits" "$(rev "task/$stopped")" "$(eval echo "\$${stopped}_head")"
expect "the next train waits for the stopped train to end, as the merge lock went with the stopped make merge" \
    "$(cat "$state/kill_a.log" "$state/kill_b.log" "$state/kill_c.log" | grep -c "waiting for the train of a stopped make merge to end")" "1"
expect "a stopped train frees the Simulator lock" "$(lock_state)" "free"
rm -f "$repo/.git/hooks/pre-rebase"

# A task that gets a new commit during its train keeps it, but does not land: that commit was not tested before the merge.
app_task moved_a
app_task moved_b
TROME_MERGE_CHECK="$passing_check && if [ ! -e \"\$FAKE_SIM_STATE/moved-marker\" ]; then touch \"\$FAKE_SIM_STATE/moved-marker\"; echo new > \"\$FAKE_SIM_STATE/moved_a/moved-new\"; git -C \"\$FAKE_SIM_STATE/moved_a\" add moved-new; git -C \"\$FAKE_SIM_STATE/moved_a\" commit -q -m new; fi"
merge_together moved_a moved_b
TROME_MERGE_CHECK=$passing_check
expect "when a task gets a new commit during its train, the other task still lands, and that task does not" "$(finish_merge moved_a) $(finish_merge moved_b)" "1 0"
expect "the new commit of a task during its train does not reach main" "$(git -C "$repo" show main:moved-new 2> /dev/null || echo absent)" "absent"
expect "the new commit of a task during its train is not lost" "$(git -C "$repo" show task/moved_a:moved-new 2> /dev/null)" "new"
expect "make merge says why the task with the new commit does not land" "$(contains "$state/moved_a.log" "make merge lands only the commit that it started with")" "yes"
expect "make merge says that it left the branch with the new commit as it was" "$(cat "$state/moved_a.log" "$state/moved_b.log" | grep -c "'task/moved_a' got a new commit during the merge")" "1"

# A task that gets a new commit while its make merge waits does not land either: a stopped make merge may still wait for the merge lock.
app_task waited
before=$(rev main)
lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
merge_lock_holder=$!
until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
start_merge waited
wait_until has_queued 1
commit "$state/waited" waited-new new
waited_head=$(rev task/waited)
echo release > "$state/release-merge-lock"
wait "$merge_lock_holder"
expect "a task that got a new commit while its make merge waited does not land" "$(finish_merge waited) $(rev main)" "1 $before"
expect "that task keeps its new commit" "$(rev task/waited)" "$waited_head"

fake_node() {
    mkdir -p "$1"
    printf '#!/bin/sh\ncase "$1" in -v) echo v%s.0.0 ;; *) echo %s ;; esac\n' "$2" "$2" > "$1/node"
    chmod +x "$1/node"
}
# make merge never calls a Node manager: these fakes write a step if it does.
for manager in fnm nvm; do
    mkdir -p "$state/managers"
    printf '#!/bin/sh\necho %s-called >> "$FAKE_SIM_STATE/steps"\nexit 1\n' "$manager" > "$state/managers/$manager"
    chmod +x "$state/managers/$manager"
done
fake_node "$state/old-node" 20
fake_node "$state/node-24" 24
advance_main .nvmrc 24
path_before_node=$PATH
export PATH="$state/old-node:$state/managers:$PATH"
TROME_MERGE_CHECK="$passing_check && node -v >> \"\$FAKE_SIM_STATE/steps\""

lockf -k "$RATP_MERGE_LOCK" sh -c 'read -r line < "$0"' "$state/release-merge-lock" &
merge_lock_holder=$!
until ! lockf -s -k -t 0 "$RATP_MERGE_LOCK" true 2> /dev/null; do sleep 0.1; done
new_task docsoldnode
mkdir -p "$state/docsoldnode/docs"
commit "$state/docsoldnode" docs/other.md "other"
before=$(rev main)
merge docsoldnode
echo release > "$state/release-merge-lock"
wait "$merge_lock_holder"
expect "with an old Node active, make merge of a docs change fails" "$status" "1"
expect "it fails before it waits for a lock" "$(contains "$state/docsoldnode.log" "waiting for the merge")" "no"
expect "it runs no gate and calls no Node manager" "$(cat "$state/steps")" ""
expect "it says which Node is needed, which is active, and what to run" \
    "$(contains "$state/docsoldnode.log" "so the gate needs Node 24 (see .nvmrc), but the active Node is v20.0.0. Run make merge again with that Node, for example: fnm exec --using=.nvmrc -- make merge")" "yes"
expect "main is unchanged when the Node is too old" "$(rev main)" "$before"

new_task videooldnode
mkdir -p "$state/videooldnode/video"
commit "$state/videooldnode" video/Film.tsx "film"
merge videooldnode
expect "with an old Node active, make merge of a film change fails" "$status" "1"
expect "it names the film folder" "$(contains "$state/videooldnode.log" "changes docs/, server/, contracts/ or video/, so the gate needs Node 24")" "yes"

new_task appoldnode
commit "$state/appoldnode" app "app"
merge appoldnode
expect "with an old Node active, make merge of a change with no docs, server or contracts succeeds" "$status" "0"
expect "it calls no Node manager" "$(grep -c called "$state/steps")" "0"

# The caller picks the Node, as fnm exec or nvm use does: its folder comes first on the PATH.
export PATH="$state/node-24:$PATH"
new_task docsnode
mkdir -p "$state/docsnode/docs"
commit "$state/docsnode" docs/page.md "page"
merge docsnode
expect "with the Node of .nvmrc active, make merge of a docs change succeeds" "$status" "0"
expect "the gate of that merge runs with that Node, and no Node manager is called" "$(tr '\n' ' ' < "$state/steps")" "check v24.0.0 "
export PATH="$path_before_node"
TROME_MERGE_CHECK=$passing_check


# The record of the E2E pass: with a remote, make merge pushes main and leaves the record on GitHub (a fake gh),
# so that the release can refuse a commit of main whose tree the full suite never passed on (e2e-proof.sh).
export FAKE_GH_STATE="$state/gh"
mkdir -p "$FAKE_GH_STATE/statuses"
git init -q --bare "$state/origin.git"
git -C "$repo" remote add origin "$state/origin.git"
git -C "$repo" push -q origin main
cat > "$state/render.sh" << 'RENDER'
#!/bin/sh
echo render >> "$FAKE_SIM_STATE/steps"
if test -n "${RATP_SIM_HELD_PID:-}" && test "$(cat "$RATP_SIM_LOCK/pid" 2> /dev/null)" = "$RATP_SIM_HELD_PID"; then echo render-locked >> "$FAKE_SIM_STATE/steps"; fi
[ ! -e "$FAKE_SIM_STATE/render-fails" ] || { echo "The text recognition of this Mac failed"; exit 1; }
echo "Too tall for their text size, in fr: 0 (list: too-tall.csv)"
echo "Cut texts in the images (OCR, for a person to read): 5 (list: cut-texts.txt)"
echo "Breaches of the cut rules (texts cut too much), in the images of 3 stations: 1 (list: breaches.txt)"
RENDER
chmod +x "$state/render.sh"
export TROME_MERGE_RENDER="$state/render.sh"
TROME_MERGE_E2E=$passing_e2e

origin_main() {
    git -C "$state/origin.git" rev-parse main
}

record() {
    jq -r '.[0] | [.context, .state, .description] | join(" | ")' "$FAKE_GH_STATE/statuses/$1.json" 2> /dev/null || echo "no record"
}

proof() {
    (cd "$repo" && "$scripts/e2e-proof.sh" read "$1" || true)
}

short_main() {
    git -C "$repo" rev-parse --short "main${1:-}"
}

app_task recorded
merge recorded
expect "a merge with a remote succeeds" "$status" "0"
expect "after the E2E suite, it draws the views, as main has no render counts on GitHub" "$(steps_line)" "check build render-build e2e e2e-locked nested-job release-run release-run-locked render render-locked "
expect "it pushes main" "$(origin_main)" "$(rev main)"
expect "it leaves on the new commit of main the record of the full E2E pass, with the tree and the render counts" "$(record "$(rev main)")" \
    "E2E on the Mac | success | Full E2E passed on tree $(rev 'main^{tree}'). Render: too tall 0, cut texts 5, breaches 1. Release run: passed."
expect "it says so" "$(contains "$state/recorded.log" "make merge: pushed main, and left on $(short_main) the record of its full E2E pass and Release app run (the status 'E2E on the Mac' on GitHub), with its render counts: too tall 0, cut texts 5, breaches 1.")" "yes"
expect "the release reads the record" "$(proof main | head -n 2)" "E2E proof: found (the full E2E suite passed on the Mac on this tree)
Release app run: found (the app as the store ships it started on the Mac on this tree, with no Testing tools)"

app_task undrawn
merge undrawn
expect "a merge whose change the views do not draw runs no render check when main has render counts" "$(steps_line)" "check build e2e e2e-locked nested-job release-run release-run-locked "
expect "its record says that it did not draw" "$(record "$(rev main)")" \
    "E2E on the Mac | success | Full E2E passed on tree $(rev 'main^{tree}'). Render: not drawn. Release run: passed."
expect "the release shows the counts of the last drawing" "$(proof main | sed -n 3p)" \
    "render counts: too tall 0, cut texts 5, breaches 1 (drawn on the Mac on $(short_main '~1'))"

new_task views
mkdir -p "$state/views/ios/Widget"
commit "$state/views" ios/Widget/View.swift view
merge views
expect "a merge that changes the views draws them" "$(steps_line)" "check build render-build e2e e2e-locked nested-job release-run release-run-locked render render-locked "

new_task recorded_docs
commit "$state/recorded_docs" recorded_docs.md docs
before=$(origin_main)
merge recorded_docs
expect "a merge that changes no app code runs no E2E suite, no Release app run and no render check" "$(steps_line)" "check "
expect "it leaves no record and does not push: the push after the merge sends it" "$(origin_main) $(record "$(rev main)")" "$before no record"
git -C "$repo" push -q origin main
expect "the release still accepts its commit, by the record of the commit before it" "$(proof main | head -n 1)" \
    "E2E proof: found (the full E2E suite passed on the Mac on $(short_main '~1'); the 1 commits since change no app code)"

new_task render_fails
mkdir -p "$state/render_fails/ios/Widget"
commit "$state/render_fails" ios/Widget/Other.swift other
touch "$state/render-fails"
merge render_fails
rm "$state/render-fails"
expect "a render check that fails does not stop the merge: it is a report" "$status $(origin_main)" "0 $(rev main)"
expect "the record then says that it did not draw" "$(record "$(rev main)")" \
    "E2E on the Mac | success | Full E2E passed on tree $(rev 'main^{tree}'). Render: not drawn. Release run: passed."
expect "the merge says that the render check gave no counts" "$(contains "$state/render_fails.log" "the render check gave no counts")" "yes"

app_task e2e_fails
commit "$state/e2e_fails" fails-e2e bad
before=$(origin_main)
TROME_MERGE_E2E=$failing_e2e
merge e2e_fails
TROME_MERGE_E2E=$passing_e2e
expect "a merge whose E2E suite fails draws nothing, pushes nothing and leaves no record" \
    "$(steps_line)$(origin_main) $(record "$(rev task/e2e_fails)")" "check build render-build e2e e2e-locked nested-job $before no record"

app_task release_fails
before=$(origin_main)
TROME_MERGE_RELEASE_RUN="$passing_release_run && exit 1"
merge release_fails
TROME_MERGE_RELEASE_RUN=$passing_release_run
expect "a merge whose Release app run fails does not land, draws nothing, pushes nothing and leaves no record" \
    "$status $(steps_line)$(origin_main) $(record "$(rev task/release_fails)")" \
    "1 check build render-build e2e e2e-locked nested-job release-run release-run-locked $before no record"
expect "it says that the Release app run failed" "$(contains "$state/release_fails.log" "the step 'Release app run' failed for task/release_fails")" "yes"
expect "it says where the result bundle of the run is" "$(tail -1 "$state/release_fails.log")" \
    "Its result bundle, with the crash report when the app crashed: $(cd "$state/release_fails" && pwd -P)/ios/.build/release-run.xcresult"

app_task push_refused
git clone -q -b main "$state/origin.git" "$state/other-clone"
commit "$state/other-clone" pushed-elsewhere other
git -C "$state/other-clone" push -q origin main
merge push_refused
expect "when the push of main is refused, the merge still lands main" "$status $(rev main)" "0 $(rev task/push_refused)"
expect "it leaves no record, and says that a release refuses the commit" \
    "$(record "$(rev main)") $(contains "$state/push_refused.log" "the push of main to origin failed, so $(short_main) has no record of its E2E pass on GitHub, and a release refuses it")" "no record yes"
git -C "$repo" fetch -q origin main
git -C "$repo" reset -q --hard FETCH_HEAD

app_task gh_fails
touch "$FAKE_GH_STATE/fail"
merge gh_fails
rm "$FAKE_GH_STATE/fail"
expect "when GitHub cannot be read, the merge draws the views, as it cannot tell if main has render counts" "$(steps_line)" "check build render-build e2e e2e-locked nested-job release-run release-run-locked render render-locked "
expect "when GitHub does not take the record, the merge still lands and pushes main, and says that a release refuses the commit" \
    "$status $(origin_main) $(contains "$state/gh_fails.log" "but GitHub did not take the record of the E2E pass of $(short_main), so a release refuses it")" "0 $(rev main) yes"
git -C "$repo" remote remove origin

[ "$failures" -eq 0 ]
