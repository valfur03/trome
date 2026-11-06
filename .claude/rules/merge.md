---
paths:
  - "ios/scripts/merge.sh"
  - "ios/scripts/tests/merge-test.sh"
  - "ios/scripts/code-paths.sh"
  - "ios/scripts/e2e-paths.txt"
  - "ios/scripts/tests/e2e-paths-test.sh"
  - "ios/scripts/full-run.sh"
  - "ios/scripts/e2e-proof.sh"
  - "ios/scripts/tests/e2e-proof-test.sh"
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

**A merge goes first, but passes a job only once.** The Simulator jobs that wait stand in a line (`.claude/rules/simulator.md`).
A `make merge` of app code joins it when it asks for the Simulator lock, after its gate and its test builds, and goes before the jobs that are not merges (QA, a review, `make e2e`): they print `Waiting for the Simulator lock: 2nd in line, a merge goes first (<folder of the merge>), held by ...`.
But a job that one merge has passed goes before the next merge: so no job waits behind more than one merge, and a merge waits at most for the jobs that the merge before it passed.
The job that holds the lock keeps it to its end: a merge never cuts it off, and it names that job in its `Waiting for the Simulator lock` line.
Before it asks (while it rebases, runs its gate or waits in the queue), a job takes the free Simulator, and the merge then waits for it.
Why a merge goes first: a merge finishes a task, and the tasks that depend on it wait for it; on 2026-10-07, a merge waited about 25 minutes behind a QA run and a review.
Why only once: on 2026-10-31, a QA run waited 59 minutes for 2.5 minutes of use, as three merges, one after the other, and two render checks went before it (TASK-489).

**A merge holds the Simulator only for its test runs.** `make merge` rebases, runs the gate and builds the tests (`make e2e-build release-run-build`, and `make live-activity-render-build` when it draws) with no Simulator lock.
Then it takes the lock, runs the E2E tests, the Release app run and the render check on the builds (`NO_BUILD=1`), and frees the lock before the fast-forward.
It keeps the merge lock while it waits for the Simulator, so `main` cannot move between its gate and its tests.
When the rebased train changes no app code (the rule of "Which E2E tests to run" in `.claude/rules/tests.md`), it takes no Simulator lock at all: it prints `no Simulator lock`.
Why: the rebase, the gate and the builds use no Simulator; on 2026-10-31 they held it about 9.5 minutes of each merge of app code, and the gates of the merges with no app code held it 184 minutes in 52 hours, while QA, reviews and E2E runs waited (TASK-489).

**Merges that wait together land as one train.** The `make merge` that gets the merge lock takes every task whose `make merge` waits, in the order they started.
A `make merge` that starts while a train waits for the Simulator goes in the next train.
When the `make merge` that drives a train is stopped, the merge lock goes with it, but its train may still put the branches back and stop its tests: the next train waits for it (`waiting for the train of a stopped make merge to end`).
A train whose `make merge`s were all stopped while it waits for the Simulator stops waiting.
It rebases each task onto the one before it, then runs the gate and the E2E tests once, on the last one, for the files that the whole train changes, and fast-forwards `main` to it.
Why: each landing held the Simulator about 5 minutes, 28% of its time on 2026-10-07; a train of 2 or 3 tasks costs about one landing.
Before its rebase, each task runs `change-notes-check` on its own commits, and a task that fails it does not land.
Why: the gate of a train sees the commits of all its tasks, so a task of the app with no note would pass on the note of another task.
When the train fails (the gate, the E2E suite, the fast-forward), `main` does not move, each branch goes back to where it was, and the tasks land one by one, in the same run, each with its own gate and E2E run, as below.
So the task at fault goes back to its Software Engineer, and the others still land.
When every task passes alone, the failure of the train was flaky: `make merge` says so, with the evidence folder, and the manager creates a bug task for it (see "Flaky tests" in `CLAUDE.md`).
A task that conflicts with a task before it in the train skips the train and lands alone when that task does not land.
Each `make merge` prints the result of its own task; the one that ran the train also prints every step.

For each task alone, or once for a train, it does these steps.
Each step runs only when the step before it passed:

