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
- **Folders by feature, with the same names everywhere.** `ios/App/`, `ios/Packages/RATPCore/Sources/RATPCore/` and `ios/Packages/RATPCore/Tests/RATPCoreTests/` use the same feature folders: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`. The app also has `Permissions` and `TestingTools`. New code goes in the folder of its feature. A new feature gets a new folder in each module where it has code. No layer folders (`Views/`, `Models/`, `Services/`, `Helpers/`), and no loose files at the top of a module. The only exceptions: `RATPActivityApp.swift` and `ContentView.swift` (the main screen) at the top of `ios/App/`, the String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) at the top of `ios/App/` and `ios/Widget/`, `Resources/` in the package, and `Fixtures/` in its tests.
- **Testing tools are for debug builds only.** Each file in `ios/App/TestingTools/` is inside `#if DEBUG`.
- **The widget is a pure view.** `ios/Widget/` uses only `StationActivityAttributes` and its value types from `RATPCore`, and `SnoozeLiveActivityIntent` for its buttons (iOS runs the intent in the app, not in the widget). No model, no provider, no network.
- **Texts in French and English.** Each text that a user sees is written in English in the code, and has its French text in the String Catalog of its target, in the same task (README, section "Languages"). `make check` fails on a text with no French text (`make strings-check`). Use a text that SwiftUI translates (`Text("...")`, a `LocalizedStringKey`) or `String(localized:)`, never a plain `String` given to `Text`. The texts of `ios/App/TestingTools/` stay in English: mark them `"shouldTranslate" : false` in the catalog. The texts of `RATPCore` (for example `TransitLine.displayName`) are not translated: the app and the widget make the texts that a user sees.
- **Access control.** In `RATPCore`, only what the app or the widget uses is `public`. The rest stays `internal`. Tests use `@testable import RATPCore`.
- **Files.** A file holds one main type and has its name. Small types that exist only for it (its state, its error, the protocol of its dependency) may stay in the same file. An extension that adds a topic goes in `Type+Topic.swift`. Names say the role: `...View`, `...Section`, `...Screen`, `...Model`, `...Rules`, `...Store`, and the framework name first for an adapter.
- **Tests.** Unit tests: `ios/Packages/RATPCore/Tests/RATPCoreTests/<Feature>/<Type>Tests.swift`. E2E tests: `ios/UITests/`, one file per core flow. Tests of the scripts: `ios/scripts/tests/<name>-test.sh` (`make test-scripts`, with a fake `xcrun` for the Simulator scripts). Docs screenshots: `ios/DocsScreenshots/`. Code that needs a unit test goes in `RATPCore`.
- **No warnings.** `make check` fails on any build warning and when a newer Xcode may recommend new project settings (README, section "No warnings"). Fix the cause. Never silence a warning, and never raise `options.xcodeVersion` in `ios/project.yml` without adding the settings that Xcode proposes. An agent cannot open that Xcode dialog: when `make recommended-settings-check` fails, ask the prompter (label `needs-prompter`).
- **New module.** Add a target in `ios/Packages/` only when it solves a real problem (code that must not see the rest, code shared with a new target, build time). Deeper changes that these rules call for are `tech` tasks.

## Budget for this repo

