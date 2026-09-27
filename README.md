# RATP Activity

An iPhone app. It shows the next metro and RER trains of the nearest Paris station on the lock screen, as a Live Activity.

## What you need

- A Mac with Xcode 27.
- Homebrew (https://brew.sh).
- For your iPhone only: a free Apple ID and a USB cable.

## First setup

Open Terminal in the main folder of the repo (the root). Run every `make` command there. Run:

```sh
make setup
```

This installs three tools with Homebrew (XcodeGen, SwiftLint and pngquant). Then it creates the Xcode project `ios/RATPActivity.xcodeproj`.

The Xcode project is not in git. The file `ios/project.yml` describes it. If you change `ios/project.yml`, run `make generate`.

## Everyday commands

| Command | What it does |
|---|---|
| `make run` | Builds the app and opens it in the Simulator, without the train data key. |
| `make run LIVE=1` | The same, with your train data key (see below). |
| `make run SMALL=1` | The same, on the smallest supported iPhone (see [The smallest iPhone](#the-smallest-iphone)). |
| `make check` | The quality gate: lint, key leak check, build, unit tests, and the tests of the Simulator scripts. Run it before each commit. |
| `make e2e` | The end-to-end tests. They open the app in the Simulator. |
| `make e2e ONLY=FakePositionTests` | Only one class of end-to-end tests. Separate many classes with spaces, in quotes. `ONLY=FakePositionTests/testTesterCanFakeThePositionAndGoBackToTheRealGPS` runs one test. The class names are the file names in `ios/UITests/`. |
| `make lint-fix` | Fixes the lint problems that SwiftLint can fix alone. |
| `make stations` | Downloads the metro and RER station list again (see below). |
| `make clean` | Deletes the build folder and the Xcode project. |
| `make clean-shared-cache` | Deletes the build cache that all folders share (see [Notes for developers](#notes-for-developers)). |
| `make docs` | Builds the docs site and serves it at http://localhost:4321 (see [The docs site](#the-docs-site)). |
| `make help` | Shows all the commands. |

## Run on the Simulator

```sh
make run
```

`make run` does not use your train data key. The app shows no trains, and "Testing tools" > "Next trains of a station" says "Train data key: not set". To see live trains, run `make run LIVE=1` (see [The train data key](#the-train-data-key-prim)).

The app opens in the Simulator. You need no Apple ID for this.

All copies of the repo (all folders) share two Simulator slots. Each slot has its own shared Simulator, an iPhone 17: `RATP-Shared` (slot 1) and `RATP-Shared-2` (slot 2). A job takes a free slot, slot 1 first. To see the ID of the Simulator of your `make run`, run `make simulator` (with no `make run`, it prints the ID of `RATP-Shared`).

- `make run` and `make e2e` remove the app and its data from the Simulator, then install the app of this folder. They also delete the saved settings of the app that the Simulator keeps outside the app data (a removed app can leave some there, and the next install reads them). So a folder never sees the data or the saved settings of another folder. A job uses only the Simulators of its slot, so two jobs at the same time never see the data of each other. They also reset the permissions, restart the home screen (SpringBoard) and the location service of the Simulator, and clear its fake position. The home screen restart adds about 6 seconds to each job. Why the home screen restart: a system popup of the removed app stays on screen after the removal ("Change to Always Allow", "Would Like to Send You Notifications", the first location question). It covers the new app, so the tests and your checks wait on a popup that they did not cause. Why the location service restart: when a job removes the app while iOS shows its "Change to Always Allow" popup, the location service keeps that popup "in flight" and then ignores every new location request of the app, so the next job never sees the location popup. Then `make e2e` gives the app the location permission "While Using the App", so the tests see no location popup.
- The Simulator of a slot stays booted between jobs, so the next job starts faster. It shuts down by itself after 5 minutes with no job in its slot.
- To delete the shared Simulators of both slots (the iPhone 17 and the small one of each slot), run `make simulator-delete`. It waits until no other Simulator job runs. The next job creates them again.

At most two Simulator jobs (`make run`, `make e2e`, `make docs-screenshots`) run at the same time on the Mac, one in each slot. A job starts next to another one only when at least 25% of the CPU is idle, so the Mac stays usable. The other jobs wait, and say why: both slots are busy, or the CPU is too busy. After `make run`, run `make simulator-shutdown` when you are done, so the others can go on. This removes the app from the Simulator and frees the lock of its slot. It does not shut down the Simulator at once.

Why two jobs, and how to go back to one job at a time: see the CLAUDE.md, section "Budget for this repo". In short, change `slots=${RATP_SIM_SLOTS:-2}` to `slots=${RATP_SIM_SLOTS:-1}` in `ios/scripts/sim-lock.sh`. For one command only, add `RATP_SIM_SLOTS=1` before it.

### The smallest iPhone

To check a screen on the smallest iPhone that the app supports, run:

```sh
make run SMALL=1
```

It opens the app in the small shared Simulator of its slot: `RATP-Shared-Small` (slot 1) or `RATP-Shared-Small-2` (slot 2). It is an iPhone SE (3rd generation): 375 x 667 points, the narrowest and the shortest screen. `RATP-Shared` and `RATP-Shared-2` are iPhone 17 (402 x 874 points).

- It takes the Simulator lock of a slot and keeps it, like `make run`. `LIVE=1` works with it too.
- Only one Simulator runs in each slot. Before it boots a shared Simulator, a job shuts down the other Simulator of its slot. So after `make run SMALL=1`, the next job in this slot waits for a cold boot of its iPhone 17.
- `make simulator-shutdown` removes the app and shuts down the small Simulator at once. Few jobs use it, so it does not stay booted.
- `SMALL=1` works only with `make run`. The end-to-end tests and the docs screenshots always use the iPhone 17 of their slot.

Before the shared Simulator, each folder had its own Simulator, named `RATP-<folder>-<hash>`. To delete these old Simulators, run `make simulator-delete-old`.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

## The main screen

The app is the Live Activity. The main screen shows only:

- **One action.** "Show the Live Activity now" shows the Live Activity of the station nearest to you. You do not pick the station. If the app cannot find a station (no location access, no metro or RER station near you, no position), it says why. While a Live Activity shows, the screen says which station ("On the lock screen: <station>") and has "Stop showing on the lock screen" instead.
- **The automatic mode.** The Live Activity starts by itself near a station (see [below](#the-live-activity-starts-and-stops-by-itself-near-a-station)). The switch "Automatic mode" turns it off or on. "Snooze" stops it for 30 minutes, 1 hour, or for the rest of today. While a snooze is on, the screen says "Snoozed", the time when the automatic mode comes back, and the time left. "Cancel the snooze" ends the snooze at once (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)).
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

The app finds the nearest station without the network. It reads the file `ios/Packages/RATPCore/Sources/RATPCore/Resources/stations.json`.

This file lists every metro station (lines 1 to 14, 3bis and 7bis) and every RER station (lines A to E). It has no bus, tram or Transilien stop. The data comes from the open data of Île-de-France Mobilités (dataset `arrets-lignes`, no key needed).

To see the list in the app, open "Testing tools" and tap "All stations". Each station shows its lines. Type part of a name in the search field to find a station. The search ignores case, accents and hyphens: `chatelet` finds "Châtelet".

To download the list again, run `make stations`. It needs Python 3. Commit the new `stations.json`.

Some names in the open data are wrong or spelled in two ways. The script fixes them with the table `STATION_NAMES` in `ios/scripts/update-stations.py`. If a unit test says that two stations "look like the same station", add the bad name to this table.

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

For developers: the code is in `ios/Packages/RATPCore/Sources/RATPCore/Trains`. `PRIMDeparturesProvider` calls the PRIM API "stop-monitoring" once for each stop of the station. A metro stop id `IDFM:<n>` becomes `STIF:StopPoint:Q:<n>:`. An RER stop id `IDFM:monomodalStopPlace:<n>` becomes `STIF:StopArea:SP:<n>:`. `CurrentStationModel` holds the station that the tester picked. `NextTrainsModel.updatingStationId` says which station the screen keeps up to date, so the Live Activity does not ask PRIM for the same station twice.

## Show the next trains on the lock screen (Live Activity)

The app shows the next trains of a station on the lock screen, as a Live Activity. On an iPhone with a Dynamic Island, it also shows there.

1. On the main screen, tap "Show the Live Activity now". It shows the Live Activity of the station nearest to you. Testers can also pick any station in "Testing tools" > "Next trains of a station", and tap "Show on the lock screen".
2. Lock the phone. The Live Activity shows the station, the line, and the next trains in both directions of the line. Each direction has the name of its end of line, the waiting time of the next train, and the waiting time of the train after it (when there is one). A direction with no upcoming train says "No trains". At the end of a line, the Live Activity shows only the other direction.

   Some lines split into branches: metro 7 (Mairie d'Ivry or Villejuif), metro 13 (Saint-Denis or Asnières-Gennevilliers), and the RER lines. On these lines, the Live Activity names where the trains go. When the next two trains of a direction go to different places, each train shows its own destination next to its waiting time, so they never look the same. When they go to the same place, the direction shows that place. After the fork, a station names only the end of its own branch (for example "Asnières - Gennevilliers - Les Courtilles" at Brochant). A train that ends before the end of the line (for example at Trocadéro on line 6) also shows its destination. RER stations show both directions too, like metro stations. For example, at Châtelet - Les Halles, RER B shows the trains to the north (Aéroport Charles de Gaulle 2 TGV or Mitry - Claye) and the trains to the south (Robinson or Saint-Rémy-lès-Chevreuse), even when the soonest trains all go north.
3. To remove it, open the app and tap "Stop showing on the lock screen".
4. To remove it and snooze the automatic mode, tap "30 min", "1 h" or "Today" at the bottom of the Live Activity (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)). The same buttons show in the Dynamic Island when you touch and hold it.

The Live Activity can also start and stop by itself near a station (see below).

The first time, iOS asks on the lock screen if it can show Live Activities from RATP Activity. Tap "Allow".

The waiting times count down by themselves. The app sends new train times every 30 seconds while the app is open. While the app is in the background, it sends new train times a few seconds after the first shown train leaves (at most every 30 seconds, and at least every 2 minutes). It stops when PRIM rejects the key or says the daily quota is used up. This works while iOS keeps the app running in the background (see the limit below). When the first shown train has left and no new times came, the Live Activity hides its waiting times and says "Open the app for new times". It says the same if the train times take more than a minute to load. If the app has no train times for the station, the Live Activity says "No data available".

If the app says that Live Activities are turned off, turn them on in Settings > RATP Activity > Live Activities.

For developers: `StationActivityAttributes` (in `RATPCore`) holds the data of the Live Activity. `LineDirections` splits the trains of the line into its two directions. For a metro station, PRIM has one stop (quay) for each direction, so the direction of a train is the quay that the app asked for. The end of line names are in `TransitLine+Ends.swift` (a unit test checks them against the station list). A train that ends before the end of the line (for example at Trocadéro on line 6) goes into the direction of its quay. Each train of a direction keeps its destination (`LineDirection.Train`). When the trains of a direction have different destinations, the view shows the destination of each train (`LineDirection.showsEachDestination`). Else it shows one name above the times (`LineDirection.name`): the destination of the trains, or the name of the direction when it has no train. For metro 7 and 13, `branchStations` in `TransitLine+Ends.swift` lists the stations after the fork, so these stations name only the end of their branch (a unit test checks the names against the station list). An RER station has one stop area for both directions. PRIM tells the quay (track) of each RER train (`ExpectedQuayRef`), and a quay serves one direction, so the trains of a quay go into the same direction. A quay gets its direction from the destinations of its trains (the RER end of line names and branches are in `TransitLine+RERLineEnds.swift`, checked against the station list). When a quay has only trains that end before the end of the line, the app uses the direction that PRIM gives (`DirectionRef`, "Aller" or "Retour"), but only when PRIM gives both values at that station: on RER A, PRIM gives "Aller" to every train. A train whose direction stays unknown shows in a row with its destination (at most 3 rows). `StationLiveActivityModel` starts, updates and stops it. The view is in `ios/Widget/StationLiveActivity.swift`.

## The Live Activity starts and stops by itself near a station

The app watches the metro and RER stations around you. The rules come from decision-3 in the backlog.

- **Arrival.** When you come within about 150 meters of a station:
  - If the app is open on screen, the Live Activity of this station starts at once.
  - If the app is closed or in the background, the phone shows one notification: "Next trains at <station>". Tap it: the app opens and starts the Live Activity of this station.
- **One station at a time.** If a Live Activity already shows and you come within 150 meters of another station, the Live Activity switches to the new station. There is no second Live Activity and no second notification.
- **Stop.** The Live Activity ends by itself when you move more than about 250 meters away from its station, or 45 minutes after it started.
- **No repeat.** You get one notification or one automatic start for each arrival. After you stop the Live Activity by hand, it does not start again until you leave the station (more than 250 meters) and come back.
- **By hand.** "Show the Live Activity now", "Show on the lock screen" (testing tools) and "Stop showing on the lock screen" still work. A Live Activity that you start by hand for a station far from you does not stop because of the distance. It stops at 250 meters only after you came near its station. The 45 minute limit applies to every Live Activity.

The main screen says which station shows on the lock screen ("On the lock screen: <station>").

### Snooze or turn off the automatic mode

The rules come from decision-3 in the backlog.

- **Snooze.** Tap "30 min", "1 h" or "Today" on the Live Activity, or "Snooze" in the automatic mode part of the main screen. The Live Activity ends at once. Then no notification and no automatic Live Activity start for 30 minutes, for 1 hour, or until midnight ("Today"). The notification of an arrival goes away too.
- **The end of the snooze.** When the time is over, the automatic mode is on again by itself. The rules above apply again. The app still follows the stations that you pass during the snooze: when the snooze ends at a station that you reached during the snooze, the Live Activity does not start. It starts at the next station that you come to.
- **Cancel the snooze.** The main screen shows "Snoozed", the time when the automatic mode comes back, and the time left. Tap "Cancel the snooze" to end it at once.
- **Turn off.** Turn off the switch "Automatic mode" on the main screen. Then no notification and no automatic Live Activity ever start, until you turn the switch on again. The app keeps this choice when you close it.
- **By hand.** While the automatic mode is snoozed or off, "Show the Live Activity now" still works. A Live Activity that you start by hand still switches to a new station and stops by itself (250 meters, 45 minutes), as above.

The first time, the app asks for your location and for notifications. To get the notification while the app is closed, the app needs the location "Always". iOS first gives "While Using the App", then later asks you if the app can keep using your location in the background. If you keep "While Using the App", the Live Activity starts by itself only while the app is open. The "Permissions" part of the main screen then says so, with a button to open Settings.

### Test it with a fake position

- **App open (the Live Activity starts at once).** Open "Testing tools", pick a station (for example Abbesses), and go back. The Live Activity starts. Pick a station near it (for example Pigalle): the Live Activity switches. Tap "Far from any station": the Live Activity ends.
- **App in the background (the notification).** The in-app fake position cannot change while the app is in the background. Use the Simulator location instead:
  1. In "Testing tools", tap "Use the real GPS". In iOS Settings, set the location of RATP Activity to "Always".
  2. Set a position far from any station: `xcrun simctl location "$(make -s simulator)" set 48.42,2.63`.
  3. Go to the home screen or lock the Simulator.
  4. Set a position at a station, for example Abbesses: `xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838`. The notification shows. iOS can take a few seconds to a few minutes to notice the move.
  5. Tap the notification.

  In the Simulator, this works only while iOS keeps the app running in the background (about 10 to 25 seconds after you leave it, or while a Live Activity shows). The Simulator cannot watch regions: in the iOS 27 Simulator, `CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)` is false (checked on the two shared Simulators, an iPhone 17 and an iPhone SE). So when iOS suspends or closes the app, no region event wakes it, and no notification shows. Check the arrival of a suspended or closed app on your iPhone.

  On your iPhone connected to the Mac, use Xcode > Debug > Simulate Location in the same way.
- **The 45 minute limit.** In debug builds, you can make it shorter. Launch the app with `-liveActivityMaximumDuration <seconds>`, for example: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.RATPActivity -liveActivityMaximumDuration 60` (replace `com.example` with your bundle ID prefix if you changed it).

For developers: the rules are in `AutoLiveActivityRules` (in `RATPCore`), and `AutoLiveActivityModel` applies them. `AutomaticModeModel` holds the automatic mode (on, snoozed until a date, or off) and saves it. While the mode is not on, the rules still follow the arrivals, but they do not notify or start. The buttons of the Live Activity run `SnoozeLiveActivityIntent` (a `LiveActivityIntent`, in `RATPCore` because the app and the widget share it). iOS runs it in the app, and opens the app in the background if needed. The intent gets `AutoLiveActivityModel` from `AppDependencyManager` (the app adds it in `RATPActivityApp`). It reads the position from `LocationService`, so the fake position works too. When the app is closed, iOS wakes it with region monitoring (`CLMonitor`, in `ios/App/AutoLiveActivity/CoreLocationStationRegions.swift`). iOS watches at most 20 regions for each app, so the app watches the 18 nearest stations (150 m), the stop area of the shown station (250 m), and one larger area around you. When you leave this larger area, the app picks the nearest stations again. Debug builds log the region monitoring: whether iOS can watch regions, and each region event with its state and its diagnostics (for example `conditionUnsupported`). To read the log in the Simulator: `xcrun simctl spawn "$(make -s simulator)" log show --last 5m --predicate 'subsystem == "RATPActivity"'`. On your iPhone, open the Console app on the Mac, choose the iPhone, and search for `subsystem:RATPActivity`. While a Live Activity shows, the app keeps getting your position in the background, so it can switch or stop the Live Activity. It also keeps the app running in the background, even when the phone does not move: `CoreLocationBackgroundLocationKeeper` (in `ios/App/AutoLiveActivity/`) runs standard location updates that never pause (`pausesLocationUpdatesAutomatically = false`, `allowsBackgroundLocationUpdates = true`). Apple's documentation says that Core Location then keeps the app running. Without it, iOS pauses the new location updates (`CLLocationUpdate.liveUpdates`) when the phone stands still, and suspends the app about 15 seconds after it leaves the screen. iOS shows the location icon in the status bar while the Live Activity shows. This costs battery, for at most 45 minutes (the limit of the Live Activity). In the background, the app gets new train times when the Live Activity starts or switches station, then again a few seconds after the first shown train leaves (`BackgroundTrainsRefresh`: at most every 30 seconds, at least every 2 minutes; it stops when PRIM rejects the key or the quota is used up). Before each refresh, the app checks that the Live Activity still shows. When you swipe it away, the app stops the background location. When the app no longer asks PRIM, it still does this check every 2 minutes. Each time it gets new train times, it asks PRIM once for each stop of the station (Châtelet: 10 calls). While the app is open, the app gets the train times of the Live Activity every 30 seconds, unless the next trains screen of the testing tools already gets them for the same station.

Limit: the app gets new train times in the background only while it runs. It stops running when you close it from the app switcher, when the location is not allowed, or when iOS ends it (for example to free memory). Then the 45 minute limit applies only when iOS wakes the app again (a region event) or when you open it, and the Live Activity gets no new train times until then. A free Apple ID has no push notifications, so no server can send new times to the Live Activity instead (see "Later" in the Product Vision).

## The train data key (PRIM)

The app gets train times from the PRIM API of Île-de-France Mobilités. PRIM needs a free key.

The app builds and runs without the key. "Testing tools" > "Next trains of a station" says "Train data key: not set".

To add the key:

1. Create a free account on https://prim.iledefrance-mobilites.fr.
2. In your account page, create an API key.
3. In the main folder of the repo, copy `ios/Config/Secrets.example.xcconfig` to `ios/Config/Secrets.xcconfig`.
4. Put your key after `PRIM_API_KEY =`.
5. Run `make run LIVE=1`. "Testing tools" > "Next trains of a station" now says "Train data key: set", and it shows live trains.

Always add `LIVE=1` when you want live trains. A plain `make run` does not use your key, also in the main folder.

Git ignores `ios/Config/Secrets.xcconfig`. Never commit your key.

Only the main folder needs `ios/Config/Secrets.xcconfig`. In a git worktree, `make run LIVE=1` finds the key in the main folder with git. It does not copy the file. If the main folder has no key file, `make run LIVE=1` stops and says so.

Before TASK-43, the key file was `Config/Secrets.xcconfig` (at the root). `make run LIVE=1` still finds it there, and git still ignores it, but it prints a note. Once your main folder has the `ios/` folder, move the file there, in the main folder: `mv Config/Secrets.xcconfig ios/Config/ && rmdir Config`. The Xcode Run button reads only `ios/Config/Secrets.xcconfig`.

The other `make` commands (`make run` without `LIVE=1`, `make check`, `make e2e`) never use the key: they build with `ios/Config/NoKey.xcconfig`. Then the tests do not use your PRIM quota. The Run button in Xcode uses the key of the folder that you open.

The build output never shows the key. `make live-key-check` proves it with a fake key. `make check` runs it.

## Install on your iPhone (free Apple ID)

The tutorial "Install the app on your iPhone" of the docs site explains it step by step, for beginners. Run `make docs`, then open "Tutorial" in the sidebar. The page is `docs/src/content/docs/tutorial/install-on-your-iphone.mdx`.

In short: your Team ID and a unique bundle ID prefix go in `ios/Config/Local.xcconfig` (a copy of `ios/Config/Local.example.xcconfig`, ignored by git). Run `make generate`, open the project `ios/RATPActivity.xcodeproj` in Xcode, choose your iPhone, and click Run. With a free Apple ID, the app stops after 7 days: click Run again to renew it.

On a device, the Run button of Xcode uses the PRIM key of `ios/Config/Secrets.xcconfig` in the folder that you open. There is no `make` command for a device build.

## The docs site

The folder `docs/` holds the docs for the users of the app, for example the tutorial to install the app on your iPhone. It is a [Starlight](https://starlight.astro.build) site (Astro). It is not online: you read it on your Mac.

The docs need Node 24 LTS. The file `.nvmrc` pins it. Install it one time with [nvm](https://github.com/nvm-sh/nvm): run `nvm install` in the main folder of the repo. Then run `nvm use` in each new terminal before a docs command. If the active Node is too old, the docs commands stop and tell you to run `nvm use`.

| Command | What it does |
|---|---|
| `make docs` | Builds the site and serves it at http://localhost:4321. The search works only here. `make docs PORT=4400` uses port 4400. |
| `make docs-dev` | Serves the site with live reload while you change a page. No search. It also accepts `PORT=<n>`. |
| `make docs-stop` | Stops the docs server of this folder. Use it when the server runs in the background (for agents, Astro starts it in the background). In a terminal, press Ctrl + C. |
| `make docs-check` | The docs quality gate: installs the packages if needed, runs the unit tests and `astro check`, builds the site, and fails on a broken internal link. It needs no Simulator. |
| `make docs-screenshots` | Takes the app screenshots of the docs on a shared iPhone 17 Simulator (the one of its slot), and saves them in `docs/src/assets/screenshots/`. |

The first docs command installs the packages in `docs/node_modules` (about 300 MB).

`make check` runs `make docs-check` only when your branch changes files in `docs/` (compared with `develop`). So a change of the app only does not need Node.

To write a page:

- Add an `.mdx` file in `docs/src/content/docs/tutorial/`. The sidebar shows it under "Tutorial".
- Use the Starlight components: `Steps` for a step list, `Aside` for a callout. See https://starlight.astro.build/components/using-components/.
- Inline code (between backticks) never breaks across two lines (`docs/src/styles/custom.css`), so a reader can copy a command as one piece. Keep it short: at most about 30 characters. Put a longer command in a code block, on its own line.
- To show the progress of a step list ("3 of 11 steps done"), put the list inside the `Checklist` component of `docs/src/components/Checklist.astro`. Give each list its own `id`: the browser saves the ticks under this id. The home page (`docs/src/content/docs/index.mdx`) shows an example. For a list of things to have, not steps, add `kind="things"`: it shows "3 of 8 things ready".
- Show an app screenshot with the `Screenshot` component of `docs/src/components/Screenshot.astro`. Do not use a Markdown image or the `Image` component of Astro. To show many screenshots side by side, put them inside the `Screenshots` component. The home page shows an example:

  ```mdx
  import Screenshot from '../../../components/Screenshot.astro';
  import Screenshots from '../../../components/Screenshots.astro';
  import appMainScreen from '../../../assets/screenshots/app-main-screen.png';

  <Screenshot src={appMainScreen} alt="The main screen of the app." />
  ```

  `Screenshot` always shows the image 300 pixels wide (less on a narrow screen), with the rounded corners of the iPhone screen. At build time, Astro makes AVIF files (and WebP files for old browsers) at 1x, 2x and 3x of this width. The browser downloads only the one that fits its screen, so the page stays light.

`make docs-screenshots` runs the XCUITest suite of `ios/DocsScreenshots/` with the key-less build and a fixed fake position (near Champ de Mars Tour Eiffel). It saves one PNG file for each screenshot, with a fixed name: `app-location-permission.png` (the location question at the first launch), `app-notification-permission.png` (the notifications question at the first launch), `app-main-screen.png` (the main app screen), `live-activity-notification-center.png` (the Live Activity in the Notification Center) and `app-testing-tools.png` (the Testing tools screen). The PNG files are in git. To add a screenshot, add a `saveScreenshot(named:)` call to the test and its name to `names` in `ios/scripts/docs-screenshots.sh`.

Rules for the screenshot files:

- **Full screen, same device.** Each screenshot shows the full screen of a shared iPhone 17 Simulator (both slots have one), also for the Live Activity (the full Notification Center, not a crop). So all screenshots have the same size and look the same side by side. The script fails if a screenshot has another size.
- **900 pixels wide.** The docs show a screenshot 300 pixels wide. A Retina (2x) screen needs 600 pixels, and a 3x screen (an iPhone) needs 900 pixels. So the script makes each screenshot 900 pixels wide (the Simulator gives 1206 pixels). More pixels make a larger file with no visible gain. Fewer pixels make a blurry image.
- **Budget: at most 500 KB for each file in git.** The script compresses each file with pngquant (quality 85 to 100: no visible loss), and fails if a file is larger than 500 KB. Today, a screen of the app is about 60 KB, and the lock screen with its wallpaper is about 450 KB. Why a budget: the files stay in the git history forever, and each new run of `make docs-screenshots` adds them again. The page does not get heavier: Astro makes small AVIF files at build time.

Rules to keep the docs true:

- A change of a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images. A docs text change alone needs no new screenshots.
- `make docs-screenshots` is a Simulator job. It takes the Simulator lock, like `make e2e`. Run `make simulator-shutdown` when your job ends.

## Project layout

Each part of the repo has its own folder. The root holds only the files of the whole repo. decision-6 in the backlog explains this layout and the code structure.

| Folder or file | What it holds |
|---|---|
| `README.md`, `CLAUDE.md`, `.gitignore`, `.nvmrc` | Files for the whole repo. `.nvmrc` pins the Node version of the Node parts (today `docs/`). |
| `Makefile` | Runs each `make` command in the folder of its part. It has no build logic. `make check` runs the checks of all parts. |
| `ios/` | The iPhone app, with its own `Makefile`, `project.yml`, `.swiftlint.yml`, build settings and scripts. Its build output goes to `ios/.build/`. |
| `docs/` | The docs site (Starlight), with its own `Makefile` and scripts. |

Inside `ios/`:

| Folder | What it holds |
|---|---|
| `App/` | The iPhone app (SwiftUI): the entry point, the views, and the adapters to the iOS frameworks. One folder per feature. |
| `Widget/` | The widget extension. It shows the Live Activity. |
| `Packages/RATPCore/` | The rules, the state and the data of the app, shared by the app and the widget, with its unit tests. One folder per feature. |
| `UITests/` | The end-to-end tests (XCUITest). |
| `DocsScreenshots/` | The XCUITest suite that takes the app screenshots of the docs. |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands of the app. |

The feature folders have the same names in `ios/App/`, in the sources of `RATPCore` and in its tests: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`. `ios/App/` also has `Permissions` and `TestingTools` (debug builds only). The rules for the code (where each file goes, which module depends on which) are in the CLAUDE.md, section "Code structure of the iOS app".

You can also run the commands of one part in its folder: `make -C ios check` runs only the checks of the app.

## Notes for developers

- Unit tests use Swift Testing. `make test` runs them on the Mac with `swift test`, so they need no Simulator. Keep `RATPCore` buildable on macOS: put iOS-only code (for example ActivityKit) inside `#if os(iOS)`.
- Build output goes to `ios/.build/` inside the folder. Many git worktrees can build and run unit tests at the same time. Each worktree has its own build folder. All worktrees share two Simulator slots, and a Simulator job waits for a free slot (see above).
- The shared build cache: all folders (and all git worktrees) share the compiled modules of the iOS SDK (for example SwiftUI and UIKit), in `~/Library/Caches/RATPActivity/`. So the first build of a new worktree does not compile them again. This cache holds no code of the app, only modules of the SDK: the build products of a worktree stay in its own `ios/.build/`. Xcode keys each module by a hash of the SDK and the compiler flags, and it writes each file in one step, so many builds can use the cache at the same time. The cache grows only when the SDK or the flags change (for example after an Xcode update). `make build LIVE=1` does not use this cache: a build with the key stays in its folder. `make live-key-check` fails if the cache holds the key. To clear the cache, run `make clean-shared-cache`. It waits for the builds that use the cache to end, and new builds wait for it, so clearing never breaks a build of another folder. Then it deletes the modules, and the next build makes them again. To use another folder, add `SHARED_CACHE=<folder>` to the `make` command.
- `make build` builds the app for the processor of your Mac only (Apple silicon: arm64), and the command line builds make no code index (Xcode makes its own index when you open the project). Both make the build faster.
- End-to-end tests are slow: all folders share two Simulators, at most two jobs at a time. So each test walks one core flow of the app, and nothing else: show the Live Activity of the nearest station now (`LiveActivityTests`, with the real location popup), the automatic mode (`AutoLiveActivityTests`), the arrival notification (`ArrivalNotificationTests`), and the fake position for testers (`FakePositionTests`). A check of a rule (formatting, sorting, search, parsing, state) is a unit test in `RATPCore`. A new step of a flow goes in the test of that flow.
- End-to-end tests: to wait for an element, use `waitFor(_:)` from `E2ETestCase` (`waitForNo(_:)` to wait until it goes, `waitForFirst(of:)` for the first of many). Tap with `tap(_:)`: it waits for the element first, so a tap after typing or navigation never fails at once on a busy Mac. They wait up to `UITestTimeout.element` (30 seconds): the Mac can be busy, so short waits fail for no real reason. They return at once when the element is already there (`waitForExistence` alone costs at least 1 second, even then). Wait for a condition that the app shows, never for a fixed time. Each test class inherits from `E2ETestCase`. It sets `continueAfterFailure = false`: a test stops at its first failure.
- End-to-end tests: when a test changes the Simulator position, wait until the app shows the new position before the next step (the position reaches the app some time later). A test that puts the app in the background adds the launch argument `--keep-running-in-background` (debug builds only). The app then keeps a background location session, so iOS does not pause it before the new position reaches it.
- End-to-end tests: open the app with `launch(app)` from `E2ETestCase`, not with `app.launch()`. On the first launch of a run, it answers the notification popup at once. If the location is "Off" (for example, you run a test from Xcode after a run that refused it), it resets the location permission and answers the location popup. It also answers "Keep Only While Using" at once when iOS asks to use the location "Always". Before each test, `makeApp()` stops the app of the last test, and stops it again if iOS starts it again in the background (iOS does it for an app that can use the location in the background). `launch(app)` does the same before it resets a refused location permission. Only `LiveActivityTests` goes through the real location popup, with `answerPermissionPrompts(in:)`. It waits until it has answered that popup.
- `make e2e` builds the tests before it takes the Simulator lock, so other jobs do not wait for the build. It runs the tests on the Simulator of its slot (`ios/scripts/simulator.sh with-destination` adds its `-destination`).
- `make e2e` does not collect Simulator diagnostics when a test fails (they took 10 minutes and kept the Simulator lock). It stops a test that runs longer than 5 minutes. When a test fails, it prints the file, the line, and the message of each failure. The full results are in `ios/.build/e2e.xcresult` (open it in Xcode).
- Swift 6 language mode. Minimum iOS version: 18.0.