1. It rebases the branch of the worktree onto the tip of `main`.
2. It runs the quality gate (`make check`).
3. It builds the tests, then takes the Simulator lock and runs `make e2e` for the core classes and the classes that `ios/scripts/e2e-paths.txt` gives to the changed files, or the full suite when a changed file of app code has no line there (see "Which E2E tests to run" in `.claude/rules/tests.md`), unless the branch changes no app code.
   It retries a failed test once, and names a test that passed only on its retry (below).
   After a pass, it runs the app as the store ships it (`make release-run-check`, below), and fails when that run fails.
   Then it runs the render check (`make live-activity-render`) when the branch changes the Live Activity views or their data (`is_render_input`).
   The render check is a report: when it fails, the merge goes on.
   Then it frees the Simulator lock.
4. It fast-forwards `main` to the rebased branch.
   When `main` is checked out in a folder (the main folder of the repo), it updates that folder too, with `git merge --ff-only`: a fast-forward, never a merge commit.
   When its Simulator checks ran, it then pushes `main` to `origin`; it leaves no record for the release (below).

When a step fails (a rebase conflict, the gate, a test build, the E2E suite), it stops at once, says which step failed, leaves `main` as it was, and frees the locks; a failed gate or test build never takes the Simulator lock.
After a rebase conflict, it names the files of the conflict and stops the rebase (`git rebase --abort`): the branch and the worktree are as they were before `make merge`.
So after a conflict in either rebase (before QA or in `make merge`), the task goes back to its Software Engineer with no rebase in progress, and the command of the Software Engineer, `git -C <worktree> rebase main`, works: it shows the conflict again, and the Software Engineer solves it.
When the folder of `main` has changes that are not committed (also staged or new files) on the files of the task, `make merge` refuses at once, before it waits for a lock, and names the folder and the files.
Changes on other files of that folder do not stop it.
It checks this again when its turn comes, and the fast-forward still fails safely when such changes appear during the run.
It refuses to start on `main`, with changes that are not committed, with `ONLY=` (it picks the E2E classes by the changed files), or with nothing to merge.
It lands only the commit that it started with: a task whose branch gets a new commit while its `make merge` waits or runs does not land, and keeps that commit.

**The run of the Release app.** Every commit of `main` must be safe to ship as it is (decision-114).
The E2E suite runs the Debug app, and `make check` only compiles the Release app, so a fault of the Release app alone (a start that fails with no key, a Testing tool left outside `#if DEBUG`) passes them.
So `make release-run-check` builds the Release app as `make run RELEASE=1` does (no PRIM key, a server that never answers), installs it on the shared Simulator, under the lock, and starts it with one UI test (`ios/ReleaseRun/`).
It fails when the app does not start, does not reach its first screen, or shows a Testing tool.
It adds about 40 s to the time that a merge of app code holds the lock (measured in TASK-451): its build of about 30 s runs before the lock; a merge with no app code skips it, with the E2E tests.
When it fails, the task goes back to its Software Engineer, with the result bundle that `make merge` names (it holds the crash report when the app crashed).

**Unfinished work stays out of the Release app** (decision-114 point 3).
A change that is a part of a larger rider feature merges only when riders cannot reach it in the Release app: it is compiled out of the Release build, or off by a switch that the Release build holds off, and the path that riders use works as before.
Its ticket names how it is hidden, and the reviewer checks it.
When it shows something on a screen, its accessibility identifier goes in the list of `ios/ReleaseRun/ReleaseRunTests.swift`, so the run of the Release app proves that it is absent; the reviewer checks that too.
The change that turns the feature on removes it from that list, and carries the headline of its release.

**The record of the full run.** The release runs on GitHub, whose Mac cannot pass the E2E suite, so it reads the proof that the full suite passed on the Mac (decision-113).
A merge runs only the core checks and the E2E tests of its changed paths, so it writes no record: the full run does (decision-126).
`make full-run` runs every check on the head of `main` in a temporary worktree; the manager runs it each day, and on the commit to release before a release.
The record is a commit status of GitHub, named `E2E on the Mac`, on the commit of `main` that the full run tested: its text names the tree of that commit, the render counts (too tall, cut texts, breaches of decision-15) or "Render: not drawn", and "Release run: passed".
After its gate, release archive, full E2E suite and Release app run passed, `make full-run` pushes `main` (GitHub keeps a status only for a commit that it has) and writes the record with `ios/scripts/e2e-proof.sh publish`; the render check is a report, so a red one writes "not drawn".
`ios/scripts/e2e-proof.sh read` (`make e2e-proof`, and the workflow **E2E proof**, which the release checks run) reads it, prints `E2E proof: found` or `missing`, then `Release app run: found` or `missing`, and fails when either is missing:

