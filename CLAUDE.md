# Rules for agents

Read the [README](README.md) first. It lists the `make` commands.

## Budget for this repo

- The factory runs **at most 2 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine. A lock enforces it (see below).

Why: each worktree builds the app and boots its own iOS Simulator. On 2026-09-26, seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work.

## The Simulator lock

Each worktree uses its own Simulator. Its name starts with `RATP-`.

`make run` and `make e2e` take a machine-wide lock: the folder `/tmp/ratp-sim.lock`. While another job holds it, they wait and print `Waiting for the Simulator lock`. This is normal. Do not stop them, and do not delete the lock. The wait can be long, so run these commands in the background.

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

## Live train data (the real PRIM key)

The real PRIM key is in the main repo folder only, in `Config/Secrets.xcconfig`. Worktrees do not have it.

- **Never read, print, copy or commit the key.** Do not open `Config/Secrets.xcconfig`. Do not copy it into a worktree.
- `make build`, `make run`, `make check` and `make e2e` never use the key. They build with `Config/NoKey.xcconfig`, so the app says "Train data key: not set". Unit tests use recorded PRIM answers (fixtures).
- `make run LIVE=1` builds the app with the key of the main repo folder (found with git) and opens it in the Simulator. The build output does not show the key. But the key is inside the built app, in `.build/` (ignored by git), and inside the app installed in the Simulator. **Never inspect them.** `LIVE=1` works only with `make build` and `make run`.
- After a live check, remove the key from `.build/` and from the Simulator: run `make run` (without `LIVE=1`, so the app has no key and makes no PRIM call), then `make simulator-shutdown`.
- `make check` runs `make live-key-check`. It builds with `LIVE=1` and a fake key, and fails if a build log shows the key. If you change the build (Makefile, `Config/`, `project.yml`, build scripts), this check must still pass.

### Who uses live data, and when

- **Only QA** uses `make run LIVE=1`. Software Engineers and the quality gate never do.
- QA uses it **only when the task touches train data**: the PRIM calls, the stop ids, the next trains screen, or the train data in the Live Activity.
- **Budget: at most 60 PRIM calls per QA run.** Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop of the station when it opens the next trains, then again every 30 seconds while the app screen is open. Calls = stops × (1 + seconds on screen / 30). Today Châtelet has 10 stops: 20 calls per minute. A station with one line has 1 or 2 stops: 2 to 4 calls per minute. TASK-23 (fewer calls per station) will lower these numbers.

To stay in the budget:

- Pick a station with few lines, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once. The app keeps calling PRIM while its screen is open. Then remove the key (see above).
- At Châtelet, stay at most 2 minutes on the next trains (50 calls).

Why 60: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day. But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day). We do not know the quota of the prompter's key, so we plan for 1,000 calls per day. 60 calls is 6% of it. After 5 QA runs, the prompter still has more than two thirds of the day's calls. When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager.
