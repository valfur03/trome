## Merge a task into main

A task reaches `main` only after QA passed it.
The order is:

1. The Software Engineer implements the task on its branch `task/<id>`, and another Software Engineer reviews it.
2. The implementer runs the quality gate (`make check`) on the last commit of the branch, plus the E2E test classes of the flows that the change touches (see "Which E2E tests to run").
   The reviewer hands the task over to QA.
   Before that, it makes sure that the gate passed on the last commit of the branch.
   A reviewer who changed no code runs nothing again: the run of the implementer covers that commit.
   A reviewer who changed code runs the gate, plus the E2E test classes of the flows that its change touches when it changed app code.
   No Software Engineer rebases the branch, merges, or runs `make merge`.
3. The manager rebases the branch onto `main` right before QA, so QA tests the branch on the latest `main`.
   When this rebase has a conflict, the manager stops it (`git rebase --abort`), and the task goes back to its Software Engineer, who solves it.
4. QA tests the branch.
5. When QA passed the task, the manager runs one command in the worktree of the task, one task at a time, instead of the separate steps (rebase, gate, E2E run, fast-forward):

```sh
make merge
```

When the branch changes `docs/`, `server/` or `contracts/`, load Node 24 first: `. "$HOME/.nvm/nvm.sh" && nvm use && make merge`.
Run it in the background: it can wait long for the Simulator lock.

It takes the Simulator lock, then does these steps.
Each step runs only when the step before it passed:

1. It rebases the branch of the worktree onto the tip of `main`.
2. It runs the quality gate (`make check`).
3. It runs the full E2E suite (`make e2e`), unless the branch changes no app code (see "Which E2E tests to run").
4. It fast-forwards `main` to the rebased branch.
   When `main` is checked out in a folder (the main folder of the repo), it updates that folder too, with `git merge --ff-only`: a fast-forward, never a merge commit.

Then it frees the lock.
When a step fails (a rebase conflict, the gate, the E2E suite), it stops at once, says which step failed, leaves `main` as it was, and frees the lock.
After a rebase conflict, it names the files of the conflict and stops the rebase (`git rebase --abort`): the branch and the worktree are as they were before `make merge`.
So after a conflict in either rebase (before QA or in `make merge`), the task goes back to its Software Engineer with no rebase in progress, and the command of the Software Engineer, `git -C <worktree> rebase main`, works: it shows the conflict again, and the Software Engineer solves it.
When the folder of `main` has changes that are not committed (also staged or new files) on the files of the task, `make merge` refuses at once, before it waits for a lock, and names the folder and the files.
Changes on other files of that folder do not stop it.
It checks this again when its turn comes, and the fast-forward still fails safely when such changes appear during the run.
It refuses to start on `main`, with changes that are not committed, with `ONLY=` (the E2E suite is always the full one), or with nothing to merge.

Why one command, with the lock all along:

- **Merges queue one after another.** A second `make merge` waits for the first one (it prints `waiting for the merge of another worktree`), then for the Simulator lock.
  When its turn comes, `main` already has the first merge, so it rebases onto it.
  Its fast-forward is never refused because another merge landed during its run.
- **A full E2E run is never repeated.** Before, another merge could land between the end of a full run and the fast-forward.
  The fast-forward was then refused, and the full suite had to run again after a new rebase.
- **History stays linear, and `main` stays green.** `main` moves only by fast-forward, to the exact commit that passed the gate and the E2E suite.
  No merge commit: a merge is always a rebase, then a fast-forward.

Why the Software Engineer does not rebase: the manager rebases right before QA, and `make merge` rebases again, so a rebase at hand-over only repeated them.
The permission system also refused it once.

`make merge` changes only `main` and the branch of the task.
It never checks out `main` in the worktree of the task.
When a step fails for a reason on the branch (a rebase conflict, the gate, the E2E suite), the task goes back to its Software Engineer (status `To Do`, with a comment).
The Software Engineer fixes the cause on the branch (for a rebase conflict, it runs `git -C <worktree> rebase main` and solves the conflict) and hands the task over again.
Then the manager runs `make merge` again.

When the E2E suite fails and `make merge` prints "The Mac slept during the E2E tests" after the failing tests, the cause is likely not on the branch: the Simulator stopped while the Mac slept, and the waits of the tests ran on the clock.
The task does not go back to its Software Engineer.
The manager runs `make merge` again, once (the rule on flaky tests).
When it fails again with no sleep, the task goes back as above.
Why: on 2026-09-30, a task that had passed QA went back to its Software Engineer for a night only because the Mac slept for 96 seconds during the full suite (TASK-140, TASK-154).
`caffeinate` cannot stop the sleep of a closed lid on battery.

When `make merge` refuses because the folder of `main` has changes that are not committed on the files of the task, the task does not go back to its Software Engineer: the branch is fine, and QA passed it.
That folder is the prompter's folder, and the changes are the prompter's.
The manager tells the prompter the folder and the files that `make merge` names, and the prompter decides: commit, stash or drop the changes.
The task stays as it is.
The manager runs `make merge` again when the prompter says that the folder is clear.
The same holds when the fast-forward fails because such changes appeared during the run.
No agent commits, stashes or discards the changes of the prompter's main folder without the prompter.
