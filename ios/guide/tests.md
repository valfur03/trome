# Test a change to the iPhone app

The app has three kinds of automatic tests, and each one catches bugs that the others cannot see.
This page helps you pick the test that your change needs, run it, and write a new one when no test covers your change.
Run the commands from the root of the repo; the paths on this page start there too.

## Pick the cheapest test that can catch the bug

Ask what a rider could lose if your change were wrong, then pick the cheapest test that can really see it.
A unit test runs in seconds on your Mac, while an end-to-end test needs the iPhone Simulator for minutes.

| Your change | The test | Run it with |
|---|---|---|
| A rule or a value that you can write as "this input gives this output": what the Live Activity shows, when it starts, switches or ends, the snooze, how a PRIM answer is read | a [unit test](#unit-tests) in `TROMECore` | `make test` |
| A place where our code meets iOS: ActivityKit starts or ends a real Live Activity, the widget draws it, a notification opens the app, the position from iOS reaches the rules, the permission popups come in order | an [end-to-end test](#end-to-end-tests) | `make e2e ONLY=<class>` |
| How the Live Activity views draw: a text cut with "…", a view too tall for the lock screen | the [render check](#the-render-check-of-the-live-activity) | `make live-activity-render` |
| A script in `ios/scripts/` | a [script test](#script-tests) | `make test-scripts` |
| The look of a screen, real train times, how a text reads in French, what happens over time in the background | no script can judge it: look at it yourself with `make run`, in French too | |

A change that no rider can see, such as the look of the Testing tools, needs no new test.
`make check` runs the unit tests and the script tests, but not the end-to-end tests or the render check.

## Unit tests

The unit tests check the rules, the state and the data of the app, which all live in the `TROMECore` package.
They use [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`, `#expect`), and run on your Mac with no Simulator:

```sh
make test
```

The first run builds the package and takes about a minute; after that, a run takes seconds.
To run one suite, or one test such as `TransitLineTests/keepsTheStopsOfALineThatHasThem`, give its name to `swift test`, with the same options as `make test` so that it does not build everything again:

```sh
swift test --package-path ios/Packages/TROMECore --scratch-path ios/.build/TROMECore -Xswiftc -warnings-as-errors --filter TransitLineTests
```

To write one:

- Put it in `ios/Packages/TROMECore/Tests/TROMECoreTests/<Feature>/<Type>Tests.swift`, next to the tests of the same type, and import the package with `@testable import TROMECore`.
  The feature folders have the same names as in `ios/Packages/TROMECore/Sources/TROMECore/`: `Stations`, `Location`, `Trains`, `LiveActivity` and `AutoLiveActivity`.
- Read a recorded PRIM answer from `contracts/prim/` with `Fixture.data(_:)`, for example `Fixture.data("stop-monitoring-abbesses")`.
  The tests of the server read the same files, so the app and the server agree on what PRIM sends.
- For a service of iOS, such as the position or ActivityKit, `TROMECore` declares a small protocol, and the test gives it a fake.
- Since the tests run on macOS, `TROMECore` must build there: put any code that only iOS has inside `#if os(iOS)`.
- Give a test the time zone, the locale and the date that it needs, such as `TimeZone(identifier: "Europe/Paris")`: the tests run with the settings of your Mac, which differ from one Mac to the next.
- A warning fails the build of the tests, as it fails the build of the app.

## End-to-end tests

The end-to-end tests run the real app in the iPhone Simulator with XCUITest, and look at what iOS shows: the Live Activity in the Notification Center, a notification, a permission popup.
They are slow, so each one guards a single place where our code meets iOS, where a fake would hide the bug.

### Run them

```sh
make e2e
```

This runs them all, which takes a few minutes.
While you work on a change, run only the classes of the flows that it touches.
The class names are the file names in `ios/UITests/`:

```sh
make e2e ONLY=SnoozeTests
make e2e ONLY="SnoozeTests LiveActivityTests"
make e2e ONLY=AutoLiveActivityTests/testLiveActivityStartsSwitchesAndStopsByItselfNearStations
```

`make e2e` builds the tests first, then waits for the Simulator when another job uses it (see [one Simulator job at a time](../README.md#one-simulator-job-at-a-time)).
The tests build with no train data key, so the Live Activity says "No data available" unless a test asks for fake trains.

When a test fails, `make e2e` prints the file, the line and the message of each failure, and the full results are in `ios/.build/e2e.xcresult`, which Xcode opens.
It stops a test that runs longer than 5 minutes.
If it says that the Mac slept during the tests, run the same command again before you look for a bug: the Simulator stops while the Mac sleeps, but the waits of the tests go on counting.

### What each class guards

Each file in `ios/UITests/` starts with a comment that names its seam with iOS, and says why a cheaper test cannot see it.

| Class | What it checks with the real iOS | Why a unit test cannot see it |
|---|---|---|
| `LiveActivityTests` | The location popups of iOS come in order, then the app starts a real Live Activity of the nearest station, and ends it. | Only iOS shows its popups, gives a position, and starts and ends a Live Activity. |
| `AutoLiveActivityTests` | A position from iOS reaches the rules, and the Live Activity starts, switches station and ends by itself, the last two with the app in the background. | The unit tests use a fake position and a fake ActivityKit. |
| `ArrivalNotificationTests` | The arrival notification comes while the app is in the background; a tap opens the app with the Live Activity; its **Not for 1 h** action snoozes without opening the app; opening the app at the station starts the Live Activity with no tap. | Only iOS delivers a notification, shows its actions, and opens the app or not. |
| `SwipeAwayTests` | A swipe of the real Live Activity pauses its station but not the next one, and cancelling the pause brings the Live Activity back while the phone stands still. | Only iOS removes a Live Activity on a swipe and tells the app, and only Core Location decides whether a new position comes. |
| `SnoozeTests` | The widget draws the trains on the real Live Activity (both directions, a train at the platform, a branch, the ends of a fork, the next line), and its buttons run in the app. | Only the widget process draws the views, and only iOS runs the intent of a button. |

One thing has no end-to-end test: the wake of a closed app when the rider reaches a station.
The Simulator cannot watch regions, so check it on an iPhone.

### Write one

Add an end-to-end test only for a place where our code meets iOS and no unit test can see the bug.
A new step for a seam that a class already covers goes in the test of that class.

- **Start the file with its seam:** a comment that says what it checks with the real iOS, and why a cheaper test cannot see it.
- **Look at what the rider sees,** such as the Live Activity in the Notification Center, not at a label of the app, which only repeats what the app believes.
  A label of the app can be a point to wait for, but not the proof.
- **Set the scene with iOS or a launch argument,** such as `moveThePhone(to:)` or `--fake-trains`, not by tapping through the app or the Testing tools.
- **Fake only what is not under test.** `--fake-trains` replaces the PRIM train data, which changes all the time and has a daily quota.
- **Give each test its own stations,** so that no test depends on what another one left behind.
- **Wait for something that the app or iOS shows, never for a fixed time.** After a move of the phone, wait for what the new position changes, such as the Live Activity, before the next step.

Each class inherits from `E2ETestCase`, which stops a test at its first failure and gives these helpers:

| Helper | What it does |
|---|---|
| `makeApp()` | Moves the phone far from any station, stops the app of the previous test (also when iOS starts it again in the background), and adds `--reset-location-source`, so that no test keeps the fake position or the fake trains of an earlier one. |
| `launch(_:)` | Launches the app and answers the permission popups that come, such as the notification question and the request for **Always**. `make e2e` has already allowed the location **While Using the App**. Use it instead of `app.launch()`. |
| `answerPermissionPrompts(in:)` | Answers the real location popups, and checks that iOS asked for **Always** right after the first question. Only `LiveActivityTests` uses it, after it resets the location permission. |
| `waitFor(_:)`, `waitForNo(_:)`, `waitForFirst(of:)` | Wait for an element to show, to go, or for the first of several to show. They wait up to `UITestTimeout.element` (30 seconds, because a busy Mac is slow), and return at once when the element is already there. |
| `tap(_:)` | Waits for the element, then taps it. |
| `moveThePhone(to:)` | Sets the position of the Simulator (`XCUIDevice.location`), which the app reads through its real Core Location code. `E2ETestCase.farFromAnyStation` is a point far from every station. |
| `openNotificationCenter(over:)`, `closeNotificationCenter()` | Pull the Notification Center down over the app, where the Live Activity shows as on the lock screen, and close it. |
| `liveActivity`, `liveActivityStation(_:)`, `liveActivityElement(containing:)` | The Live Activity in the Notification Center, and the elements in it. |
| `tapOnTheLiveActivity(_:)` | Waits until a button of the Live Activity stops moving, then taps it. |

The debug builds of the app take these launch arguments for the tests:

| Argument | What it does |
|---|---|
| `--fake-trains` | Fake next trains instead of PRIM, with no call to PRIM. Add the name of a state after it, such as `--fake-trains at-platform`, to get a train at the platform at once ([the states](../README.md#test-it-with-a-fake-position)). |
| `--keep-running-in-background` | Keeps the app awake in the background with no Live Activity, so that a new position reaches it before iOS suspends it. |
| `--reset-location-source` | Drops the fake position of the Testing tools, so that the app uses the position of iOS. `makeApp()` adds it. |

## The render check of the Live Activity

`make live-activity-render` draws the Live Activity views for every station, and lists the views that are too tall and the texts that are cut ([Check how the Live Activity draws](../README.md#check-how-the-live-activity-draws)).
Run it before and after a change to these views, and compare what it lists: it reports, and never fails on a cut text.

## Script tests

Each script of `ios/scripts/` that a `make` command runs has a test, `ios/scripts/tests/<name>-test.sh`:

```sh
make test-scripts
```

The tests of the Simulator scripts use a fake `xcrun` (in `ios/scripts/tests/bin/`), so they need no Simulator.
The server has its own tests: see [server/README.md](../../server/README.md).

## When a test fails only sometimes

A test that fails, then passes with no change, is a bug, in the test or in the app.
Run it again once, to know whether it is flaky.
If the test covers your change, find the cause and fix it in your change: a race, a state that another test left behind, or a missing wait for a condition.
A retry or a longer timeout alone hides the bug, and the next person meets it again.
If the test does not cover your change, open an issue with the name of the test, how often it failed, and its error.
