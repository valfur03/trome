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

This installs three tools with Homebrew (XcodeGen, SwiftLint and pngquant). Then it creates the Xcode project `RATPActivity.xcodeproj`.

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
| `make docs` | Builds the docs site and serves it at http://localhost:4321 (see [The docs site](#the-docs-site)). |
| `make help` | Shows all the commands. |

## Run on the Simulator

```sh
make run
```

`make run` does not use your train data key. The app shows no trains, and "Testing tools" > "Next trains of a station" says "Train data key: not set". To see live trains, run `make run LIVE=1` (see [The train data key](#the-train-data-key-prim)).

The app opens in the Simulator. You need no Apple ID for this.

All copies of the repo (all folders) use one shared Simulator, named `RATP-Shared`. To see its ID, run `make simulator`.

- `make run` and `make e2e` remove the app and its data from the Simulator, then install the app of this folder. So a folder never sees the data or the saved settings of another folder. They also reset the permissions and clear the fake position of the Simulator.
- The Simulator stays booted between jobs, so the next job starts faster. It shuts down by itself after 5 minutes with no job.
- To delete the shared Simulator, run `make simulator-delete`. The next job creates it again.

Only one Simulator job (`make run`, `make e2e`) runs at a time on the Mac. The others wait and say so. After `make run`, run `make simulator-shutdown` when you are done, so the others can go on. This removes the app from the Simulator and frees the lock. It does not shut down the Simulator at once.

Before the shared Simulator, each folder had its own Simulator, named `RATP-<folder>-<hash>`. To delete these old Simulators, run `make simulator-delete-old`.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

## The main screen

The app is the Live Activity. The main screen shows only:

- **One action.** "Show the Live Activity for the nearest station now" shows the Live Activity of the station nearest to you. If the app cannot find a station (no location access, no metro or RER station near you, no position), it says why. While a Live Activity shows, the screen says which station ("On the lock screen: <station>") and has "Stop showing on the lock screen" instead.
- **The automatic mode.** It is always on for now (see [below](#the-live-activity-starts-and-stops-by-itself-near-a-station)). A later task adds a way to snooze it or turn it off.
- **The permissions.** The state of the location and of the notifications. When one is missing or refused, the screen says what does not work, with a button to fix it ("Open Settings", or "Allow location").

The station picker and the next trains list are only for testers, in "Testing tools" (debug builds).

## Fake your position (testing tools)

Debug builds have a "Testing tools" screen. `make run` and the Run button in Xcode make debug builds. Release builds do not have this screen.

1. Open the app. Tap "Testing tools" at the top right of the screen.
2. Choose a fake position:
   - "Pick a station": choose a metro or RER station from a list.
   - "Far from any station": a point in the Fontainebleau forest, far from any metro or RER station.
   - "Coordinates": type the latitude, then the longitude, for example `48.8584, 2.2945`. Tap "Use these coordinates".
   - "Address": type an address, for example `10 rue de Rivoli, Paris`. Tap "Find this address". This needs the network.
3. The section "Position used by the app" shows the position that every feature uses, and the nearest station.
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

Debug builds can show the next trains of a station that you pick by hand. This needs no location permission. Release builds do not have this screen.

1. Open "Testing tools", then tap "Next trains of a station" at the bottom.
2. Tap "Pick a station". Type part of a name to find a station, then tap it.
3. The screen shows the next trains of each line and destination, in minutes. The app asks for new times every 30 seconds while this screen is open.
4. Tap "Change station" to pick another station.

The app remembers the picked station when you close it.

The screen tells you when:

- the train data key is not set (see below),
- the station has no live data right now,
- the app cannot reach the train data service (for example, no internet),
- the service refuses the key, gets too many requests, or does not work.

For developers: the code is in `Packages/RATPCore/Sources/RATPCore/Trains`. `PRIMDeparturesProvider` calls the PRIM API "stop-monitoring" once for each stop of the station. A metro stop id `IDFM:<n>` becomes `STIF:StopPoint:Q:<n>:`. An RER stop id `IDFM:monomodalStopPlace:<n>` becomes `STIF:StopArea:SP:<n>:`. `CurrentStationModel` holds the station that the tester picked. `NextTrainsModel.updatingStationId` says which station the screen keeps up to date, so the Live Activity does not ask PRIM for the same station twice.

## Show the next trains on the lock screen (Live Activity)

The app shows the next trains of a station on the lock screen, as a Live Activity. On an iPhone with a Dynamic Island, it also shows there.

1. On the main screen, tap "Show the Live Activity for the nearest station now". Testers can also pick any station in "Testing tools" > "Next trains of a station", and tap "Show on the lock screen".
2. Lock the phone. The Live Activity shows the station, the line, and the next trains in both directions of the line. Each direction has the name of its end of line, the waiting time of the next train, and the waiting time of the train after it (when there is one). A direction with no upcoming train says "No trains". At the end of a line, the Live Activity shows only the other direction.
3. To remove it, open the app and tap "Stop showing on the lock screen".

The Live Activity can also start and stop by itself near a station (see below).

The first time, iOS asks on the lock screen if it can show Live Activities from RATP Activity. Tap "Allow".

The waiting times count down by themselves. The app sends new train times every 30 seconds while the app is open. While the app is in the background, it sends new train times a few seconds after the first shown train leaves (at most every 20 seconds, and at least every 2 minutes). This works while iOS keeps the app running in the background (see the limit below). When the first shown train has left and no new times came, the Live Activity hides its waiting times and says "Open the app for new times". It says the same if the train times take more than a minute to load. If the app has no train times for the station, the Live Activity says "No data available".

If the app says that Live Activities are turned off, turn them on in Settings > RATP Activity > Live Activities.

For developers: `StationActivityAttributes` (in `RATPCore`) holds the data of the Live Activity. `LineDirections` splits the trains of the line into its two directions. For a metro station, PRIM has one stop (quay) for each direction, so the direction of a train is the quay that the app asked for. The end of line names are in `TransitLine+Ends.swift` (a unit test checks them against the station list). A train that ends before the end of the line (for example at Trocadéro on line 6) goes into the direction of its quay. RER stations have one stop area for both directions, so the Live Activity shows the next trains of their soonest destinations (at most 3) until TASK-7 handles branches. `StationLiveActivityModel` starts, updates and stops it. The view is in `Widget/StationLiveActivity.swift`.

## The Live Activity starts and stops by itself near a station

The app watches the metro and RER stations around you. The rules come from decision-3 in the backlog.

- **Arrival.** When you come within about 150 meters of a station:
  - If the app is open on screen, the Live Activity of this station starts at once.
  - If the app is closed or in the background, the phone shows one notification: "Next trains at <station>". Tap it: the app opens and starts the Live Activity of this station.
- **One station at a time.** If a Live Activity already shows and you come within 150 meters of another station, the Live Activity switches to the new station. There is no second Live Activity and no second notification.
- **Stop.** The Live Activity ends by itself when you move more than about 250 meters away from its station, or 45 minutes after it started.
- **No repeat.** You get one notification or one automatic start for each arrival. After you stop the Live Activity by hand, it does not start again until you leave the station (more than 250 meters) and come back.
- **By hand.** "Show the Live Activity for the nearest station now", "Show on the lock screen" (testing tools) and "Stop showing on the lock screen" still work. A Live Activity that you start by hand for a station far from you does not stop because of the distance. It stops at 250 meters only after you came near its station. The 45 minute limit applies to every Live Activity.

The main screen says which station shows on the lock screen ("On the lock screen: <station>").

The first time, the app asks for your location and for notifications. To get the notification while the app is closed, the app needs the location "Always". iOS first gives "While Using the App", then later asks you if the app can keep using your location in the background. If you keep "While Using the App", the Live Activity starts by itself only while the app is open. The "Permissions" part of the main screen then says so, with a button to open Settings.

### Test it with a fake position

- **App open (the Live Activity starts at once).** Open "Testing tools", pick a station (for example Abbesses), and go back. The Live Activity starts. Pick a station near it (for example Pigalle): the Live Activity switches. Tap "Far from any station": the Live Activity ends.
- **App closed (the notification).** The in-app fake position cannot change while the app is closed. Use the Simulator location instead:
  1. In "Testing tools", tap "Use the real GPS". In iOS Settings, set the location of RATP Activity to "Always".
  2. Set a position far from any station: `xcrun simctl location "$(make -s simulator)" set 48.42,2.63`.
  3. Go to the home screen or lock the Simulator.
  4. Set a position at a station, for example Abbesses: `xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838`. The notification shows. iOS can take a few seconds to a few minutes to notice the move.
  5. Tap the notification.

  On your iPhone connected to the Mac, use Xcode > Debug > Simulate Location in the same way.
- **The 45 minute limit.** In debug builds, you can make it shorter. Launch the app with `-liveActivityMaximumDuration <seconds>`, for example: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.RATPActivity -liveActivityMaximumDuration 60` (replace `com.example` with your bundle ID prefix if you changed it).

For developers: the rules are in `AutoLiveActivityRules` (in `RATPCore`), and `AutoLiveActivityModel` applies them. It reads the position from `LocationService`, so the fake position works too. When the app is closed, iOS wakes it with region monitoring (`CLMonitor`, in `App/CoreLocationStationRegions.swift`). iOS watches at most 20 regions for each app, so the app watches the 18 nearest stations (150 m), the stop area of the shown station (250 m), and one larger area around you. When you leave this larger area, the app picks the nearest stations again. While a Live Activity shows, the app keeps getting your position in the background, so it can switch or stop the Live Activity. In the background, the app gets new train times when the Live Activity starts or switches station, then again a few seconds after the first shown train leaves (`BackgroundTrainsRefresh`: at most every 20 seconds, at least every 2 minutes). While the app is open, the app gets the train times of the Live Activity every 30 seconds, unless the next trains screen of the testing tools already gets them for the same station.

Limit: iOS can pause or close the app in the background (for example with a fake position, which sends no new positions, or after you close the app from the app switcher). Then the 45 minute limit applies only when iOS wakes the app again (a region event) or when you open it, and the Live Activity gets no new train times until then.

## The train data key (PRIM)

The app gets train times from the PRIM API of Île-de-France Mobilités. PRIM needs a free key.

The app builds and runs without the key. "Testing tools" > "Next trains of a station" says "Train data key: not set".

To add the key:

1. Create a free account on https://prim.iledefrance-mobilites.fr.
2. In your account page, create an API key.
3. In the main folder of the repo, copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.
4. Put your key after `PRIM_API_KEY =`.
5. Run `make run LIVE=1`. "Testing tools" > "Next trains of a station" now says "Train data key: set", and it shows live trains.

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

## The docs site

The folder `docs/` holds the docs for the users of the app, for example the tutorial to install the app on your iPhone. It is a [Starlight](https://starlight.astro.build) site (Astro). It is not online: you read it on your Mac.

The docs need Node 24 LTS. The file `.nvmrc` pins it. Install it one time with [nvm](https://github.com/nvm-sh/nvm): run `nvm install` in this folder. Then run `nvm use` in each new terminal before a docs command. If the active Node is too old, the docs commands stop and tell you to run `nvm use`.

| Command | What it does |
|---|---|
| `make docs` | Builds the site and serves it at http://localhost:4321. The search works only here. `make docs PORT=4400` uses port 4400. |
| `make docs-dev` | Serves the site with live reload while you change a page. No search. It also accepts `PORT=<n>`. |
| `make docs-stop` | Stops the docs server of this folder. Use it when the server runs in the background (for agents, Astro starts it in the background). In a terminal, press Ctrl + C. |
| `make docs-check` | The docs quality gate: installs the packages if needed, runs the unit tests and `astro check`, builds the site, and fails on a broken internal link. It needs no Simulator. |
| `make docs-screenshots` | Takes the app screenshots of the docs on the shared Simulator, and saves them in `docs/src/assets/screenshots/`. |

The first docs command installs the packages in `docs/node_modules` (about 300 MB).

`make check` runs `make docs-check` only when your branch changes files in `docs/` (compared with `develop`). So a change of the app only does not need Node.

To write a page:

- Add an `.mdx` file in `docs/src/content/docs/tutorial/`. The sidebar shows it under "Tutorial".
- Use the Starlight components: `Steps` for a step list, `Aside` for a callout. See https://starlight.astro.build/components/using-components/.
- To show the progress of a step list ("3 of 11 steps done"), put the list inside the `Checklist` component of `docs/src/components/Checklist.astro`. Give each list its own `id`: the browser saves the ticks under this id. The home page (`docs/src/content/docs/index.mdx`) shows an example.
- Show an app screenshot with the `Screenshot` component of `docs/src/components/Screenshot.astro`. Do not use a Markdown image or the `Image` component of Astro. To show many screenshots side by side, put them inside the `Screenshots` component. The home page shows an example:

  ```mdx
  import Screenshot from '../../../components/Screenshot.astro';
  import Screenshots from '../../../components/Screenshots.astro';
  import appMainScreen from '../../../assets/screenshots/app-main-screen.png';

  <Screenshot src={appMainScreen} alt="The main screen of the app." />
  ```

  `Screenshot` always shows the image 300 pixels wide (less on a narrow screen), with the rounded corners of the iPhone screen. At build time, Astro makes AVIF files (and WebP files for old browsers) at 1x, 2x and 3x of this width. The browser downloads only the one that fits its screen, so the page stays light.

`make docs-screenshots` runs the XCUITest suite of `DocsScreenshots/` with the key-less build and a fixed fake position (near Champ de Mars Tour Eiffel). It saves one PNG file for each screenshot, with a fixed name: `app-main-screen.png` (the main app screen) and `live-activity-notification-center.png` (the Live Activity in the Notification Center). The PNG files are in git. To add a screenshot, add a `saveScreenshot(named:)` call to the test and its name to `names` in `scripts/docs-screenshots.sh`.

Rules for the screenshot files:

- **Full screen, same device.** Each screenshot shows the full screen of the shared Simulator (an iPhone 17), also for the Live Activity (the full Notification Center, not a crop). So all screenshots have the same size and look the same side by side. The script fails if a screenshot has another size.
- **900 pixels wide.** The docs show a screenshot 300 pixels wide. A Retina (2x) screen needs 600 pixels, and a 3x screen (an iPhone) needs 900 pixels. So the script makes each screenshot 900 pixels wide (the Simulator gives 1206 pixels). More pixels make a larger file with no visible gain. Fewer pixels make a blurry image.
- **Budget: at most 500 KB for each file in git.** The script compresses each file with pngquant (quality 85 to 100: no visible loss), and fails if a file is larger than 500 KB. Today, a screen of the app is about 60 KB, and the lock screen with its wallpaper is about 450 KB. Why a budget: the files stay in the git history forever, and each new run of `make docs-screenshots` adds them again. The page does not get heavier: Astro makes small AVIF files at build time.

Rules to keep the docs true:

- A change of a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. For a changed screen, run `make docs-screenshots` and commit the new images.
- `make docs-screenshots` is a Simulator job. It takes the Simulator lock, like `make e2e`. Run `make simulator-shutdown` when your job ends.

## Project layout

| Folder | What it holds |
|---|---|
| `App/` | The iPhone app (SwiftUI). |
| `Widget/` | The widget extension. It shows the Live Activity. |
| `Packages/RATPCore/` | Shared code for the app and the widget, with its unit tests. |
| `UITests/` | The end-to-end tests (XCUITest). |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands. |
| `docs/` | The docs site (Starlight). |
| `DocsScreenshots/` | The XCUITest suite that takes the app screenshots of the docs. |

## Notes for developers

- Unit tests use Swift Testing. `make test` runs them on the Mac with `swift test`, so they need no Simulator. Keep `RATPCore` buildable on macOS: put iOS-only code (for example ActivityKit) inside `#if os(iOS)`.
- Build output goes to `.build/` inside the folder. Many git worktrees can build and run unit tests at the same time. Each worktree has its own build folder. All worktrees share one Simulator, and Simulator jobs wait for each other (see above).
- End-to-end tests: to wait for an element, use `waitForExistence(timeout: UITestTimeout.element)` (30 seconds). The Mac can be busy, so short waits fail for no real reason. A wait ends as soon as the element shows, so a passing test stays fast. Each test class inherits from `E2ETestCase`. It sets `continueAfterFailure = false`: a test stops at its first failure.
- `make e2e` does not collect Simulator diagnostics when a test fails (they took 10 minutes and kept the Simulator lock). It stops a test that runs longer than 5 minutes. When a test fails, it prints the file, the line, and the message of each failure. The full results are in `.build/e2e.xcresult` (open it in Xcode).
- Swift 6 language mode. Minimum iOS version: 18.0.
