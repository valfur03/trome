---
paths:
  - "ios/scripts/sim-lock.sh"
  - "ios/scripts/simulator.sh"
  - "ios/scripts/tests/sim-lock-test.sh"
commands:
  - '^(\S*/)?make\b.*\s(run|e2e|docs-screenshots|live-activity-render|switch-language|merge|simulator-delete|simulator-delete-old)(\s|$)'
  - '^\S*sim-lock\.sh(\s|$)'
  - '^\S*simulator\.sh(\s|$)'
  - '^xcrun\b.*\ssimctl\b'
  - '^xcodebuild\b.*(\stest(-without-building)?(\s|$)|-destination)'
  - '^open\b.*Simulator'
---
# The shared Simulator and its lock

These rules are for every job that boots or uses a Simulator: `make run`, `make e2e`, `make docs-screenshots`, `make live-activity-render`, `make merge`, and any command through `ios/scripts/sim-lock.sh`.
The two rules above them, never a second Simulator and at most one Simulator job, are in `CLAUDE.md`.

**The code of the second slot (decided against on this Mac):** `ios/scripts/sim-lock.sh` keeps the code of a second slot, but off (`slots=${RATP_SIM_SLOTS:-1}`).
It is not a trial that an agent or a task can run.
Never change this line, and never add `RATP_SIM_SLOTS=2` to a command.
Only the prompter, in person, can decide to turn it on again, and only with a new reason (for example, a different Mac).
How that code works, and the measurements behind these rules, are in `.claude/rules/simulator-history.md`.

## The shared Simulator

All worktrees use one shared Simulator, named `RATP-Shared`.

- Each job installs its own build of the app.
  Before that, it removes the app and its data (and the host app of the render check), resets the permissions, sets the text size and the appearance back to the iOS default (Large text, Light), and clears the fake position of the Simulator.
  So a job never sees the data or the saved settings of another worktree.
- The Simulator stays booted between jobs, so the next job does not wait for a cold boot.
- It shuts down by itself after 5 minutes with no job.
  Why 5 minutes: it is longer than the usual gap between two jobs (fix a test, then run `make e2e` again; the next agent starts its job).
  It is short enough to give the Mac back soon when the factory stops.
  A small background process (`ios/scripts/sim-lock.sh watch`) does this.
  It uses no Simulator and almost no CPU, and it stops by itself.
  With the second slot on, it does the same for each slot, with the same delay.
