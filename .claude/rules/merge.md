---
paths:
  - "ios/scripts/merge.sh"
  - "ios/scripts/tests/merge-test.sh"
commands:
  - '^(\S*/)?make\b.*\smerge(\s|$)'
  - '^git(\s+-[Cc]\s+\S+|\s+--?\S+)*\s+(rebase|merge|pull)(\s|$)'
---
# Merge a task into main

These rules are for the manager, who rebases a branch before QA and runs `make merge`, and for the Software Engineer who solves a rebase conflict.
A task reaches `main` only after QA passed it.
The order is:

1. The Software Engineer implements the task on its branch `task/<id>`, and another Software Engineer reviews it.
2. The implementer runs the quality gate (`make check`) on the last commit of the branch, plus the E2E test classes of the flows that the change touches (see "Which E2E tests to run" in `.claude/rules/tests.md`).
   The reviewer hands the task over to QA.
   Before that, it makes sure that the gate passed on the last commit of the branch.
   A reviewer who changed no code runs nothing again: the run of the implementer covers that commit.
   A reviewer who changed code runs the gate, plus the E2E test classes of the flows that its change touches when it changed app code.
   No Software Engineer rebases the branch, merges, or runs `make merge`.
3. The manager rebases the branch onto `main` right before QA, so QA tests the branch on the latest `main`.
   When this rebase has a conflict, the manager stops it (`git rebase --abort`), and the task goes back to its Software Engineer, who solves it.
4. QA tests the branch.
5. When QA passed the task, the manager runs one command in the worktree of the task, instead of the separate steps (rebase, gate, E2E run, fast-forward), as soon as QA passed it, also while another merge runs:

```sh
fnm exec --using=.nvmrc -- make merge
```

Run it through fnm whatever the branch changes: the shell of an agent loads no Node manager, so its `node` is an old one, or none, and the docs, server and film checks of the gate need the Node of `.nvmrc`.
`make merge` uses the Node of its caller and calls no Node manager, so it works with any of them.
When that Node is older than the one of `.nvmrc` and the branch changes `docs/`, `server/`, `contracts/` or `video/`, `make merge` refuses at once, before it waits for a lock, and says what to run.
Why: twice (2026-10-04 and 2026-10-07), a merge waited for the lock, then failed in the gate because the shell had the old default Node and the branch changed a docs page.
Run it in the background: it can wait long for the Simulator lock.

**A merge goes first.** While a `make merge` waits, a Simulator job that is not a merge (QA, a review, `make e2e`) does not take the lock: it prints `Waiting for the Simulator lock of slot 1: a merge goes first`, with the folder of that merge.
The job that holds the lock keeps it to its end: a merge never cuts it off.
Why: a merge finishes a task, and the tasks that depend on it wait for it; on 2026-10-07, a merge waited about 25 minutes behind a QA run and a review.

**Merges that wait together land as one train.** The `make merge` that gets the Simulator lock takes every task whose `make merge` waits, in the order they started.
It rebases each task onto the one before it, then runs the gate and the full E2E suite once, on the last one, and fast-forwards `main` to it.
Why: each landing held the Simulator about 5 minutes, 28% of its time on 2026-10-07; a train of 2 or 3 tasks costs about one landing.
When the train fails (the gate, the E2E suite, the fast-forward), `main` does not move, each branch goes back to where it was, and the tasks land one by one, in the same run, each with its own gate and E2E run, as below.
So the task at fault goes back to its Software Engineer, and the others still land.
When every task passes alone, the failure of the train was flaky: `make merge` says so, with the evidence folder, and the manager creates a bug task for it (see "Flaky tests" in `CLAUDE.md`).
A task that conflicts with a task before it in the train skips the train and lands alone when that task does not land.
Each `make merge` prints the result of its own task; the one that ran the train also prints every step.

For each task alone, or once for a train, it takes the Simulator lock, then does these steps.
Each step runs only when the step before it passed:

1. It rebases the branch of the worktree onto the tip of `main`.
2. It runs the quality gate (`make check`).
3. It runs the full E2E suite (`make e2e`), unless the branch changes no app code (see "Which E2E tests to run" in `.claude/rules/tests.md`).
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
It lands only the commit that it started with: a task whose branch gets a new commit while its `make merge` waits or runs does not land, and keeps that commit.

Why one command, with the lock all along:

- **Merges queue one after another.** A second `make merge` waits for the first one (it prints `waiting for the merge of another worktree`): it lands in the train of the first one when that one still waits for the Simulator, or else after it.
  When its turn comes, `main` already has the first merge, so it rebases onto it.
  Its fast-forward is never refused because another merge landed during its run.
- **A full E2E run is never repeated.** Before, another merge could land between the end of a full run and the fast-forward.
  The fast-forward was then refused, and the full suite had to run again after a new rebase.
- **A recorded set of promises is never part of a conflict fix.** In a rebase, a conflict in `contracts/builds/` is solved by taking the version of `main`, never by a mix or an edit; a branch that edits or deletes a recorded set is sent back, unless the release guide retires every build of that set in the same branch.
  `make merge` runs `make server-check` for a change of `server/` or `contracts/`, which fails on such an edit and on a server change that breaks a set as its builds read it.
  Why: riders hold those builds and they never change, so the server changes by adding (decision-93, decision-94; `.claude/rules/server.md`).
- **History stays linear, and `main` stays green.** `main` moves only by fast-forward, to the exact commit that passed the gate and the E2E suite.
  No merge commit: a merge is always a rebase, then a fast-forward.

Why the Software Engineer does not rebase: the manager rebases right before QA, and `make merge` rebases again, so a rebase at hand-over only repeated them.
The permission system also refused it once.

`make merge` changes only `main` and the branches of the tasks that it tries to land.
A task that lands, or a task alone whose gate or E2E suite fails, keeps its branch rebased onto `main`; after a train fails, each branch is back where it was.
It never checks out `main` in the worktree of the task.
When a step fails for a reason on the branch (a rebase conflict, the gate, the E2E suite), the task goes back to its Software Engineer (status `To Do`, with a comment).
The Software Engineer fixes the cause on the branch (for a rebase conflict, it runs `git -C <worktree> rebase main` and solves the conflict) and hands the task over again.
Then the manager runs `make merge` again.

When the E2E suite fails, `make merge` prints the folder where the run kept its log, its `.xcresult` and the Simulator log (in `~/Library/Logs/TROME/e2e-failures/`).
Put that path in the comment or the bug task: the folder outlives the worktree and the next run, so the next agent can read the evidence.

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
