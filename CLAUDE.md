# Rules for agents

Read the [README](README.md) first. It lists the `make` commands.

## Repo layout

Each part of the repo has its own folder: `ios/` (the iPhone app, with its config and scripts) and `docs/` (the docs site). Later: `server/` and `contracts/` (decision-6). The root holds only the files of the whole repo: `README.md`, `CLAUDE.md`, `Makefile`, `.gitignore`, `.nvmrc`.

- Run the `make` commands from the root. The root `Makefile` has no build logic: it runs each command in the `Makefile` of its part (`make e2e` runs `make -C ios e2e`). A new command goes in the `Makefile` of its part, and its name goes in the list of the root `Makefile`.
- A file goes in the folder of the part it serves: its scripts in `<part>/scripts/`, its config and its build output in its folder. Never add a file of one part at the root.
- The paths in this file are from the root.

## Code structure of the iOS app

decision-6 (section 10) explains these rules and their sources. Follow them in every task. The reviewer checks them: a file in the wrong place or a wrong dependency direction is a medium finding.

- **Two modules, one direction.** `ios/Packages/RATPCore` holds the rules, the state (`@Observable` models), the value types, the PRIM client, and the protocols of the system services. The app (`ios/App/`) and the widget (`ios/Widget/`) depend on `RATPCore`, never the reverse.
- **`RATPCore` stays free of the UI and of iOS.** No `import SwiftUI`, `UIKit`, `WidgetKit` or `MapKit`. It must build and pass its tests on the Mac (`make test`). An iOS-only framework is allowed only for a type that the app and the widget share (today: the `ActivityAttributes` conformance and `SnoozeLiveActivityIntent`, the intent of the Live Activity's buttons), inside `#if os(iOS)`.
- **Views hold no rules.** A view reads a model and calls it. A rule goes in `RATPCore`, with unit tests.
- **Protocols in the core, adapters in the app.** For an Apple system service (ActivityKit, Core Location, notifications), `RATPCore` declares a small protocol, and the app implements it in a file named after the framework (`ActivityKitStationLiveActivityClient`, `CoreLocationProvider`, `UserNotificationArrivalNotifier`). Unit tests use fakes. Foundation types that run on the Mac (`URLSession`, `UserDefaults`) may conform inside `RATPCore`.
- **One composition root.** `ios/App/RATPActivityApp.swift` makes the models and the adapters and gives them to the views. No singletons of our own, no global state.
- **Folders by feature, with the same names everywhere.** `ios/App/`, `ios/Packages/RATPCore/Sources/RATPCore/` and `ios/Packages/RATPCore/Tests/RATPCoreTests/` use the same feature folders: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`. The app also has `Permissions` and `TestingTools`. New code goes in the folder of its feature. A new feature gets a new folder in each module where it has code. No layer folders (`Views/`, `Models/`, `Services/`, `Helpers/`), and no loose files at the top of a module. The only exceptions: `RATPActivityApp.swift` and `ContentView.swift` (the main screen) at the top of `ios/App/`, `Resources/` in the package, and `Fixtures/` in its tests.
- **Testing tools are for debug builds only.** Each file in `ios/App/TestingTools/` is inside `#if DEBUG`.
- **The widget is a pure view.** `ios/Widget/` uses only `StationActivityAttributes` and its value types from `RATPCore`, and `SnoozeLiveActivityIntent` for its buttons (iOS runs the intent in the app, not in the widget). No model, no provider, no network.
- **Access control.** In `RATPCore`, only what the app or the widget uses is `public`. The rest stays `internal`. Tests use `@testable import RATPCore`.
- **Files.** A file holds one main type and has its name. Small types that exist only for it (its state, its error, the protocol of its dependency) may stay in the same file. An extension that adds a topic goes in `Type+Topic.swift`. Names say the role: `...View`, `...Section`, `...Screen`, `...Model`, `...Rules`, `...Store`, and the framework name first for an adapter.
- **Tests.** Unit tests: `ios/Packages/RATPCore/Tests/RATPCoreTests/<Feature>/<Type>Tests.swift`. E2E tests: `ios/UITests/`, one file per core flow. Tests of the Simulator scripts: `ios/scripts/tests/` (`make test-scripts`, with a fake `xcrun`). Docs screenshots: `ios/DocsScreenshots/`. Code that needs a unit test goes in `RATPCore`.
- **New module.** Add a target in `ios/Packages/` only when it solves a real problem (code that must not see the rest, code shared with a new target, build time). Deeper changes that these rules call for are `tech` tasks.

## Budget for this repo

- The factory runs **at most 3 Software Engineers** in parallel for this repo.
- **At most two Simulator jobs** run at the same time on the machine, each on its own Simulator. A job starts next to another one only when at least 25% of the CPU is idle. The Simulator lock enforces both (see below).

Why a limit: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work. So the limit was one Simulator job at a time.

Why two Simulator jobs: on 2026-09-27, a QA run that needed the Simulator for 8 minutes waited 30 minutes for the lock, while the CPU was often 50 to 80% idle. The prompter asked for a second Simulator job, if the Mac stays usable (2026-09-27). The CPU check protects the Mac: when the CPU is less than 25% idle, the second job waits, as it did with one job at a time. It is the same condition as the one for a new agent. TASK-63 records how long the jobs wait and run, so the factory can decide to keep two jobs or go back to one.

**How to go back to one Simulator job at a time:** in `ios/scripts/sim-lock.sh`, change `slots=${RATP_SIM_SLOTS:-2}` to `slots=${RATP_SIM_SLOTS:-1}`, and change this section, "The shared Simulators" and the README back to one job. Nothing else changes: slot 1 uses the same Simulators (`RATP-Shared`, `RATP-Shared-Small`) and the same lock (`/tmp/ratp-sim.lock`) as before the second slot. Then run `make simulator-delete` once, to delete the Simulators of slot 2. To try one job at a time for one command only, add `RATP_SIM_SLOTS=1` before it (for example `RATP_SIM_SLOTS=1 make e2e`). The CPU condition is in the same file (`min_idle_percent`, or `RATP_SIM_MIN_IDLE_PERCENT` for one command).

Why 3 Software Engineers: the cap was 2 after that day. Two checks now protect the Mac, so the prompter set it back to 3 (2026-09-26). The factory starts a new agent only when at least 25% of the CPU is idle. The Simulator lock keeps the Simulator jobs to at most two at a time, and the second one only when the CPU has room.

## The shared Simulators

All worktrees share two Simulator slots. Each slot has its own shared Simulator, an iPhone 17: `RATP-Shared` (slot 1) and `RATP-Shared-2` (slot 2). A job takes a free slot (slot 1 first), and uses only the Simulators of its slot.

- Each job installs its own build of the app. Before that, it removes the app and its data, resets the permissions, and clears the fake position of the Simulator. So a job never sees the data or the saved settings of another worktree. A job never touches the Simulators of the other slot, so two jobs at the same time never see the data of each other.
- The Simulator of a slot stays booted between jobs, so the next job does not wait for a cold boot.
- It shuts down by itself after 5 minutes with no job in its slot. Why 5 minutes: it is longer than the usual gap between two jobs (fix a test, then run `make e2e` again; the next agent starts its job). It is short enough to give the Mac back soon when the factory stops. With two slots, the delay stays the same for each slot: slot 2 has a job only when two jobs overlap, so it goes idle first and shuts down first. A small background process (`ios/scripts/sim-lock.sh watch`) does this for both slots. It uses no Simulator and almost no CPU, and it stops by itself.
- **The smallest iPhone.** To check a screen on the smallest supported iPhone (375 x 667 pt), run `make run SMALL=1`. It uses the small shared Simulator of its slot (an iPhone SE): `RATP-Shared-Small` (slot 1) or `RATP-Shared-Small-2` (slot 2), through the same lock. A job shuts down the other Simulator of its slot before it boots its own, so at most one Simulator runs in each slot: at most two on the Mac. `make simulator-shutdown` shuts down the small Simulator at once. Never boot another Simulator by hand to check a screen size.
- `make simulator` prints the ID of the Simulator of your `make run` (it can be in slot 2). Use it in your `xcrun simctl` commands; never type a Simulator name.

## The Simulator lock

`make run` and `make e2e` take a machine-wide lock of one slot: the folder `/tmp/ratp-sim.lock` (slot 1) or `/tmp/ratp-sim.lock.2` (slot 2). They wait and print `Waiting for the Simulator lock`, with the reason, when both slots are busy, or when one slot is busy and the CPU is less than 25% idle. This is normal. Do not stop them, and do not delete the lock. The wait can be long, so run these commands in the background.

- `make e2e` frees the lock when the tests end, pass or fail.
- `make run` keeps the lock. You can then check the app by hand, or run `make e2e`.
- Any other command that boots or uses a Simulator (for example `xcodebuild test` or `xcrun simctl boot`) must run through the lock, on the shared Simulator of its slot:

  ```sh
  ios/scripts/sim-lock.sh job <command>
  ```

  To boot the shared Simulator of the slot and remove the app of the last job first, run `ios/scripts/sim-lock.sh job ios/scripts/simulator.sh reset <command>`. The lock gives the slot to the command (`RATP_SIM_SLOT`), and `ios/scripts/simulator.sh` uses it. With `xcodebuild`, put `ios/scripts/simulator.sh with-destination` before it, and add `-project ios/RATPActivity.xcodeproj`: it adds the `-destination` of the Simulator of the slot. Never name the Simulator (`name=RATP-Shared`): the job can run in slot 2.

`make docs-screenshots` is a Simulator job too: it takes the lock, like `make e2e`, and frees it when the tests end.

`make check`, `make test` and `make test-scripts` need no Simulator and no lock.

The lock of a slot frees itself when its job dies, when its worktree is removed, or when its Simulator is shut down.

`make simulator-delete` takes the locks of both slots, so it waits until no other Simulator job runs.

## Which E2E tests to run

A full `make e2e` keeps a shared Simulator for several minutes. So:

- **The implementer and the reviewers** run only the E2E test classes that cover their change: `make e2e ONLY=FakePositionTests`, or `make e2e ONLY="FakePositionTests LiveActivityTests"` for more than one. The class names are the file names in `ios/UITests/`.
- **The Software Engineer who merges** runs the full `make e2e` once.
- **QA** runs no automated tests. It explores the app like a real user.

## Flaky tests

A flaky test (it fails, then passes with no change) is a bug. Rerun a failing test at most once, to know if it is flaky. Then fix the cause in your task if the test covers your code. Otherwise, create a `bug` task with the test name, how often it failed, and the error. Never fix it with retries or longer timeouts alone: find the cause (a race, a shared state, a missing wait for a condition).

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

## The shared build cache

All worktrees share the compiled modules of the iOS SDK, in `~/Library/Caches/RATPActivity/` (the README explains it). It holds no code of the app, so two tasks never mix their build products.

- `make clean` does not touch it. Only the prompter runs `make clean-shared-cache`. It waits for the running builds, and new builds wait for it (they print `Waiting: the shared build cache ... is being cleared`). Never delete the folder by hand: a build that runs at that moment fails.
- `make build LIVE=1` does not use it, so it never holds a build with the real key. `make live-key-check` checks it.

## The docs site (`docs/`)

The README explains the docs site and its commands (section "The docs site").

- **Keep the docs true.** A task that changes a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images. A docs text change alone needs no new screenshots. The reviewer checks it.
- **Node 24.** Each Bash call starts a new shell with the old default Node. Run the docs commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make docs-check`. The same goes for `make check` when your task changes `docs/`.
- **Install `docs/node_modules` only when your task touches the docs.** It takes about 300 MB. `make check` runs `make docs-check` only when your branch changes `docs/`, so the other tasks never install it.
- **Use your own port.** The default port 4321 is for the prompter. Run `make docs PORT=<n>` or `make docs-dev PORT=<n>` with a port that no other agent uses (for example 4300 plus your task number).
- **Stop the docs server when your job ends.** For agents, Astro starts the server in the background and the command returns at once. Run `make docs-stop` in your worktree before you end.
- **Screenshots.** Show each app screenshot with the `Screenshot` component (`docs/src/components/Screenshot.astro`), never with a Markdown image or the `Image` component. Put screenshots side by side inside `Screenshots`. Take each screenshot full screen on a shared iPhone 17 Simulator (`make docs-screenshots` does), so all have the same size. Each file in git stays under the budget of the README (section "The docs site"). The script checks the size and the budget.

## Live train data (the real PRIM key)

The real PRIM key is in the main repo folder only, in `ios/Config/Secrets.xcconfig` (or at its old place, `Config/Secrets.xcconfig`, until the prompter moves it). Worktrees do not have it.

- **Never read, print, copy or commit the key.** Do not open `ios/Config/Secrets.xcconfig` or `Config/Secrets.xcconfig`. Do not copy it into a worktree.
- `make build`, `make run`, `make check` and `make e2e` never use the key. They build with `ios/Config/NoKey.xcconfig`, so the app says "Train data key: not set". Unit tests use recorded PRIM answers (fixtures).
- `make run LIVE=1` builds the app with the key of the main repo folder (found with git) and opens it in the Simulator. The build output does not show the key. But the key is inside the built app, in `ios/.build/` (ignored by git), and inside the app installed in the Simulator. **Never inspect them.** `LIVE=1` works only with `make build` and `make run`.
- After a live check, remove the key from the Simulator and from `ios/.build/`: run `make simulator-shutdown` (it removes the app from the shared Simulator, so the app stops calling PRIM), then `make build` (without `LIVE=1`, so the built app has no key). The next Simulator job also removes the app before it installs its own build, so a live build never reaches another worktree's job.
- `make check` runs `make live-key-check`. It builds with `LIVE=1` and a fake key, and fails if a build log shows the key. If you change the build (the `Makefile` files, `ios/Config/`, `ios/project.yml`, `ios/scripts/`), this check must still pass.

### Who uses live data, and when

- **Only QA** uses `make run LIVE=1`. Software Engineers and the quality gate never do.
- QA uses it **only when the task touches train data**: the PRIM calls, the stop ids, the next trains screen, or the train data in the Live Activity.
- **Budget: at most 60 PRIM calls per QA run.** Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop of the station when it opens the next trains, then again every 30 seconds while the app screen is open. Calls = stops × (1 + seconds on screen / 30). Today Châtelet has 10 stops: 20 calls per minute. A station with one line has 1 or 2 stops: 2 to 4 calls per minute. TASK-23 (fewer calls per station) will lower these numbers.

To stay in the budget:

- Pick a station with few lines, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once. The app keeps calling PRIM while it runs, and the shared Simulator stays booted after your job. `make simulator-shutdown` removes the app, so the calls stop. Then remove the key from `ios/.build/` (see above).
- At Châtelet, stay at most 2 minutes on the next trains (50 calls).

Why 60: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day. But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day). We do not know the quota of the prompter's key, so we plan for 1,000 calls per day. 60 calls is 6% of it. After 5 QA runs, the prompter still has more than two thirds of the day's calls. When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager.
