# Rules for agents

Read the [README](README.md) first. It lists the `make` commands.

## Budget for this repo

- The factory runs **at most 2 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine. A lock enforces it (see below).

Why: each worktree builds the app and boots its own iOS Simulator. On 2026-09-26, seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work.

## The Simulator lock

Each worktree uses its own Simulator. Its name starts with `RATP-`.

`make run` and `make e2e` take a machine-wide lock: the folder `/tmp/ratp-sim.lock`. While another job holds it, they wait and print `Waiting for the Simulator lock`. This is normal. Do not stop them, and do not delete the lock.

- `make e2e` shuts down the Simulator when the tests end, pass or fail. Then it frees the lock.
- `make run` keeps the Simulator open, and keeps the lock. You can then check the app by hand, or run `make e2e`.
- Any other command that boots or uses a Simulator (for example `xcodebuild test` or `xcrun simctl boot`) must run through the lock:

  ```sh
  ./scripts/sim-lock.sh job <command>
  ```

`make check` and `make test` need no Simulator and no lock.

The lock frees itself when its job dies, when its worktree is removed, or when its Simulator is shut down.

## When your job ends

In your worktree, shut down its Simulator. This also frees the lock:

```sh
make simulator-shutdown
```

## Before you remove a worktree

In the worktree, delete its Simulator:

```sh
make simulator-delete
```