- **The smallest iPhone.** To check a screen on the smallest supported iPhone (375 x 667 pt), run `make run SMALL=1`.
  It uses a second shared Simulator, `RATP-Shared-Small` (an iPhone SE), through the same lock.
  Only one shared Simulator of a slot is booted at a time.
  Before a job or a `make run` boots its Simulator, it shuts down the other shared Simulator of its slot.
  When it cannot shut it down, it stops, and it does not boot a second one.
  `make simulator-shutdown` removes the app from `RATP-Shared-Small` and keeps it booted, alone.
  The watcher shuts it down after 5 minutes with no job.
  So each size switch (`make run`, then `make run SMALL=1`, then back) waits for a cold boot of the other size (about 125 of load, and the job takes about 4 times longer than on a warm Simulator, TASK-84).
  This cost is accepted, and it is not a bug.
  Why: on 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running for speed (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing").
  From 2026-09-27 (TASK-92) to 2026-09-28, the scripts kept the other size booted, so that a size switch did not wait for a cold boot.
  That kept a second Simulator running next to a job, for speed, so TASK-119 removed it.
  Never boot another Simulator by hand to check a screen size.
- **A Simulator that something else boots.** While a job or a `make run` holds the lock, the watcher (`ios/scripts/sim-lock.sh watch`) checks every 10 seconds that no other shared Simulator of its slot boots during the job.
  It shuts down a shared Simulator of the slot that the job does not use, also one that was already booted when the job took the lock (for example, left by a worktree with older scripts).
  So at most one shared Simulator of the slot is booted while a job runs (TASK-119).
  Why: on 2026-09-27 (TASK-67), the Simulator panel of the Claude app booted `RATP-Shared` again, while `make run SMALL=1` used `RATP-Shared-Small`.
  The panel boots the device that it showed last.
  So do not boot a shared Simulator from the panel or by hand: the watcher shuts it down while a job runs.
- **A watcher of old scripts.** Only one watcher runs.
  A job, a `make run`, and a `make simulator-shutdown` that frees the lock start it when none runs.
  When the watcher that runs has an older `watcher_version` (in `ios/scripts/sim-lock.sh`), or no version, they stop it and start the watcher of their own scripts.
  A watcher also stops when its worktree is removed.
  Why: on 2026-09-27 (TASK-78), a watcher of old scripts ran for hours, because a job held the lock almost all the time, so the fix of TASK-67 did not work.
  **When you change what the watcher does, raise `watcher_version` by 1.**
- `make simulator` prints the ID of the Simulator of your `make run`.
  Use it in your `xcrun simctl` commands; never type a Simulator name.

## The Simulator lock

`make run` and `make e2e` take a machine-wide lock: the folder `/tmp/ratp-sim.lock`.
While another job holds it, they wait and print `Waiting for the Simulator lock`, with the reason.
This is normal.
Do not stop them, and do not delete the lock.
The wait can be long, so run these commands in the background.

- `make e2e` frees the lock when the tests end, pass or fail.
- `make run` keeps the lock.
  You can then check the app by hand, or run `make e2e`.
  Free it with `make simulator-shutdown` as soon as your check is done (see "Hold the Simulator only while you use it").
- Any other command that boots or uses a Simulator (for example `xcodebuild test` or `xcrun simctl boot`) must run through the lock, on the shared Simulator:

  ```sh
  ios/scripts/sim-lock.sh job <command>
  ```

  To boot the shared Simulator and remove the app of the last job first, run `ios/scripts/sim-lock.sh job ios/scripts/simulator.sh reset <command>`.
  The lock gives its slot to the command (`RATP_SIM_SLOT`), and `ios/scripts/simulator.sh` uses it.
  With `xcodebuild`, put `ios/scripts/simulator.sh with-destination` before it, and add `-project ios/TROME.xcodeproj`: it adds the `-destination` of the Simulator of the job.
  Never name the Simulator (`name=RATP-Shared`), so the command still works when the second slot is on.

`make docs-screenshots` is a Simulator job too: it takes the lock, like `make e2e`, and frees it when the tests end.
So is `make live-activity-render` (the render check of the Live Activity views, see `.claude/rules/render-check.md`).

`make merge` takes the lock before the rebase and frees it after the fast-forward, success or failure (see `.claude/rules/merge.md`).
Before that, it takes a merge lock (`/tmp/ratp-merge.lock`, with `lockf`), so only one merge runs at a time, even with two Simulator slots.
A `ios/scripts/sim-lock.sh job` that starts inside a job that holds the lock runs at once, in that job's slot: so the `make e2e` of `make merge` does not wait for its own lock.
It does not free the lock when it ends: the outer job does.

`make check`, `make test` and `make test-scripts` need no Simulator and no lock.

The lock frees itself when its job dies, when its worktree is removed, or when the Simulator is shut down.

## Hold the Simulator only while you use it

Every job that uses the Simulator (`make run`, `make e2e`, `make docs-screenshots`, a job through `ios/scripts/sim-lock.sh job`) frees it as soon as its check is done, not a moment later.

- **Prepare first.** Read, plan and build before you take the Simulator.
  `make e2e` already builds before it takes the lock.
- **Free it right after the check.** `make e2e` and `make docs-screenshots` free the lock by themselves when the tests end.
  After `make run`, run `make simulator-shutdown` as soon as your check by hand is done, not at the end of your job.
- **Never hold it while you do something else.** Do not keep the lock while you think, fix code, write notes or wait for another job.
  To check again after a fix, run `make run` again: another job may use the Simulator in the meantime.

## When your job ends

Free the Simulator right after your last check, not later (see "Hold the Simulator only while you use it").
Before your job ends, run this again in your worktree, to be sure.
It removes your app from the Simulator and frees the lock (needed after `make run`, and harmless after `make e2e`):

```sh
make simulator-shutdown
```

After `make run`, it removes the app from the shared Simulator, so the app stops at once.
It does not shut down the Simulator: the Simulator shuts down by itself after 5 minutes with no job.

## Before you remove a worktree

Nothing to do: the worktree has no Simulator of its own.

## Old Simulators

Before the shared Simulator, each worktree had its own Simulator, named `RATP-<folder>-<hash>`.
To delete them, run this in any worktree:

```sh
make simulator-delete-old
```

It keeps the Simulators that are not shut down, because a worktree with the old scripts can still use them.
