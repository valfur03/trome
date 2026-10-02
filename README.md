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

The Xcode project is not in git.
The file `ios/project.yml` describes it.
The `make` commands update the project by themselves, but the Run button of Xcode does not.
An old project lists files that no longer exist, and misses the new ones: the build fails with "Build input file cannot be found" or "Cannot find ... in scope".
To update the project by hand, run `make generate`.
Do it also after you change `ios/project.yml`.

### Update the Xcode project after each git pull

Run this one time in the main folder:

```sh
make git-hooks
```

It turns on the git hooks of the repo (`ios/scripts/git-hooks/`): it sets `core.hooksPath` in the git config of your clone.
After that, each `git pull`, `git checkout`, `git switch`, `git merge` or `git rebase` in the main folder creates the Xcode project again (`make project`).
So `make merge` updates it too, when it moves `main` in the main folder.
XcodeGen writes the project only when the code or `ios/project.yml` changed (its cache is in `ios/.build/`).
When Xcode is open, it loads the new project by itself.

- The hooks change only the Xcode project and the cache in `ios/.build/`. Git ignores both, so the main folder stays clean.
- The hooks do nothing in the other folders of the repo (the worktrees of the agents). Their `make` commands create the project before each build.
- A hook never stops the git command. When XcodeGen fails, the hook prints a warning: run `make generate` before you build in Xcode.
- `make git-hooks` refuses to start when your clone already uses other git hooks (in `.git/hooks/` or another `core.hooksPath`): git runs only one hooks folder.
- `git reset --hard` runs no hook. After it, run `make generate`.

To turn the hooks off, run `make git-hooks-off`. Then run `make generate` after each `git pull`, before you build in Xcode.

## Everyday commands

