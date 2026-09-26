# Rules for agents

Read the [README](README.md) first. It lists the `make` commands.

## Budget for this repo

- The factory runs **at most 2 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine. A lock enforces it (see below).

Why: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work.

## The shared Simulator

All worktrees use one shared Simulator, named `RATP-Shared`.

- Each job installs its own build of the app. Before that, it removes the app and its data, resets the permissions, and clears the fake position of the Simulator. So a job never sees the data or the saved settings of another worktree.
- The Simulator stays booted between jobs, so the next job does not wait for a cold boot.
- It shuts down by itself after 5 minutes with no job. Why 5 minutes: it is longer than the usual gap between two jobs (fix a test, then run `make e2e` again; the next agent starts its job). It is short enough to give the Mac back soon when the factory stops. A small background process (`scripts/sim-lock.sh watch`) does this. It uses no Simulator and almost no CPU, and it stops by itself.

## The Simulator lock

`make run` and `make e2e` take a machine-wide lock: the folder `/tmp/ratp-sim.lock`. While another job holds it, they wait and print `Waiting for the Simulator lock`. This is normal. Do not stop them, and do not delete the lock. The wait can be long, so run these commands in the background.

- `make e2e` frees the lock when the tests end, pass or fail.
- `make run` keeps the lock. You can then check the app by hand, or run `make e2e`.
- Any other command that boots or uses a Simulator (for example `xcodebuild test` or `xcrun simctl boot`) must run through the lock, on the shared Simulator:

  ```sh
  ./scripts/sim-lock.sh job <command>
  ```

  To boot the shared Simulator and remove the app of the last job first, run `./scripts/sim-lock.sh job ./scripts/simulator.sh reset <command>`. With `xcodebuild`, use `-destination "platform=iOS Simulator,name=RATP-Shared"`.

`make docs-screenshots` is a Simulator job too: it takes the lock, like `make e2e`, and frees it when the tests end.

`make check` and `make test` need no Simulator and no lock.

The lock frees itself when its job dies, when its worktree is removed, or when the Simulator is shut down.

## When your job ends

In your worktree, remove your app from the Simulator and free the lock (needed after `make run`, and harmless after `make e2e`):

```sh
make simulator-shutdown
```

After `make run`, it removes the app from the shared Simulator, so the app stops at once. It does not shut down the Simulator: the Simulator shuts down by itself after 5 minutes with no job.

## Before you remove a worktree

Nothing to do: the worktree has no Simulator of its own.

## Old Simulators

Before the shared Simulator, each worktree had its own Simulator, named `RATP-<folder>-<hash>`. To delete them, run this in any worktree:

```sh
make simulator-delete-old
```

It keeps the Simulators that are not shut down, because a worktree with the old scripts can still use them.

## The docs site (`docs/`)

The README explains the docs site and its commands (section "The docs site").

- **Keep the docs true.** A task that changes a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. For a changed screen, run `make docs-screenshots` and commit the new images. The reviewer checks it.
- **Node 24.** Each Bash call starts a new shell with the old default Node. Run the docs commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make docs-check`. The same goes for `make check` when your task changes `docs/`.
- **Install `docs/node_modules` only when your task touches the docs.** It takes about 300 MB. `make check` runs `make docs-check` only when your branch changes `docs/`, so the other tasks never install it.
- **Use your own port.** The default port 4321 is for the prompter. Run `make docs PORT=<n>` or `make docs-dev PORT=<n>` with a port that no other agent uses (for example 4300 plus your task number).
- **Stop the docs server when your job ends.** For agents, Astro starts the server in the background and the command returns at once. Run `make docs-stop` in your worktree before you end.
- `make docs-screenshots` is a Simulator job: one job at a time (the lock), then `make simulator-shutdown`.

## Live train data (the real PRIM key)

The real PRIM key is in the main repo folder only, in `Config/Secrets.xcconfig`. Worktrees do not have it.

- **Never read, print, copy or commit the key.** Do not open `Config/Secrets.xcconfig`. Do not copy it into a worktree.
- `make build`, `make run`, `make check` and `make e2e` never use the key. They build with `Config/NoKey.xcconfig`, so the app says "Train data key: not set". Unit tests use recorded PRIM answers (fixtures).
- `make run LIVE=1` builds the app with the key of the main repo folder (found with git) and opens it in the Simulator. The build output does not show the key. But the key is inside the built app, in `.build/` (ignored by git), and inside the app installed in the Simulator. **Never inspect them.** `LIVE=1` works only with `make build` and `make run`.
- After a live check, remove the key from the Simulator and from `.build/`: run `make simulator-shutdown` (it removes the app from the shared Simulator, so the app stops calling PRIM), then `make build` (without `LIVE=1`, so the built app has no key). The next Simulator job also removes the app before it installs its own build, so a live build never reaches another worktree's job.
- `make check` runs `make live-key-check`. It builds with `LIVE=1` and a fake key, and fails if a build log shows the key. If you change the build (Makefile, `Config/`, `project.yml`, build scripts), this check must still pass.

### Who uses live data, and when

- **Only QA** uses `make run LIVE=1`. Software Engineers and the quality gate never do.
- QA uses it **only when the task touches train data**: the PRIM calls, the stop ids, the next trains screen, or the train data in the Live Activity.
- **Budget: at most 60 PRIM calls per QA run.** Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop of the station when it opens the next trains, then again every 30 seconds while the app screen is open. Calls = stops × (1 + seconds on screen / 30). Today Châtelet has 10 stops: 20 calls per minute. A station with one line has 1 or 2 stops: 2 to 4 calls per minute. TASK-23 (fewer calls per station) will lower these numbers.

To stay in the budget:

- Pick a station with few lines, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once. The app keeps calling PRIM while it runs, and the shared Simulator stays booted after your job. `make simulator-shutdown` removes the app, so the calls stop. Then remove the key from `.build/` (see above).
- At Châtelet, stay at most 2 minutes on the next trains (50 calls).

Why 60: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day. But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day). We do not know the quota of the prompter's key, so we plan for 1,000 calls per day. 60 calls is 6% of it. After 5 QA runs, the prompter still has more than two thirds of the day's calls. When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager.
