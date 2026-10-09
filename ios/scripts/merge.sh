#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
target=main
check_command=${TROME_MERGE_CHECK:-make check}
e2e_command=${TROME_MERGE_E2E:-make e2e}
merge_lock=${RATP_MERGE_LOCK:-/tmp/ratp-merge.lock}
# sim-lock.sh reads the same queue: a job that is not a merge waits while a merge waits in it.
queue=${RATP_MERGE_QUEUE:-${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}.merge-queue}
owner_changes="These changes belong to the owner of that folder. Ask the owner to commit, stash or drop them, and run 'make merge' again when the owner says that the folder is clear. Do not touch them yourself."

say() {
    echo "make merge: $1" >&2
}

fail() {
    say "$1"
    exit 1
}

step() {
    say "$1"
}

short() {
    git rev-parse --short "$1"
}

target_head() {
    git rev-parse "refs/heads/$target"
}

root=$(git rev-parse --show-toplevel 2> /dev/null) || fail "run it inside the worktree of the task."
cd "$root"

in_rebase() {
    for name in rebase-merge rebase-apply; do
        [ ! -d "$(git -C "$1" rev-parse --path-format=absolute --git-path "$name")" ] || return 0
    done
    return 1
}

branch_of() {
    git -C "$1" symbolic-ref --short -q HEAD
}

# Prints why the worktree $1 cannot go to main now, or nothing.
worktree_problem() {
    if ! problem_branch=$(branch_of "$1"); then
        echo "HEAD of $1 is not on a branch. Check out the branch of the task."
    elif [ "$problem_branch" = "$target" ]; then
        echo "you are on '$problem_branch'. Run it on the branch of the task."
    elif in_rebase "$1"; then
        echo "a rebase is in progress in $1. Finish it (git rebase --continue) or stop it (git rebase --abort) first."
    elif [ -n "$(git -C "$1" status --porcelain)" ]; then
        echo "$1 has changes that are not committed. Commit them first, so the gate checks what $target gets."
    elif [ -z "$(git -C "$1" rev-list -n 1 "$target..HEAD")" ]; then
        echo "'$problem_branch' has no commit that '$target' does not have. There is nothing to merge."
    fi
}

target_worktree() {
    git worktree list --porcelain | awk -v ref="refs/heads/$target" '
        /^worktree / { path = substr($0, 10) }
        $0 == "branch " ref { print path; exit }
    '
}

# Prints the files that the task of the worktree $1 changes and that have changes that are not committed
# in the folder where main is checked out, with what to do, or nothing.
target_folder_problem() {
    checked_out=$(target_worktree)
    [ -n "$checked_out" ] || return 0
    blocked=$({
        git -C "$1" diff --name-only --no-renames "$target...HEAD"
        echo
        git -C "$checked_out" diff --name-only --no-renames HEAD
        git -C "$checked_out" ls-files --others --exclude-standard
    } | awk '!sep && $0 == "" { sep = 1; next } !sep { task[$0]; next } ($0 in task) && !seen[$0]++ { print "  " $0 }')
    [ -z "$blocked" ] || echo "$target is checked out in $checked_out, and that folder has changes that are not committed on files that '$(branch_of "$1")' changes:
$blocked
The fast-forward would not be able to update these files. $target does not get '$(branch_of "$1")'.
$owner_changes"
}

node_major() {
    "${1:-node}" -p 'process.versions.node.split(".")[0]' 2> /dev/null
}

required_node() {
    tr -d '[:space:]v' < .nvmrc
}

# The caller picks the Node, with any Node manager: this script only checks it, at once, before it waits for a lock.
check_node() {
    [ -f .nvmrc ] || return 0
    required=$(required_node)
    [ "$(node_major || echo 0)" -lt "$required" ] || return 0
    git diff --quiet "$target...HEAD" -- docs server contracts && return 0
    active=$(node -v 2> /dev/null || echo "none")
    fail "'$branch' changes docs/, server/ or contracts/, so the gate needs Node $required (see .nvmrc), but the active Node is $active. Run make merge again with that Node, for example: fnm exec --using=.nvmrc -- make merge (run 'fnm install' once before)."
}