| Command | What it does |
|---|---|
| `make run` | Builds the app and opens it in the Simulator, without the train data key. |
| `make run LIVE=1` | The same, with your train data key (see below). |
| `make run SMALL=1` | The same, on the smallest supported iPhone (see [The smallest iPhone](#the-smallest-iphone)). |
| `make run LANGUAGE=fr` | The same, with the Simulator in French (see [The language of the Simulator](#the-language-of-the-simulator)). |
| `make switch-language LANGUAGE=en` | After `make run`: puts the Simulator in English (or `fr`) and opens the app again, with its data. |
| `make check` | The quality gate: lint, Markdown line check (see [Notes for developers](#notes-for-developers)), public text check (see [CONTRIBUTING.md](CONTRIBUTING.md#public-text)), recommended settings check, key leak check, build, strings check (see [Languages](#languages)), unit tests, and the tests of the scripts. It fails on any warning (see [No warnings](#no-warnings)). Run it before each commit. |
| `make e2e` | The end-to-end tests. They open the app in the Simulator. |
| `make e2e ONLY=AutoLiveActivityTests` | Only one class of end-to-end tests. Separate many classes with spaces, in quotes. `ONLY=AutoLiveActivityTests/testLiveActivityStartsSwitchesAndStopsByItselfNearStations` runs one test. The class names are the file names in `ios/UITests/`. |
| `make live-activity-render` | Draws the Live Activity views for every station and page, in French, and lists the too tall ones, the cut texts and the breaches of decision-15. `ENGLISH=1` draws them in English too. On demand, not in the gate (see [Check how the Live Activity draws](#check-how-the-live-activity-draws)). |
| `make merge` | Merges the branch of this folder into `main`, with the Simulator lock from start to end: rebase onto `main`, `make check`, the full `make e2e`, then a fast-forward of `main`. The manager runs it, after QA passed the task (see [Merge a task into main](#merge-a-task-into-main)). |
| `make lint-fix` | Fixes the lint problems that SwiftLint can fix alone. |
| `make strings-sync` | Updates the String Catalogs as a build in Xcode does (see [Languages](#languages)). |
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

All copies of the repo (all folders) use one shared Simulator, named `RATP-Shared`. To see its ID, run `make simulator`.

- `make run` and `make e2e` remove the app and its data from the Simulator (and the host app of the render check, see [Check how the Live Activity draws](#check-how-the-live-activity-draws)), then install the app of this folder.
  They also delete the saved settings of the app that the Simulator keeps outside the app data (a removed app can leave some there, and the next install reads them).
  So a folder never sees the data or the saved settings of another folder.
  They also reset the permissions, set the text size and the appearance back to the iOS default (Large text, Light mode), restart the home screen (SpringBoard) and the location service of the Simulator, and clear its fake position.
  Why the text size and the appearance: a check of large text or of dark mode changes them for the whole Simulator, and the next job keeps them.
  With a very large text size, the main screen scrolls over 5 pages, and every E2E test fails because it does not find its buttons.
  The home screen restart adds about 6 seconds to each job.
  Why the home screen restart: a system popup of the removed app stays on screen after the removal ("Change to Always Allow", "Would Like to Send You Notifications", the first location question).
  It covers the new app, so the tests and your checks wait on a popup that they did not cause.
  Why the location service restart: when a job removes the app while iOS shows its "Change to Always Allow" popup, the location service keeps that popup "in flight" and then ignores every new location request of the app, so the next job never sees the location popup.
  Then `make e2e` gives the app the location permission "While Using the App", so the tests see no location popup.
- To check dark mode or another text size after `make run`, change the setting of the Simulator: `xcrun simctl ui "$(make -s simulator)" appearance dark`, or `xcrun simctl ui "$(make -s simulator)" content_size accessibility-extra-extra-extra-large` (`xcrun simctl ui --help` lists the sizes).
  The next job (`make run`, `make e2e`, `make docs-screenshots`) sets them back to Large text and Light mode, so run the command again after each `make run`.
- After a cold boot, the notification service of the Simulator can stay silent for some minutes (3 minutes on 2026-09-27, when the Mac was busy).
  During that time, the app shows no notification question and no "Notifications" row.
  Why: the home screen (SpringBoard) serves the notification settings only after the background task service of iOS (`dasd`) accepts its tasks, and at boot `dasd` first handles the tasks of all the other services.
  So the end-to-end tests and the docs screenshots first ask the notification service for its settings, and wait for its answer (at most 4 minutes) before they open the app.
  `make run` does not wait: after a cold boot, the notification question can come some minutes late.
- After some cold boots, the widget host of the Simulator (`chronod`, the iOS service that draws widgets and Live Activities) first works through a queue of tasks for all the system widgets (up to 40 tasks, for almost 3 minutes on 2026-10-01, when the Mac was busy).
  During that time, a Live Activity that the app starts shows nowhere: `chronod` must first read the widget of the new install, and that task waits at the end of the queue.
  So `make run`, `make e2e` and `make docs-screenshots` wait until the queue of `chronod` is empty (at most 4 minutes, `RATP_WIDGET_HOST_WAIT_SECONDS`), and print `Waiting for the widget host of the Simulator` when they wait.
  They read the queue in the log of `chronod`.
  When the queue is empty, they do not wait.
  Why: on 2026-10-01, the first E2E test of a full run (`ArrivalNotificationTests`, the first Live Activity after the install) found no Live Activity in the Notification Center for 30 seconds, because `chronod` read the widget of the app only 51 seconds after the first launch (TASK-162).
  A newer iOS may change these log messages.
  Then the jobs do not wait any more, and this failure can come back.
- The Simulator stays booted between jobs, so the next job starts faster.
  It shuts down by itself after 5 minutes with no job.
  Only one of the two shared Simulators (`RATP-Shared` and the small one, see below) is booted at a time: a job shuts down the other one before it boots its own.
  While a job runs, when the other shared Simulator is booted (for example, the Simulator panel of the Claude app boots it), it shuts down within about 10 seconds.
- To delete the shared Simulators (`RATP-Shared`, the small one, and the ones of the second slot if an old trial made them), run `make simulator-delete`. It waits until no other Simulator job runs. The next job creates them again.

Only one Simulator job (`make run`, `make e2e`) runs at a time on the Mac.
The others wait and say so.
After `make run`, run `make simulator-shutdown` as soon as you are done with your check, so the others can go on.
This removes the app from the Simulator and frees the lock.
It does not shut down the Simulator at once.

Why one job, and no second Simulator: a second Simulator takes the whole CPU of the Mac.
On 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running on this Mac, for any reason: a faster job, a Simulator for QA, a Simulator for `make run`, or a second job slot.
This is a closed decision, not a trial on pause.
Only the prompter can open it again, and only with a new reason (for example, a different Mac).
The measurements behind it (8-core Mac, 16 GB):

- 2026-09-27, a second Simulator job next to the first one: load average 257 to 286, and the second job ran about 3 times slower than alone (TASK-62).
- 2026-09-27, a QA Simulator that booted during a `make e2e`: load average 326 (TASK-84). So QA uses the shared Simulator and its lock too.
- 2026-09-28, the boot of a second Simulator next to the booted `RATP-Shared`, with no job: load average 333 for the first boot of a new Simulator (the Mac did not answer for about 1 minute), and 234 for a cold boot of the existing small Simulator (TASK-106).
  A boot with no other Simulator booted measured lower: about 125 to 157 (TASK-84, TASK-92).

The code of a second job slot is still in `ios/scripts/sim-lock.sh`, but it is off, and it stays off. Do not turn it on. The CLAUDE.md (section "Budget for this repo") explains the numbers and the decision. `make run SMALL=1` follows the same rule: one shared Simulator at a time (see below).

### The smallest iPhone

To check a screen on the smallest iPhone that the app supports, run:

```sh
make run SMALL=1
```

It opens the app in a second shared Simulator, named `RATP-Shared-Small`. It is an iPhone SE (3rd generation): 375 x 667 points, the narrowest and the shortest screen. `RATP-Shared` is an iPhone 17 (402 x 874 points).

- It takes the Simulator lock and keeps it, like `make run`. `LIVE=1` works with it too.
- It shuts down `RATP-Shared` before it boots `RATP-Shared-Small`, and a job on `RATP-Shared` shuts down `RATP-Shared-Small` first.
  Only one shared Simulator is booted at a time.
  So each size switch waits for a cold boot of the other size.
  This cost is accepted: on 2026-09-28, the prompter decided that no design may keep a second Simulator running for speed (TASK-119).
- `make simulator-shutdown` removes the app from `RATP-Shared-Small`, and keeps it booted for the next `make run SMALL=1` (until a job on `RATP-Shared` shuts it down). Like `RATP-Shared`, it shuts down by itself after 5 minutes with no job.
- `SMALL=1` works only with `make run`. The end-to-end tests and the docs screenshots always use `RATP-Shared`.

### The language of the Simulator

The app is in French and in English. It follows the language of the phone (see [Languages](#languages)). To see it in French, run:

```sh
make run LANGUAGE=fr
```

- `make run` puts the Simulator in English, as before. `LANGUAGE=fr` puts it in French (language French, region France). The whole Simulator changes: the app, the Live Activity, the Dynamic Island, the notifications and the permission popups.
- To switch the language of the open app, run `make switch-language LANGUAGE=en` (or `LANGUAGE=fr`) after `make run`.
  It changes the language of the Simulator, restarts the home screen (SpringBoard), and opens the app again.
  It keeps the app, its data and its permissions, so you do not set up the app again.
  The Live Activity shows in the new language.
  A notification that the app sent before the switch keeps its old language.
  It works only while this folder keeps the Simulator after `make run`, and it uses the same Simulator (also after `make run SMALL=1`).
- `make e2e` and `make docs-screenshots` always put the Simulator back in English: the tests and the docs screenshots are in English.
- `LANGUAGE=` works only with `make run` and `make switch-language`.

Before the shared Simulator, each folder had its own Simulator, named `RATP-<folder>-<hash>`. To delete these old Simulators, run `make simulator-delete-old`.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

## The main screen

The app is the Live Activity. The main screen shows only:

- **One action.** "Show the Live Activity now" shows the Live Activity of the station nearest to you.
  You do not pick the station.
  If the app cannot find a station (no location access, no metro or RER station near you, no position), it says why.
  While a Live Activity shows, the screen says which station ("On the lock screen: <station>") and has "Stop showing on the lock screen" instead.
- **The automatic mode.** The Live Activity starts by itself near a station (see [below](#the-live-activity-starts-and-stops-by-itself-near-a-station)).
  The switch "Automatic mode" turns it off or on.
  "Snooze" stops it for 30 minutes, 1 hour, or for the rest of today.
  While a snooze is on, the screen says "Snoozed", the time when the automatic mode comes back, and the time left.
  "Cancel the snooze" ends the snooze at once (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)).
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

Each line of a station also has its official color (`color`: the color of the line, and the color of the text on it).
It comes from the dataset `referentiel-des-lignes` of Île-de-France Mobilités (fields `colourweb_hexa` and `textcolourweb_hexa`, made for web and phone screens).
The Live Activity uses only these colors for the lines.

To see the list in the app, open "Testing tools" and tap "All stations". Each station shows its lines. Type part of a name in the search field to find a station. The search ignores case, accents and hyphens: `chatelet` finds "Châtelet".

To download the list again, run `make stations`. It needs Python 3. Commit the new `stations.json`.

The script also gives a `hubId` to the stations of one place with different names (for example Châtelet and Châtelet - Les Halles).
It comes from the "pôles d'échange" of Île-de-France Mobilités (dataset `relations`, field `pdeid`).
`StationCatalog.hubStations(of:)` gives the stations whose lines show for a station: the station itself, then the other stations of its place, nearest first, each with only the lines that the stations before it do not have.
For a station with no `hubId`, it gives only the station.

The script also gives the stop area (`stopAreaIds`) of each metro line of a station.
A metro line has one stop (quay) for each direction, in `stopIds`.
All the quays of one metro station are in one stop area.
It comes from the dataset `arrets` of Île-de-France Mobilités (field `zdaid`).
For example, the quays 22059 and 463116 of Abbesses are in the stop area 42155.

Some names in the open data are wrong or spelled in two ways. The script fixes them with the table `STATION_NAMES` in `ios/scripts/update-stations.py`. If a unit test says that two stations "look like the same station", add the bad name to this table.

## Next trains of a station

Debug builds can show the next trains of a station that you pick by hand. This needs no location permission. Release builds do not have this screen.

1. Open "Testing tools", then tap "Next trains of a station" at the bottom.
2. Tap "Pick a station". Type part of a name to find a station, then tap it.
3. The screen shows the next trains of each line and destination, in minutes.
   It shows only the trains of the next 60 minutes: PRIM sometimes gives a time much later (for example 154 min), and it is not a real prediction.
   When PRIM gives a destination only times more than 60 minutes away, the screen still shows its row, with "Next train in over 1 hour" instead of the times.
   The app asks for new times every 30 seconds while this screen is open.
4. Tap "Change station" to pick another station.

The app remembers the picked station when you close it.

The screen tells you when:

- the train data key is not set (see below),
- the station has no live data right now,
- the app cannot reach the train data service (for example, no internet),
- the service refuses the key, gets too many requests, or does not work.

For developers: the code is in `ios/Packages/RATPCore/Sources/RATPCore/Trains`.
`PRIMDeparturesProvider` calls the PRIM API "stop-monitoring" once for each stop area of the station, and of the other stations of its place (see [The station list](#the-station-list)).
So Châtelet costs 2 calls: the metro stop area of Châtelet (its 10 metro quays) and the RER stop of Châtelet - Les Halles.
Saint-Lazare costs 5 calls.
A stop area id `IDFM:monomodalStopPlace:<n>` (the `stopAreaIds` of a metro line, the `stopIds` of an RER line) becomes `STIF:StopArea:SP:<n>:`.
A metro line with no stop area asks for each quay: its stop id `IDFM:<n>` becomes `STIF:StopPoint:Q:<n>:`.
The answer for a stop area can have trains of lines that the app gives to another station of the place.
The app keeps only the trains of the lines that it asked this stop area for.
`CurrentStationModel` holds the station that the tester picked.
`NextTrainsModel.updatingStationId` says which station the screen keeps up to date, so the Live Activity does not ask PRIM for the same station twice.

## Show the next trains on the lock screen (Live Activity)

The app shows the next trains of a station on the lock screen, as a Live Activity. On an iPhone with a Dynamic Island, it also shows there.

1. On the main screen, tap "Show the Live Activity now". It shows the Live Activity of the station nearest to you. Testers can also pick any station in "Testing tools" > "Next trains of a station", and tap "Show on the lock screen".
2. Lock the phone.
   The Live Activity shows the station, the line, and the next trains in both directions of the line.
   Each direction has the name of its end of line, the waiting time of the next train, and the waiting time of the train after it (when there is one).
   The Live Activity shows only the trains of the next 60 minutes, like the next trains screen.
   A direction whose next train is more than 60 minutes away says "In over 1 hour", and the Dynamic Island says "> 1 h" when no direction has a train in the next 60 minutes.
   A direction with no upcoming train at all says "No trains".
   At the end of a line, the Live Activity shows only the other direction.
   The Live Activity must fit in the space that iOS gives it on the lock screen (160 points high), with its snooze buttons.
   So each name stays on one line: a long name gets smaller, and if it is still too long, it ends with "…".
   When the Live Activity shows 3 rows, each row shows only its next train.
   When you touch and hold the Dynamic Island, it has less room than the lock screen (160 points high, with the camera at the top).
   So when the trains and the snooze buttons do not fit, each row shows only its next train.
   If they still do not fit (for example a line with three directions), the rows use a smaller text.
   The content always keeps a small space above the bottom edge, so the last snooze button stays out of the round corner of the Dynamic Island.
   At a station with several lines (for example Châtelet), the Live Activity shows every line, with no choice to make, one page at a time.
   Each line has its own page: a metro line with the strips of that line, an RER line with the rows of the RER screens (see below).
   The header of a page has the badge of the line of the page (a circle on a metro page, a rounded square on an RER page, both 26 points high, so the header does not move from one page to the next), the station name, and at the right end a small "+N >", where N is the number of the other lines of the station (for example "+7" at Châtelet).
   It never shows the badges of the other lines.
   To see the next page, tap anywhere on the header (the badge, the name or "+N >"): the whole header is one button, at least 44 points high (its tap area goes past the drawn row, so the row is not taller for it).
   After the last page, the first page comes again.
   "+N >" is at the same place on every page, also on the RER pages, so you can tap many times in a row without aiming again.
   "+N" counts the other lines of the station, metro and RER (one page for each line).
   The order of the pages is the order of the lines (below).
   A line of another station of the place (below) has a walking icon and the name of that station in the header, in the place of the station name, so the rider knows where to walk (on a page in rows, this label is next to the badge of the line).
   VoiceOver reads the header as the line of the page and the station (or "walk to" the other station), then "Show the next line" and the number of other lines.
   The same header shows in the Dynamic Island when you touch and hold it.
   The Dynamic Island, when you do not touch it, shows the line whose train comes first, of all the lines of the station, and its waiting time (see below).
   Why one line per page: a page of one line keeps the full strips or rows under the 160 points of the lock screen, like a real platform panel, which shows one line (decision-18, decision-21).
   It costs more taps at big stations: Châtelet has 8 pages (5 metro lines, then RER A, B and D, each alone because they are at Châtelet - Les Halles), Opéra 9 and Saint-Lazare 9 (2, 1 and 2 pages more than before), and a station with two metro lines has two pages.
   Châtelet - Les Halles has 8 pages and Gare du Nord 6: one more each than when the RER lines of a station shared a page.
   Some places are two or more stations in the station list, with different names: for example "Châtelet" (metro 1, 4, 7, 11, 14), "Châtelet - Les Halles" (RER A, B, D) and "Les Halles" (metro 4) are one place, joined underground.
   The Live Activity of one of these stations shows the lines of all of them together, as one station.
   When two of them have the same line (metro 4 at Châtelet and Les Halles), it shows the trains of the station itself, else of the nearest station.
   The lines of the station itself come first (metro by number, then RER).
   The lines of the other stations follow, from the nearest station to the farthest.
   So at Châtelet - Les Halles, RER A, B and D show first, then metro 4 (Les Halles), then metro 1, 7, 11 and 14 (Châtelet).
   The next trains screen of the testing tools shows the same lines.

   Some lines split into branches: metro 7 (Mairie d'Ivry or Villejuif), metro 13 (Saint-Denis or Asnières-Gennevilliers), and the RER lines.
   On these lines, the Live Activity names where the trains go.
   On an RER page, each train has its own row, with its own destination.
   On a metro row, when the next two trains of a direction go to different places, each train shows its own destination next to its waiting time, so they never look the same.
   When they go to the same place, the direction shows that place.
   After the fork, a station names only the end of its own branch (for example "Asnières - Gennevilliers - Les Courtilles" at Brochant).
   On a branch, a train that ends before the fork goes into the other direction (for example a train to Paris Gare de Lyon or Corbeil-Essonnes at Boigneville, on RER D, is in the Creil direction and shows its destination).
   On the trunk of an RER line (the stations before every fork, for example Vincennes or Châtelet - Les Halles on RER A), a train that ends at a station of the branches of one direction goes into that direction and shows its destination (for example a train to Sartrouville at Vincennes is in the Saint-Germain-en-Laye / Cergy le Haut / Poissy direction).
   A train whose direction stays unknown there is not on the Live Activity (the next trains screen still shows it), so each direction keeps its next two trains.
   A train that ends before the end of the line (for example at Trocadéro on line 6) also shows its destination.
   RER stations show both directions too, like metro stations.
   For example, at Châtelet - Les Halles, RER B shows the trains to the north (Aéroport Charles de Gaulle 2 TGV or Mitry - Claye) and the trains to the south (Robinson or Saint-Rémy-lès-Chevreuse), even when the soonest trains all go north.
   A metro line looks like the PANAM screens on the metro platforms.
   Its badge is a circle with the number of the line, in the official color of the line (from the station list, see above), also for 3bis and 7bis ("bis" is smaller).
   The app draws the badge itself: it does not use the RATP or Île-de-France Mobilités pictograms, which the app may not share.
   On every metro page, each direction is a strip, like a small platform panel: a white plate with a thin bar in the color of the line and the end of line in bold dark blue, then a black box with the waits of the next two trains in large amber numbers, with a thin rule between them.
   The numbers are bare, like on the platform: "4" means 4 minutes.
   At a station with one line, the header says "1er" and "2e" ("1st" and "2nd" in English) above the two columns of numbers; a page with "+N >" has no such words.
   When the station name does not fit next to them, these two words go first.
   Then the name gets smaller, down to 60% of its size.
   Then, only on a page with one strip or none, the name goes onto a second line; else it is cut.
   Why: a page with two strips is 144 points high at the default size (155 points when its times are old), so a second line of the name (about 20 points) would push it over the bar of 156 points.
   With the station list of today, no name needs the second line: the longest one, "Aubervilliers - Pantin - Quatre Chemins", is whole on the iPhone 17 and the iPhone SE.
   A wait is in whole minutes, rounded up: "1" means that the train leaves in less than one minute, and the countdown never says "0" before the train leaves (the "0" of the last minute before the train arrives is a state of its own, see below).
   The number counts down by itself, minute by minute, also when the app is closed (it is a timer of iOS that shows only its minutes).
   When a train arrives in less than one minute, its box says a bare "0", as the real PANAM screens do (decision-27; steady: a Live Activity cannot blink).
   While the train is at the platform (PRIM says `VehicleAtStop`, or the time is between its arrival and its departure), its box says "À quai" ("At the platform" in English), on one line, like the platform screens.
   When it does not fit on one line at that size, it gets smaller, in two steps, then goes onto two lines ("At the platform" always takes two lines).
   A direction whose next train is more than 60 minutes away says "In over 1 hour", or "> 1 h" when the words do not fit in the box, and a direction with no upcoming train at all says "No trains" in its box.
   With one train only, the second column is empty.
   At the end of a line, there is one strip.
   On metro 7 and 13, before the fork and at the fork (and at the end stations La Courneuve - 8 Mai 1945 and Châtillon - Montrouge), the direction toward the fork goes to two ends of line.
   It is one strip too, a "tagged" strip: its white plate lists both ends, one above the other, in the same bold text (smaller than on a plain strip, so that the page keeps its height), in the order of the line (metro 13 to the north: Saint-Denis - Université, then Asnières - Gennevilliers - Les Courtilles; metro 7 to the south: Mairie d'Ivry, then Villejuif - Louis Aragon).
   Each end starts with its mark: a small yellow dot (#FFDF00) for the first end, a small blue square (#009FE3) for the second one, in the yellow and the blue of the metro map, with no border (decision-24).
   The square has the same area as the dot, so the two look the same size, and the two marks differ in shape, so the colour is never the only cue.
   A mark is never a triangle, never hollow, and never amber, orange or red, because these are the shapes and colours of a warning, and amber is the colour of the waits (decision-23).
   In the black box, a one-digit wait stays centred in its column, under the wait of the strip below, with its mark at its left; when the mark has no room there (for example two digits), the mark and the wait are centred together.
   For a train at the platform, the mark is centred above "À quai", so that the words keep the width of the box (TASK-157).
   The black box shows the next two trains of the direction, in time order, and each number has the mark of the end of its train.
   The plate never changes with the trains: only the marks on the numbers follow them.
   So a rider for one branch may see one number for their end, or none when the next two trains both go to the other end.
   The other direction is a plain strip.
   A station after the fork names only the end of its branch, so its page has plain strips.
   VoiceOver reads each strip as its end of line and its waits in minutes (for example "Mairie d'Issy, 4 minutes, then 8 minutes"), and a tagged strip as its two ends, then each wait with the end of its train (for example "Saint-Denis - Université and Asnières - Gennevilliers - Les Courtilles, 3 minutes to Saint-Denis - Université, then 7 minutes to Asnières - Gennevilliers - Les Courtilles").
   The strips are for every metro page of the 321 metro stations of the station list: the 248 stations with one line and no hub (220 with plain strips and 28 with a tagged strip), and the 186 metro pages of the 73 stations with several lines or a hub (a tagged strip on the page of metro 7 or 13 at 22 of them, for example Maison Blanche, the fork of metro 7, which also has metro 14).
   A metro page keeps rows (one row for each direction, or for each branch of a direction: its destination, then the waiting times of its next trains, in amber in a black box, for example "4 minutes") only for as long as it lasts:
   a direction whose next two trains go to two different places (for example a train that ends early at Trocadéro on line 6), or a tagged direction with a train that goes to neither of its two ends (a train that ends early), so that the rider always knows which train goes where.
   In these rows, "1 minute" means that the train leaves in less than one minute, the box says "Approaching" or "At the platform", and the waits count down by themselves too.
   While the app runs in the background, it draws the Live Activity again when a train on it (metro or RER) starts approaching, arrives or leaves, with the train times that it has (no new PRIM call).
   So the box changes by itself.
   Like an RER direction, a metro row whose next train is more than 60 minutes away says "In over 1 hour", and a row with no upcoming train at all says "No trains" (a line with no upcoming train in any direction says it once, next to its badge).
   The app has no timetable, so it cannot tell a line that stopped for the night from a line that is closed for a while (works or an incident): it never says that the service ended.
   When PRIM has no train at all for the station, the Live Activity shows each line of the station with "No trains", not "No data available".
   An RER line looks like the current RER A screen on the platforms (decision-21, decision-33).
   Its badge is a rounded square with the letter of the line, white or black on the official color of the line (from the station list), drawn by the app, for the five lines A to E: no RER, SNCF or Île-de-France Mobilités pictogram.
   No badge of the Live Activity is grey, hollow or outlined.
   Below the header, each direction is a white plate with a thin bar in the color of the line, and one row for each of its next trains (two at most, or one when the line shows three directions), in time order.
   A row is the destination of its train, in bold dark blue (one size smaller than on the metro strips, 13 points at the default size), then a black box with its wait in amber.
   The black box has the left edge and the width of the box of the metro strips, so nothing moves from a metro page to an RER page.
   The two directions are never mixed in one plate.
   The wait is a bare number, rounded up, that counts down by itself, like on the metro strips (15 points at the default size), with no unit.
   In the last minute, the box says "Approaching" ("À l'approche"); while the train is at the platform (PRIM says `VehicleAtStop`, or its time is between its arrival and its departure), it says "At the platform" ("À quai").
   An RER row never says "0".
   The two words share one size, the largest at which the longer of the two fits the box with a margin of 4 points on each side (13 points in French at the default size; 9 points in English, for "At the platform").
   The smallest sizes grow with the box at large text sizes, so the words never touch its edges.
   The RER row draws no other status: PRIM gives none that a rider can trust (decision-33).
   A direction whose next train is more than 60 minutes away says "In over 1 hour" (or "> 1 h") in its box, and a direction with no train says "No trains".
   When the times are old, each direction keeps one row with its name and an empty box.
   VoiceOver reads each row as its destination and its wait in minutes, or "Approaching" or "At the platform" (for example "Saint-Germain-en-Laye, 3 minutes").
   Like the real screen, an RER page shows only the next trains of each direction, so with three ends in one direction (for example Saint-Germain-en-Laye, Cergy le Haut and Poissy on RER A at Auber), the train of one end may not be on the page.

   The Dynamic Island, when you do not touch it (the compact view), shows the badge of a line on the left of the camera and the wait of its next train on the right, as a bare amber number, like on the platform: "4" means 4 minutes, with no "min" and no "dans" (decision-28).
   The badge is the circle of a metro line, or a rounded square with the letter of an RER line, both drawn by the app in the official color.
   No system icon of a tram or a train.
   The line is the one whose next train comes first, of all the lines of the station and of the other stations of its place, also the lines of the other pages: so at a hub (for example Châtelet) the line changes by itself as the trains come and go, and the badge and the number always belong to the same train.
   The number counts down by itself, rounded up like the strips.
   A train less than one minute away says "0" (for the metro and the RER: "À l'approche" does not fit, decision-27 and decision-28), and a train at the platform says "À quai" ("At the platform" in English) on one small line.
   A word wider than 60 points goes onto two lines (and shrinks a little if a line is still too wide), so that the island stays narrow: the English "At the platform" does (on one line it made the island as wide as the status bar).
   With no upcoming train, the island says "No trains" ("Pas de train") on two small grey lines; when the next train is more than 60 minutes away, it says "> 1 h".
   These words have one size.
   When the times are old (the Live Activity is stale), it shows a grey dash, never a number that may be wrong.
   On metro 7 and 13, when the next train is on a tagged strip, its mark (the yellow dot or the blue square) sits at the left of the number.
   When another app's Live Activity also shows, iOS gives ours a small round place (the minimal view): it shows the wait alone, as a bare amber number, with no badge.
   There the last minute and the platform both say "0" (a word does not fit), and stale, no train and "> 1 h" show a grey dash.
   The cost of this choice (the prompter's, decision-28): next to another app's Live Activity, the number alone does not say which line it is.
   VoiceOver reads the line, then the wait in minutes, or "Approaching", or "At the platform", never "zero".
   The compact and minimal views have no button (Apple allows controls only on the lock screen and in the expanded view).
3. To remove it, open the app and tap "Stop showing on the lock screen".
4. To remove it and snooze the automatic mode, tap "30 min", "1 h" or "Today" at the bottom of the Live Activity (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)). The same buttons show in the Dynamic Island when you touch and hold it.

The Live Activity can also start and stop by itself near a station (see below).

The first time, iOS asks on the lock screen if it can show Live Activities from RATP Activity. Tap "Allow".

The waiting times count down by themselves, in whole minutes (a bare "3" in a metro strip or an RER row, or "3 minutes" in a metro row, see above).
The app sends new train times every 30 seconds while the app is open.
While the app is in the background, it sends new train times a few seconds after the first shown train leaves (at most every 30 seconds, and at least every 2 minutes).
When you lock the phone (or leave the app) while the Live Activity still says "Loading the next trains...", for example right after you tap the arrival notification, the app asks for the train times again at once in the background: the first trains do not wait for the next background refresh.
Between two calls, it draws the Live Activity again at each moment when a train on it changes (see above).
It stops asking PRIM when PRIM rejects the key or says the daily quota is used up.
This works while iOS keeps the app running in the background (see the limit below).
When the first shown train has left and no new times came, the Live Activity hides its waiting times and says "Open the app for new times" (iOS does it by itself, also when the app is closed).
The strips stay, with their ends of line, and their boxes are empty.
It says the same if the train times take too long to load (its stale date is 1 minute after the "Loading" content, so 2 minutes with the rule below).
iOS does it at the stale date of the content (`ContentState.staleDate`: the first shown train), but never sooner than 2 minutes after the last content that the app sent.
Apple does not document this rule.
The log of the Simulator shows it: `liveactivitiesd` schedules its task "Marking activities stale" at the later of the two dates, and ActivityKit has no setting for it (TASK-150).
While the app runs, this does not matter: the app sends a new content when the train leaves.
When the app does not run (closed, or killed by iOS) and its last content came more than 2 minutes before the train left, iOS hides the times 1 to 3 seconds after the train left.
When that content came less than 2 minutes before the train left, it stays until 2 minutes after it came: a "0" in a strip ("0 minutes" in a row) for up to about 1 minute after the train left, and "0" (approaching) or "At the platform" for up to about 2 minutes.
When no direction has a train in the next 60 minutes, the same happens when the first train comes within 60 minutes and no new times came: the Live Activity hides "In over 1 hour" and "> 1 h".
When a refresh fails (no network, a time out, a PRIM error, a rejected key or a used-up quota) while the Live Activity shows train times of its station, the Live Activity keeps the last times.
They keep counting down, and the rule above applies: once the first shown train has left and no new times came, the Live Activity hides them and says "Open the app for new times".
Until that moment, the app still draws them again when a train on them changes, but not after it.
The next refresh that works shows its times at once.
If the app has no train times for the station (no key, or the first load fails, also after a switch to another station), the Live Activity says "No data available".
It says the same when a refresh fails after an answer with no train at all ("No trains"), because "No trains" never goes stale.

If the app says that Live Activities are turned off, turn them on in Settings > RATP Activity > Live Activities.

For developers: `StationActivityAttributes` (in `RATPCore`) holds the data of the Live Activity.
`LineDirections` splits the trains of the line into its two directions.
For a metro station, PRIM has one stop (quay) for each direction, so the direction of a train is its quay.
The app asks for the stop area of the station, and PRIM tells the quay of each train (`MonitoringRef` of the train).
When PRIM does not tell the quay, the direction of a train comes from its destination (the end of line names).
The end of line names are in `TransitLine+Ends.swift` (a unit test checks them against the station list).
A train that ends before the end of the line (for example at Trocadéro on line 6) goes into the direction of its quay.
Each train of a direction keeps its destination (`LineDirection.Train`).
When the trains of a direction have different destinations, the view shows the destination of each train (`LineDirection.showsEachDestination`).
Else it shows one name above the times (`LineDirection.name`): the destination of the trains, or the name of the direction when it has no train.
For metro 7 and 13, `branchStations` in `TransitLine+Ends.swift` lists the stations after the fork, so these stations name only the end of their branch (a unit test checks the names against the station list).
At a station of a branch, a train whose destination is neither an end of line nor a station of any branch goes into the other direction: it ends before the fork.
So does a train to a station that two branches of the side share, when the station of the Live Activity is on only one of them (for example Corbeil-Essonnes at Saint-Fargeau, on RER D): it ends before the fork of this branch.
This rule does not apply to a train to another station of a branch (for example Versailles Chantiers or Juvisy at Orly Ville, on RER C): its direction comes from the rules below.
At a station of the trunk of an RER line (a station that is neither an end of line nor in `branchStations`, for example Vincennes or Châtelet - Les Halles on RER A), a train that no rule above or below places goes into the direction whose branches hold its destination, when the branches of only one direction hold it (for example Sartrouville, on the branches of Cergy le Haut and Poissy).
An RER station has one stop area for both directions.
PRIM tells the quay (track) of each RER train (`ExpectedQuayRef`), and a quay serves one direction, so the trains of a quay go into the same direction.
A quay gets its direction from the destinations of its trains (the RER end of line names and branches are in `TransitLine+RERLineEnds.swift`, checked against the station list).
When a quay has only trains that end before the end of the line, the app uses the direction that PRIM gives (`DirectionRef`, "Aller" or "Retour"), but only when PRIM gives both values at that station: on RER A, PRIM gives "Aller" to every train.
A train whose direction stays unknown shows in a row with its destination (at most 3 rows), except at a station of the trunk of an RER line: there it is not on the Live Activity, so a short trip never adds a third row, which would keep only the next train of each row (TASK-171).
On a metro line, PRIM sometimes lists one train twice, with two times less than a minute apart.
No metro train leaves a platform less than a minute after the train before it, so a direction keeps only the first of two trains that leave less than a minute apart (`LineDirections.minimumMetroHeadway`), and it never shows the same train twice.
An RER direction keeps them: two RER trains of one direction can leave in the same minute from two tracks.
`LinesPage` (in `RATPCore`) decides which lines the Live Activity shows: from the first asked line, one metro line alone, or as many RER lines as fit in 4 rows (at least one line, and never a metro line with an RER line).
With more than 2 rows, it keeps only the next train of each row, so the Live Activity stays under the 160 points of the lock screen.
It also keeps the soonest train of all the lines, for the Dynamic Island (`SoonestTrain`: its line, the train with its state, and the mark of its end on a tagged strip), and, when no line has a train in the next 60 minutes, the line of the first later train.
`ContentState.dynamicIslandWait(isStale:)` (in `RATPCore`, `DynamicIslandWait`) decides what the compact and minimal views show: the line, the mark, and the wait (minutes, approaching, at the platform, over an hour, no train, stale, loading or no data), and what the minimal view shows instead (`minimalWait`: the minutes, "0" or a dash).
The views are `IslandLineBadge` (`MetroLineBadge`, or the `RERSquareBadge` of the RER pages), `CompactIslandWait`, `MinimalIslandWait` and `IslandNumber`, in `ios/Widget/`.
The number (20 points) and the words (11 points) have fixed sizes: the compact island of iOS draws every text style at about the same size (title3 at about 14 points, caption2 at about 13), so with text styles the number was smaller and the words bigger than in the picked drawing (TASK-37 review).
When you touch and hold the Dynamic Island, the view tries the page as it is, then the page with only the next train of each row (`ContentState.keepingOnlyTheNextTrains`), then the same with a smaller text, and shows the first one that fits (`ViewThatFits`).
`PlatformStatus` (in `RATPCore`) says when a train is approaching or at the platform, from the arrival time, the departure time and `VehicleAtStop` of PRIM.
`LineDirection.trainsByDestination` gives the rows of a direction: one row, or one row for each branch.
`LineDirection.Train.roundedUpCountdownEnd` rounds the live waiting time up: the lock screen counts the minutes by itself between two updates, and it must never say "0 minutes" before the train leaves.
iOS does not draw a Live Activity again by itself when a train comes, so in the background `AutoLiveActivityModel` wakes at `LinesPage.nextRedrawDate(after:)` (a metro train starts approaching, arrives or leaves; an RER train leaves;
the soonest train of the station, on any page and of any line, starts approaching, arrives or leaves, for the Dynamic Island) and `StationLiveActivityModel.redraw()` builds the content again at that time, with no PRIM call.
`Date.ComponentsFormatStyle` ("4 min") stayed frozen until the next update in a Live Activity, so the metro rows use the SwiftUI style `.offset` ("4 minutes"), which counts down by itself.
No format of iOS gives a bare number that counts by itself, and a format style of our own (a `DiscreteFormatStyle` with `TimeDataSource`) makes iOS draw the whole Live Activity as a grey placeholder (TASK-140).
So the strips (`ios/Widget/PanamStrip.swift`) and the compact and minimal views of the Dynamic Island use `PanamMinutes`: the timer of iOS (`Text(timerInterval:countsDown:)`, "m:ss"), in a box as wide as its minutes, with the ":ss" part outside the box and hidden.
Its end is `roundedUpCountdownEnd`, so it shows the same number as `.offset`.
`LineDirection.Train.countdownMinutes(at:)` gives the number that it shows when the view is drawn, for the width of the box (one or two digits: the number only goes down).
A wait drawn with two digits can count below 10 before the next update, and its one digit must then stay in the centre of its column (TASK-151).
No layout runs between two updates: iOS only aligns each self-counting text again in its frame.
So `PanamMinutes` draws two layers, and each one is one text with the same timer twice.
The layer of two digits is aligned to the right: when the timer loses a digit, the second timer is shorter, and the first timer goes to the right, out of the box.
The layer of one digit is aligned to the left, with a clear digit between the two timers: while the timer has two digits, the box shows only that clear digit; when the timer loses a digit, the second timer comes one digit to the left, into the box.
Page 95 of Lamarck - Caulaincourt in the render check draws this case.
`LinesPage.panamStripsLine` (in `RATPCore`) decides if a page gets the strips:
one metro line (also a line of another station of the place, whose name `PanamStripsHeader` shows with the walking icon), at most two directions (a train whose direction stays unknown adds a third one, which would push the snooze row out), a page made by an app that knows the ends at the station (`LineTrains.hasADirectionWithTwoEnds` is set;
a Live Activity of an app older than TASK-140 has rows until the app updates it), and no direction whose shown trains go to two places, except a direction with two ends at this station.
`LineDirections` gives that direction its two ends in the order of the line (`LineDirection.branchEnds`, from `TransitLine+Ends.swift`, so the order never depends on the trains), and it gets the tagged strip while each of its trains goes to one of these ends (`LineDirection.branchEndIndex(of:)` gives the mark of a train).
`PanamStripsView` draws the page, `PanamStripsHeader` its header (the order above:
the words "1er" and "2e", then smaller steps of the name, then a second line, only when `LineTrains.hasRoomForATwoLineStationName`), `PanamBranchEnds` and `PanamBranchMark` the plate and the marks of a tagged strip, and `PanamAtPlatformText` the words of a train at the platform (the largest of its one-line sizes that fits, else two lines, with `ViewThatFits`).
Every strip of every page has the same width of its number boxes (`cellWidth` in `PanamStripsView`), so the plates and the boxes line up.
The RER rows use `WaitingTime` (`Date.AnchoredRelativeFormatStyle`, "in 3 min."), which counts down by itself too.
The header of a page with other lines is a button with `ShowNextLinesIntent` (`LinesPagerButton`, with `OtherLinesControl` for "+N >", used by the strips and the rows): iOS runs it in the app (in the background), and `StationLiveActivityModel.showNextLines()` shows the next lines.
The Live Activity shows the first lines again when it starts or switches to another station.
`StationLiveActivityModel` starts, updates and stops it.
The view is in `ios/Widget/StationLiveActivity.swift`.

### Check how the Live Activity draws

`make live-activity-render` draws the Live Activity views for every station of the list and every page of its lines, and saves the results in `ios/.build/live-activity-render/`.
Run it before and during a task that changes these views (for example TASK-36, TASK-65, TASK-37), and give its output to the reviewer and QA.
It replaces the temporary UI tests that each Live Activity task wrote before.
It is not part of `make check` or `make e2e`: it saves images and lists for a person to read, and it fails only when it cannot run.

- **What it draws.** The lock screen view (`LockScreenView`) at the width of the iPhone 17 (373 points) and of the iPhone SE (355 points), and the bottom region of the expanded Dynamic Island (`ExpandedIslandBottomRegion`, 338 points), at the default text size (Large) and at the largest size that iOS uses for a Live Activity (XXXL), fresh and stale (the "Open the app for new times" state).
  The data comes from the rules of the app: each station with the stations of its hub, the fake trains of the testing tools, and every page of lines.
  The views are drawn inside a unit test bundle (`ios/RenderCheck/`), with SwiftUI's `ImageRenderer`: no lock screen.
  The test bundle runs in a small host app (`ios/RenderCheck/Host/`) that holds the String Catalog of the widget, as the widget extension does, so the texts are the ones that a rider reads.
  It draws in French (the main language, region France).
  `make live-activity-render ENGLISH=1` then draws the same in English (region United States).
  Each language has its own folder: `ios/.build/live-activity-render/fr/` and `ios/.build/live-activity-render/en/`, with the same file names.
  The test fails when the texts are not in the language that it draws.
  Why English only on demand: the French texts are longer, and on 2026-09-29 the English render found no too tall drawing and no cut image that the French render did not find too, for about 130 s more of Simulator time.
  Add `ENGLISH=1` when the task changes an English text of the Live Activity.
  The render leaves its host app on the shared Simulator.
  The next job removes it.
- **What it reports.** For each language that it draws, `heights.csv` has the height of each drawing, in points, drawn at 3x like the iPhone (so a height is a multiple of a third of a point, for example 137.33).
  `too-tall.csv` lists the drawings taller than the limit of their text size, and the command prints their count for each surface and size:
  160 points on the lock screen at the default size (iOS cuts the Live Activity there), 195 points at XXXL (the tallest Live Activity that TASK-124 saw whole at that size, not a proven limit), and 87 points for the bottom region of the Dynamic Island at the default size, on a page with one line (the station name is then in the center region).
  A hub page of the Dynamic Island has more room, not measured yet: it has no limit, and only its images are saved.
  The images (PNG, 3x) are saved for every station of a hub (23 stations today: only they show station labels, so only they can show a cut label or a destination squeezed by a label), and for 33 stations with the extreme cases (the biggest hubs, the longest station and line names, RER branches, Gare du Nord, where TASK-112 saw French times cut, 10 stations with the metro strips of TASK-140:
  the longest station names and ends of line, an end of line, 3bis and 7bis, and 4 stations of the tagged strip of TASK-143: Liège, Tolbiac, the fork La Fourche, and the longest name Aubervilliers - Pantin - Quatre Chemins, and 4 stations of the pages of one metro line of TASK-144:
  Pigalle, with two metro lines, Maison Blanche, the fork of metro 7 with metro 14, Bibliothèque François Mitterrand, the longest name of a station with several lines, and Palais Royal - Musée du Louvre, and 3 stations of the RER rows of TASK-65: Invalides, Gare de Lyon and Auber, Auber being also a station of a hub): 52 stations in all.
  It also draws the metro strips of Lamarck - Caulaincourt with every state of a wait (approaching, at the platform, one train, two digits, more than 60 minutes, no trains, the end of a line), as pages 90 to 94 of that station, and a wait drawn at 11 that counted down to 9 by itself, next to a wait drawn with one digit, as page 95,
  and the tagged strip of Liège with every state ("0" (approaching) and "At the platform" with their marks, one train, two trains to the same end, no train, more than 60 minutes, and a train to a third end, which gives rows), as pages 95 to 100, and a train at the platform in the first box, in the second box (with the plain strip at the platform too) and in both boxes,
  next to a wait of two digits, as pages 101 to 103.
  Pages 104 to 107 of Liège have a made-up station name that is too long for one line, with two strips (the name is cut), one strip, none (the name goes onto a second line), and two strips with a train at the platform.
  Pages 108 and 109 of Liège are the header of the hub Place de Clichy (with "+1 >") with a train at the platform.
  The RER rows are drawn with every state of a wait as pages 100 to 102 of Auber ("At the platform" and "Approaching" with two-digit waits, no trains and more than 60 minutes, three directions with one train each) and page 103 of Invalides (RER C with the longest ends of line).
  `cut-texts.txt` lists each text of these images that ends with "…" (the text recognition of macOS, Vision, reads it as "...").
  `cut-texts.txt` does not decide if a cut is a bug: a person reads the list and the images.
- **The breaches of decision-15.** decision-15 (in the backlog) is the product rule of what may be cut when a row of the Live Activity is too narrow.
  In the images, the command finds the texts that break it, and prints their count for each language, phone, surface and text size (0 included), then each breach with its station, page, surface, size and image.
  `breaches.csv` has the same list.
  A breach is one of these:
  - **time cut**: a time that is cut, so it can lose its number or its unit (for example "dans 3…"). A shorter spelling that is whole ("3 min") is not a breach.
  - **destination under 6**: a destination shown with fewer than 6 characters before its "…" (for example "Na…"). A destination shorter than 6 characters that is shown whole is not a breach, and neither is a long destination with 6 or more characters before its "…".
  - **two directions the same**: the two directions of one line that show the same text (for example "Mairie d'…" twice).
  - **label cut**: the station name of a station label (a line of another station of the hub) that is cut.

  How it finds them: the render test reads SwiftUI's own layout of each text (`Text.LayoutKey`): where it is, if it is cut, and how many characters show.
  It saves these in `texts.json`, with the texts of the drawn state (the station, the labels, the destinations of each direction).
  Then, on the Mac, the text recognition (Vision) reads each cut text in its part of the image, and the command compares it with the texts of the state, to know if it is a time, a destination, a label or the station name.
  The cut texts that are none of these (for example "Ouvrez l'app pour mettre à jour les horaires") are "other cut texts": the command prints their count, and a person reads them.
  It looks at the images only, so at the 42 stations of the image set, not at every station, and the summary says how many stations it looked at.
  Why the hubs: the first version looked at the 15 stations of the extreme cases only, and missed 17 of the 23 stations with a label (for example La Muette, with its label "Boulainvilliers", and Bir-Hakeim, with "Champ de Mars Tour Eiffel").
  It is a report: it does not fail on a breach (decision-15 keeps it out of the gate until option C of decision-14 is shipped, because C redraws these views).
  A Live Activity task writes the counts before and after its change in its notes.
- **Its limits (calibration).** The numbers above come from the real Live Activity, measured by TASK-124 on the iOS 27.0 Simulator (a UI test that opened the real Live Activity and read its frames).
  iOS draws a Live Activity at most at the XXXL text size: at the accessibility sizes, the rows keep their XXXL size (only the snooze buttons get wider).
  So the command draws XXXL, not the accessibility sizes, which would give false alarms.
  The render cannot see what iOS draws around the views: the round corner of the Dynamic Island, and the real room of its bottom region, which changes when the leading or center region changes.
  At XXXL, the Dynamic Island has no measured limit, so only its images are saved.
  After a new iOS version or a redesign of the regions of the Dynamic Island, measure the numbers again on the real Live Activity (TASK-124's notes explain how) and change them in `ios/RenderCheck/LiveActivityRenderCheck.swift`.
  It also cannot see a one-line text that the real Live Activity cuts while it has room: the render measures and draws each text in one process, so a text that fits is always drawn whole, but on the real Live Activity iOS can give a text a frame a fraction of a point narrower than it needs to draw it, and then the text ends with "…" (TASK-144:
  "Opéra" became "Opé…" at XXXL in the header of its own metro pages, while the render drew it whole, and "Pigalle" stayed whole).
  So a one-line text of the Live Activity that can be shown at exactly its own width needs a `minimumScaleFactor`: it then shrinks by an invisible amount instead of being cut.
  The station name of the header has one since TASK-144; TASK-161 finds the other texts that need one.
  A text in the render check that is whole is not a proof that it is whole on the real Live Activity: check the tight texts there at XXXL (TASK-161).
- **Its cost.** It is a Simulator job: it builds first, then takes the Simulator lock, like `make docs-screenshots`, and frees it when the drawing ends.
  The text recognition then runs on the Mac, with no lock.
  Measured on 2026-09-29 (iPhone 17 Simulator, iOS 27.0, 551 stations, 7,919 drawings and 636 images in each language, load average 6 to 12): about 150 s of Simulator time for the drawing in French, with the install of the host app, and about 130 s more for English with `ENGLISH=1` (296 s for both), plus about 10 s for the reset of the Simulator.
  Since the images of every station of a hub (948 images instead of 636), the French drawing took 142 s on the branch of TASK-112 (2026-09-29): the same as before, within the noise.
  Since every height is measured at 3x (TASK-153), the French drawing took 184 s, against 173 s for `main` on the same day (2026-10-01, 1,500 images, load average 10 to 30): 6% more.
  Before TASK-135, it drew only in English, with no host app, in 85 s.
  Why it takes longer: a test that runs in an app draws about 2 times slower than a test bundle with no app (28 s against 13 s for the first 80 stations).
  To keep this down, it reuses one renderer for all the drawings, and for a station with no image it measures the height only, with no pixels.
  It measures it at the scale of the images (3x, like the iPhone), so the height is the one that the image would have, to a third of a point.
  Why: before TASK-153, it measured at 1x and rounded up to a point, and SwiftUI lays out the views to whole points at 1x.
  So most of these heights were 0.7 to 4.3 points higher than the image of the same page (Varenne: 138 and 156 points instead of 137.3 and 154.7, fresh and stale), and a few were up to 19 points lower.
  A page could fail a limit that its real drawing passes, or pass a limit that it fails.
  The build before it and the text recognition after it (about 1 minute for each language, and about 30 s more for the breaches since the images of the hubs: 28 s on the branch of TASK-112) use no Simulator.

## The Live Activity starts and stops by itself near a station

The app watches the metro and RER stations around you. The rules come from decision-3 in the backlog.

- **Arrival.** When you come within about 150 meters of a station:
  - If the app is open on screen, the Live Activity of this station starts at once.
  - If a system popup covers the open app (for example a permission question at the first launch), the app waits.
    The Live Activity starts as soon as the app is active again.
    If the app goes to the background first, the notification comes instead.
  - If the app is closed or in the background, the phone shows one notification: "Next trains at <station>".
    Tap it: the app opens and starts the Live Activity of this station.
    Touch and hold it (or pull it down) to see two actions: "Not for 1 h" and "Not today" (in French "Pas pendant 1 h" and "Pas aujourd’hui").
    Each one snoozes the automatic mode (see below) without opening the app.
    They also work while the phone is locked.
- **One station at a time.** If a Live Activity already shows and you come within 150 meters of another station, the Live Activity switches to the new station. There is no second Live Activity and no second notification.
- **Stop.** The Live Activity ends by itself when you move more than about 250 meters away from its station, or 45 minutes after it started.
- **No repeat.** You get one notification or one automatic start for each arrival. After you stop the Live Activity by hand, it does not start again until you leave the station (more than 250 meters) and come back.
- **By hand.** "Show the Live Activity now", "Show on the lock screen" (testing tools) and "Stop showing on the lock screen" still work.
  A Live Activity that you start by hand for a station far from you does not stop because of the distance.
  It stops at 250 meters only after you came near its station.
  The 45 minute limit applies to every Live Activity.

The main screen says which station shows on the lock screen ("On the lock screen: <station>").

### Snooze or turn off the automatic mode

The rules come from decision-3 in the backlog.

- **Snooze.** Tap "30 min", "1 h" or "Today" on the Live Activity, "Not for 1 h" or "Not today" on the arrival notification, or "Snooze" in the automatic mode part of the main screen.
  The Live Activity ends at once.
  Then no notification and no automatic Live Activity start for 30 minutes, for 1 hour, or until midnight ("Today").
  The notification of an arrival goes away too.
- **The end of the snooze.** When the time is over, the automatic mode is on again by itself.
  The rules above apply again.
  The app still follows the stations that you pass during the snooze: when the snooze ends at a station that you reached during the snooze, the Live Activity does not start.
  It starts at the next station that you come to.
- **Cancel the snooze.** The main screen shows "Snoozed", the time when the automatic mode comes back, and the time left. Tap "Cancel the snooze" to end it at once.
- **Turn off.** Turn off the switch "Automatic mode" on the main screen. Then no notification and no automatic Live Activity ever start, until you turn the switch on again. The app keeps this choice when you close it.
- **By hand.** While the automatic mode is snoozed or off, "Show the Live Activity now" still works. A Live Activity that you start by hand still switches to a new station and stops by itself (250 meters, 45 minutes), as above.

The first time, the app asks for your location and for notifications.
To get the notification while the app is closed, the app needs the location "Always".
iOS first asks for "While Using the App".
Right after your answer, the app asks iOS for "Always", and iOS asks you if the app can also use your location when you do not use it.
The app asks for notifications only after this second answer.
For developers: `LocationQuestionsRules` (in `RATPCore`) decides when to ask, and `CoreLocationPermission` (in `ios/App/Location/`) applies it.
iOS does not tell the app when you tap "Keep Only While Using", so the app waits until it becomes active again after the question.
When iOS does not show the second question (after "Allow Once", iOS ignores it), the app waits at most 20 seconds, then asks for notifications.
If you keep "While Using the App", the Live Activity starts by itself only while the app is open.
The "Permissions" part of the main screen then says so, with a button to open Settings.

### Test it with a fake position

- **App open (the Live Activity starts at once).** Open "Testing tools", pick a station (for example Abbesses), and go back. The Live Activity starts. Pick a station near it (for example Pigalle): the Live Activity switches. Tap "Far from any station": the Live Activity ends.
- **App in the background (the notification).** The in-app fake position cannot change while the app is in the background. Use the Simulator location instead:
  1. In "Testing tools", tap "Use the real GPS". In iOS Settings, set the location of RATP Activity to "Always".
  2. Set a position far from any station: `xcrun simctl location "$(make -s simulator)" set 48.42,2.63`.
  3. Go to the home screen or lock the Simulator.
  4. Set a position at a station, for example Abbesses: `xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838`. The notification shows. iOS can take a few seconds to a few minutes to notice the move.
  5. Tap the notification. Or touch and hold it, then tap "Not for 1 h" or "Not today": the app does not open, and its main screen shows the snooze.

  In the Simulator, this works only while iOS keeps the app running in the background (about 10 to 25 seconds after you leave it, or while a Live Activity shows).
  The Simulator cannot watch regions: in the iOS 27 Simulator, `CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)` is false (checked on the two shared Simulators, an iPhone 17 and an iPhone SE).
  So when iOS suspends or closes the app, no region event wakes it, and no notification shows.
  Check the arrival of a suspended or closed app on your iPhone.

  On your iPhone connected to the Mac, use Xcode > Debug > Simulate Location in the same way.
- **The 45 minute limit.** In debug builds, you can make it shorter.
  Launch the app with `-liveActivityMaximumDuration <seconds>`, for example: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.RATPActivity -liveActivityMaximumDuration 60` (replace `com.example` with your bundle ID prefix if you changed it).
- **Fake trains.** A build with no train data key shows no trains.
  In debug builds, launch the app with `--fake-trains` to get fake next trains instead, with no PRIM call: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.RATPActivity --fake-trains`.
  The app saves this choice (`FakeTrainsStore`, in `RATPCore`), so the rule is:
  - A launch with launch arguments comes from you or from a test (`xcrun simctl launch` with arguments, XCUITest, the Run button of Xcode when the scheme has arguments).
    It turns the fake trains on with `--fake-trains`, and off without it.
    For example, a launch with only `-liveActivityMaximumDuration 60` has no fake trains.
  - The Run button of Xcode passes no argument with the default scheme, so it keeps the last choice, as a launch by iOS does.
    This matters on your iPhone, where the fake trains then replace the real trains of your key.
    To drop them, run the app once with any other argument in the scheme (Product > Scheme > Edit Scheme > Run > Arguments), or delete the app.
  - A launch with no launch argument comes from iOS itself: the tap on a button of the Live Activity after iOS closed the app, a region wake, a relaunch in the background.
    iOS passes no argument, so the app keeps the last choice.
    So you can close the app (`xcrun simctl terminate "$(make -s simulator)" com.example.RATPActivity`), tap the Live Activity, and still see the fake trains.
    While a Live Activity shows, iOS starts the app again in the background a moment after you close it (it keeps getting the position in the background), so the tap often reaches an app that iOS started, not a closed one.
  - `make run` installs the app again, with no saved data, so it starts with no fake trains. `make switch-language` keeps the data of the app, so it keeps the fake trains.
- **Ask the fake trains for a state.** Live trains show some states only by luck: PRIM shows a train at the platform for 20 to 30 seconds, and the app updates the Live Activity only every 2 minutes in the background.
  So, in debug builds, add the name of a state after `--fake-trains`, for example `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.RATPActivity --fake-trains at-platform`.
  The times start at this launch, the same for each line and each direction of the station (the second direction is one minute later), and the app follows its real rules with them (`FakeTrainsScenario`, in `RATPCore`).
  Then start the Live Activity at once (a fake position, or "Show the Live Activity now"), and put the app in the background to look at the lock screen and the Notification Center.
  - `at-platform`: the first box of each strip shows "À quai" for 5 minutes. Then the train leaves, and trains come every 4 minutes, each one 30 seconds at the platform, like real trains.
  - `at-platform-second`: the second box shows "À quai", next to a train that leaves first, for about 3 minutes. Then the first train comes ("0", then "À quai": both boxes), leaves, and the second one leaves 2 minutes later.
  - `at-platform-both`: both boxes show "À quai" for 5 minutes. Then the first train leaves, and the second one 2 minutes later.
  - `ten-to-nine`: trains every 6 minutes. The second box shows 10 or more, and counts down to 9 by itself about 3 to 4 minutes after the launch, then every 6 minutes. Look while the app is in the background, before the next update (at most 2 minutes).
  - A fork with both ends: at a station of lines 7 or 13 before the fork (for example Liège or Poissonnière), the two boxes of the tagged strip always show one train for each end, with or without a state.
  - The RER lines get the same times. Their rows show "À quai" only when the RER look draws it.
  - Check that the app got the arguments: `ps -axww -o args | grep "RATPActivity.app/RATPActivity"` shows `--fake-trains` and the name.
    When the line ends with `RATPActivity` alone, iOS had already started the app again in the background (it does so while a Live Activity shows), and the launch only brought that app to the front: launch it again.
    On 2026-10-02 (TASK-170), the first launch after `make run` lost its arguments both times, and one or two more launches fixed it.
  - To start the state again, launch the app again with the same arguments. A launch by iOS (no argument) keeps the state and its start time. A name that the app does not know gives no fake trains, so the Live Activity says "No data available".

For developers: the rules are in `AutoLiveActivityRules` (in `RATPCore`), and `AutoLiveActivityModel` applies them.
`AutomaticModeModel` holds the automatic mode (on, snoozed until a date, or off) and saves it.
While the mode is not on, the rules still follow the arrivals, but they do not notify or start.
The buttons of the Live Activity run `SnoozeLiveActivityIntent` (a `LiveActivityIntent`, in `RATPCore` because the app and the widget share it).
iOS runs it in the app, and opens the app in the background if needed.
The intent gets `AutoLiveActivityModel` from `AppDependencyManager` (the app adds it in `RATPActivityApp`).
It reads the position from `LocationService`, so the fake position works too.
When the app is closed, iOS wakes it with region monitoring (`CLMonitor`, in `ios/App/AutoLiveActivity/CoreLocationStationRegions.swift`).
iOS watches at most 20 regions for each app, so the app watches the 18 nearest stations (150 m), the stop area of the shown station (250 m), and one larger area around you.
When you leave this larger area, the app picks the nearest stations again.
Debug builds log the region monitoring: whether iOS can watch regions, and each region event with its state and its diagnostics (for example `conditionUnsupported`).
They also log the Live Activity: at each launch, the Live Activities that iOS still lists with their state; each state change that iOS sends (`active`, `stale`, `ended`, `dismissed`); each end that the app asks for itself; and when the background location starts and stops.
So you can see when iOS tells the app that you swiped the Live Activity away (TASK-146).
They also log each content that the app sends to the Live Activity (category `LiveActivityContent`: each shown train with its time, its destination and its state), and each PRIM answer (category `PRIM`: one line per train of the answer, with its destination, its times, its quay, its journey, and whether the app keeps it or drops it, and why).
The PRIM key is never in the log.
So, with live data, you can tell whether a change on the Live Activity comes from PRIM, from the rules of the app (for example the 60 s rule of a metro direction), or from iOS (TASK-169).
To read the log in the Simulator: `xcrun simctl spawn "$(make -s simulator)" log show --last 5m --predicate 'subsystem == "RATPActivity"'`.
On your iPhone, open the Console app on the Mac, choose the iPhone, and search for `subsystem:RATPActivity`.
While a Live Activity shows, the app keeps getting your position in the background, so it can switch or stop the Live Activity.
It also keeps the app running in the background, even when the phone does not move: `CoreLocationBackgroundLocationKeeper` (in `ios/App/AutoLiveActivity/`) runs standard location updates that never pause (`pausesLocationUpdatesAutomatically = false`, `allowsBackgroundLocationUpdates = true`).
Apple's documentation says that Core Location then keeps the app running.
Without it, iOS pauses the new location updates (`CLLocationUpdate.liveUpdates`) when the phone stands still, and suspends the app about 15 seconds after it leaves the screen.
With the location access "Always", the app hides the blue location indicator of iOS (the blue status bar, or the blue bubble in the Dynamic Island): `showsBackgroundLocationIndicator = false`, and no `CLBackgroundActivitySession`, because this session always shows the indicator.
With "While Using the App", the app needs a `CLBackgroundActivitySession` to get positions in the background, and iOS always shows the indicator while the Live Activity shows.
This costs battery, for at most 45 minutes (the limit of the Live Activity).
In the background, the app gets new train times when the Live Activity starts or switches station, and when the app leaves the screen while the Live Activity still waits for its first trains (the load that ran on screen stops when the app leaves it, so `keepFeedingInBackground` asks PRIM again at once, instead of at the next background refresh),
then again a few seconds after the first shown train leaves (`BackgroundTrainsRefresh`: at most every 30 seconds, at least every 2 minutes; it stops when PRIM rejects the key or the quota is used up).
Before each refresh, the app checks that the Live Activity still shows.
When you swipe it away, the app stops the background location.
When the app no longer asks PRIM, it still does this check every 2 minutes.
Each time it gets new train times, it asks PRIM once for each stop area of the station and of the other stations of its place (Châtelet: 2 calls, Saint-Lazare: 5 calls).
While the app is open, the app gets the train times of the Live Activity every 30 seconds, unless the next trains screen of the testing tools already gets them for the same station.

Limit: the app gets new train times in the background only while it runs.
It stops running when you close it from the app switcher, when the location is not allowed, or when iOS ends it (for example to free memory).
Then the 45 minute limit applies only when iOS wakes the app again (a region event) or when you open it, and the Live Activity gets no new train times until then.
A free Apple ID has no push notifications, so no server can send new times to the Live Activity instead (see "Later" in the Product Vision).

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

Before TASK-43, the key file was `Config/Secrets.xcconfig` (at the root).
`make run LIVE=1` still finds it there, and git still ignores it, but it prints a note.
Once your main folder has the `ios/` folder, move the file there, in the main folder: `mv Config/Secrets.xcconfig ios/Config/ && rmdir Config`.
The Xcode Run button reads only `ios/Config/Secrets.xcconfig`.

The other `make` commands (`make run` without `LIVE=1`, `make check`, `make e2e`) never use the key: they build with `ios/Config/NoKey.xcconfig`. Then the tests do not use your PRIM quota. The Run button in Xcode uses the key of the folder that you open.

When you change your key, the next `make run LIVE=1` puts the new key in the app.
Why this needs care: `make build LIVE=1` gives the key file to Xcode with `-xcconfig`.
Xcode keeps a copy of the build settings (the build description, in `ios/.build/DerivedData/Build/Intermediates.noindex/XCBuildData/`), and it makes a new one only when the path of that file changes, not its content.
So `make build LIVE=1` also passes `PRIM_SECRETS_STAMP`: the time, the file number and the size of the key file (never its content).
A change of the key file changes the stamp, so Xcode reads the file again.

The build output never shows the key. `make live-key-check` proves it with fake keys: it builds with a first key, changes the key file, builds again, and checks that the app has the new key and not the old one. Then it builds without `LIVE=1` and checks that the app has no key. `make check` runs it.

## Install on your iPhone (free Apple ID)

The tutorial "Install the app on your iPhone" of the docs site explains it step by step, for beginners. Run `make docs`, then open "Tutorial" in the sidebar. The page is `docs/src/content/docs/tutorial/install-on-your-iphone.mdx`.

In short: your Team ID and a unique bundle ID prefix go in `ios/Config/Local.xcconfig` (a copy of `ios/Config/Local.example.xcconfig`, ignored by git).
Run `make generate`, open the project `ios/RATPActivity.xcodeproj` in Xcode, choose your iPhone, and click Run.
With a free Apple ID, the app stops after 7 days: run `make generate` again, then click Run again to renew it.

On a device, the Run button of Xcode uses the PRIM key of `ios/Config/Secrets.xcconfig` in the folder that you open. There is no `make` command for a device build.

## The docs site

The folder `docs/` holds the docs for the users of the app, for example the tutorial to install the app on your iPhone. It is a [Starlight](https://starlight.astro.build) site (Astro). It is not online: you read it on your Mac.

The docs need Node 24 LTS.
The file `.nvmrc` pins it.
Install it one time with [nvm](https://github.com/nvm-sh/nvm): run `nvm install` in the main folder of the repo. Then run `nvm use` in each new terminal before a docs command. If the active Node is too old, the docs commands stop and tell you to run `nvm use`.

| Command | What it does |
|---|---|
| `make docs` | Builds the site and serves it at http://localhost:4321. The search works only here. `make docs PORT=4400` uses port 4400. |
| `make docs-dev` | Serves the site with live reload while you change a page. No search. It also accepts `PORT=<n>`. |
| `make docs-stop` | Stops the docs server of this folder. Use it when the server runs in the background (for agents, Astro starts it in the background). In a terminal, press Ctrl + C. |
| `make docs-check` | The docs quality gate: installs the packages if needed, runs the unit tests and `astro check`, builds the site, and fails on a broken internal link. It needs no Simulator. |
| `make docs-screenshots` | Takes the app screenshots of the docs on the shared Simulator, and saves them in `docs/src/assets/screenshots/`. |

The first docs command installs the packages in `docs/node_modules` (about 300 MB).

`make check` runs `make docs-check` only when your branch changes files in `docs/` (compared with `main`). So a change of the app only does not need Node.

To write a page:

- Add an `.mdx` file in `docs/src/content/docs/tutorial/`. The sidebar shows it under "Tutorial".
- Use the Starlight components: `Steps` for a step list, `Aside` for a callout. See https://starlight.astro.build/components/using-components/.
- Inline code (between backticks) never breaks across two lines (`docs/src/styles/custom.css`), so a reader can copy a command as one piece. Keep it short: at most about 30 characters. Put a longer command in a code block, on its own line.
- To show the progress of a step list ("3 of 11 steps done"), put the list inside the `Checklist` component of `docs/src/components/Checklist.astro`.
  Give each list its own `id`: the browser saves the ticks under this id.
  The home page (`docs/src/content/docs/index.mdx`) shows an example.
  For a list of things to have, not steps, add `kind="things"`: it shows "3 of 8 things ready".
- Show an app screenshot with the `Screenshot` component of `docs/src/components/Screenshot.astro`. Do not use a Markdown image or the `Image` component of Astro. To show many screenshots side by side, put them inside the `Screenshots` component. The home page shows an example:

  ```mdx
  import Screenshot from '../../../components/Screenshot.astro';
  import Screenshots from '../../../components/Screenshots.astro';
  import appMainScreen from '../../../assets/screenshots/app-main-screen.png';

  <Screenshot src={appMainScreen} alt="The main screen of the app." />
  ```

  `Screenshot` always shows the image 300 pixels wide (less on a narrow screen), with the rounded corners of the iPhone screen.
  At build time, Astro makes AVIF files (and WebP files for old browsers) at 1x, 2x and 3x of this width.
  The browser downloads only the one that fits its screen, so the page stays light.

`make docs-screenshots` runs the XCUITest suite of `ios/DocsScreenshots/` with the key-less build and a fixed fake position (near Champ de Mars Tour Eiffel).
It saves one PNG file for each screenshot, with a fixed name: `app-location-permission.png` (the location question at the first launch), `app-always-permission.png` (the location "Always" question, right after it), `app-notification-permission.png` (the notifications question at the first launch), `app-main-screen.png` (the main app screen),
`live-activity-notification-center.png` (the Live Activity in the Notification Center) and `app-testing-tools.png` (the Testing tools screen).
The PNG files are in git.
To add a screenshot, add a `saveScreenshot(named:)` call to the test and its name to `names` in `ios/scripts/docs-screenshots.sh`.

Rules for the screenshot files:

- **Full screen, same device.** Each screenshot shows the full screen of the shared Simulator (an iPhone 17), also for the Live Activity (the full Notification Center, not a crop).
  So all screenshots have the same size and look the same side by side.
  The script fails if a screenshot has another size.
- **900 pixels wide.** The docs show a screenshot 300 pixels wide.
  A Retina (2x) screen needs 600 pixels, and a 3x screen (an iPhone) needs 900 pixels.
  So the script makes each screenshot 900 pixels wide (the Simulator gives 1206 pixels).
  More pixels make a larger file with no visible gain.
  Fewer pixels make a blurry image.
- **Budget: at most 500 KB for each file in git.** The script compresses each file with pngquant (quality 85 to 100: no visible loss), and fails if a file is larger than 500 KB.
  Today, a screen of the app is about 60 KB, and the lock screen with its wallpaper is about 450 KB.
  Why a budget: the files stay in the git history forever, and each new run of `make docs-screenshots` adds them again.
  The page does not get heavier: Astro makes small AVIF files at build time.

Rules to keep the docs true:

- A change of a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task. Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images. A docs text change alone needs no new screenshots.
- `make docs-screenshots` is a Simulator job. Like `make e2e`, it builds first, then takes the Simulator lock, and frees it when the screenshots are taken. Run `make simulator-shutdown` when your job ends.

## Languages

Almost every user of the app is French. The app shows each text in French when the language of the iPhone is French, and in English for any other language (Settings > General > Language & Region). English is the language of the code: each text is written in English in the Swift code.

- The French texts are in String Catalogs: `ios/App/Localizable.xcstrings` (the main screen and the notifications), `ios/App/InfoPlist.xcstrings` (the texts that iOS shows when it asks for the location) and `ios/Widget/Localizable.xcstrings` (the Live Activity and the Dynamic Island).
  Xcode shows them as tables.
  You can also edit the JSON by hand.
- The "Testing tools" screen (debug builds only) stays in English. Its texts are inside `#if DEBUG`, so Xcode keeps them out of the catalog.
- The name of the app (`CFBundleDisplayName` and `CFBundleName`, in `ios/App/InfoPlist.xcstrings`) is the same in French: it is marked "Don't translate" (`"shouldTranslate" : false`).
- A new text on a screen needs its French text in the catalog, in the same task. Write a text that a Paris rider knows: "Prochains passages", "écran verrouillé", "activité en direct", "Réglages", "Toujours", as iOS and the RATP say them.
- **A build in Xcode updates the catalogs.** When you build in Xcode, Xcode reads the texts of the code and of the Info.plist, and writes the catalogs again: it adds a new text, marks a text that is no longer in the code as "stale", marks a French text "needs review" when its English text changed, and leaves out the texts inside `#if DEBUG`.
  The command line builds (`make build`, `make run`, `make check`, `make e2e`) never change the catalogs.
- **The catalogs in git are always the ones that Xcode writes.** So a build in Xcode, or a `make` command, in the main folder on `main` leaves `git status` clean. You have nothing to set up for this. `make strings-check` makes sure of it on each task.
- `make strings-sync` updates the catalogs as a build in Xcode does (with `xcodebuild -exportLocalizations`).
  Run it after you add, change or remove a text in the code, or a permission text in `ios/project.yml`.
  Then add the French texts, check the change with `git diff`, and commit the catalogs.
  You can also edit the JSON by hand: then run `make strings-sync` too.
- `make strings-check` (part of `make check`) fails when a build in Xcode would change a catalog (it shows the change, then puts the catalogs back as they were: run `make strings-sync`).
  It also fails when a text has no French text (state "translated"), or is no longer in the code ("stale": remove it).
  A text marked "Don't translate" needs no French text.
- For a text in the code, use a text that SwiftUI translates (`Text("...")`, `Button("...")`, a `LocalizedStringKey`), or `String(localized: "...")` for a `String` (for example a notification).
  A plain `String` given to `Text` is not translated.
  Use `Text(verbatim:)` for a text that never changes (a name).

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
| `RenderCheck/` | The render check of the Live Activity views (`make live-activity-render`): a unit test bundle, and in `Host/` the small app that runs it with the texts of the widget. |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands of the app. |

The feature folders have the same names in `ios/App/`, in the sources of `RATPCore` and in its tests: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`.
`ios/App/` also has `Permissions` and `TestingTools` (debug builds only).
The rules for the code (where each file goes, which module depends on which) are in the CLAUDE.md, section "Code structure of the iOS app".

You can also run the commands of one part in its folder: `make -C ios check` runs only the checks of the app.

## Notes for developers

- **The README: one sentence per line.** Write each sentence of this README on its own line.
  When one sentence is longer than 400 characters, break the line after a comma, a colon or a semicolon.
  When a change makes a sentence false, edit only that sentence, and never reflow a paragraph.
  Why: git merges by line, so two changes to two sentences of one long line conflict.
  `make prose-check` (part of `make check`) fails on a line of prose longer than 400 characters, in every Markdown and MDX file of the repo ([CONTRIBUTING.md](CONTRIBUTING.md)).
  Tables and code blocks may have long lines.
- Unit tests use Swift Testing. `make test` runs them on the Mac with `swift test`, so they need no Simulator. Keep `RATPCore` buildable on macOS: put iOS-only code (for example ActivityKit) inside `#if os(iOS)`.
- Build output goes to `ios/.build/` inside the folder. Many git worktrees can build and run unit tests at the same time. Each worktree has its own build folder. All worktrees share one Simulator, and Simulator jobs wait for each other (see above).
- The shared build cache: all folders (and all git worktrees) share the compiled modules of the iOS SDK (for example SwiftUI and UIKit), in `~/Library/Caches/RATPActivity/`.
  So the first build of a new worktree does not compile them again.
  This cache holds no code of the app, only modules of the SDK: the build products of a worktree stay in its own `ios/.build/`.
  Xcode keys each module by a hash of the SDK and the compiler flags, and it writes each file in one step, so many builds can use the cache at the same time.
  The cache grows only when the SDK or the flags change (for example after an Xcode update).
  `make build LIVE=1` does not use this cache: a build with the key stays in its folder.
  `make live-key-check` fails if the cache holds the key.
  To clear the cache, run `make clean-shared-cache`.
  It waits for the builds that use the cache to end, and new builds wait for it, so clearing never breaks a build of another folder.
  Then it deletes the modules, and the next build makes them again.
  To use another folder, add `RATP_SHARED_CACHE=<folder>` to the `make` command.
- `make build` builds the app for the processor of your Mac only (Apple silicon: arm64), and the command line builds make no code index (Xcode makes its own index when you open the project). Both make the build faster.
- End-to-end tests are slow: all folders share one Simulator, one job at a time.
  So each test guards one seam where our code meets iOS, and nothing else (CLAUDE.md, section "Test levels", and decision-9 in the backlog): the real location popups, then a Live Activity that the app starts and stops by hand (`LiveActivityTests`), the automatic start, switch and end of the Live Activity from the position that iOS gives (`AutoLiveActivityTests`),
  the arrival notification of an app in the background, the tap on it and its "Not for 1 h" action (`ArrivalNotificationTests`), and the trains on the real Live Activity with its two buttons (`SnoozeTests`).
  Each test looks at the real Live Activity in the Notification Center (`openNotificationCenter(over:)` from `E2ETestCase` pulls it down over the app, and `liveActivity` is the Live Activity there), not at the app label "On the lock screen: <station>": at most, this label is a point to wait for.
  The tests move the phone with the Simulator position (`moveThePhone(to:)`, which sets `XCUIDevice.location`), so the app reads it through Core Location, with our real code.
  They never go through the Testing tools: the fake position for testers has no E2E test, and QA checks it when a task changes it.
  Each test uses its own stations, so no test depends on the arrival that another test left behind.
  A check of a rule (formatting, sorting, search, parsing, state) is a unit test in `RATPCore`.
  A new step goes in the test of its seam.
- End-to-end tests: to wait for an element, use `waitFor(_:)` from `E2ETestCase` (`waitForNo(_:)` to wait until it goes, `waitForFirst(of:)` for the first of many).
  Tap with `tap(_:)`: it waits for the element first, so a tap after typing or navigation never fails at once on a busy Mac.
  They wait up to `UITestTimeout.element` (30 seconds): the Mac can be busy, so short waits fail for no real reason.
  They return at once when the element is already there (`waitForExistence` alone costs at least 1 second, even then).
  Wait for a condition that the app shows, never for a fixed time.
  Each test class inherits from `E2ETestCase`.
  It sets `continueAfterFailure = false`: a test stops at its first failure.
- End-to-end tests: when a test changes the Simulator position, wait for what the new position changes before the next step (the position reaches the app some time later): the Live Activity in the Notification Center, or the "Stop showing on the lock screen" button of the app before the test leaves the app.
  While a Live Activity shows, the app keeps getting positions in the background (the path of a phone in a pocket), so `AutoLiveActivityTests` and `SnoozeTests` move the phone while the Notification Center is open.
  A test that needs the app awake in the background with no Live Activity (`ArrivalNotificationTests`) adds the launch argument `--keep-running-in-background` (debug builds only).
  The app then keeps a background location session, so iOS does not suspend it before the new position reaches it.
- End-to-end tests: the E2E builds have no train data key, so the Live Activity says "No data available".
  A test that checks the trains on the Live Activity adds the launch argument `--fake-trains` (debug builds only).
  The app then gets fake next trains from `FakeDeparturesProvider` in `RATPCore`, with times from now (or from the launch, when a state follows the argument), and makes no PRIM call.
  Each line of the station gets trains toward both ends, and a side with branches sends its trains to each branch in turn.
  Every E2E launch has launch arguments (`makeApp()` adds `--reset-location-source`), so a test without `--fake-trains` never keeps the fake trains of an earlier test.
  When iOS starts the app by itself (no launch argument), it keeps them (see [Test it with a fake position](#test-it-with-a-fake-position), "Fake trains").
  Only `SnoozeTests` uses it (`--fake-trains at-platform`, see [Test it with a fake position](#test-it-with-a-fake-position), "Ask the fake trains for a state"), to check the station name, both directions, a train at the platform, a branch and the header button that shows the next line on the real Live Activity (Notification Center).
  It does not replace the real trains: QA still checks them with `make run LIVE=1`.
- End-to-end tests: open the app with `launch(app)` from `E2ETestCase`, not with `app.launch()`.
  On the first launch of a run, it answers the notification popup at once.
  If the location is "Off" (for example, you run a test from Xcode after a run that refused it), it resets the location permission and answers the location popup.
  It also answers "Keep Only While Using" at once when iOS asks to use the location "Always".
  After it answers the first location popup, it waits for this "Always" popup too, because the app asks for it right away.
  Before each test, `makeApp()` stops the app of the last test, and stops it again if iOS starts it again in the background (iOS does it for an app that can use the location in the background).
  `launch(app)` does the same before it resets a refused location permission.
  Only `LiveActivityTests` goes through the real location popups, with `answerPermissionPrompts(in:)`.
  It waits until it has answered both, and checks that the "Always" popup came right after the first one.
- `make e2e` builds the tests before it takes the Simulator lock, so other jobs do not wait for the build. It runs the tests on the Simulator of its job (`ios/scripts/simulator.sh with-destination` adds its `-destination`).
- `make e2e` does not collect Simulator diagnostics when a test fails (they took 10 minutes and kept the Simulator lock).
  It stops a test that runs longer than 5 minutes.
  When a test fails, it prints the file, the line, and the message of each failure.
  When the Mac went to sleep during the tests (for example, the lid was closed on battery, which `caffeinate` cannot stop), it also says when, from the power log of macOS (`pmset -g log`): the Simulator stops while the Mac sleeps, but the waits of the tests count on the clock, so a test can fail with no bug in the code.
  Run the command again before you look for a bug.
  Why: on 2026-09-30, the Mac slept for 96 seconds during the full suite of `make merge`, a test failed, and a task that had passed QA went back to its Software Engineer for a night (TASK-154).
  The full results are in `ios/.build/e2e.xcresult` (open it in Xcode).
- Swift 6 language mode. Minimum iOS version: 18.0.

### Merge a task into main

`main` is always green. It holds only the tasks that passed review and QA. There is no other long-lived branch.

1. A Software Engineer implements a task on its branch `task/<id>`, and another Software Engineer reviews it.
2. The implementer runs `make check` on the last commit of the branch, plus the E2E test classes of the flows that the change touches.
   The reviewer hands the task over to QA.
   Before that, it makes sure that `make check` passed on the last commit of the branch.
   A reviewer who changed no code runs nothing again.
   A reviewer who changed code runs `make check`, plus the E2E test classes of the flows that its change touches when it changed app code.
   No Software Engineer rebases the branch or merges.
3. The manager rebases the branch onto `main` right before QA, so QA tests the branch on the latest `main`.
4. QA tests the branch.
5. When QA passed the task, the manager runs `make merge` in the worktree of the task.
   It takes the Simulator lock, rebases the branch onto the tip of `main` again, runs `make check`, runs the full `make e2e` (skipped when the task changes only docs or unit tests), then fast-forwards `main` to the rebased branch.
   When `main` is checked out in a folder, it updates that folder too, with `git merge --ff-only`.
   When a step fails, `main` stays as it was.

When a rebase has a conflict (before QA or in `make merge`), or the gate or the E2E suite fails, the task goes back to its Software Engineer, who fixes the cause on the branch.
One exception: when the E2E suite fails and `make merge` says that the Mac slept during the tests, the task does not go back.
The manager runs `make merge` again, once.
After a rebase conflict, the rebase is stopped (`git rebase --abort`: the manager does it before QA, and `make merge` does it by itself), so the Software Engineer starts the rebase again (`git -C <worktree> rebase main`) and solves the conflict.

The folder of `main` is the prompter's folder.
When it has changes that are not committed on the files of the task, `make merge` refuses at once, before it waits for a lock, and names the files.
The task does not go back to its Software Engineer for this.
The manager tells the prompter the folder and the files, and the prompter decides: commit, stash or drop the changes.
The manager runs `make merge` again when the prompter says that the folder is clear.
The same holds when the fast-forward fails because such changes appeared during the run.
No agent commits, stashes or discards the changes of the prompter's main folder without the prompter.

Why:

- **Merges queue one at a time.** A second `make merge` waits for the first one (a merge lock, `/tmp/ratp-merge.lock`), then for the Simulator lock.
  When its turn comes, `main` already has the first merge, so it rebases onto it.
  Its fast-forward is never refused because another merge landed during its run.
- **A full E2E run is never repeated.** The full suite runs once for each task, on the exact commit that `main` gets. No other merge can land between the end of the run and the fast-forward.
- **History stays linear.** `main` moves only by fast-forward. A merge is always a rebase, then a fast-forward: never a merge commit.

The CLAUDE.md gives the details (section "Merge a task into main").

### No warnings

The project has no warning, and the quality gate keeps it so:

- **Build warnings.** The command line builds (`make build`, `make e2e`, `make docs-screenshots`) treat each compiler warning as an error.
  `make test` does the same for `RATPCore`.
  After `make build`, `ios/scripts/build-warnings.py` reads the result of the build (`ios/.build/build.xcresult`) and fails on any other warning that Xcode reports (for example the linker or the asset catalog).
  The Run button in Xcode does not treat warnings as errors, so you can try code that is not finished yet.
- **Recommended settings.** A new version of Xcode can recommend new project settings: Xcode then shows the warning "Update to recommended settings".
  `options.xcodeVersion` in `ios/project.yml` says which Xcode version last checked the settings.
  `make recommended-settings-check` (part of `make check`) fails when your Xcode is newer (a bug fix release, for example 27.0.1, does not count).
  Then open `ios/RATPActivity.xcodeproj` in Xcode, click the warning, and add each setting that Xcode proposes to `ios/project.yml`.
  Do not click "Perform Changes": the Xcode project is not in git, and `make generate` would undo it.
  Then set `options.xcodeVersion` to your Xcode version, and run `make generate`.
