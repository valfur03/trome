---
paths:
  - "ios/scripts/**"
  - "ios/Makefile"
  - "Makefile"
---
# The build tooling: the shared build cache, the build gate and the git hooks

These rules are for a change to the scripts or the `Makefile` files of the app.

## The shared build cache

All worktrees share the compiled modules of the iOS SDK, in `~/Library/Caches/TROME/`.
It holds no code of the app, so two tasks never mix their build products.

- `make clean` does not touch it.
  Only the prompter runs `make clean-shared-cache` (a rule of `CLAUDE.md`, with "never delete the folder by hand").
  It waits for the running builds, and new builds wait for it (they print `Waiting: the shared build cache ... is being cleared`).
- `make build LIVE=1` does not use it, so it never holds a build with the real key.
  `make live-key-check` checks it.

## The build gate

`ios/scripts/build-gate.py` keeps the Mac quiet while a Simulator test run runs: many builds run at once, a test run runs alone.
A test run waits for the builds of every worktree to end, and new builds wait for it.
Why: on 2026-10-08 (TASK-324, TASK-330), the `swift test` of another worktree's `make check` ran next to the full E2E suite (Mac load 80 to 92 on 8 cores).
iOS then took 33 s instead of 2 s to start the process that runs the intent of a Live Activity button, so its own watchdog gave up on the tap at 30 s, and `SnoozeTests` failed.
No wait in a test can fix that: iOS itself drops the tap.

- A new heavy command (a compile, a test build, the unit tests, a script that runs `swift <file>`) runs through `$(BUILD_GATE)`, outside `$(QUIET)`, so its wait message shows.
  `$(XCODEBUILD)` already holds it, for a build that a script runs.
- A new Simulator test run puts `$(TEST_RUN_GATE)` right after `$(SIM_LOCK) job`.
  A command inside a held gate runs at once, so the build steps of a test run never wait for themselves.
- A test run waits at most 20 minutes for the builds, and a build at most 30 minutes for a test run; then each runs anyway and says so.
  Why: a hung `swift test` or a hung test run must not freeze every build and every Simulator job of every worktree.
- `make run` takes no gate: a QA session holds the Simulator for many minutes, and the builds of the other worktrees must go on.
- A script test that runs `swift`, `swiftc` or `xcodebuild` (or one of them through `xcrun`) runs itself through the gate (its first lines, as in `store-screenshots-test.sh`).
  `make test-scripts` puts `ios/scripts/tests/gate-guard/` first on `PATH`, so such a call outside the gate fails the test (TASK-438); a call by an absolute path skips `PATH`, so `build-gate-test.sh` refuses one in `ios/scripts/`.
- `ios/scripts/tests/build-gate-test.sh` checks the gate and this wiring of `ios/Makefile`.

## The git hooks

`ios/scripts/git-hooks/` creates the Xcode project again after a `git pull`, a checkout, a merge or a rebase in the main folder (`ios/README.md`, section "Keep the Xcode project up to date").
The prompter turns them on with `make git-hooks`.

- **Never run `make git-hooks` or `make git-hooks-off`** (a rule of `CLAUDE.md`, with its reason).
  In a test, use a repo of your own (as `ios/scripts/tests/git-hooks-test.sh` does).
- The hooks do nothing in a worktree of an agent.
  The `make` commands create the project there.
- A hook must never leave the main folder dirty, and must never make a git command fail.
  `make test-scripts` checks both.