# The gate of a train needs the Node that each of its tasks needs: when the Node of this process is too old,
# it takes the Node that the make merge of another task of the train found.
use_node_of() {
    [ -f .nvmrc ] || return 0
    required=$(required_node)
    [ "$(node_major || echo 0)" -lt "$required" ] || return 0
    for node_key; do
        dir=$(field "$node_key" node)
        if [ -n "$dir" ] && [ "$(node_major "$dir/node" || echo 0)" -ge "$required" ]; then
            PATH="$dir:$PATH"
            export PATH
            step "uses Node $(node -v) of $dir, as .nvmrc asks"
            return 0
        fi
    done
}

is_app_code() {
    case "$1" in
        ios/Packages/TROMECore/Tests/*) return 1 ;;
        ios/App/* | ios/Widget/* | ios/UITests/* | ios/DocsScreenshots/* | ios/RenderCheck/* | ios/Packages/*) return 0 ;;
        docs/* | server/* | contracts/* | .claude/* | .github/* | *.md | *.mdx | LICENSE) return 1 ;;
    esac
    return 0
}

changes_app_code() {
    git diff --name-only --no-renames "$1" "$2" | {
        while IFS= read -r path; do
            ! is_app_code "$path" || exit 0
        done
        exit 1
    }
}

e2e_evidence() {
    kept=$(cat "$1" 2> /dev/null || true)
    rm -f "$1"
    if [ -n "$kept" ]; then
        echo "The log, the .xcresult and the Simulator log of the failed run are kept in $kept"
    else
        echo "The failed run kept no evidence folder: it stopped before the tests ran, so its output above is all there is."
    fi
}

# The queue: each make merge writes one entry, <key>.task, then waits for the merge lock.
# The make merge that gets the merge lock lands every task that waits, as one train, and writes the result of each task
# (<key>.result); the make merge of each task prints its own result.

field() {
    if [ -n "${work:-}" ] && [ -f "$work/$1.task" ]; then
        sed -n "s/^$2=//p" "$work/$1.task"
    else
        sed -n "s/^$2=//p" "$queue/$1.task"
    fi
}

enqueue() {
    mkdir -p "$queue"
    key=$(perl -MTime::HiRes=time -e 'printf "%.6f", time').$$
    node_path=$(command -v node 2> /dev/null || true)
    printf 'pid=%s\nroot=%s\nbranch=%s\nhead=%s\nnode=%s\n' "$$" "$root" "$branch" "$(git rev-parse HEAD)" "${node_path:+$(dirname "$node_path")}" > "$queue/$key.new"
    trap 'rm -f "$queue/$key.new" "$queue/$key.task" "$queue/$key.result" "$queue/$key.result.new"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mv "$queue/$key.new" "$queue/$key.task"
}

finish() {
    # The make merge of the task has ended (it was stopped): nobody waits for the result.
    [ -e "$queue/$1.task" ] || return 0
    {
        echo "$2"
        if [ "$(field "$1" root)" != "$root" ]; then
            echo "make merge: this task went in the train of the make merge of $root, whose output shows each step."
            printf '%s\n' "$3" >&2
        fi
        printf '%s\n' "$3"
    } > "$queue/$1.result.new"
    mv "$queue/$1.result.new" "$queue/$1.result"
}

# A pid that the system gave again to another process is not the make merge of the entry.
alive() {
    ps -p "$(field "$1" pid)" -o command= 2> /dev/null | grep -q 'merge\.sh'
}

failed() {
    echo "make merge: the step '$1' failed for $2. $target does not get it ($target is $(short "$(target_head)")).${3:+
$3}"
}

# Stops the rebase of the worktree $1 after a conflict, and prints what happened.
stop_rebase() {
    if ! in_rebase "$1"; then
        failed rebase "$2" "git rebase failed before it started, so no rebase is in progress: '$2' is as it was before."
        return
    fi
    conflicts=$(git -C "$1" diff --name-only --diff-filter=U | sed 's/^/  /')
    if ! git -C "$1" rebase --abort >&2; then
        failed rebase "$2" "The rebase had a conflict, and 'git rebase --abort' failed: the rebase is still in progress in $1."
        return
    fi
    failed rebase "$2" "The rebase had a conflict on these files:
$conflicts
make merge stopped the rebase (git rebase --abort): '$2' is as it was before. The task goes back to its Software Engineer, who runs 'git -C $1 rebase $target', solves the conflict, and hands the task over again."
}

# Puts the branches of a train that did not land back where they were before make merge,
# so that no branch keeps the commits of another task of the train.
# A branch that got a new commit during the merge stays as it is: a reset would drop that commit.
put_back() {
    for put_key in $touched; do
        put_root=$(field "$put_key" root)
        put_orig=$(cat "$work/$put_key.orig")
        put_head=$(git -C "$put_root" rev-parse HEAD)
        [ "$put_head" != "$put_orig" ] || continue
        if [ -f "$work/$put_key.tested" ] && [ "$put_head" != "$(cat "$work/$put_key.tested")" ]; then
            say "'$(field "$put_key" branch)' got a new commit during the merge, so make merge leaves it on $(short "$put_head"), and it does not land. It may hold the commits of the tasks before it in the train: before its next make merge, check that 'git -C $put_root log --oneline $target..HEAD' shows only commits of this task."
            continue
        fi
        git -C "$put_root" reset -q --keep "$put_orig" \
            || say "could not put '$(field "$put_key" branch)' back on $(short "$put_orig"), likely because of changes that are not committed in $put_root. Commit or stash them, then run 'git -C $put_root reset --keep $put_orig' before its next make merge."
    done
    put_back_on_exit=
}

on_train_exit() {
    status=$?
    trap - EXIT
    if [ -n "${rebasing:-}" ] && in_rebase "$rebasing"; then
        git -C "$rebasing" rebase --abort || true
    fi
    if [ -n "${put_back_on_exit:-}" ]; then
        put_back
    fi
    rm -rf "$work"
    exit "$status"
}

fast_forward() {
    checked_out=$(target_worktree)
    if [ -z "$checked_out" ]; then
        if ! git update-ref -m "make merge: fast-forward to $(short "$tip")" "refs/heads/$target" "$tip" "$old"; then
            stack_failure="$target moved during the merge, outside 'make merge'."
            return 1
        fi
        return 0
    fi
    if [ "$(target_head)" != "$old" ]; then
        stack_failure="$target moved during the merge, outside 'make merge'."
        return 1
    fi
    if ! git -C "$checked_out" merge --ff-only -q "$tip" >&2; then
        stack_failure="$target is checked out in $checked_out, and git could not update its files.
$owner_changes"
        return 1
    fi
}

# Rebases the tasks of the keys one on top of the other, onto main, runs the gate and the E2E suite once on the last one,
# and fast-forwards main to it.
# When a train of two tasks or more fails, it puts their branches back, and sets 'fallback' to the tasks that land one by one.
land() {
    old=$(target_head)
    base=$old
    stacked=
    conflicted=
    fallback=
    touched=
    put_back_on_exit=
    for key; do
        if ! alive "$key"; then
            step "the make merge of $(field "$key" branch) was stopped: it does not land."
            continue
        fi
        task_root=$(field "$key" root)
        problem=$(worktree_problem "$task_root" 2>&1)
        [ -n "$problem" ] || problem=$(target_folder_problem "$task_root")
        if [ -n "$problem" ]; then
            finish "$key" 1 "make merge: $problem"
            continue
        fi
        task_branch=$(branch_of "$task_root")
        git -C "$task_root" rev-parse HEAD > "$work/$key.orig"
        # Only the commit that make merge started with lands: a later commit was not tested before the merge.
        if [ "$(cat "$work/$key.orig")" != "$(field "$key" head)" ]; then
            finish "$key" 1 "make merge: '$task_branch' got a new commit ($(short "$(cat "$work/$key.orig")")) after its make merge started on $(short "$(field "$key" head)"). It does not land: make merge lands only the commit that it started with. Run 'make merge' again if the new commit belongs to the task."
            continue
        fi
        touched="$touched $key"
        # From the first rebase on, a stopped train puts every branch back: a later task is rebased onto the earlier ones.
        [ "$#" -le 1 ] || put_back_on_exit=1
        if [ "$base" = "$old" ]; then
            step "1/4 rebase $task_branch onto $target ($(short "$base"))"
        else
            step "1/4 rebase $task_branch onto the tasks before it in the train ($(short "$base"))"
        fi
        rebasing=$task_root
        if ! git -C "$task_root" rebase --no-rebase-merges "$base" >&2; then
            message=$(stop_rebase "$task_root" "$task_branch")
            rebasing=
            if [ "$base" = "$old" ]; then
                finish "$key" 1 "$message"
            else
                printf '%s\n' "$message" > "$work/$key.conflict"
                conflicted="$conflicted $key"
                step "$task_branch conflicts with the tasks before it in the train: it lands alone if one of them does not land."
            fi
            continue
        fi
        rebasing=
        tested=$(git -C "$task_root" rev-parse HEAD)
        if [ "$tested" = "$base" ]; then
            finish "$key" 1 "make merge: '$task_branch' has no change after the rebase. There is nothing to merge."
            continue
        fi
        echo "$tested" > "$work/$key.tested"
        base=$tested
        stacked="$stacked $key"
        tip_root=$task_root
    done
    [ -n "$stacked" ] || return 0
    tip=$base
    set -- $stacked
    count=$#
    names=
    for key; do
        names="$names${names:+, }$(field "$key" branch)"
    done
    if [ "$count" -gt 1 ]; then
        once=", once for $names"
    else
        # One task alone keeps its rebased branch when a step fails, as a merge alone always did.
        put_back_on_exit=
        once=
    fi
    stack_step=
    stack_failure=
    shared="one gate"
    use_node_of "$@"
    step "2/4 quality gate ($check_command)$once"
    if ! (cd "$tip_root" && sh -c "$check_command"); then
        stack_step="quality gate"
    elif changes_app_code "$old" "$tip"; then
        shared="one gate and one E2E run"
        step "3/4 full E2E suite ($e2e_command)$once"
        evidence_note=$(mktemp "${TMPDIR:-/tmp}/trome-e2e-evidence.XXXXXX")
        if ! (cd "$tip_root" && TROME_E2E_EVIDENCE_NOTE=$evidence_note sh -c "$e2e_command"); then
            stack_step="full E2E suite"
            stack_failure=$(e2e_evidence "$evidence_note")
        fi
        rm -f "$evidence_note"
    else
        step "3/4 full E2E suite: skipped, $names changes no app code (only docs, Markdown, LICENSE, .claude/, .github/, unit tests, the server or the contracts, see .claude/rules/tests.md)"
    fi
    if [ -z "$stack_step" ]; then
        step "4/4 fast-forward $target to $(short "$tip")"
        stack_step=fast-forward
        for key; do
            if [ "$(git -C "$(field "$key" root)" rev-parse HEAD)" != "$(cat "$work/$key.tested")" ]; then
                stack_failure="HEAD of $(field "$key" root) moved during the merge."
            elif ! alive "$key"; then
                stack_failure="the make merge of $(field "$key" branch) was stopped during the merge, so it does not land."
            fi
        done
        if [ -n "$stack_failure" ]; then
            :
        elif ! git merge-base --is-ancestor "$old" "$tip"; then
            stack_failure="$names does not start from $target."
        elif fast_forward; then
            stack_step=
            put_back_on_exit=
        fi
    fi
    if [ -z "$stack_step" ]; then
        for key; do
            if [ "$count" -eq 1 ]; then
                finish "$key" 0 "make merge: $target is now $(short "$tip") ($names)."
            else
                finish "$key" 0 "make merge: $target is now $(short "$tip") ($names). $(field "$key" branch) landed in a train of $count tasks, which shared $shared."
            fi
        done
        for key in $conflicted; do
            finish "$key" 1 "$(cat "$work/$key.conflict")"
        done
        return 0
    fi
    if [ "$count" -eq 1 ]; then
        finish "$1" 1 "$(failed "$stack_step" "$names" "$stack_failure")"
        fallback=$conflicted
        return 0
    fi
    say "the train of $names failed at the step '$stack_step'. $target is unchanged ($(short "$old")).${stack_failure:+
$stack_failure}"
    put_back
    for key in $train_keys; do
        case " $stacked $conflicted " in
            *" $key "*) fallback="$fallback $key" ;;
        esac
    done
}

train() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/trome-merge.XXXXXX")
    trap on_train_exit EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    train_keys=
    for entry in "$queue"/*.task; do
        [ -f "$entry" ] || continue
        entry_key=$(basename "$entry" .task)
        [ ! -e "$queue/$entry_key.result" ] || continue
        if ! alive "$entry_key"; then
            rm -f "$entry"
            continue
        fi
        # A copy: the entry goes away when its make merge is stopped, and the train still needs to know its worktree.
        cp "$entry" "$work/$entry_key.task"
        train_keys="$train_keys $entry_key"
    done
    set -- $train_keys
    if [ "$#" -gt 1 ]; then
        names=
        for entry_key; do
            names="$names${names:+, }$(field "$entry_key" branch)"
        done
        step "$# tasks wait to land, in this order: $names. They go as one train, with one gate and one E2E run for all."
    fi
    land "$@"
    [ -n "$fallback" ] || return 0
    train_step=$stack_step
    train_evidence=$stack_failure
    train_stacked=$stacked
    step "the tasks of the train now land one by one:$(for one in $fallback; do printf ' %s' "$(field "$one" branch)"; done)"
    for one in $fallback; do
        land "$one"
    done
    case "$train_step" in
        "quality gate" | "full E2E suite") ;;
        *) return 0 ;;
    esac
    last=
    for one in $train_stacked; do
        [ "$(head -n 1 "$queue/$one.result" 2> /dev/null)" = 0 ] || return 0
        last=$one
    done
    flaky="make merge: the train failed at the step '$train_step', but each of its tasks passed it alone: that failure is flaky. Create a bug task for it (see 'Flaky tests' in CLAUDE.md).${train_evidence:+
$train_evidence}"
    say "$flaky"
    [ ! -e "$queue/$last.result" ] || printf '%s\n' "$flaky" >> "$queue/$last.result"
}

case "${1:-}" in
    "")
        branch=$(branch_of "$root") || fail "HEAD is not on a branch. Check out the branch of the task."
        [ "$branch" != "$target" ] || fail "you are on '$branch'. Run it on the branch of the task."
        git rev-parse -q --verify "refs/heads/$target" > /dev/null || fail "there is no branch '$target'."
        [ -z "${ONLY:-}" ] || fail "ONLY works only with 'make e2e'. make merge always runs the full E2E suite."
        problem=$(worktree_problem "$root")
        [ -z "$problem" ] || fail "$problem"
        problem=$(target_folder_problem "$root")
        [ -z "$problem" ] || fail "$problem"
        check_node
        enqueue
        lockf -s -k -t 0 "$merge_lock" true || step "waiting for the merge of another worktree to end; this task may go in its train"
        status=0
        lockf -k "$merge_lock" "$scripts/merge.sh" drive "$key" || status=$?
        if [ -e "$queue/$key.result" ]; then
            sed 1d "$queue/$key.result" >&2
            exit "$(head -n 1 "$queue/$key.result")"
        fi
        fail "the merge of '$branch' stopped before its end (status $status). $target is $(short "$(target_head)")."
        ;;
    drive)
        # With the merge lock: the task already landed in the train of another make merge, or this one drives the next train.
        [ ! -e "$queue/$2.result" ] || exit 0
        RATP_SIM_MERGE=1
        export RATP_SIM_MERGE
        exec "$scripts/sim-lock.sh" job "$scripts/merge.sh" train
        ;;
    train)
        train
        ;;
    *)
        echo "Usage: $0   Land the branch of this worktree on $target, before the other Simulator jobs that wait: rebase, gate, full E2E suite, fast-forward. The merges that wait together share one gate and one E2E run." >&2
        exit 1
        ;;
esac