- A commit that `make full-run` tested has its own record; so has a commit that an older `make merge` tested, when it still ran the full suite.
- A commit that changes no app code since a tested commit has none: the reader finds the record of the last commit before it that has one, when no commit between them changes app code.
  This is the rule by which `make merge` skips the E2E tests, from the same list (`ios/scripts/code-paths.sh`), so it opens no new way to skip them.
- A commit that changes app code with no record (any merge of app code, a push by hand) is refused, and so is every commit after it, until a full run passes on it or on a later commit.
- The render counts follow the same walk, with the list of the files that the views draw: a commit that changes them with no drawing has "render counts: missing", which shows but does not fail.

Only a token of the owner of the repo can write the record that counts: the reader keeps only the statuses whose author is the owner.
A workflow writes a status with its own token, whose author is `github-actions[bot]`, so a workflow on a pushed branch cannot forge one, and a branch push writes no status.
Never write the status `E2E on the Mac` by hand (`gh api .../statuses`): only `make full-run` writes it, after a full pass.
Why: the owner's token is the only guard, and agents use it.

When `make full-run` says that GitHub did not take the record, its checks passed, but a release refuses the commit.
Tell the prompter: the next full run writes the record.

Why one command, with the merge lock all along:

- **Merges queue one after another.** A second `make merge` waits for the first one (it prints `waiting for the merge of another worktree`): it lands in the train of the first one when both waited for the merge lock together, or else after it.
  When its turn comes, `main` already has the first merge, so it rebases onto it.
  Its fast-forward is never refused because another merge landed during its run.
- **The E2E run of a merge is never repeated.** Before, another merge could land between the end of an E2E run and the fast-forward.
  The fast-forward was then refused, and the E2E tests had to run again after a new rebase.
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

**Guide steps after a rebase.** When a rebase of the Software Engineer brings in a change of `main` on what the guide steps of the task describe (the steps that the task writes or changes in `ios/guide/` or `server/guide/`, the code that they run, or the page itself),
the Software Engineer runs those steps again by hand before the task goes back to review, through the Simulator lock when a step uses the Simulator.
Its notes carry the line `Guide steps run again after the rebase: yes`, with what it ran and saw, or `Guide steps run again after the rebase: none to run`, when the rebase changed nothing that a step of the task describes.
The reviewer of a rebased task checks that line: a missing line, or a `none to run` that the rebase diff contradicts, is a finding.
Why: on 2026-11-01, a rebase changed what the guide steps of a task described, nobody ran them again, and the guide told a thing that the app no longer did (TASK-504).

When the E2E tests fail, `make merge` prints the folder where the run kept its log, its `.xcresult` and the Simulator log (in `~/Library/Logs/TROME/e2e-failures/`).
Put that path in the comment or the bug task: the folder outlives the worktree and the next run, so the next agent can read the evidence.

**A test that fails, then passes on its retry.** `make merge` runs `make e2e E2E_RETRY=1`: the runner of Xcode runs a failed test once more.
A test that fails twice is red: the task goes back as above.
A test that passes only on its retry lets the task land, and `make merge` names it: `make merge: flaky E2E tests (each failed, then passed on its retry): ...`, with its evidence folder in the log of the run.
The manager then creates its `flaky` bug task, or adds the run to the open one ("Flaky tests" in `CLAUDE.md`); no script writes to the backlog.
The retry also covers a sleep of the Mac during the tests (the test that the sleep broke runs again after the wake), so a merge is no longer run again by hand for it.
Why: on 2026-09-30, a task that had passed QA went back to its Software Engineer for a night only because the Mac slept for 96 seconds during the full suite (TASK-140, TASK-154); `caffeinate` cannot stop the sleep of a closed lid on battery.

When `make merge` refuses because the folder of `main` has changes that are not committed on the files of the task, the task does not go back to its Software Engineer: the branch is fine, and QA passed it.
That folder is the prompter's folder, and the changes are the prompter's.
The manager tells the prompter the folder and the files that `make merge` names, and the prompter decides: commit, stash or drop the changes.
The task stays as it is.
The manager runs `make merge` again when the prompter says that the folder is clear.
The same holds when the fast-forward fails because such changes appeared during the run.
No agent commits, stashes or discards the changes of the prompter's main folder without the prompter.
