# Test a change to the iPhone app

This page helps you pick the test that your change needs, run it, and write one when no test covers your change.
Set up the app first ([ios/README.md](../README.md)), and run the commands from the root of the repo.

## Pick the cheapest test that can catch the bug

| Your change | The test | Run it with |
|---|---|---|
| A rule or a value, "this input gives this output": what the Live Activity shows, when it starts or ends, the snooze, how an answer of PRIM, the train data service, is read | a [unit test](#unit-tests) | `make test`, in seconds |
| A place where the app meets iOS: a real Live Activity, a notification, the position, the permission popups, a button of the Live Activity | an [end-to-end test](#end-to-end-tests) | `make e2e ONLY=<class>` ([the classes](#end-to-end-tests)), in minutes |
| How the Live Activity views draw: a cut text, a view too tall | the [render check](#the-render-check-of-the-live-activity) | `make live-activity-render` |
| A script in `ios/scripts/` | a [script test](#script-tests) | `make test-scripts` |
| The look of a screen, real train times, a text in French | look at it yourself with `make run` | |

A change that no rider can see, such as the look of the Testing tools, needs no new test.
`make check` runs the unit tests and the script tests, but not the others.

## Unit tests

The unit tests check the rules, the state and the data of the app, in the `TROMECore` package, with [Swift Testing](https://developer.apple.com/documentation/testing).
They run on your Mac with no Simulator: `make test`.
To run one suite or one test, give its name to `swift test`, with the options of `make test` so that it builds nothing again:

```sh
swift test --package-path ios/Packages/TROMECore --scratch-path ios/.build/TROMECore -Xswiftc -warnings-as-errors --filter TransitLineTests
```

To write one:

- Put it in `ios/Packages/TROMECore/Tests/TROMECoreTests/<Feature>/<Type>Tests.swift`, in the folder of the feature of its code (`Stations`, `Location`, `Trains`, `LiveActivity` or `AutoLiveActivity`), with `@testable import TROMECore`.
- Read a recorded PRIM answer from `contracts/prim/` with `Fixture.data(_:)`, such as `Fixture.data("stop-monitoring-abbesses")`.
- Give a service of iOS, such as the position or ActivityKit, a fake of the small protocol that `TROMECore` declares for it.
- Give the test the time zone, the locale and the date it needs: the settings of your Mac are not the ones of the next Mac.
- The tests run on macOS, so put any code that only iOS has inside `#if os(iOS)`.

## End-to-end tests

The end-to-end tests run the real app in the Simulator, and look at what iOS shows: the Live Activity in the Notification Center, a notification, a popup.
They are slow, so run only the classes of the flows that your change touches; the class names are the file names in `ios/UITests/`:

```sh
make e2e ONLY=SnoozeTests
make e2e ONLY="SnoozeTests LiveActivityTests"
```

`make e2e` alone runs them all, in a few minutes.
The tests have no train data key, so the Live Activity says "No data available" unless a test asks for fake trains.
On a failure, `make e2e` prints the file, the line and the message; open `ios/.build/e2e.xcresult` in Xcode for the full results.

| Class | What it checks on the real iOS |
|---|---|
| `LiveActivityTests` | The location popups come in order, then the app starts and ends a real Live Activity. |
| `AutoLiveActivityTests` | A position from iOS starts, switches and ends the Live Activity, also with the app in the background. |
| `ArrivalNotificationTests` | The arrival notification, its tap and its **Not for 1 h** action, and the app opened at the station. |
| `SwipeAwayTests` | A swipe of the Live Activity pauses its station only, and cancelling the pause brings it back. |
| `SnoozeTests` | The widget draws the trains on the real Live Activity, and its buttons run in the app. |

The wake of a closed app at a station has no test, because the Simulator cannot watch regions: check it on an iPhone.

### Write one

Add one only where the app meets iOS and no unit test can see the bug; a new step for a flow that a class covers goes in that class.

- Start the file with a comment that says what it checks on the real iOS, and why a unit test cannot.
- Look at what the rider sees, such as the Live Activity, not at a label of the app, which only repeats what the app believes.
- Set the scene with iOS (`moveThePhone(to:)`) or a launch argument, not by tapping through the app or the Testing tools.
- Give each test its own stations, and wait for what the app or iOS shows, never for a fixed time.

Each class inherits from `E2ETestCase` ([`ios/UITests/E2ETestCase.swift`](../UITests/E2ETestCase.swift)):

| Helper | What it does |
|---|---|
| `makeApp()`, `launch(_:)` | Make the app with a clean state, launch it, and answer the permission popups. Use them, not `app.launch()`. |
| `waitFor(_:)`, `waitForNo(_:)`, `tap(_:)` | Wait up to 30 seconds for an element to show or to go, or before a tap. |
| `moveThePhone(to:)` | Sets the position of the Simulator, which the app reads through its real Core Location code. |
| `openNotificationCenter(over:)`, `liveActivityStation(_:)` | Open the Notification Center, where the Live Activity shows as on the lock screen, and find a station in it. |
| `tapOnTheLiveActivity(_:)` | Waits until a button of the Live Activity stops moving, then taps it. |

In debug builds, `--fake-trains` gives fake trains with no call to PRIM, and `--fake-trains at-platform` a train at the platform at once ([the other states](../README.md#test-it-with-a-fake-position)).
`--keep-running-in-background` keeps the app awake in the background, so that a new position reaches it.

## The render check of the Live Activity

`make live-activity-render` draws the Live Activity views for every station, and lists the views that are too tall and the texts that are cut ([Check how the Live Activity draws](../README.md#check-how-the-live-activity-draws)).
Run it before and after a change to these views, and compare: it reports, and never fails on a cut text.

## Script tests

`make test-scripts` runs `ios/scripts/tests/<name>-test.sh`; the tests of the Simulator scripts use a fake `xcrun`, so they need no Simulator.
The server has [its own tests](../../server/README.md).

## When a test fails only sometimes

A test that fails, then passes with no change, is a bug: run it again once to know.
If it covers your change, find the cause, such as a race or a missing wait, and fix it: a retry or a longer timeout only hides it.
If it does not, open an issue with the name of the test, how often it failed, and its error.
