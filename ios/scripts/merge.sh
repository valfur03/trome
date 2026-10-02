#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
target=main
check_command=${RATP_MERGE_CHECK:-make check}
e2e_command=${RATP_MERGE_E2E:-make e2e}
merge_lock=${RATP_MERGE_LOCK:-/tmp/ratp-merge.lock}
owner_changes="These changes belong to the owner of that folder. Ask the owner to commit, stash or drop them, and run 'make merge' again when the owner says that the folder is clear. Do not touch them yourself."

fail() {
    echo "make merge: $1" >&2
    exit 1
}

root=$(git rev-parse --show-toplevel 2> /dev/null) || fail "run it inside the worktree of the task."
cd "$root"

in_rebase() {
    [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

check_worktree() {
    branch=$(git symbolic-ref --short -q HEAD) || fail "HEAD is not on a branch. Check out the branch of the task."
    case "$branch" in
        "$target") fail "you are on '$branch'. Run it on the branch of the task." ;;
    esac
    git rev-parse -q --verify "refs/heads/$target" > /dev/null || fail "there is no branch '$target'."
    ! in_rebase || fail "a rebase is in progress. Finish it (git rebase --continue) or stop it (git rebase --abort) first."
    [ -z "${ONLY:-}" ] || fail "ONLY works only with 'make e2e'. make merge always runs the full E2E suite."
    [ -z "$(git status --porcelain)" ] || fail "the worktree has changes that are not committed. Commit them first, so the gate checks what $target gets."
    [ -n "$(git rev-list -n 1 "$target..HEAD")" ] || fail "'$branch' has no commit that '$target' does not have. There is nothing to merge."
    check_target_folder
}

check_target_folder() {
    checked_out=$(target_worktree)
    [ -n "$checked_out" ] || return 0
    blocked=$({
        git diff --name-only --no-renames "$target...HEAD"
        echo
        git -C "$checked_out" diff --name-only --no-renames HEAD
        git -C "$checked_out" ls-files --others --exclude-standard
    } | awk '!sep && $0 == "" { sep = 1; next } !sep { task[$0]; next } ($0 in task) && !seen[$0]++ { print "  " $0 }')
    [ -z "$blocked" ] || fail "$target is checked out in $checked_out, and that folder has changes that are not committed on files that '$branch' changes:
$blocked
The fast-forward would not be able to update these files. $target is unchanged.
$owner_changes"
}

step_failed() {
    echo "make merge: the step '$1' failed. $target is unchanged (still $(git rev-parse --short "$old")). make merge now frees the Simulator lock." >&2
    if [ -n "${2:-}" ]; then
        echo "$2" >&2
    fi
    exit 1
}

stop_rebase() {
    in_rebase || step_failed rebase "git rebase failed before it started, so no rebase is in progress: '$branch' is as it was before."
    conflicts=$(git diff --name-only --diff-filter=U | sed 's/^/  /')
    git rebase --abort || step_failed rebase "The rebase had a conflict, and 'git rebase --abort' failed: the rebase is still in progress in $root."
    step_failed rebase "The rebase had a conflict on these files:
$conflicts
make merge stopped the rebase (git rebase --abort): '$branch' is as it was before. The task goes back to its Software Engineer, who runs 'git -C $root rebase $target', solves the conflict, and hands the task over again."
}

changes_app_code() {
    git diff --name-only --no-renames "$1" "$2" | grep -qv -e '^docs/' -e '^README\.md$' -e '^CLAUDE\.md$' -e '^ios/Packages/RATPCore/Tests/'
}

step() {
    echo "make merge: $1" >&2
}

target_worktree() {
    git worktree list --porcelain | awk -v ref="refs/heads/$target" '
        /^worktree / { path = substr($0, 10) }
        $0 == "branch " ref { print path; exit }
    '
}

fast_forward() {
    checked_out=$(target_worktree)
    if [ -z "$checked_out" ]; then
        git update-ref -m "make merge: fast-forward to $branch" "refs/heads/$target" "$tested" "$old" \
            || step_failed fast-forward "$target moved during the merge, outside 'make merge'."
        return
    fi
    [ "$(git rev-parse "refs/heads/$target")" = "$old" ] || step_failed fast-forward "$target moved during the merge, outside 'make merge'."
    git -C "$checked_out" merge --ff-only -q "$tested" \
        || step_failed fast-forward "$target is checked out in $checked_out, and git could not update its files.
$owner_changes"
}

merge() {
    check_worktree
    old=$(git rev-parse "refs/heads/$target")
    step "1/4 rebase $branch onto $target ($(git rev-parse --short "$old"))"
    git rebase --no-rebase-merges "$old" || stop_rebase
    tested=$(git rev-parse HEAD)
    [ "$tested" != "$old" ] || fail "'$branch' has no change after the rebase. There is nothing to merge."
    step "2/4 quality gate ($check_command)"
    sh -c "$check_command" || step_failed "quality gate"
    if changes_app_code "$old" "$tested"; then
        step "3/4 full E2E suite ($e2e_command)"
        sh -c "$e2e_command" || step_failed "full E2E suite"
    else
        step "3/4 full E2E suite: skipped, $branch changes no app code (only docs or unit tests, see CLAUDE.md)"
    fi
    step "4/4 fast-forward $target to $(git rev-parse --short "$tested")"
    [ "$(git rev-parse HEAD)" = "$tested" ] || step_failed fast-forward "HEAD moved during the merge."
    git merge-base --is-ancestor "$old" "$tested" || step_failed fast-forward "$branch does not start from $target."
    fast_forward
    echo "make merge: $target is now $(git rev-parse --short "$tested") ($branch)." >&2
}

case "${1:-}" in
    "")
        check_worktree
        lockf -s -k -t 0 "$merge_lock" true || echo "make merge: waiting for the merge of another worktree to end" >&2
        exec lockf -k "$merge_lock" "$scripts/sim-lock.sh" job "$scripts/merge.sh" locked
        ;;
    locked)
        merge
        ;;
    *)
        echo "Usage: $0   Rebase the branch of this worktree onto $target, run the gate and the full E2E suite, then fast-forward $target, all with the Simulator lock" >&2
        exit 1
        ;;
esac
