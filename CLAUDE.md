# Rules for agents

Read the [README of the app](ios/README.md) first. It names the everyday `make` commands, and `make help` lists them all. The front page, `README.md`, is for a stranger who lands on the repo: it holds no rule and no command.

## Repo layout

Each part of the repo has its own folder: `ios/` (the iPhone app, with its config and scripts), `docs/` (the docs site), `server/` (the server, a Cloudflare Worker, decision-40) and `contracts/` (the files that the app and the server both test against, decision-6 section 3). The root holds only the files of the whole repo: `README.md`, `CLAUDE.md`, `Makefile`, `.gitignore`, `.nvmrc`.

- Run the `make` commands from the root. The root `Makefile` has no build logic: it runs each command in the `Makefile` of its part (`make e2e` runs `make -C ios e2e`). A new command goes in the `Makefile` of its part, and its name goes in the list of the root `Makefile`.
- A file goes in the folder of the part it serves: its scripts in `<part>/scripts/`, its config and its build output in its folder. Never add a file of one part at the root.
- The paths in this file are from the root.

## Code structure of the iOS app

decision-6 (section 10) explains these rules and their sources. Follow them in every task. The reviewer checks them: a file in the wrong place or a wrong dependency direction is a medium finding.

- **Two modules, one direction.** `ios/Packages/TROMECore` holds the rules, the state (`@Observable` models), the value types, the PRIM client, and the protocols of the system services. The app (`ios/App/`) and the widget (`ios/Widget/`) depend on `TROMECore`, never the reverse.
- **`TROMECore` stays free of the UI and of iOS.** No `import SwiftUI`, `UIKit`, `WidgetKit` or `MapKit`. It must build and pass its tests on the Mac (`make test`). An iOS-only framework is allowed only for a type that the app and the widget share (today: the `ActivityAttributes` conformance and `SnoozeLiveActivityIntent`, the intent of the Live Activity's buttons), inside `#if os(iOS)`.
- **Views hold no rules.** A view reads a model and calls it. A rule goes in `TROMECore`, with unit tests.
- **Protocols in the core, adapters in the app.** For an Apple system service (ActivityKit, Core Location, notifications), `TROMECore` declares a small protocol, and the app implements it in a file named after the framework (`ActivityKitStationLiveActivityClient`, `CoreLocationProvider`, `UserNotificationArrivalNotifier`). Unit tests use fakes. Foundation types that run on the Mac (`URLSession`, `UserDefaults`) may conform inside `TROMECore`.
- **One composition root.** `ios/App/TROMEApp.swift` makes the models and the adapters and gives them to the views. No singletons of our own, no global state.
- **Folders by feature, with the same names everywhere.** `ios/App/`, `ios/Packages/TROMECore/Sources/TROMECore/` and `ios/Packages/TROMECore/Tests/TROMECoreTests/` use the same feature folders: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`. The app also has `AppName`, `Permissions` and `TestingTools`, and the package has `Logging` (the one name of the log, `Logger.subsystem`). New code goes in the folder of its feature. A new feature gets a new folder in each module where it has code. No layer folders (`Views/`, `Models/`, `Services/`, `Helpers/`), and no loose files at the top of a module. The only exceptions: `TROMEApp.swift` and `ContentView.swift` (the main screen) at the top of `ios/App/`, the String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) at the top of `ios/App/` and `ios/Widget/`, and `Resources/` in the package.
- **Testing tools are for debug builds only.** Each file in `ios/App/TestingTools/` is inside `#if DEBUG`.
- **The widget is a pure view.** `ios/Widget/` uses only `StationActivityAttributes` and its value types from `TROMECore`, and `SnoozeLiveActivityIntent` for its buttons (iOS runs the intent in the app, not in the widget). No model, no provider, no network.
- **Texts in French and English.** Each text that a user sees is written in English in the code, and has its French text in the String Catalog of its target, in the same task (`ios/README.md`, section "Languages"). `make check` fails on a text with no French text (`make strings-check`). Use a text that SwiftUI translates (`Text("...")`, a `LocalizedStringKey`) or `String(localized:)`, never a plain `String` given to `Text`. The texts of `ios/App/TestingTools/` stay in English: they are inside `#if DEBUG`, so Xcode keeps them out of the catalog. The catalogs in git must be the ones that Xcode writes, so that a build in Xcode in the main folder changes no file: after you change a text, run `make strings-sync`, then add the French texts and commit the catalogs (`make strings-check` fails when a build in Xcode would change a catalog). The texts of `TROMECore` (for example `TransitLine.displayName`) are not translated: the app and the widget make the texts that a user sees. The name of the app is written once, `APP_NAME` in `ios/Config/Base.xcconfig` (decision-43): never write it in a text of the app or the widget. A view reads it with `@Environment(\.appName)` and puts it in its text as an argument (`%@` in the catalog); a permission text of `ios/project.yml` uses `$(APP_NAME)`, and `make strings-sync` puts it in their French texts.
- **Access control.** In `TROMECore`, only what the app or the widget uses is `public`. The rest stays `internal`. Tests use `@testable import TROMECore`.
- **Files.** A file holds one main type and has its name. Small types that exist only for it (its state, its error, the protocol of its dependency) may stay in the same file. An extension that adds a topic goes in `Type+Topic.swift`. Names say the role: `...View`, `...Section`, `...Screen`, `...Model`, `...Rules`, `...Store`, and the framework name first for an adapter.
- **Tests.** Unit tests: `ios/Packages/TROMECore/Tests/TROMECoreTests/<Feature>/<Type>Tests.swift`. The recorded PRIM answers are in `contracts/prim/`, shared with the server tests (`Fixture.data(_:)` reads them). E2E tests: `ios/UITests/`, one file per seam with iOS (see "Test levels"). Tests of the scripts: `ios/scripts/tests/<name>-test.sh` (`make test-scripts`, with a fake `xcrun` for the Simulator scripts). Docs screenshots: `ios/DocsScreenshots/`. The render check of the Live Activity views: `ios/RenderCheck/`. Code that needs a unit test goes in `TROMECore`.
- **No warnings.** `make check` fails on any build warning and when a newer Xcode may recommend new project settings (`ios/README.md`, section "Before you commit"; `make recommended-settings-check` prints the steps for new settings). Fix the cause. Never silence a warning, and never raise `options.xcodeVersion` in `ios/project.yml` without adding the settings that Xcode proposes. An agent cannot open that Xcode dialog: when `make recommended-settings-check` fails, ask the prompter (label `needs-prompter`).
- **New module.** Add a target in `ios/Packages/` only when it solves a real problem (code that must not see the rest, code shared with a new target, build time). Deeper changes that these rules call for are `tech` tasks.

## Budget for this repo

- The factory runs **at most 3 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine. A lock enforces it (see below).
- **Never a second Simulator on this Mac.** On 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running on this Mac, for any reason: a faster job, a Simulator for QA, a Simulator for `make run`, or the second job slot (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing"). Why: the boot of a second Simulator next to a booted one, even with no job running, already takes the Mac to an unsafe load (234 to 333, TASK-106, see below). A boot with no other Simulator booted measured lower (about 125 to 157, TASK-84 and the QA of TASK-92). This is a closed decision, not a trial on pause. Only the prompter, in person, can open it again, and only with a new reason (for example, a different Mac). Never propose, build or measure a new design with a second Simulator. This also covers the two iPhone sizes: every job and every `make run`, `make run SMALL=1` included, uses one shared Simulator at a time (TASK-119, see "The shared Simulator").

Why one Simulator job: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work.

Why not two Simulator jobs: TASK-62 added a second Simulator slot, for a second job next to the first one, only when at least 25% of the CPU is idle. It was measured on 2026-09-27 on the real Simulators. The CPU check works at the start. But once the second Simulator runs, the CPU is 0% idle for the whole job. The 1-minute load average went from 44 to 257 in one run, and from 22 to 286 in another (8-core Mac). The job in slot 2 took 2 to 3.5 minutes instead of about 46 seconds alone: about 3 times slower. So the gain is not clear, and the risk is the one of 2026-09-26. The prompter kept the code of the second slot, but off (2026-09-27). On 2026-09-28, after TASK-106 (below), the prompter decided against the second slot on this Mac: it stays off. TASK-63 records how long the jobs wait and run. Its numbers are not a reason to try two jobs again on this Mac.

**The code of the second slot (decided against on this Mac):** `ios/scripts/sim-lock.sh` keeps the code of a second slot, but off (`slots=${RATP_SIM_SLOTS:-1}`). It is not a trial that an agent or a task can run. Never change this line, and never add `RATP_SIM_SLOTS=2` to a command. Only the prompter, in person, can decide to turn it on again, and only with a new reason (for example, a different Mac). For that case only, this is how the code works. With `slots=${RATP_SIM_SLOTS:-2}`, a job takes a free slot (slot 1 first). It runs next to another job only when at least 25% of the CPU is idle (`min_idle_percent` in the same file, or `RATP_SIM_MIN_IDLE_PERCENT` for one command). Slot 2 uses its own Simulators (`RATP-Shared-2`, `RATP-Shared-Small-2`) and its own lock (`/tmp/ratp-sim.lock.2`), so two jobs never see the data of each other. A change to two slots must also change this section, "The shared Simulator" and `ios/README.md`. To go back to one job, change the line back, then run `make simulator-delete` once, to delete the Simulators of slot 2.

Why QA has no Simulator of its own: a QA session keeps the lock while QA explores the app (12 to 19 minutes each on 2026-09-27), and the other jobs wait for it. TASK-84 measured a QA Simulator next to the shared one before it built anything (2026-09-27, 8-core Mac, 16 GB). The Mac was quiet before (load 5, CPU 66 to 74% idle). A full `make e2e` ran on `RATP-Shared`, and a QA session booted `RATP-Shared-QA` 20 seconds after the job took the lock, then opened the app. The 1-minute load average went from 13 to 106 during the boot, then to 326 about 15 seconds after the app opened. The CPU was 0% idle for about 90 seconds. The load logger, which writes a line every 5 seconds, wrote nothing twice for about 30 seconds: the Mac did not answer. A safety check then shut down the QA Simulator. The tests passed, but they took 221 seconds instead of 133 to 152 seconds alone. This is above the level of the second slot trial (257 to 286), for which the prompter kept the second slot off. So the QA Simulator was not shipped: QA uses the shared Simulator and its lock, like every job. Limits of the measurement: one run, only the cold case (the QA Simulator boots during the job), and no CPU per process. The warm case (the QA Simulator booted before the job) was not run, so as not to freeze the Mac again. The script of the measurement is `ios/scripts/timing/qa-load-check.sh`. It boots a second Simulator outside the lock, so it never runs on this Mac (see "Never a second Simulator on this Mac"). It stays only to measure on another Mac, when the prompter asks for it. It deletes `RATP-Shared-QA` when it ends.

Why no second Simulator at all: TASK-106 tried a Simulator of its own for `make run`, apart from the Simulator of the jobs, and measured it on 2026-09-28 (8-core Mac, 16 GB). Its boot never ran next to a job: `RATP-Shared` was booted and idle, and no job ran. The first boot of the new Simulator took the 1-minute load average to 333, and the Mac did not answer for about 64 seconds. Two minutes later, a normal `make run SMALL=1` took the load to 234. It was a cold boot of the existing `RATP-Shared-Small` next to the booted `RATP-Shared`, with no job (the scripts of TASK-92 kept the other size booted then), so it was not a boot alone. During the first boot, the Mac used 5.5 to 5.7 GB of swap (6.4 of its 7 GB on the day of the decision, doc-3). A boot with no other Simulator booted measured lower: about 125 (TASK-84) to 157 (the QA of TASK-92). So the boot of a second Simulator next to a booted one, even with no job (234 to 333), reaches the levels of TASK-62 (257 to 286, two jobs at once) and TASK-84 (326, a QA Simulator next to a job), and it is close to the freeze of 2026-09-26. For this reason, the prompter decided against every design with a second Simulator on this Mac, and TASK-106 was closed.

Why 3 Software Engineers: the cap was 2 after that day. Two checks now protect the Mac, so the prompter set it back to 3 (2026-09-26). The factory starts a new agent only when at least 25% of the CPU is idle. The Simulator lock and the shared Simulator keep the Simulator jobs to one at a time.

## The shared Simulator

All worktrees use one shared Simulator, named `RATP-Shared`.

- Each job installs its own build of the app. Before that, it removes the app and its data (and the host app of the render check), resets the permissions, sets the text size and the appearance back to the iOS default (Large text, Light), and clears the fake position of the Simulator. So a job never sees the data or the saved settings of another worktree.
- The Simulator stays booted between jobs, so the next job does not wait for a cold boot.
- It shuts down by itself after 5 minutes with no job. Why 5 minutes: it is longer than the usual gap between two jobs (fix a test, then run `make e2e` again; the next agent starts its job). It is short enough to give the Mac back soon when the factory stops. A small background process (`ios/scripts/sim-lock.sh watch`) does this. It uses no Simulator and almost no CPU, and it stops by itself. With the second slot on, it does the same for each slot, with the same delay.
- **The smallest iPhone.** To check a screen on the smallest supported iPhone (375 x 667 pt), run `make run SMALL=1`. It uses a second shared Simulator, `RATP-Shared-Small` (an iPhone SE), through the same lock. Only one shared Simulator of a slot is booted at a time. Before a job or a `make run` boots its Simulator, it shuts down the other shared Simulator of its slot. When it cannot shut it down, it stops, and it does not boot a second one. `make simulator-shutdown` removes the app from `RATP-Shared-Small` and keeps it booted, alone. The watcher shuts it down after 5 minutes with no job. So each size switch (`make run`, then `make run SMALL=1`, then back) waits for a cold boot of the other size (about 125 of load, and the job takes about 4 times longer than on a warm Simulator, TASK-84). This cost is accepted, and it is not a bug. Why: on 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running for speed (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing"). From 2026-09-27 (TASK-92) to 2026-09-28, the scripts kept the other size booted, so that a size switch did not wait for a cold boot. That kept a second Simulator running next to a job, for speed, so TASK-119 removed it. Never boot another Simulator by hand to check a screen size.
- **A Simulator that something else boots.** While a job or a `make run` holds the lock, the watcher (`ios/scripts/sim-lock.sh watch`) checks every 10 seconds that no other shared Simulator of its slot boots during the job. It shuts down a shared Simulator of the slot that the job does not use, also one that was already booted when the job took the lock (for example, left by a worktree with older scripts). So at most one shared Simulator of the slot is booted while a job runs (TASK-119). Why: on 2026-09-27 (TASK-67), the Simulator panel of the Claude app booted `RATP-Shared` again, while `make run SMALL=1` used `RATP-Shared-Small`. The panel boots the device that it showed last. So do not boot a shared Simulator from the panel or by hand: the watcher shuts it down while a job runs.
- **A watcher of old scripts.** Only one watcher runs. A job, a `make run`, and a `make simulator-shutdown` that frees the lock start it when none runs. When the watcher that runs has an older `watcher_version` (in `ios/scripts/sim-lock.sh`), or no version, they stop it and start the watcher of their own scripts. A watcher also stops when its worktree is removed. Why: on 2026-09-27 (TASK-78), a watcher of old scripts ran for hours, because a job held the lock almost all the time, so the fix of TASK-67 did not work. **When you change what the watcher does, raise `watcher_version` by 1.**
- `make simulator` prints the ID of the Simulator of your `make run`. Use it in your `xcrun simctl` commands; never type a Simulator name.

## The Simulator lock

`make run` and `make e2e` take a machine-wide lock: the folder `/tmp/ratp-sim.lock`. While another job holds it, they wait and print `Waiting for the Simulator lock`, with the reason. This is normal. Do not stop them, and do not delete the lock. The wait can be long, so run these commands in the background.

- `make e2e` frees the lock when the tests end, pass or fail.
- `make run` keeps the lock. You can then check the app by hand, or run `make e2e`. Free it with `make simulator-shutdown` as soon as your check is done (see "Hold the Simulator only while you use it").
- Any other command that boots or uses a Simulator (for example `xcodebuild test` or `xcrun simctl boot`) must run through the lock, on the shared Simulator:

  ```sh
  ios/scripts/sim-lock.sh job <command>
  ```

  To boot the shared Simulator and remove the app of the last job first, run `ios/scripts/sim-lock.sh job ios/scripts/simulator.sh reset <command>`. The lock gives its slot to the command (`RATP_SIM_SLOT`), and `ios/scripts/simulator.sh` uses it. With `xcodebuild`, put `ios/scripts/simulator.sh with-destination` before it, and add `-project ios/TROME.xcodeproj`: it adds the `-destination` of the Simulator of the job. Never name the Simulator (`name=RATP-Shared`), so the command still works when the second slot is on.

`make docs-screenshots` is a Simulator job too: it takes the lock, like `make e2e`, and frees it when the tests end. So is `make live-activity-render` (the render check of the Live Activity views, see "The Live Activity render check").

`make merge` takes the lock before the rebase and frees it after the fast-forward, success or failure (see "Merge a task into main"). Before that, it takes a merge lock (`/tmp/ratp-merge.lock`, with `lockf`), so only one merge runs at a time, even with two Simulator slots. A `ios/scripts/sim-lock.sh job` that starts inside a job that holds the lock runs at once, in that job's slot: so the `make e2e` of `make merge` does not wait for its own lock. It does not free the lock when it ends: the outer job does.

`make check`, `make test` and `make test-scripts` need no Simulator and no lock.

The lock frees itself when its job dies, when its worktree is removed, or when the Simulator is shut down.

## Test levels

The test strategy of this repo is decision-9 in the backlog (`backlog/decisions/decision-9 - What-each-test-level-is-for-and-how-deep-a-change-is-tested.md`). Read it before you add or change a test: it gives the reasons, the worked examples, and how the QA depth is chosen. The product is the Live Activity. The app screen is its small control panel, and the Testing tools are part of the test harness. For each thing that could go wrong, ask: what could a rider lose, and what is the cheapest check that can really see it?

- **Unit test** (`TROMECore`, on the Mac, seconds). Any rule or value that you can write as "this input gives this output": what the Live Activity must show, the start, switch and end rules, the snooze, the PRIM answers (recorded fixtures, in `contracts/prim/`).
- **Code review.** The structure, the wiring, the access control, and the level of each new check. A new E2E test or step with no seam, an assert on the app's own echo of its state, a setup through the UI that is not the seam, or a fake of our code or of iOS at the seam under test is a medium finding.
- **Render check of the Live Activity** (proposed by decision-9, not built yet). How our views draw a given ContentState at the extreme cases: the 160 pt limit, cut or wrapped text.
- **E2E test** (the shared Simulator, the factory's bottleneck). Only for a seam where our code meets iOS and a fake would lie: ActivityKit starts, switches and ends a real Live Activity; the widget process draws our ContentState; iOS runs the intents of the Live Activity buttons; a real notification opens the app; the position from iOS reaches the rules; the permission popups come in order. Assert on what the rider or iOS shows (the Live Activity in the Notification Center, the notification, the popup), not on an app label. Set up the state with a platform hook (`XCUIDevice.location`) or a launch argument, not through the app screen or the Testing tools. Fake only what is not the seam under test (`--fake-trains` replaces PRIM). One test per seam. Each file in `ios/UITests/` starts with its seam and why a cheaper check cannot see it. Keep the test phase of the full suite at a few minutes.
- **QA** (exploratory, the shared Simulator for a whole session). What no script can judge: does it look and read right, with real data, in French, over time, in the background. The Dynamic Island and the wake of a closed app by region monitoring are checked here and on the prompter's iPhone, not in E2E.
- **No check.** A change that no rider can see, or whose risk another check already covers (the look of the Testing tools, a README text).

## Which E2E tests to run

The E2E tests must make sure that no breaking bug lands on `main`, and that no agent ever sees a failing test because another agent brought a bug. But a full `make e2e` keeps the shared Simulator for several minutes, and the shared Simulator is the factory's bottleneck. So the factory runs far fewer E2E tests, at the right time:

**`main` is always green.** It holds only tasks that passed review and QA. Each fast-forward of `main` lands on a commit where the full E2E suite passed. The manager runs it on that exact commit, with `make merge`. This is the only full run of a task.

**App code**, for these rules, is what the E2E tests exercise: `ios/App/`, `ios/Widget/`, `ios/Packages/` (except its unit tests), the E2E tests in `ios/UITests/`, and what builds or runs them (`ios/project.yml`, `ios/Config/`, the `Makefile` files, `ios/scripts/`). Docs are not app code: `docs/`, every Markdown or MDX file (`*.md`, `*.mdx`, in any folder, for example `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `ios/README.md`, `ios/guide/`), `LICENSE` at the root, and `.claude/` (the agents' rules and settings). No E2E test, no build and no script of the E2E suite reads them, and `make check` still checks them. One exception: a Markdown or MDX file in a folder that the build of the app takes as its sources (`ios/App/`, `ios/Widget/`, `ios/UITests/`, `ios/DocsScreenshots/`, `ios/RenderCheck/`, `ios/Packages/` except its unit tests) is app code, because XcodeGen copies it into the app as a resource. Unit tests (`ios/Packages/TROMECore/Tests/`), the server (`server/`, its `Makefile` included: no E2E test uses it), the shared test files of `contracts/` and backlog files are not app code either. `contracts/` holds only files that tests read: no build of the app or of the server ships one. A task that makes the app read a file of `contracts/` at run time, or makes the build or an E2E test read one of these docs files, makes it app code, and changes `is_app_code` in `ios/scripts/merge.sh` in the same task.

- **The implementer** runs only the E2E test classes of the flows that it changed: `make e2e ONLY=SnoozeTests`, or `make e2e ONLY="SnoozeTests LiveActivityTests"` for more than one. The class names are the file names in `ios/UITests/`. When its change touches no flow of the E2E tests (for example, a rule that only unit tests cover), it runs no E2E test.
- **A reviewer** runs no E2E test, unless it changes app code. For example, a review with no change, or a change to the docs (Markdown files included), the unit tests or the backlog files only, runs none. A reviewer who changes app code runs only the E2E test classes of the flows that its change touches.
- **The manager** runs `make merge` after QA passed the task (see "Merge a task into main"). It runs the full `make e2e` once, after the rebase onto `main`, on the commit that it fast-forwards `main` to. A task that changes only docs (Markdown and MDX files, `LICENSE`, `.claude/`), unit tests, `server/` or `contracts/` (no app code) skips the full run: `main` was green, and the task adds no app code. `make merge` sees this by itself.
- **QA** runs no automated tests. It explores the app like a real user.

These rules do not change the rule on flaky tests (below): a failing test may be rerun once, to know if it is flaky.

## Merge a task into main

A task reaches `main` only after QA passed it. The order is:

1. The Software Engineer implements the task on its branch `task/<id>`, and another Software Engineer reviews it.
2. The implementer runs the quality gate (`make check`) on the last commit of the branch, plus the E2E test classes of the flows that the change touches (see "Which E2E tests to run"). The reviewer hands the task over to QA. Before that, it makes sure that the gate passed on the last commit of the branch. A reviewer who changed no code runs nothing again: the run of the implementer covers that commit. A reviewer who changed code runs the gate, plus the E2E test classes of the flows that its change touches when it changed app code. No Software Engineer rebases the branch, merges, or runs `make merge`.
3. The manager rebases the branch onto `main` right before QA, so QA tests the branch on the latest `main`. When this rebase has a conflict, the manager stops it (`git rebase --abort`), and the task goes back to its Software Engineer, who solves it.
4. QA tests the branch.
5. When QA passed the task, the manager runs one command in the worktree of the task, one task at a time, instead of the separate steps (rebase, gate, E2E run, fast-forward):

```sh
make merge
```

When the branch changes `docs/`, `server/` or `contracts/`, load Node 24 first: `. "$HOME/.nvm/nvm.sh" && nvm use && make merge`. Run it in the background: it can wait long for the Simulator lock.

It takes the Simulator lock, then does these steps. Each step runs only when the step before it passed:

1. It rebases the branch of the worktree onto the tip of `main`.
2. It runs the quality gate (`make check`).
3. It runs the full E2E suite (`make e2e`), unless the branch changes no app code (see "Which E2E tests to run").
4. It fast-forwards `main` to the rebased branch. When `main` is checked out in a folder (the main folder of the repo), it updates that folder too, with `git merge --ff-only`: a fast-forward, never a merge commit.

Then it frees the lock. When a step fails (a rebase conflict, the gate, the E2E suite), it stops at once, says which step failed, leaves `main` as it was, and frees the lock. After a rebase conflict, it names the files of the conflict and stops the rebase (`git rebase --abort`): the branch and the worktree are as they were before `make merge`. So after a conflict in either rebase (before QA or in `make merge`), the task goes back to its Software Engineer with no rebase in progress, and the command of the Software Engineer, `git -C <worktree> rebase main`, works: it shows the conflict again, and the Software Engineer solves it. When the folder of `main` has changes that are not committed (also staged or new files) on the files of the task, `make merge` refuses at once, before it waits for a lock, and names the folder and the files. Changes on other files of that folder do not stop it. It checks this again when its turn comes, and the fast-forward still fails safely when such changes appear during the run. It refuses to start on `main`, with changes that are not committed, with `ONLY=` (the E2E suite is always the full one), or with nothing to merge.

Why one command, with the lock all along:

- **Merges queue one after another.** A second `make merge` waits for the first one (it prints `waiting for the merge of another worktree`), then for the Simulator lock. When its turn comes, `main` already has the first merge, so it rebases onto it. Its fast-forward is never refused because another merge landed during its run.
- **A full E2E run is never repeated.** Before, another merge could land between the end of a full run and the fast-forward. The fast-forward was then refused, and the full suite had to run again after a new rebase.
- **History stays linear, and `main` stays green.** `main` moves only by fast-forward, to the exact commit that passed the gate and the E2E suite. No merge commit: a merge is always a rebase, then a fast-forward.

Why the Software Engineer does not rebase: the manager rebases right before QA, and `make merge` rebases again, so a rebase at hand-over only repeated them. The permission system also refused it once.

`make merge` changes only `main` and the branch of the task. It never checks out `main` in the worktree of the task. When a step fails for a reason on the branch (a rebase conflict, the gate, the E2E suite), the task goes back to its Software Engineer (status `To Do`, with a comment). The Software Engineer fixes the cause on the branch (for a rebase conflict, it runs `git -C <worktree> rebase main` and solves the conflict) and hands the task over again. Then the manager runs `make merge` again.

When the E2E suite fails and `make merge` prints "The Mac slept during the E2E tests" after the failing tests, the cause is likely not on the branch: the Simulator stopped while the Mac slept, and the waits of the tests ran on the clock. The task does not go back to its Software Engineer. The manager runs `make merge` again, once (the rule on flaky tests). When it fails again with no sleep, the task goes back as above. Why: on 2026-09-30, a task that had passed QA went back to its Software Engineer for a night only because the Mac slept for 96 seconds during the full suite (TASK-140, TASK-154). `caffeinate` cannot stop the sleep of a closed lid on battery.

When `make merge` refuses because the folder of `main` has changes that are not committed on the files of the task, the task does not go back to its Software Engineer: the branch is fine, and QA passed it. That folder is the prompter's folder, and the changes are the prompter's. The manager tells the prompter the folder and the files that `make merge` names, and the prompter decides: commit, stash or drop the changes. The task stays as it is. The manager runs `make merge` again when the prompter says that the folder is clear. The same holds when the fast-forward fails because such changes appeared during the run. No agent commits, stashes or discards the changes of the prompter's main folder without the prompter.

## Hold the Simulator only while you use it

Every job that uses the Simulator (`make run`, `make e2e`, `make docs-screenshots`, a job through `ios/scripts/sim-lock.sh job`) frees it as soon as its check is done, not a moment later.

- **Prepare first.** Read, plan and build before you take the Simulator. `make e2e` already builds before it takes the lock.
- **Free it right after the check.** `make e2e` and `make docs-screenshots` free the lock by themselves when the tests end. After `make run`, run `make simulator-shutdown` as soon as your check by hand is done, not at the end of your job.
- **Never hold it while you do something else.** Do not keep the lock while you think, fix code, write notes or wait for another job. To check again after a fix, run `make run` again: another job may use the Simulator in the meantime.

## Flaky tests

A flaky test (it fails, then passes with no change) is a bug. Rerun a failing test at most once, to know if it is flaky. Then fix the cause in your task if the test covers your code. Otherwise, create a `bug` task with the test name, how often it failed, and the error. Never fix it with retries or longer timeouts alone: find the cause (a race, a shared state, a missing wait for a condition).

## When your job ends

Free the Simulator right after your last check, not later (see "Hold the Simulator only while you use it"). Before your job ends, run this again in your worktree, to be sure. It removes your app from the Simulator and frees the lock (needed after `make run`, and harmless after `make e2e`):

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

All worktrees share the compiled modules of the iOS SDK, in `~/Library/Caches/RATPActivity/`. It holds no code of the app, so two tasks never mix their build products.

- `make clean` does not touch it. Only the prompter runs `make clean-shared-cache`. It waits for the running builds, and new builds wait for it (they print `Waiting: the shared build cache ... is being cleared`). Never delete the folder by hand: a build that runs at that moment fails.
- `make build LIVE=1` does not use it, so it never holds a build with the real key. `make live-key-check` checks it.

## The git hooks

`ios/scripts/git-hooks/` creates the Xcode project again after a `git pull`, a checkout, a merge or a rebase in the main folder (`ios/README.md`, section "Keep the Xcode project up to date"). The prompter turns them on with `make git-hooks`.

- **Never run `make git-hooks` or `make git-hooks-off`.** They change `core.hooksPath` in the git config, and all the worktrees share it with the prompter's main folder. Only the prompter turns the hooks on or off. In a test, use a repo of your own (as `ios/scripts/tests/git-hooks-test.sh` does).
- The hooks do nothing in a worktree of an agent. The `make` commands create the project there.
- A hook must never leave the main folder dirty, and must never make a git command fail. `make test-scripts` checks both.

## The Live Activity render check

`make live-activity-render` draws the Live Activity views (the lock screen and the bottom region of the expanded Dynamic Island) for every station and page, at both phone widths and at the Large and XXXL text sizes. It lists the drawings that are too tall, the cut texts and the breaches of decision-15, and saves images for a person to read (`ios/README.md`, section "Check how the Live Activity draws").

- **When to run it.** In any task that changes the Live Activity views or their data (`ios/Widget/`, `LinesPage`, `ContentState`), for example TASK-36, TASK-65 and TASK-37: once before the change and once after it. Write in the task notes, before and after the change, the number of too tall drawings and the counts of each kind of breach of decision-15 (the summary prints them for each phone, surface and text size), and the cut texts that changed, and put the images that matter in the notes for the reviewer and QA. Do not write a temporary UI test for this any more.
- **The breaches of decision-15.** decision-15 is the product rule of what may be cut in a row of the Live Activity. The render check lists the texts that break it, in the images: (a) a time that is cut (for example "dans 3…"); (b) a destination shown with fewer than 6 characters before its "…" (a destination shorter than 6 characters that is shown whole is not a breach); (c) the two directions of one line that show the same text (for example "Mairie d'…" twice); (d) a station label name that is cut. It knows which text is cut from SwiftUI's own layout of each text (`Text.LayoutKey`: cut or not, and how many characters show), and which text it is from the text recognition of the Mac on that part of the image, compared with the texts of the drawn state. A breach is a defect to write in the task notes: the Product Owner decides case by case (decision-15). "Other cut texts" (for example "Ouvrez l'app pour mettre à jour les horaires") are not breaches: a person reads them in `cut-texts.txt`.
- **It is not a gate.** It is not part of `make check` or `make e2e`, and it fails only when it cannot run, even with breaches. Why: decision-15 keeps it a report until option C (decision-14) is shipped, because C redraws these views. Making it a gate is not for a Live Activity task to decide.
- **French, and English on demand.** It draws in French (the main language), in `ios/.build/live-activity-render/fr/`. `make live-activity-render ENGLISH=1` draws in English too, in `.../en/`: use it only when the task changes an English text of the Live Activity. Why: the English run costs about 130 s more of the shared Simulator, and on 2026-09-29 it found nothing that the French run did not find (the French texts are longer). Write the numbers of each language that you drew in the notes. The views get their texts from a small host app, `ios/RenderCheck/Host/`, that holds the String Catalog of the widget, as the widget extension does. Why: a test bundle with no app finds no texts, so it drew only the English texts of the code, and it missed the French cuts of TASK-112. The test fails when the texts are not in the language that it draws. A new String Catalog of the widget goes in this host app too (`ios/project.yml`).
- **Its two entry views.** It draws `LockScreenView(state:isStale:)` and `ExpandedIslandBottomRegion(state:isStale:)` of `ios/Widget/StationLiveActivity.swift`. Keep them `internal` with these parameters. A redesign may change what is inside them.
- **Its numbers.** The widths and the height limits in `ios/RenderCheck/LiveActivityRenderCheck.swift` were measured on the real Live Activity (TASK-124). A task that changes the regions of the Dynamic Island, or a new iOS version, measures them again before it trusts the check.
- It is a Simulator job, through the lock, like `make docs-screenshots`. It frees the lock when the drawing ends.

## Code structure of the server

decision-6 (sections 2, 3 and 6) and decision-40 explain these rules. The reviewer checks them, as for the iOS app.

- **Two modules, one direction.** `server/src/core/` holds the logic in plain TypeScript: the routes, the rules, the counts, the logs. `server/src/cloudflare/` is the thin layer on the Cloudflare API: the Worker entry (`worker.ts`, the composition root), the Durable Object, and the adapters (for example `DurableObjectSqlDatabase`). `cloudflare/` depends on `core/`, never the reverse. Why: decision-40 keeps the exit to another host a medium task, not a rewrite.
- **`core/` runs on Node too.** It imports no `cloudflare:` or `node:` module and no file of `cloudflare/` (ESLint fails on it), and it type-checks with the types of Node and none of Cloudflare (`test/core/tsconfig.json`). Its unit tests run on Node (`test/core/`), with a real SQLite database (`node:sqlite`) behind the `SqlDatabase` interface. A platform service gets a small interface in `core/` and an adapter in `cloudflare/`.
- **Tests.** `server/test/core/<feature>/<file>.test.ts` (Vitest on Node, with a fake clock) for the logic. The examples of the app API in `contracts/api/` are checked by `server/test/core/http/departures-contract.test.ts`. `server/test/cloudflare/<file>.test.ts` (Vitest in the Cloudflare runtime, `@cloudflare/vitest-plugin`) for the thin layer: the Worker, the Durable Object and its storage. Tests of the scripts: `server/scripts/tests/<name>-test.sh`. The server tests read the recorded PRIM answers of `contracts/prim/` (no copy). No real PRIM call and no real secret in a test: `fetch` to PRIM is faked with the recorded answers.
- **Folders by feature** inside `core/` (`http/`, `logging/`, `config/`, `storage/`, `time/`, `auth/`, `relay/`, `budget/`, `usage/`), with the same names in `test/core/`. The fakes of the tests go in the folder of what they replace (`test/core/time/fake-clock.ts`, `test/core/relay/fake-prim-client.ts`). Files in kebab case, one main export each.
- **Secrets by name only.** The PRIM key, the app token and the owner token are Cloudflare secrets (`secrets.required` in `server/wrangler.jsonc`). Their values are never in git, never in a log line (the logger of `core/logging/` hides them, and a unit test proves it), and never in the app. `server/worker-configuration.d.ts` is generated by `wrangler types` and in git: after a change of `server/wrangler.jsonc`, run `npm run types` in `server/` (`make server-check` fails when it is old).

## The server (`server/`)

`server/README.md` explains the server and its commands; `server/guide/how-it-works.md` its API and its quota, and `server/guide/deploy.md` the deploy and the secrets.

- **Node 24.** Run the server commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make server-check`. The same goes for `make check` when your task changes `server/` or `contracts/`: `make check` runs `make server-check` only then, so the app tasks never install `server/node_modules` (about 300 MB).
- **Use your own port.** `make server-dev` uses 8787 in the main folder only (the prompter's), 8787 plus the number at the end of the folder name in a worktree (8974 in `task-187`), and a port from 9800 to 9899 in a worktree whose name ends with no number (for example `qa`). Run it in the background, and stop it with `make server-stop` as soon as your check is done, and before your job ends.
- **Fake secrets only.** `make server-dev` creates `server/.dev.vars` (ignored by git) from `server/.dev.vars.example`, with fake values. Never put a real key in it, and never commit it (`make server-check` fails when git tracks a `.dev.vars` or `.env` file of `server/`).
- **No deploy and no account.** Only the prompter runs `make server-login`, `make server-secrets`, `make server-secret`, `make server-deploy-staging`, `make server-deploy` and `make server-counts` on a deployed server, with his Cloudflare account and his owner token. An agent never runs them, never logs in to Cloudflare, and never reads the real secrets.
- **No PRIM call from `make server-dev`.** The dev server calls the real PRIM, with the fake key, as soon as a departures request has the right app token. So an agent never sends `GET /v1/stops/.../departures` with the app token of `server/.dev.vars` to it: check those answers in the tests, which fake PRIM. Requests that never reach PRIM are fine (`/health`, a missing or wrong token, a bad stop reference, `make server-counts` with the fake owner token).
- **Server jobs need no Simulator and no lock.**

## The docs site (`docs/`)

`docs/README.md` explains the docs site and its commands (section "Run the site").

The rules on writing (who writes the pages, the writing guide, one sentence per line, public text, where a change writes its text) hold for the whole repo, not only for `docs/`.

- **Keep the docs true.** A task that changes a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images. A docs text change alone needs no new screenshots. The reviewer checks it.
- **Who writes the pages.** The Technical Writer writes and rewrites the docs pages (decision-49, section 9). A Software Engineer writes only the docs lines that its own change makes false, in the file that the table below names. Why: each page is written for one reader and one job (decision-49); a page that grows by the facts of each task stops serving its reader, as the README did.
- **The writing guide and the review bar.** A page follows `docs/README.md` ("Write a page"), and a docs review uses its "Review a page", the public form of the bar of decision-49 section 5. These rules for agents stay out of the public pages: `CONTRIBUTING.md` is for an outside contributor, and the checks below explain themselves when they fail.
- **One sentence per line.** Write each sentence of a Markdown or MDX file of the repo on its own line. When one sentence is longer than 400 characters, break the line after a comma, a colon or a semicolon. When a change makes a sentence false, edit only that sentence, and never reflow a paragraph. Tables and code blocks may have long lines. Why: git merges by line, so two tasks that change two sentences of one long line conflict (TASK-173). `make prose-check` (part of `make check`) fails on a line of prose longer than 400 characters (CLAUDE.md is skipped until it is split by topic).
- **Public text.** The repo is public: anyone can read the README, the docs and the code. So a file of the repo has no backlog id, no word of the team's own way of working (the prompter, the factory, the manager, agents), no personal data (for example an email address that is not an example one), no local path of a computer, and not the old name of the app. Write the rule and its reason instead. Why: a stranger cannot open a private task, but they can read a reason. `make public-text-check` (part of `make check`) fails on each of these, and prints the file, the line and the reason. Its word list is in `ios/scripts/public-text-check.py`. It also fails on the old names of the Xcode project and of its module (in the word list, in any case): only the files that remove what a build of the old name left on a Mac or on the Simulator may write the old project name, and `ALLOWED_TEXTS` lists them with the reason. When a hit is a normal word in its place (for example the name of a type), add it to `ALLOWED_TEXTS` in that file, with its path, its text and the reason. `CLAUDE.md` and `.claude/` are the manual of Claude Code: they may cite the backlog, but never personal data or a local path. For now, the check also lets `ios/README.md` cite the backlog, until the rewrites of its feature sections (TASK-203, TASK-204) move them to the files of the table below: the last one removes its line from `INTERNAL_FILES`. `server/README.md` passes the whole check since TASK-202. The front page, `README.md`, passes the whole check.
- **Where a change writes its text.** Each text lives in one file, chosen by its reader. Link to the file that holds a fact, and never copy the fact. A text in the wrong file is asked to move in the review, like a code file in the wrong folder. Some of these files do not exist yet: until a file exists, edit the section of `ios/README.md` or `server/README.md` (or of `CLAUDE.md`, for a rule for Claude Code) on the same topic. Never add a command, a step or a rule to the front page, `README.md`: it only says what TROME is, how to get it, and where to go next.

  | Kind of change | The file that the change edits |
  |---|---|
  | A new or changed `make` command | the `help` line of its Makefile, and the guide page of its topic; `CONTRIBUTING.md` only when a command that it names changes |
  | A changed rule that a rider sees (the Live Activity) | the guide file of its feature (`ios/guide/<feature>.md`); a rider page of the docs site only when its summary becomes false |
  | The internals of a type | the doc comment on the type |
  | A new feature folder | a new guide file, a line in `ios/README.md`, a line in `ARCHITECTURE.md` |
  | Structure or dependency direction | `ARCHITECTURE.md` |
  | A screen that the docs site shows | the page of the site, and its screenshots |
  | A rule for Claude Code | the file of its topic in `.claude/rules/` |
  | A product rule | the decision in the backlog, outside the repo; the repo states the behaviour and its reason |
  | The notes of a version | not in a change: "What's new" and `CHANGELOG.md` are written at each release |
  | The server | `server/README.md` or `server/guide/` |
- **Node 24.** Each Bash call starts a new shell with the old default Node. Run the docs commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make docs-check`. The same goes for `make check` when your task changes `docs/`.
- **Install `docs/node_modules` only when your task touches the docs.** It takes about 300 MB. `make check` runs `make docs-check` only when your branch changes `docs/`, so the other tasks never install it.
- **Use your own port.** The default port 4321 is for the prompter. Run `make docs PORT=<n>` or `make docs-dev PORT=<n>` with a port that no other agent uses (for example 4300 plus your task number).
- **Stop the docs server when your job ends.** For agents, Astro starts the server in the background and the command returns at once. Run `make docs-stop` in your worktree before you end.
- **Screenshots.** Show each app screenshot with the `Screenshot` component (`docs/src/components/Screenshot.astro`), never with a Markdown image or the `Image` component. Put screenshots side by side inside `Screenshots`. Take each screenshot full screen on a shared iPhone 17 Simulator (`make docs-screenshots` does), so all have the same size. Each file in git stays under the budget of `docs/README.md` (section "Make the pictures again"). The script checks the size and the budget.

## QA: French first

Almost every user of the app is French. So French is the main language of QA.

- **The main pass is in French.** QA runs `make run LANGUAGE=fr` (with `LIVE=1` or `SMALL=1` when needed). The whole Simulator is then in French. QA's main pass through each screen, the Live Activity (lock screen), the Dynamic Island, the notifications and the permission messages is in French.
- **Then a quick look in English, at the changed screens only.** After the main pass, QA runs `make switch-language LANGUAGE=en`. It puts the Simulator in English and opens the app again, with its data and its permissions, so QA does not set up the app again. It uses the Simulator of the `make run` (also with `SMALL=1`). A notification sent before the switch keeps its old language: this is not a bug. QA looks only at the screens, the Live Activity views, the notifications and the messages that the task changed: a text that is not translated, a text in the wrong language, or a layout problem with the English text (English and French texts do not have the same length). Keep this look short: it must not make the QA run longer. When the task changes no text and no screen, skip it. With `LIVE=1`, the app keeps calling PRIM in English too: these calls count in the budget of the QA run (section "Live train data"). Then QA runs `make simulator-shutdown` at once. `make switch-language LANGUAGE=fr` goes back to French.
- **What is a bug.** A screen or a message that mixes French and English. A French text that a Paris rider would not say (the words of the RATP signage and of iOS in French are the reference: "Prochains passages", "écran verrouillé", "Réglages"). The "Testing tools" screen, the "Testing tools" link and the "Fake position" banner of the main screen (debug builds only) stay in English: this is not a bug.
- The system popups (for example "Autoriser une fois") come from iOS in the language of the Simulator. Only their explanation text comes from the app.
- `make e2e` and `make docs-screenshots` put the Simulator back in English by themselves.

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
- **Budget of a QA run.** Until the first external build (G5 in doc-5, "The release plan": friends can install a TestFlight build), at most 60 PRIM calls per QA run. From G5 on, at most 30 PRIM calls per QA run, at most 2 live QA runs in one PRIM day (00:00 to 24:00 UTC), and no live QA run on the day the first external group is invited. The manager knows whether G5 has passed, counts the live QA runs of the day, and gives QA its budget (60, 30 or none) when it starts a QA run that needs `LIVE=1`. When QA has no budget from the manager, it uses 30. A task that needs more asks the manager, who asks the prompter for that day. Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop area of the station when it opens the next trains, then again every 30 seconds while the app screen is open. Calls = stop areas × (1 + seconds on screen / 30). All the metro lines of a station share one stop area, and an RER stop is one stop area. The stop areas of a station include the stop areas of the other stations of its place (its hub, see `ios/README.md`, section "The station list"). Today Châtelet has 2 stop areas (the metro stop area of Châtelet, and the RER stop of Châtelet - Les Halles): 4 calls per minute. Saint-Lazare has 5: 10 calls per minute. A metro station with no hub has 1 stop area: 2 calls per minute.

To stay in the budget:

- Pick a station with few lines and no hub, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once. The app keeps calling PRIM while it runs, and the shared Simulator stays booted after your job. `make simulator-shutdown` removes the app, so the calls stop. Then remove the key from `ios/.build/` (see above).
- At Châtelet, stay at most 2 minutes on the next trains (10 calls).

Why 60, then 30: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day. But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day). We do not know the quota of the prompter's key, so we plan for 1,000 calls per day. One key serves the production server, the staging server and every Debug build that holds it, QA's `make run LIVE=1` included. Their shares are in one table, "The day of the PRIM key" in `server/README.md` (decision-59): read the numbers there, and do not copy them here. The Debug builds and QA share one row of it, with the prompter's own tests and iPhone trial, and the server does not count them. Before G5, production spends nothing, so a QA run may use 60 calls. From G5 on, production spends up to its full share once riders use it, so 5 QA runs a day no longer leave the prompter most of the day: a QA run gets 30 calls, and 2 runs a day at most.

When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager. The manager tells the prompter that the production server may have paused its PRIM calls for an hour: every rider then reads "Times unavailable for now".
