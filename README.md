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
| `make run` | Builds the app and opens it in the Simulator. |
| `make check` | The quality gate: lint, build, and unit tests. Run it before each commit. |
| `make e2e` | The end-to-end tests. They open the app in the Simulator. |
| `make lint-fix` | Fixes the lint problems that SwiftLint can fix alone. |
| `make stations` | Downloads the metro and RER station list again (see below). |
| `make clean` | Deletes the build folder and the Xcode project. |
| `make help` | Shows all the commands. |

## Run on the Simulator

```sh
make run
```

The app opens in the Simulator. You need no Apple ID for this.

Each copy of the repo (each folder) gets its own Simulator. Its name starts with `RATP-`. To see its ID, run `make simulator`. To shut it down, run `make simulator-shutdown`. To delete it, run `make simulator-delete`.

Only one Simulator job (`make run`, `make e2e`) runs at a time on the Mac. The others wait and say so. After `make run`, run `make simulator-shutdown` when you are done, so the others can go on.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

## Fake your position (testing tools)

Debug builds have a "Testing tools" screen. `make run` and the Run button in Xcode make debug builds. Release builds do not have this screen.

1. Open the app. Tap "Testing tools" at the bottom of the screen.
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

## The train data key (PRIM)

The app gets train times from the PRIM API of Île-de-France Mobilités. PRIM needs a free key.

The app builds and runs without the key. The app screen says "Train data key: not set".

To add the key:

1. Create a free account on https://prim.iledefrance-mobilites.fr.
2. In your account page, create an API key.
3. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.
4. Put your key after `PRIM_API_KEY =`.
5. Run `make run`. The app screen now says "Train data key: set".

Git ignores `Config/Secrets.xcconfig`. Never commit your key.

Each folder of the repo needs its own copy of `Config/Secrets.xcconfig`.

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
- Build output goes to `.build/` inside the folder. Many git worktrees can build and run unit tests at the same time. Each worktree has its own build folder and its own Simulator, but Simulator jobs wait for each other (see above).
- Swift 6 language mode. Minimum iOS version: 18.0.
