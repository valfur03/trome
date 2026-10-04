---
paths:
  - "ios/Config/**"
  - "ios/scripts/live-key-check.sh"
  - "ios/scripts/tests/live-key-check-test.sh"
commands:
  - '^(\S*/)?make\b.*\sLIVE=1(\s|$)'
agents:
  - 'qa'
---
# Live train data (the real PRIM key)

These rules are for QA when it uses live train data, for the manager who gives QA its budget of PRIM calls, and for a change to the build of the key.
The rule on the key itself (never read, print, copy or commit it, and where it is) is in `CLAUDE.md`.

- `make build`, `make run`, `make check` and `make e2e` never use the key.
  They build with `ios/Config/NoKey.xcconfig`, so the app says "Train data key: not set".
  Unit tests use recorded PRIM answers (fixtures).
- `make run LIVE=1` builds the app with the key of the main repo folder (found with git) and opens it in the Simulator.
  The build output does not show the key.
  But the key is inside the built app, in `ios/.build/` (ignored by git), and inside the app installed in the Simulator.
  **Never inspect them.** `LIVE=1` works only with `make build` and `make run`.
- After a live check, remove the key from the Simulator and from `ios/.build/`: run `make simulator-shutdown` (it removes the app from the shared Simulator, so the app stops calling PRIM), then `make build` (without `LIVE=1`, so the built app has no key).
  The next Simulator job also removes the app before it installs its own build, so a live build never reaches another worktree's job.
- `make check` runs `make live-key-check`.
  It builds with `LIVE=1` and a fake key, and fails if a build log shows the key.
  If you change the build (the `Makefile` files, `ios/Config/`, `ios/project.yml`, `ios/scripts/`), this check must still pass.

## Who uses live data, and when

- **Only QA** uses `make run LIVE=1`.
  Software Engineers and the quality gate never do.
- QA uses it **only when the task touches train data**: the PRIM calls, the stop ids, the next trains screen, or the train data in the Live Activity.
- **Budget of a QA run.** Until the first external build (G5 in doc-5, "The release plan": friends can install a TestFlight build), at most 60 PRIM calls per QA run.
  From G5 on, at most 30 PRIM calls per QA run, at most 2 live QA runs in one PRIM day (00:00 to 24:00 UTC), and no live QA run on the day the first external group is invited.
  The manager knows whether G5 has passed, counts the live QA runs of the day, and gives QA its budget (60, 30 or none) when it starts a QA run that needs `LIVE=1`.
  When QA has no budget from the manager, it uses 30.
  A task that needs more asks the manager, who asks the prompter for that day.
  Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop area of the station when it opens the next trains, then again every 30 seconds while the app screen is open.
Calls = stop areas × (1 + seconds on screen / 30).
All the metro lines of a station share one stop area, and an RER stop is one stop area.
The stop areas of a station include the stop areas of the other stations of its place (its hub, see `ios/guide/stations.md`).
Today Châtelet has 2 stop areas (the metro stop area of Châtelet, and the RER stop of Châtelet - Les Halles): 4 calls per minute.
Saint-Lazare has 5: 10 calls per minute.
A metro station with no hub has 1 stop area: 2 calls per minute.

To stay in the budget:

- Pick a station with few lines and no hub, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once.
  The app keeps calling PRIM while it runs, and the shared Simulator stays booted after your job.
  `make simulator-shutdown` removes the app, so the calls stop.
  Then remove the key from `ios/.build/` (see above).
- At Châtelet, stay at most 2 minutes on the next trains (10 calls).

Why 60, then 30: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day.
But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day).
We do not know the quota of the prompter's key, so we plan for 1,000 calls per day.
One key serves the production server, the staging server and every Debug build that holds it, QA's `make run LIVE=1` included.
Their shares are in one table, "The day of the PRIM key" in `server/guide/how-it-works.md` (decision-59): read the numbers there, and do not copy them here.
The Debug builds and QA share one row of it, with the prompter's own tests and iPhone trial, and the server does not count them.
Before G5, production spends nothing, so a QA run may use 60 calls.
From G5 on, production spends up to its full share once riders use it, so 5 QA runs a day no longer leave the prompter most of the day: a QA run gets 30 calls, and 2 runs a day at most.

When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager.
The manager tells the prompter that the production server may have paused its PRIM calls for an hour: every rider then reads "Times unavailable for now".
