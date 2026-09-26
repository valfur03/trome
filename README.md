# RATP Activity

An iPhone app. It shows the next metro and RER trains of the nearest Paris station on the lock screen, as a Live Activity.

## What you need

- A Mac with Xcode 27.
- Homebrew (https://brew.sh).
- For your iPhone only: a free Apple ID and a USB cable.

## First setup

Open Terminal in this folder. Run:

```sh
make setup
```

This installs two tools with Homebrew (XcodeGen and SwiftLint). Then it creates the Xcode project `RATPActivity.xcodeproj`.

The Xcode project is not in git. The file `project.yml` describes it. If you change `project.yml`, run `make generate`.

## Everyday commands

| Command | What it does |
|---|---|
| `make run` | Builds the app and opens it in the Simulator, without the train data key. |
| `make run LIVE=1` | The same, with your train data key (see below). |
| `make check` | The quality gate: lint, key leak check, build, and unit tests. Run it before each commit. |
| `make e2e` | The end-to-end tests. They open the app in the Simulator. |
| `make lint-fix` | Fixes the lint problems that SwiftLint can fix alone. |
| `make stations` | Downloads the metro and RER station list again (see below). |
| `make clean` | Deletes the build folder and the Xcode project. |
| `make help` | Shows all the commands. |

## Run on the Simulator

```sh
make run
```

`make run` does not use your train data key. The app shows no trains, and it says "Train data key: not set". To see live trains, run `make run LIVE=1` (see [The train data key](#the-train-data-key-prim)).

The app opens in the Simulator. You need no Apple ID for this.

All copies of the repo (all folders) use one shared Simulator, named `RATP-Shared`. To see its ID, run `make simulator`.

- `make run` and `make e2e` remove the app and its data from the Simulator, then install the app of this folder. So a folder never sees the data or the saved settings of another folder. They also reset the permissions and clear the fake position of the Simulator.
- The Simulator stays booted between jobs, so the next job starts faster. It shuts down by itself after 5 minutes with no job.
- To delete the shared Simulator, run `make simulator-delete`. The next job creates it again.

Only one Simulator job (`make run`, `make e2e`) runs at a time on the Mac. The others wait and say so. After `make run`, run `make simulator-shutdown` when you are done, so the others can go on. This frees the lock. It does not shut down the Simulator at once.

Before the shared Simulator, each folder had its own Simulator, named `RATP-<folder>-<hash>`. To delete these old Simulators, run `make simulator-delete-old`.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

## Fake your position (testing tools)

Debug builds have a "Testing tools" screen. `make run` and the Run button in Xcode make debug builds. Release builds do not have this screen.

1. Open the app. Tap "Testing tools" at the top right of the screen.
2. Choose a fake position:
   - "Pick a station": choose a metro or RER station from a list.
   - "Far from any station": a point in the Fontainebleau forest, far from any metro or RER station.
   - "Coordinates": type the latitude, then the longitude, for example `48.8584, 2.2945`. Tap "Use these coordinates".
   - "Address": type an address, for example `10 rue de Rivoli, Paris`. Tap "Find this address". This needs the network.
3. The section "Position used by the app" shows the position that every feature uses.
4. To stop faking, tap "Use the real GPS".

The app keeps your choice when you close it. While a fake position is on, the main screen shows "Fake position" in orange.

This works in the Simulator and on your iPhone, also when the iPhone is not connected to the Mac.

For developers: all code must read the position from `LocationService` (in `RATPCore`), never from Core Location directly. Then the fake position works for every feature.

## The station list

The app finds the nearest station without the network. It reads the file `Packages/RATPCore/Sources/RATPCore/Resources/stations.json`.

This file lists every metro station (lines 1 to 14, 3bis and 7bis) and every RER station (lines A to E). It has no bus, tram or Transilien stop. The data comes from the open data of Île-de-France Mobilités (dataset `arrets-lignes`, no key needed).

To see the list in the app, open "Testing tools" and tap "All stations". Each station shows its lines. Type part of a name in the search field to find a station. The search ignores case, accents and hyphens: `chatelet` finds "Châtelet".

To download the list again, run `make stations`. It needs Python 3. Commit the new `stations.json`.

Some names in the open data are wrong or spelled in two ways. The script fixes them with the table `STATION_NAMES` in `scripts/update-stations.py`. If a unit test says that two stations "look like the same station", add the bad name to this table.

## Next trains of a station

The main screen shows the next trains of a station that you pick by hand. This needs no location permission.

1. Under "Next trains", tap "Pick a station". Type part of a name to find a station, then tap it.
2. The screen shows the next trains of each line and destination, in minutes. The app asks for new times every 30 seconds while the screen is open.
3. Tap "Change station" to pick another station.

The app remembers the picked station when you close it.

The screen tells you when:

- the train data key is not set (see below),
- the station has no live data right now,
- the app cannot reach the train data service (for example, no internet),
- the service refuses the key, gets too many requests, or does not work.

For developers: the code is in `Packages/RATPCore/Sources/RATPCore/Trains`. `PRIMDeparturesProvider` calls the PRIM API "stop-monitoring" once for each stop of the station. A metro stop id `IDFM:<n>` becomes `STIF:StopPoint:Q:<n>:`. An RER stop id `IDFM:monomodalStopPlace:<n>` becomes `STIF:StopArea:SP:<n>:`. `CurrentStationModel` holds the station that the user picked. Other features (for example the Live Activity) can use it.

## Show the next trains on the lock screen (Live Activity)

The app can show the next train of the picked station on the lock screen, as a Live Activity. On an iPhone with a Dynamic Island, it also shows there.

1. Pick a station (see above).
2. Tap "Show on the lock screen".
3. Lock the phone. The Live Activity shows the station, the line, the direction, and the waiting time of the next train.
4. To remove it, open the app and tap "Stop showing on the lock screen".

The first time, iOS asks on the lock screen if it can show Live Activities from RATP Activity. Tap "Allow".

The waiting time counts down by itself. The app sends new train times only while its screen is open. When the shown train has left, the Live Activity hides its waiting time and says "Open the app for new times". It says the same if the train times take more than a minute to load. If the app has no train times for the station, the Live Activity says "No data available".

If the app says that Live Activities are turned off, turn them on in Settings > RATP Activity > Live Activities.

For developers: `StationActivityAttributes` (in `RATPCore`) holds the data of the Live Activity. `StationLiveActivityModel` starts, updates and stops it. The view is in `Widget/StationLiveActivity.swift`.

## The train data key (PRIM)

The app gets train times from the PRIM API of Île-de-France Mobilités. PRIM needs a free key.

The app builds and runs without the key. The app screen says "Train data key: not set".

To add the key:

1. Create a free account on https://prim.iledefrance-mobilites.fr.
2. In your account page, create an API key.
3. In the main folder of the repo, copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.
4. Put your key after `PRIM_API_KEY =`.
5. Run `make run LIVE=1`. The app screen now says "Train data key: set", and it shows live trains.

Always add `LIVE=1` when you want live trains. A plain `make run` does not use your key, also in the main folder.

Git ignores `Config/Secrets.xcconfig`. Never commit your key.

Only the main folder needs `Config/Secrets.xcconfig`. In a git worktree, `make run LIVE=1` finds the key in the main folder with git. It does not copy the file. If the main folder has no `Config/Secrets.xcconfig`, `make run LIVE=1` stops and says so.

The other `make` commands (`make run` without `LIVE=1`, `make check`, `make e2e`) never use the key: they build with `Config/NoKey.xcconfig`. Then the tests do not use your PRIM quota. The Run button in Xcode uses the key of the folder that you open.

The build output never shows the key. `make live-key-check` proves it with a fake key. `make check` runs it.

## Install on your iPhone (free Apple ID)

You do these steps one time.

1. **Add your Apple ID to Xcode.** Open Xcode. Go to Xcode > Settings > Accounts. Click `+` and sign in. Xcode creates a "Personal Team" for you.
2. **Find your Team ID.** In Xcode > Settings > Accounts, select your team. The Team ID has 10 letters and digits. You can also find it at https://developer.apple.com/account, under Membership details.
3. **Create your local settings.** Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`. Fill in:
   - `DEVELOPMENT_TEAM`: your Team ID.
   - `RATP_BUNDLE_ID_PREFIX`: a name that only you use, for example `io.github.your-github-name`. Do not keep `com.example`.

   Git ignores `Config/Local.xcconfig`.
4. **Create the project again.** Run `make generate`.
5. **Connect your iPhone** to the Mac with the cable. Unlock it. Tap "Trust" if the iPhone asks.
6. **Turn on Developer Mode** on the iPhone: Settings > Privacy & Security > Developer Mode. The iPhone restarts.
7. **Open the project** in Xcode: `open RATPActivity.xcodeproj`.
8. At the top of the Xcode window, choose the scheme `RATPActivity` and your iPhone.
9. Click the Run button (the triangle), or press Cmd + R.
10. The first time, the iPhone blocks the app. On the iPhone, go to Settings > General > VPN & Device Management. Tap your Apple ID, then tap "Trust".
11. Click Run again in Xcode. The app opens on your iPhone.

Limits of a free Apple ID:

- The app stops working after 7 days. Connect the iPhone and click Run in Xcode again to renew it.
- You can have at most 3 of your own apps on one iPhone.
- No push notifications.

To fake your position on the iPhone: while the app runs from Xcode, use Debug > Simulate Location.

## Project layout

| Folder | What it holds |
|---|---|
| `App/` | The iPhone app (SwiftUI). |
| `Widget/` | The widget extension. It shows the Live Activity. |
| `Packages/RATPCore/` | Shared code for the app and the widget, with its unit tests. |
| `UITests/` | The end-to-end tests (XCUITest). |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands. |

## Notes for developers

- Unit tests use Swift Testing. `make test` runs them on the Mac with `swift test`, so they need no Simulator. Keep `RATPCore` buildable on macOS: put iOS-only code (for example ActivityKit) inside `#if os(iOS)`.
- Build output goes to `.build/` inside the folder. Many git worktrees can build and run unit tests at the same time. Each worktree has its own build folder. All worktrees share one Simulator, and Simulator jobs wait for each other (see above).
- End-to-end tests: to wait for an element, use `waitForExistence(timeout: UITestTimeout.element)` (30 seconds). The Mac can be busy, so short waits fail for no real reason. A wait ends as soon as the element shows, so a passing test stays fast. Each test class inherits from `E2ETestCase`. It sets `continueAfterFailure = false`: a test stops at its first failure.
- `make e2e` does not collect Simulator diagnostics when a test fails (they took 10 minutes and kept the Simulator lock). It stops a test that runs longer than 5 minutes. When a test fails, it prints the file, the line, and the message of each failure. The full results are in `.build/e2e.xcresult` (open it in Xcode).
- Swift 6 language mode. Minimum iOS version: 18.0.
