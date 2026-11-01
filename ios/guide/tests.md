# Test a change to the iPhone app

This page helps you pick the test that your change needs, run it, and write one when no test covers your change.
Set up the app first ([ios/README.md](../README.md)), and run the commands from the root of the repo.
Each step of a test command prints one line when it passes and its whole output when it fails, and keeps that output in `.build/logs/` of its part; add `VERBOSE=1` to the command to see every line as it runs.

## Pick the cheapest test that can catch the bug

| Your change | The test | Run it with |
|---|---|---|
| A rule or a value, "this input gives this output": what the Live Activity shows, when it starts or ends, the snooze, how an answer of PRIM, the train data service, is read | a [unit test](#unit-tests) | `make test`, in seconds |
| A place where the app meets iOS: a real Live Activity, the position, the permission popups, a button of the Live Activity | an [end-to-end test](#end-to-end-tests) | `make e2e ONLY=<class>` ([the classes](#end-to-end-tests)), in minutes |
| How the Live Activity views draw: a cut text, a view too tall | the [render check](#the-render-check-of-the-live-activity) | `make live-activity-render` |
| A script in `ios/scripts/` | a [script test](#script-tests) | `make test-scripts` |
| The look of a screen, real train times, a text in French | look at it yourself with `make run` | |

A change that no rider can see, such as the look of the Testing tools, needs no new test.
`make check` runs the unit tests and the script tests, but not the others.

## Unit tests

The unit tests check the rules, the state and the data of the app, in the `TROMECore` package, with [Swift Testing](https://developer.apple.com/documentation/testing).
They run on your Mac with no Simulator: `make test`.
The same command runs the test of the line badge, `LineBadgeViewTests`: it draws the badge of every line at the size of each surface, and fails when a label does not look centred (the weight of the ink of a metro number across, the box otherwise), a metro badge is not round, or a colour is not the colour of the line.
To run one suite or one test, give its name to `swift test`, with the options of `make test` so that it builds nothing again:

```sh
swift test --package-path ios/Packages/TROMECore --scratch-path ios/.build/TROMECore -Xswiftc -warnings-as-errors --filter TransitLineTests
```

To write one:

- Put it in `ios/Packages/TROMECore/Tests/TROMECoreTests/<Feature>/<Type>Tests.swift`, in the folder of the feature of its code (`Stations`, `Location`, `Trains`, `LiveActivity` or `AutoLiveActivity`), with `@testable import TROMECore`.
- Read a recorded PRIM answer from `contracts/prim/` with `Fixture.data(_:)`, such as `Fixture.data("stop-monitoring-abbesses")`.
- When a change of the app changes the content of the Live Activity or the rules of a line, `LiveActivityContentContractTests` fails: the server builds the same content for a start, from `contracts/live-activity/`.
  Run it with `LIVE_ACTIVITY_CONTRACT_WRITE=1` to write the new contents and line data, then change the server in the same change until `make server-check` passes.
- When a change of a value that the app keeps on the phone (Automatic mode, the Live Activity that it follows, its last times, the line page that the rider tapped to) or of the content of the Live Activity would make an update forget it, `PhoneSetTests` fails: it reads the values that each build in the field wrote, from `contracts/phone/`.
  Make the new code read them; never edit a recorded set.
  `PhoneSetRecorder` records the set of a new build at its upload (`make phone-set-record`).
- Give a service of iOS, such as the position or ActivityKit, a fake of the small protocol that `TROMECore` declares for it.
- Give the test the time zone, the locale and the date it needs: the settings of your Mac are not the ones of the next Mac.
- The tests run on macOS, so put any code that only iOS has inside `#if os(iOS)`.
- To wait for work that runs in the background, use `waitUntil { ... }`, and wait for the state that your next check reads, never for an earlier step: the code under test may not have caught up yet.
  The wait fails at its own line when its condition never holds.
  To check that something does not happen, such as one more call, use `expectNever { ... }`.
- `make check` runs the tests of the test files that you changed with `make test-waits`: 3 times with waits that look again at once, as when the code under test runs late on a busy Mac, and 3 times with waits that look again after 50 ms, as when the test itself runs late.
  A test that passes in `make test` and fails there waits for one thing and checks another.
  To replay one failure, run `swift test` as above with `TROME_TEST_WAITS=eager` or `TROME_TEST_WAITS=late` in front.
- The `make` commands run at most as many unit tests at once as the Mac has cores (`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH`, set in `ios/Makefile`).
  Without it, Swift Testing starts every test at once, and the tests of the main actor share its one thread, so on a busy Mac a wait runs out of time while that thread serves hundreds of other tests.
  When many waits of one run fail at the same moment, the whole run was slow, not one test.
  To make a run slow without loading the Mac, put `taskpolicy -b` in front of the command: it runs at the lowest priority of macOS, on fewer and slower cores.

## End-to-end tests

The end-to-end tests run the real app in the Simulator, and look at what iOS shows: the Live Activity in the Notification Center, a popup.
They are slow, so run only the classes of the flows that your change touches; the class names are the file names in `ios/UITests/`:

```sh
make e2e ONLY=SnoozeTests
make e2e ONLY="SnoozeTests LiveActivityTests"
```

`make e2e` alone runs them all, in a few minutes.
It builds the tests first, then waits for the shared Simulator only to run them: `make e2e-build` does only the build, and `make e2e NO_BUILD=1` then runs the tests of that build.
Once a day, a run may first wait a few minutes for iOS to update its wallpapers, which keeps the Simulator so busy that a test next to it can fail.
The tests have no train data key, so the Live Activity says "Times unavailable" unless a test asks for fake trains.
On a pass, `make e2e` prints the counts of the tests and their time.
On a failure, `make e2e` prints the file, the line and the message; open `ios/.build/e2e.xcresult` in Xcode for the full results.
A failed run also keeps its log, its `.xcresult`, the Simulator log of the run, the crash reports of the app and its context (the load of the Mac, the tests in the order they ran) in `~/Library/Logs/TROME/e2e-failures/`, one folder per run, and prints that folder.
The next run and a new worktree do not touch it, so the evidence of a flaky failure stays; it keeps the 20 newest runs.
A failed `make docs-screenshots` keeps its evidence in the same folder.

| Class | What it checks on the real iOS |
|---|---|
| `LiveActivityTests` | The real location popups, then a Live Activity that starts with the app open at a station and that "Snooze" ends. |
| `AutoLiveActivityTests` | A position from iOS starts the Live Activity, then switches and ends it in the pocket: the location "Always", the app in the background long after iOS stops the position stream, and no launch argument of the tests. |
| `BackgroundArrivalTests` | No notification of the app at an arrival in the background, and the Live Activity when the rider then opens the app at the station. |
| `SwipeAwayTests` | A swipe of the Live Activity pauses its station only, and cancelling the pause brings it back. |
| `SnoozeTests` | The widget draws the trains on the real Live Activity, and its buttons run in the app. |
| `BackgroundPositionTests` | With no Live Activity, the app in the background follows no position: a phone that rides through a station at the speed of a train brings no arrival. |

The paths of the automatic start that no test can run in the Simulator, and what checks them instead, are in [the test flags](#the-test-flags-and-a-riders-path).

### Write one

Add one only where the app meets iOS and no unit test can see the bug; a new step for a flow that a class covers goes in that class.

- Start the file with a comment that says what it checks on the real iOS, and why a unit test cannot.
- Look at what the rider sees, such as the Live Activity, not at a label of the app, which only repeats what the app believes.
- Set the scene with iOS (`moveThePhone(to:)`) or a launch argument, not by tapping through the app or the Testing tools.
- Give each test its own stations, and wait for what the app or iOS shows, never for a fixed time.
- When a test changes the Simulator position, wait for what the new position changes before the next step (the position reaches the app some time later): the Live Activity in the Notification Center, or the app label "On the lock screen: <station>" before the test leaves the app.

Each class inherits from `E2ETestCase` ([`ios/UITests/E2ETestCase.swift`](../UITests/E2ETestCase.swift)):

| Helper | What it does |
|---|---|
| `makeApp()`, `launch(_:)` | Make the app with a clean state, launch it, and answer the permission popups. Use them, not `app.launch()`. |
| `resetLocationAuthorization(of:)` | Resets the location permission, so that the next launch shows the real popups. Use it, not `app.resetAuthorizationStatus(for: .location)`: on the reset, iOS may start the app in the background, and a launch at that moment fails with "No such process". |
| `waitFor(_:)`, `waitForNo(_:)`, `tap(_:)` | Wait up to 30 seconds for an element to show or to go, or before a tap. |
| `moveThePhone(to:)` | Sets the position of the Simulator, which the app reads through its real Core Location code. |
| `openNotificationCenter(over:)`, `liveActivityStation(_:)` | Open the Notification Center, where the Live Activity shows as on the lock screen, and find a station in it. |
| `bringToFront(_:)` | Opens the app again, and waits until the Notification Center no longer covers it. Use it, not `app.activate()`: iOS drops a tap while the Notification Center still slides away. |
| `tapOnTheLiveActivity(_:)` | Waits until the tap point of a button of the Live Activity stays on the card on screen, then taps that point. The frame of a widget element is in the card's own space, so the frame alone does not show the card move. |

In debug builds, `--fake-trains` gives fake trains with no call to PRIM, and `--fake-trains at-platform` a train at the platform at once ([the other states](testing-tools.md#ask-for-a-train-at-the-platform-or-another-state)).
A test of the Live Activity in the pocket uses no launch argument that changes a rider's path ([the list](#the-test-flags-and-a-riders-path)).
`makeApp()` adds `--end-live-activity` (debug builds only): at launch, the app ends the Live Activity that the last test left, so each test starts with none, and no test taps a button of the app to end it.
Before it kills the app of the last test, `makeApp()` sends it to the background and waits until it ends its position stream and its background sessions (debug builds only, `E2ETestCase+LocationEnd.swift`).
Why: iOS keeps the stream of an app killed while it streams, and starts the app again to serve it, so a launch at that moment fails with "No such process".

### The test flags and a rider's path

A launch argument or a Testing tool that changes what the app does on a rider's path is in this list, with the test that runs the same path without it, or why the Simulator cannot.
Why: `--keep-running-in-background` once kept the app following the position in the pocket, so the tests passed while the Live Activity never switched on a phone.

| Flag | What it changes | The tests that use it | The same path without it |
|---|---|---|---|
| `--keep-running-in-background` | The app stays awake and follows the position in the background for the whole run, in place of the wake for the area of a station. | `BackgroundArrivalTests`: with no Live Activity, nothing else brings a position to the app in the background. | None in the Simulator: see the arrival in the background below. |
| `--fake-trains [state]` | Fake trains in place of PRIM. | `SnoozeTests`: the boxes and the buttons need trains, and PRIM has a daily quota and data that changes. | The other classes run with no train data ("Times unavailable"); the real answers are unit tests of `contracts/prim/`, and a look with `make run`. |
| `--content-as-the-server` | Every content of the Live Activity is the one that the server pushes. | `SnoozeTests`, for the page that a tap chose. | The other classes send the content of the app; `LiveActivityContentContractTests` and the server tests check that both are the same. |
| `--end-live-activity` | At launch, the app ends the Live Activity of the last test. | Every class, through `makeApp()`. | No test launches the app while a Live Activity shows (iOS ended the app, then started it again): `AutoLiveActivityModelTests` checks it. |
| A fake position (Testing tools) | Always trusted; iOS never sees it, and the app watches no area. | None: `--reset-location-source` (every class) puts back the real GPS. | Every class: the Simulator position, read through Core Location. |
| A Live Activity shown by hand (Testing tools) | It starts far from its station, and ends at 250 m only after the phone came near. | None. | `AutoLiveActivityTests`. |
| `-liveActivityMaximumDuration`, `-exampleDuration` | Shorter limits than the 45 minutes and the 10 minutes of the example. | None. | No test waits 45 minutes: the unit tests of the rules check the end. |
| A Debug build | No [silent start](auto-live-activity.md#the-silent-start): a Simulator build does not ask the server, and a real server pushes only to the Release build. | Every class. | None in the Simulator: `AutoLiveActivitySilentStartTests`, the server tests, and a [walk with a TestFlight build](testing-tools.md#record-a-walk-with-a-testflight-build). |

`--hide-testing-tools` only hides the link of the Testing tools, for the store pictures, and the wake log only reads: they change no path.
iOS never suspends an app that a test launched, so no test sees the app suspended or ended in the background.

| Path of the automatic start | The test that runs it as on a rider's phone (only `makeApp()` flags) | What checks it when the Simulator cannot |
|---|---|---|
| The start with the app open | `AutoLiveActivityTests`, `LiveActivityTests` | |
| The switch in the pocket | `AutoLiveActivityTests` | |
| The end in the pocket | `AutoLiveActivityTests` | |
| The arrival in the background | None: on a phone, the wake for the area of the station starts it, and the Simulator cannot watch areas (`isMonitoringAvailable` is false). | `BackgroundArrivalTests` with `--keep-running-in-background`: no notification, then the Live Activity once the rider opens the app. The unit tests of a reported arrival (`ReportedArrivalRulesTests`, `AutoLiveActivitySecondChanceTests`, `AutoLiveActivityRestartTests`) and of the silent start. The wake log of a walk. |
| The wake of a closed app at a station | None, for the same reason. | The unit tests of the watched areas (`StationRegionPlanTests`, `StationRegionSyncTests`, `WakeProcessTests`), and the wake log of a walk. |

## The render check of the Live Activity

`make live-activity-render` draws the Live Activity views for every station, and lists the views that are too tall and the texts that are cut ([what it reports and what it cannot see](render-check.md)).
Run it before and after a change to these views, and compare: it reports, and never fails on a cut text.

## Script tests

`make test-scripts` runs `ios/scripts/tests/<name>-test.sh`; the tests of the Simulator scripts use a fake `xcrun`, so they need no Simulator.
A script test that runs `swift`, `swiftc` or `xcodebuild` (directly or through `xcrun`) runs itself through the build gate, as the first lines of `store-screenshots-test.sh` do: a Swift compile slows a Simulator test run of the same Mac, so `make test-scripts` fails on such a call outside the gate.
The server has [its own tests](../../server/README.md).

## When a test fails only sometimes

A test that fails, then passes with no change, is a bug: run it again once to know.
If it covers your change, find the cause, such as a race or a missing wait, and fix it: a retry or a longer timeout only hides it.
If it does not, open an issue with the name of the test, how often it failed, and its error.
The folder that the failed run printed (in `~/Library/Logs/TROME/e2e-failures/`) holds the evidence: its `simulator.log` shows what iOS did around the failure, such as a launch or an end of the app.
Its `context.txt` also says how long iOS took to run each tap on a Live Activity button, and names a tap that took more than 30 s: iOS starts a new process for each tap before the app gets it, and a busy Mac can delay that start past the wait of a test.
It also says how long iOS took to draw the Live Activity, and names each draw that iOS stopped at its watchdog of about 10 s: the Live Activity then keeps the last content that iOS drew.
It also names the heavy background tasks that iOS ran during the run, such as its daily update of the wallpapers.
`mac-load.log` holds the load of the Mac and its 5 busiest processes every 10 s of the run, so that it shows what kept the Mac busy at the moment of the failure.