- The factory runs **at most 3 Software Engineers** in parallel for this repo.
- **At most one Simulator job** runs at a time on the machine. A lock enforces it (see below).
- **Never a second Simulator on this Mac.** On 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running on this Mac, for any reason: a faster job, a Simulator for QA, a Simulator for `make run`, or the second job slot (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing"). Why: the boot of a second Simulator alone, with no job next to it, already takes the Mac to an unsafe load (234 to 333, TASK-106, see below). This is a closed decision, not a trial on pause. Only the prompter, in person, can open it again, and only with a new reason (for example, a different Mac). Never propose, build or measure a new design with a second Simulator. One case is still open: `make run SMALL=1` keeps the small shared Simulator booted next to `RATP-Shared` between jobs (TASK-92, see "The shared Simulator"). TASK-119 weighs whether this is safe. Until TASK-119 decides, it stays as it is.

Why one Simulator job: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac. The load average went above 600, and the prompter could not work.

Why not two Simulator jobs: TASK-62 added a second Simulator slot, for a second job next to the first one, only when at least 25% of the CPU is idle. It was measured on 2026-09-27 on the real Simulators. The CPU check works at the start. But once the second Simulator runs, the CPU is 0% idle for the whole job. The 1-minute load average went from 44 to 257 in one run, and from 22 to 286 in another (8-core Mac). The job in slot 2 took 2 to 3.5 minutes instead of about 46 seconds alone: about 3 times slower. So the gain is not clear, and the risk is the one of 2026-09-26. The prompter kept the code of the second slot, but off (2026-09-27). On 2026-09-28, after TASK-106 (below), the prompter decided against the second slot on this Mac: it stays off. TASK-63 records how long the jobs wait and run. Its numbers are not a reason to try two jobs again on this Mac.

**The code of the second slot (decided against on this Mac):** `ios/scripts/sim-lock.sh` keeps the code of a second slot, but off (`slots=${RATP_SIM_SLOTS:-1}`). It is not a trial that an agent or a task can run. Never change this line, and never add `RATP_SIM_SLOTS=2` to a command. Only the prompter, in person, can decide to turn it on again, and only with a new reason (for example, a different Mac). For that case only, this is how the code works. With `slots=${RATP_SIM_SLOTS:-2}`, a job takes a free slot (slot 1 first). It runs next to another job only when at least 25% of the CPU is idle (`min_idle_percent` in the same file, or `RATP_SIM_MIN_IDLE_PERCENT` for one command). Slot 2 uses its own Simulators (`RATP-Shared-2`, `RATP-Shared-Small-2`) and its own lock (`/tmp/ratp-sim.lock.2`), so two jobs never see the data of each other. A change to two slots must also change this section, "The shared Simulator" and the README. To go back to one job, change the line back, then run `make simulator-delete` once, to delete the Simulators of slot 2.

Why QA has no Simulator of its own: a QA session keeps the lock while QA explores the app (12 to 19 minutes each on 2026-09-27), and the other jobs wait for it. TASK-84 measured a QA Simulator next to the shared one before it built anything (2026-09-27, 8-core Mac, 16 GB). The Mac was quiet before (load 5, CPU 66 to 74% idle). A full `make e2e` ran on `RATP-Shared`, and a QA session booted `RATP-Shared-QA` 20 seconds after the job took the lock, then opened the app. The 1-minute load average went from 13 to 106 during the boot, then to 326 about 15 seconds after the app opened. The CPU was 0% idle for about 90 seconds. The load logger, which writes a line every 5 seconds, wrote nothing twice for about 30 seconds: the Mac did not answer. A safety check then shut down the QA Simulator. The tests passed, but they took 221 seconds instead of 133 to 152 seconds alone. This is above the level of the second slot trial (257 to 286), for which the prompter kept the second slot off. So the QA Simulator was not shipped: QA uses the shared Simulator and its lock, like every job. Limits of the measurement: one run, only the cold case (the QA Simulator boots during the job), and no CPU per process. The warm case (the QA Simulator booted before the job) was not run, so as not to freeze the Mac again. The script of the measurement is `ios/scripts/timing/qa-load-check.sh`. It boots a second Simulator outside the lock, so it never runs on this Mac (see "Never a second Simulator on this Mac"). It stays only to measure on another Mac, when the prompter asks for it. It deletes `RATP-Shared-QA` when it ends.

Why no second Simulator at all: TASK-106 tried a Simulator of its own for `make run`, apart from the Simulator of the jobs, and measured it on 2026-09-28 (8-core Mac, 16 GB). Its boot never ran next to a job: `RATP-Shared` was booted and idle, and no job ran. The first boot of the new Simulator took the 1-minute load average to 333, and the Mac did not answer for about 64 seconds. Two minutes later, a normal `make run SMALL=1` (a cold boot of the existing `RATP-Shared-Small`, with no job next to it) took the load to 234. During the first boot, the Mac used 5.5 to 5.7 GB of swap (6.4 of its 7 GB on the day of the decision, doc-3). So the boot of a second Simulator alone (234 to 333) reaches the levels of TASK-62 (257 to 286, two jobs at once) and TASK-84 (326, a QA Simulator next to a job), and it is close to the freeze of 2026-09-26. For this reason, the prompter decided against every design with a second Simulator on this Mac, and TASK-106 was closed.

Why 3 Software Engineers: the cap was 2 after that day. Two checks now protect the Mac, so the prompter set it back to 3 (2026-09-26). The factory starts a new agent only when at least 25% of the CPU is idle. The Simulator lock and the shared Simulator keep the Simulator jobs to one at a time.

## The shared Simulator

All worktrees use one shared Simulator, named `RATP-Shared`.

- Each job installs its own build of the app. Before that, it removes the app and its data, resets the permissions, sets the text size and the appearance back to the iOS default (Large text, Light), and clears the fake position of the Simulator. So a job never sees the data or the saved settings of another worktree.
- The Simulator stays booted between jobs, so the next job does not wait for a cold boot.
- It shuts down by itself after 5 minutes with no job. Why 5 minutes: it is longer than the usual gap between two jobs (fix a test, then run `make e2e` again; the next agent starts its job). It is short enough to give the Mac back soon when the factory stops. A small background process (`ios/scripts/sim-lock.sh watch`) does this. It uses no Simulator and almost no CPU, and it stops by itself. With the second slot on, it does the same for each slot, with the same delay.
- **The smallest iPhone.** To check a screen on the smallest supported iPhone (375 x 667 pt), run `make run SMALL=1`. It uses a second shared Simulator, `RATP-Shared-Small` (an iPhone SE), through the same lock. A job does not shut down the other shared Simulator of its slot: both can stay booted, but only one job uses a Simulator at a time. `make simulator-shutdown` removes the app from `RATP-Shared-Small` and keeps it booted. The watcher shuts down both after 5 minutes with no job. Why: on 2026-09-27 (TASK-84), each `make run SMALL=1` shut down `RATP-Shared`, and the next job waited for a cold boot of it (the load went to about 125, and that job took about 4 times longer than on a warm Simulator). The prompter decided that a size choice must not force a cold boot of the other size (TASK-92). Never boot another Simulator by hand to check a screen size.
- **A Simulator that something else boots.** While a job or a `make run` holds the lock, the watcher (`ios/scripts/sim-lock.sh watch`) checks every 10 seconds that no other shared Simulator of its slot boots during the job. It shuts down a shared Simulator of the slot that the job does not use and that was not booted when the job took the lock. It keeps the one that was already booted, so the next job of that size finds it warm (TASK-92). Why: on 2026-09-27 (TASK-67), the Simulator panel of the Claude app booted `RATP-Shared` again, while `make run SMALL=1` used `RATP-Shared-Small`. The panel boots the device that it showed last. So do not boot a shared Simulator from the panel or by hand: the watcher shuts it down while a job runs.
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

  To boot the shared Simulator and remove the app of the last job first, run `ios/scripts/sim-lock.sh job ios/scripts/simulator.sh reset <command>`. The lock gives its slot to the command (`RATP_SIM_SLOT`), and `ios/scripts/simulator.sh` uses it. With `xcodebuild`, put `ios/scripts/simulator.sh with-destination` before it, and add `-project ios/RATPActivity.xcodeproj`: it adds the `-destination` of the Simulator of the job. Never name the Simulator (`name=RATP-Shared`), so the command still works when the second slot is on.

`make docs-screenshots` is a Simulator job too: it takes the lock, like `make e2e`, and frees it when the tests end.

`make merge` takes the lock before the rebase and frees it after the fast-forward, success or failure (see "Merge a task into main"). Before that, it takes a merge lock (`/tmp/ratp-merge.lock`, with `lockf`), so only one merge runs at a time, even with two Simulator slots. A `ios/scripts/sim-lock.sh job` that starts inside a job that holds the lock runs at once, in that job's slot: so the `make e2e` of `make merge` does not wait for its own lock. It does not free the lock when it ends: the outer job does.

`make check`, `make test` and `make test-scripts` need no Simulator and no lock.

The lock frees itself when its job dies, when its worktree is removed, or when the Simulator is shut down.

## Which E2E tests to run

The E2E tests must make sure that no breaking bug lands on `main`, and that no agent ever sees a failing test because another agent brought a bug. But a full `make e2e` keeps the shared Simulator for several minutes, and the shared Simulator is the factory's bottleneck. So the factory runs far fewer E2E tests, at the right time:

**`main` is always green.** It holds only tasks that passed review and QA. Each fast-forward of `main` lands on a commit where the full E2E suite passed. The manager runs it on that exact commit, with `make merge`. This is the only full run of a task.

**App code**, for these rules, is what the E2E tests exercise: `ios/App/`, `ios/Widget/`, `ios/Packages/` (except its unit tests), the E2E tests in `ios/UITests/`, and what builds or runs them (`ios/project.yml`, `ios/Config/`, the `Makefile` files, `ios/scripts/`). Docs (`docs/`, `README.md`, `CLAUDE.md`), unit tests (`ios/Packages/RATPCore/Tests/`) and backlog files are not app code.

- **The implementer** runs only the E2E test classes of the flows that it changed: `make e2e ONLY=SnoozeTests`, or `make e2e ONLY="SnoozeTests LiveActivityTests"` for more than one. The class names are the file names in `ios/UITests/`. When its change touches no flow of the E2E tests (for example, a rule that only unit tests cover), it runs no E2E test.
- **A reviewer** runs no E2E test, unless it changes app code. For example, a review with no change, or a change to the docs, the unit tests or the backlog files only, runs none. A reviewer who changes app code runs only the E2E test classes of the flows that its change touches.
- **The manager** runs `make merge` after QA passed the task (see "Merge a task into main"). It runs the full `make e2e` once, after the rebase onto `main`, on the commit that it fast-forwards `main` to. A task that changes only docs or unit tests (no app code) skips the full run: `main` was green, and the task adds no app code. `make merge` sees this by itself.
- **QA** runs no automated tests. It explores the app like a real user.

These rules do not change the rule on flaky tests (below): a failing test may be rerun once, to know if it is flaky.

## Merge a task into main

A task reaches `main` only after QA passed it. The order is:

1. The Software Engineer implements the task on its branch `task/<id>`, and another Software Engineer reviews it.
2. The Software Engineer rebases the branch onto `main`, runs the light gate, and hands the task over to QA. The Software Engineer never merges, and never runs `make merge`.
3. QA tests the branch.
4. When QA passed the task, the manager runs one command in the worktree of the task, one task at a time, instead of the separate steps (rebase, gate, E2E run, fast-forward):

```sh
make merge
```

When the branch changes `docs/`, load Node 24 first: `. "$HOME/.nvm/nvm.sh" && nvm use && make merge`. Run it in the background: it can wait long for the Simulator lock.

It takes the Simulator lock, then does these steps. Each step runs only when the step before it passed:

1. It rebases the branch of the worktree onto the tip of `main`.
2. It runs the quality gate (`make check`).
3. It runs the full E2E suite (`make e2e`), unless the branch changes no app code (see "Which E2E tests to run").
4. It fast-forwards `main` to the rebased branch. When `main` is checked out in a folder (the main folder of the repo), it updates that folder too, with `git merge --ff-only`: a fast-forward, never a merge commit.

Then it frees the lock. When a step fails (a rebase conflict, the gate, the E2E suite), it stops at once, says which step failed, leaves `main` as it was, and frees the lock. After a rebase conflict, the rebase stays in progress: solve it, run `git rebase --continue`, then run `make merge` again. When the folder of `main` has changes that are not committed on the files of the task, the fast-forward fails: commit or stash them, then run `make merge` again. It refuses to start on `main`, with changes that are not committed, with `ONLY=` (the E2E suite is always the full one), or with nothing to merge.

Why one command, with the lock all along:

- **Merges queue one after another.** A second `make merge` waits for the first one (it prints `waiting for the merge of another worktree`), then for the Simulator lock. When its turn comes, `main` already has the first merge, so it rebases onto it. Its fast-forward is never refused because another merge landed during its run.
- **A full E2E run is never repeated.** Before, another merge could land between the end of a full run and the fast-forward. The fast-forward was then refused, and the full suite had to run again after a new rebase.
- **History stays linear, and `main` stays green.** `main` moves only by fast-forward, to the exact commit that passed the gate and the E2E suite. No merge commit: a merge is always a rebase, then a fast-forward.

`make merge` changes only `main` and the branch of the task. It never checks out `main` in the worktree of the task. When it fails, the task goes back to the Software Engineer (status `To Do`, with a comment). The Software Engineer fixes the cause on the branch and hands the task over again. Then the manager runs `make merge` again.

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
- **Budget: at most 60 PRIM calls per QA run.** Write the number of calls you made in your QA notes.

How to count: the app calls PRIM once for each stop area of the station when it opens the next trains, then again every 30 seconds while the app screen is open. Calls = stop areas × (1 + seconds on screen / 30). All the metro lines of a station share one stop area, and an RER stop is one stop area. The stop areas of a station include the stop areas of the other stations of its place (its hub, see the README section "The station list"). Today Châtelet has 2 stop areas (the metro stop area of Châtelet, and the RER stop of Châtelet - Les Halles): 4 calls per minute. Saint-Lazare has 5: 10 calls per minute. A metro station with no hub has 1 stop area: 2 calls per minute.

To stay in the budget:

- Pick a station with few lines and no hub, unless the task needs a big station.
- Check what you need, then run `make simulator-shutdown` at once. The app keeps calling PRIM while it runs, and the shared Simulator stays booted after your job. `make simulator-shutdown` removes the app, so the calls stop. Then remove the key from `ios/.build/` (see above).
- At Châtelet, stay at most 2 minutes on the next trains (10 calls).

Why 60: the public PRIM page of the API "Prochains passages - requête unitaire" gives a quota of 1,000,000 calls per day. But since 13 March 2024, new PRIM accounts get a lower quota by default (users report 1,000 calls per day). We do not know the quota of the prompter's key, so we plan for 1,000 calls per day. 60 calls is 6% of it. After 5 QA runs, the prompter still has more than two thirds of the day's calls. When PRIM answers "too many requests" (HTTP 429), stop at once and tell the manager.
