---
paths:
  - "ios/scripts/**"
  - "ios/Makefile"
  - "Makefile"
---
# The build tooling: the shared build cache and the git hooks

These rules are for a change to the scripts or the `Makefile` files of the app.

## The shared build cache

All worktrees share the compiled modules of the iOS SDK, in `~/Library/Caches/RATPActivity/`.
It holds no code of the app, so two tasks never mix their build products.

- `make clean` does not touch it.
  Only the prompter runs `make clean-shared-cache` (a rule of `CLAUDE.md`, with "never delete the folder by hand").
  It waits for the running builds, and new builds wait for it (they print `Waiting: the shared build cache ... is being cleared`).
- `make build LIVE=1` does not use it, so it never holds a build with the real key.
  `make live-key-check` checks it.

## The git hooks

`ios/scripts/git-hooks/` creates the Xcode project again after a `git pull`, a checkout, a merge or a rebase in the main folder (`ios/README.md`, section "Keep the Xcode project up to date").
The prompter turns them on with `make git-hooks`.

- **Never run `make git-hooks` or `make git-hooks-off`** (a rule of `CLAUDE.md`, with its reason).
  In a test, use a repo of your own (as `ios/scripts/tests/git-hooks-test.sh` does).
- The hooks do nothing in a worktree of an agent.
  The `make` commands create the project there.
- A hook must never leave the main folder dirty, and must never make a git command fail.
  `make test-scripts` checks both.
