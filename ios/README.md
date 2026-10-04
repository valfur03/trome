# Build, run and test the iPhone app

This folder holds the iPhone app of TROME, its Live Activity, and their tests.
This page gets you from a clone to the app in the Simulator, and to a change that passes the checks; [CONTRIBUTING.md](../CONTRIBUTING.md) says how to propose one.
Run every `make` command from the root of the repo.

## Set up and run the app

You need a Mac with Xcode 27 and its iOS Simulator (select it with `xcode-select` if you have several versions), and [Homebrew](https://brew.sh).
Then, in your clone:

```sh
make setup
make run
```

`make setup` installs XcodeGen, SwiftLint and pngquant, and creates the Xcode project, `ios/TROME.xcodeproj`.
`make run` builds the app and opens it in the Simulator.
The first build takes several minutes: it compiles the modules of the iOS SDK once, into a cache that all your clones share.

The app shows no real train times until you add your own free key ([The train data key (PRIM)](#the-train-data-key-prim)), but it can show [fake trains](#test-it-with-a-fake-position).
To try it at a station without going there, tap **Testing tools** at the top right, and pick a fake position.
To put the app on your own iPhone, see [Install on your iPhone](#install-on-your-iphone-free-apple-id).

## The commands you use every day

| Command | What it does |
|---|---|
| `make run` | Builds the app and opens it in the Simulator. Add `SMALL=1` for the smallest iPhone (an iPhone SE), or `LANGUAGE=fr` for a Simulator in French. |
| `make test` | Runs the unit tests on your Mac, with no Simulator. |
| `make e2e ONLY=<class>` | Runs one class of end-to-end tests in the Simulator; with no `ONLY`, all of them. |
| `make strings-sync` | Adds the new texts of the code to the String Catalogs, where you write their French text ([Languages](#languages)). |
| `make check` | Runs the checks of a change that need no Simulator: run it before each commit. |
| `make simulator-shutdown` | Removes the app from the Simulator, and frees it for your other clones. |

`make help` lists every command.

## One Simulator for all your clones

The `make` commands run the app on one shared Simulator, `RATP-Shared`, and only one of them uses it at a time, in any clone or git worktree of the repo.
A second command waits, and prints `Waiting for the Simulator lock`: let it wait.
After `make run`, the Simulator stays with your folder until you run `make simulator-shutdown`.
Before it installs the app, each command removes the app and its data, and resets the permissions, the text size, the appearance and the language of the Simulator.
In your own `xcrun simctl` commands, use the ID that `make -s simulator` prints.

To run the app from Xcode instead, pick a Simulator of your own, because the `make` commands shut the shared ones down when no command uses them.
Free and shut down the shared one first, so that only one Simulator runs: `make simulator-shutdown`, then `xcrun simctl shutdown "$(make -s simulator)"`.

## Keep the Xcode project up to date

The Xcode project is not in git: XcodeGen makes it from `ios/project.yml`, so change the settings there, not in Xcode.
The `make` commands update the project before they build, but the **Run** button of Xcode does not, and an old project fails with "Build input file cannot be found".
So run `make generate` after each `git pull` or change of branch, or run `make git-hooks` once, and git does it for you.

## Before you commit

Run `make check`.
It runs the lint, the checks of the texts, the build, the unit tests and the tests of the scripts, and stops at the first failure, with a message that says what to do.
The build accepts no warning: fix its cause, and never silence it.
When your branch changes `docs/`, `server/` or `contracts/`, `make check` checks them too, with Node 24.

`make check` runs no end-to-end test: [Test a change to the iPhone app](guide/tests.md) says which tests your change needs, and how to write one.

## The guides

- [tests.md](guide/tests.md): which test a change needs, how to run it and how to write one.

## How each feature works

These sections explain each feature of the app, and how to try it in the Simulator.

### The main screen

The app is the Live Activity. The main screen shows only:

- **The state of the Live Activity, and no button.** While a Live Activity shows, the screen says which station ("On the lock screen: <station>").
  Otherwise, it says what the Live Activity does.
  The Live Activity starts by itself near a station, and the snooze, the swipe and the pause stop it, so the screen has no button to show or stop it (decision-47).
  When iOS refuses to start it because Live Activities are off for the app, the screen says so, with "Open Settings"; the line goes once they are on again and you come back to the app.
- **The automatic mode.** The Live Activity starts by itself near a station (see [below](#the-live-activity-starts-and-stops-by-itself-near-a-station)).
  The switch "Automatic mode" turns it off or on.
  "Snooze" stops it for 30 minutes, 1 hour, or for the rest of today.
  While a snooze is on, the screen says "Snoozed", the time when the automatic mode comes back, and the time left.
  "Cancel the snooze" ends the snooze at once (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)).
  After you swipe the Live Activity away, the screen says "Paused at <station> until <time>", with the time left, and "Cancel the pause at <station>" (see [Swipe the Live Activity away](#swipe-the-live-activity-away)).
  This line and the snooze line can show together.
- **The permissions.** The state of the location and of the notifications. When one is missing or refused, the screen says what does not work, with a button to fix it ("Open Settings", or "Allow location").

The station picker and the next trains list are only for testers, in "Testing tools" (debug builds).

### Fake your position (testing tools)

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

For developers: all code must read the position from `LocationService` (in `TROMECore`), never from Core Location directly. Then the fake position works for every feature.

To fake your position in the Simulator:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

### The station list

The app finds the nearest station without the network. It reads the file `ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json`.

This file lists every metro station (lines 1 to 14, 3bis and 7bis) and every RER station (lines A to E). It has no bus, tram or Transilien stop. The data comes from the open data of Île-de-France Mobilités (dataset `arrets-lignes`, no key needed).
In all, the list is made from four datasets of Île-de-France Mobilités under two licences, the ODbL and the Licence Ouverte v2.0: [NOTICE.md](../NOTICE.md) names them, and says what you must do when you reuse the list.

Each line of a station also has its official color (`color`: the color of the line, and the color of the text on it).
It comes from the dataset `referentiel-des-lignes` of Île-de-France Mobilités (fields `colourweb_hexa` and `textcolourweb_hexa`, made for web and phone screens).
The Live Activity uses only these colors for the lines.

To see the list in the app, open "Testing tools" and tap "All stations". Each station shows its lines. Type part of a name in the search field to find a station. The search ignores case, accents and hyphens: `chatelet` finds "Châtelet".

To download the list again, run `make stations`. It needs Python 3. Commit the new `stations.json`.
The script writes the day of the download in the `date` field of `stations.json`: the app shows it in the notice of the station list.
Write the same date in [NOTICE.md](../NOTICE.md), in the same commit: twice as the script prints it (2026-09-27), in the sentence on the date of the data and in the list of what to give when you share the list, and once in the quote of the app's English sentence (September 27, 2026).
`make test` fails when a date differs.
Then open the four dataset pages that NOTICE.md links, check that they still show the same licences, and write the day of this check in NOTICE.md.

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

### Next trains of a station

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

For developers: the code is in `ios/Packages/TROMECore/Sources/TROMECore/Trains`.
`PRIMDeparturesProvider` calls the PRIM API "stop-monitoring" once for each stop area of the station, and of the other stations of its place (see [The station list](#the-station-list)).
So Châtelet costs 2 calls: the metro stop area of Châtelet (its 10 metro quays) and the RER stop of Châtelet - Les Halles.
Saint-Lazare costs 5 calls.
A stop area id `IDFM:monomodalStopPlace:<n>` (the `stopAreaIds` of a metro line, the `stopIds` of an RER line) becomes `STIF:StopArea:SP:<n>:`.
A metro line with no stop area asks for each quay: its stop id `IDFM:<n>` becomes `STIF:StopPoint:Q:<n>:`.
The answer for a stop area can have trains of lines that the app gives to another station of the place.
The app keeps only the trains of the lines that it asked this stop area for.
`CurrentStationModel` holds the station that the tester picked.
`NextTrainsModel.updatingStationId` says which station the screen keeps up to date, so the Live Activity does not ask PRIM for the same station twice.

### Show the next trains on the lock screen (Live Activity)

The app shows the next trains of a station on the lock screen, as a Live Activity. On an iPhone with a Dynamic Island, it also shows there.

1. Open the app within about 150 meters of a metro or RER station: the Live Activity of this station shows at once. Testers can also tap "Show the Live Activity now" in "Testing tools" (the station nearest to you, up to 2 km away), or pick any station in "Testing tools" > "Next trains of a station", and tap "Show on the lock screen".
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
   It is one group of two rows, one row for each end, on one white plate with the bar of the line (decision-35).
   The rows are in the order of the line, and the order never changes with the trains (metro 13 to the north: Saint-Denis - Université, then Asnières - Gennevilliers - Les Courtilles; metro 7 to the south: Mairie d'Ivry, then Villejuif - Louis Aragon).
   Each row writes its end in bold dark blue, at the size of the RER rows (13 points at the default size), then the next two trains of that end in the black columns "1er" and "2e", in amber numbers of 15 points (the plain strip below keeps its larger numbers).
   A thin rule separates the two rows.
   There is no mark: the rider reads the name of the end.
   The black column of the group has the left edge and the width of the boxes of the plain strip, with the same divider, so the numbers of the group stand above the numbers of the strip.
   The two ends have the same text size: when the long end (Asnières - Gennevilliers - Les Courtilles) does not fit, both names get smaller together, down to 70%, then both are cut.
   The words follow the metro: "0" in the last minute, "À quai" at the platform, drawn as in the plain strip.
   An end with one train leaves "2e" empty.
   PRIM lists only 3 or 4 trains of a direction, for both ends together, so an end with one train is the usual look, and an end with nothing listed is common (decision-45).
   An end that PRIM does not list, while the other end has trains, shows a grey dash "–" (the one of the Dynamic Island) in "1er", and "2e" stays empty: the app has no time for this end now, which does not mean that no train comes.
   An end whose next train is more than 60 minutes away says "In over 1 hour", or "> 1 h" when the words do not fit, across both columns.
   "No trains" shows in both rows only when PRIM lists no train at all for the direction, not even beyond the hour (the night); when only one end has a train beyond the hour, the other end shows the dash.
   The rule is `LineDirection.branchEndRows` (in `TROMECore`), tested on three recorded PRIM answers of Liège.
   When the times are old, the rows keep their names with empty boxes, as high as their text.
   The other direction is a plain strip.
   A station after the fork names only the end of its branch, so its page has plain strips.
   VoiceOver reads each strip as its end of line and its waits in minutes (for example "Mairie d'Issy, 4 minutes, then 8 minutes"), and each row of a fork group the same way, as its end and the waits of its trains (for example "Saint-Denis - Université, 4 minutes, then 12 minutes"), or as its end and "no train announced" ("aucun train annoncé") for the grey dash.
   The strips are for every metro page of the 321 metro stations of the station list: the 248 stations with one line and no hub (220 with plain strips and 28 with a fork group), and the 186 metro pages of the 73 stations with several lines or a hub (a fork group on the page of metro 7 or 13 at 22 of them, for example Maison Blanche, the fork of metro 7, which also has metro 14).
   A metro page keeps rows (one row for each direction, or for each branch of a direction: its destination, then the waiting times of its next trains, in amber in a black box, for example "4 minutes") only for as long as it lasts:
   a direction whose next two trains go to two different places (for example a train that ends early at Trocadéro on line 6), or a fork direction whose next two trains include a train that goes to neither of its two ends (a train that ends early), so that the rider always knows which train goes where.
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
   At a fork of metro 7 and 13, it shows the badge and the wait too, with no mark of the end (decision-41).
   When another app's Live Activity also shows, iOS gives ours a small round place (the minimal view): it shows the wait alone, as a bare amber number, with no badge.
   There the last minute and the platform both say "0" (a word does not fit), and stale, no train and "> 1 h" show a grey dash.
   The cost of this choice (the prompter's, decision-28): next to another app's Live Activity, the number alone does not say which line it is.
   VoiceOver reads the line, then the wait in minutes, or "Approaching", or "At the platform", never "zero".
   The compact and minimal views have no button (Apple allows controls only on the lock screen and in the expanded view).
3. Testers can remove it in "Testing tools", with "Stop showing on the lock screen". The main screen has no such button.
4. To remove it and snooze the automatic mode, tap "30 min", "1 h" or "Today" at the bottom of the Live Activity (see [Snooze or turn off the automatic mode](#snooze-or-turn-off-the-automatic-mode)).
   To remove it and pause only its station for 1 hour, swipe it away (see [Swipe the Live Activity away](#swipe-the-live-activity-away)).
   The snooze buttons show in the Dynamic Island too, when you touch and hold it.

The Live Activity can also start and stop by itself near a station (see below).

The first time, iOS asks on the lock screen if it can show Live Activities from TROME. Tap "Allow".

The waiting times count down by themselves, in whole minutes (a bare "3" in a metro strip or an RER row, or "3 minutes" in a metro row, see above).
The app sends new train times every 30 seconds while the app is open.
While the app is in the background, it sends new train times a few seconds after the first shown train leaves (at most every 30 seconds, and at least every 2 minutes).
When you lock the phone (or leave the app) while the Live Activity still says "Loading the next trains...", for example right after you tap the arrival notification, the app asks for the train times again at once in the background: the first trains do not wait for the next background refresh.
The same holds when you lock the phone right after the app opened again while a Live Activity shows, before the app sent its first times: the app does not know when the times on the Live Activity came, so it asks for them at once.
Between two calls, it draws the Live Activity again at each moment when a train on it changes (see above).
It stops asking PRIM when PRIM rejects the key or says the daily quota is used up.
A Release build (TestFlight or the App Store) asks the server of the app instead of PRIM (see [The train data key (PRIM)](#the-train-data-key-prim)), at the same moments.
It stops asking only when the server rejects its app token: when the server has no times for now, the refresh fails, and the app asks again at the next moment.
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

If the app says that Live Activities are turned off, turn them on in Settings > TROME > Live Activities.

For developers: `StationActivityAttributes` (in `TROMECore`) holds the data of the Live Activity.
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
`LinesPage` (in `TROMECore`) decides which lines the Live Activity shows: from the first asked line, one metro line alone, or as many RER lines as fit in 4 rows (at least one line, and never a metro line with an RER line).
With more than 2 rows, it keeps only the next train of each row, so the Live Activity stays under the 160 points of the lock screen.
It also keeps the soonest train of all the lines, for the Dynamic Island (`SoonestTrain`: its line and the train with its state), and, when no line has a train in the next 60 minutes, the line of the first later train.
`ContentState.dynamicIslandWait(isStale:)` (in `TROMECore`, `DynamicIslandWait`) decides what the compact and minimal views show: the line and the wait (minutes, approaching, at the platform, over an hour, no train, stale, loading or no data), and what the minimal view shows instead (`minimalWait`: the minutes, "0" or a dash).
The views are `IslandLineBadge` (`MetroLineBadge`, or the `RERSquareBadge` of the RER pages), `CompactIslandWait`, `MinimalIslandWait` and `IslandNumber`, in `ios/Widget/`.
The number (20 points) and the words (11 points) have fixed sizes: the compact island of iOS draws every text style at about the same size (title3 at about 14 points, caption2 at about 13), so with text styles the number was smaller and the words bigger than in the picked drawing (TASK-37 review).
When you touch and hold the Dynamic Island, the view tries the page as it is, then the page with only the next train of each row (`ContentState.keepingOnlyTheNextTrains`), then the same with a smaller text, and shows the first one that fits (`ViewThatFits`).
`PlatformStatus` (in `TROMECore`) says when a train is approaching or at the platform, from the arrival time, the departure time and `VehicleAtStop` of PRIM.
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
`LinesPage.panamStripsLine` (in `TROMECore`) decides if a page gets the strips:
one metro line (also a line of another station of the place, whose name `PanamStripsHeader` shows with the walking icon), at most two directions (a train whose direction stays unknown adds a third one, which would push the snooze row out), a page made by an app that knows the ends at the station (`LineTrains.hasADirectionWithTwoEnds` is set;
a Live Activity of an app older than TASK-140 has rows until the app updates it), and no direction whose shown trains go to two places, except a direction with two ends at this station.
`LineDirections` gives that direction its two ends in the order of the line (`LineDirection.branchEnds`, from `TransitLine+Ends.swift`, so the order never depends on the trains), and the next two trains of each end (`LineDirection.trainsOfEachEnd`, one `BranchEndTrains` for each end, in the same order, with its own "over 1 hour" state).
The page gets the strips while each of the next two trains of the direction goes to one of these ends, and the fork direction is then the group of `PanamBranchEndRows`, one row for each end.
`LinesPage.nextRedrawDate(after:)` also reads the trains of each end, so the second train of an end is drawn again when it arrives.
`PanamStripsView` draws the page, `PanamStripsHeader` its header (the order above:
the words "1er" and "2e", then smaller steps of the name, then a second line, only when `LineTrains.hasRoomForATwoLineStationName`), `PanamStrip` a plain strip,
`PanamBranchEndRows` the group of a fork direction (with the plate `SielPlate` and the rule `SielRule` of the RER rows, and one shared size of the two end names, with `ViewThatFits`),
`PanamCell` a column of a strip or of the group, and `PanamAtPlatformText` the words of a train at the platform (the largest of its one-line sizes that fits, else two lines, with `ViewThatFits`).
Every strip of every page has the same width of its number boxes (`cellWidth` in `PanamStripsView`), so the plates and the boxes line up.
The RER rows use `WaitingTime` (`Date.AnchoredRelativeFormatStyle`, "in 3 min."), which counts down by itself too.
The header of a page with other lines is a button with `ShowNextLinesIntent` (`LinesPagerButton`, with `OtherLinesControl` for "+N >", used by the strips and the rows): iOS runs it in the app (in the background), and `StationLiveActivityModel.showNextLines()` shows the next lines.
The Live Activity shows the first lines again when it starts or switches to another station.
`StationLiveActivityModel` starts, updates and stops it.
The view is in `ios/Widget/StationLiveActivity.swift`.

#### Check how the Live Activity draws

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
  the longest station names and ends of line, an end of line, 3bis and 7bis, and 4 stations of the fork page (TASK-143, now the group of TASK-181): Liège, Tolbiac, the fork La Fourche, and the longest name Aubervilliers - Pantin - Quatre Chemins, and 4 stations of the pages of one metro line of TASK-144:
  Pigalle, with two metro lines, Maison Blanche, the fork of metro 7 with metro 14, Bibliothèque François Mitterrand, the longest name of a station with several lines, and Palais Royal - Musée du Louvre, and 3 stations of the RER rows of TASK-65: Invalides, Gare de Lyon and Auber, Auber being also a station of a hub): 52 stations in all.
  It also draws the metro strips of Lamarck - Caulaincourt with every state of a wait (approaching, at the platform, one train, two digits, more than 60 minutes, no trains, the end of a line), as pages 90 to 94 of that station, and a wait drawn at 11 that counted down to 9 by itself, next to a wait drawn with one digit, as page 95,
  and the fork group of Liège with every state, as pages 95 to 100: "0" (approaching) and "À quai" in the first column of each row, an end over an hour next to an end with one train, an end that PRIM does not list (the grey dash), a direction with no train (both ends "No trains"), both ends over an hour, and a train to a third end (a short trip, which gives rows),
  and a train at the platform in the first column of the second row next to a wait of two digits, in both columns of the first row (with the plain strip at the platform too), and in both rows (both columns of the second row), as pages 101 to 103.
  Pages 104 to 107 of Liège have a made-up station name that is too long for one line, with two strips (the name is cut), one strip, none (the name goes onto a second line), and two strips with a train at the platform.
  Pages 108 and 109 of Liège are the header of the hub Place de Clichy (with "+1 >") with a train at the platform.
  Page 110 of Liège has a wait drawn at 11 that counted down to 9 by itself in each row of the group, next to waits drawn with one digit.
  Page 111 of Liège has a fork direction with no train in the hour: one end over an hour ("> 1 h"), the other end with the dash.
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

### The Live Activity starts and stops by itself near a station

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
    If you open the app at the station without tapping the notification (also with notifications turned off), the Live Activity of this station starts too, and the notification goes away.
- **One station at a time.** If a Live Activity already shows and you come within 150 meters of another station, the Live Activity switches to the new station. There is no second Live Activity and no second notification.
- **Stop.** The Live Activity ends by itself when you move more than about 250 meters away from its station, or 45 minutes after it started.
- **No repeat.** You get at most one notification and one automatic start for each arrival. After you stop the Live Activity by hand, it does not start again until you leave the station (more than 250 meters) and come back.
- **By hand (testers).** "Show the Live Activity now", "Show on the lock screen" and "Stop showing on the lock screen", in "Testing tools", still work.
  A Live Activity that you start by hand for a station far from you does not stop because of the distance.
  It stops at 250 meters only after you came near its station.
  The 45 minute limit applies to every Live Activity.
- **Swipe.** When you swipe the Live Activity away, its station is paused for 1 hour (see [below](#swipe-the-live-activity-away)).
  The other stations work as above.

The main screen says which station shows on the lock screen ("On the lock screen: <station>").

#### Swipe the Live Activity away

The rules come from decision-32 in the backlog.

- **The pause.** When you swipe the Live Activity away (on the lock screen or in the Notification Center), the app pauses its station for 1 hour.
  During this hour, at this station, no notification and no automatic Live Activity start, with the app open, in the background or closed, also when you leave the station and come back.
  Every other station works as usual: the notification when the app is in the background, the start at once when the app is open.
  After the hour, the station works again: the Live Activity starts at the next arrival at the station.
  The app hears the swipe within about 1 second, and stops getting your position in the background at once.
- **One pause at a time.** A swipe at another station replaces the pause.
  "Show the Live Activity now" (in "Testing tools") at the paused station, or a tap on its arrival notification, ends the pause.
  A snooze does not change the pause.
- **See and cancel it.** The main screen says "Paused at <station> until <time>" (in French "<station> : en sourdine jusqu’à <time>"), with the time left.
  Tap "Cancel the pause at <station>" ("Réactiver <station>") to end it at once.
  If you are at the station with the app open, the Live Activity then starts, also when you have not moved for a while: the app asks iOS for your position once, and the button waits for the answer (at most 5 seconds), with a small spinner in place of its icon.
  When no position comes, the pause still ends, nothing starts, and the screen says "Can’t find your position for now" ("Position introuvable pour l’instant") until a position comes or you leave the app.
  The line goes away when the pause ends.
  While the automatic mode is off, the screen does not show it.
- **What is not a swipe.** The app ends the Live Activity itself (the snooze buttons, "Stop showing on the lock screen", the 250 meters, the 45 minutes): no pause.
  You turn off Live Activities for the app in Settings: no pause.
  iOS ends a Live Activity after 8 hours: no pause.
- **Its limit.** The app sets the pause only when it runs at the swipe (normally the case: while a Live Activity shows, the app keeps getting your position in the background, so iOS keeps it running).
  When the app was not running, iOS starts it in the background right after the swipe, but it does not tell the app why, and the app cannot tell this start from another one (for example a region wake hours later).
  So the app sets no pause then, and it works as before decision-32: the Live Activity does not come back at this station until you leave it (more than 250 meters away, with no station within 150 meters) and come back.

For developers: `AutoLiveActivityRules.outcome(of:shown:now:)` (in `TROMECore`) decides whether a removal is a swipe: the app did not end it (`LiveActivityRemoval.endedByTheApp`), it still had a shown Live Activity in its saved state, Live Activities are on (`ActivityAuthorizationInfo().areActivitiesEnabled`), and it started less than 8 hours ago.
`AutoLiveActivityModel` applies it and saves the pause (`StationPause`) with its state, so the pause survives a relaunch.
`ActivityKitStationLiveActivityClient` (in `ios/App/LiveActivity/`) follows each Live Activity of the app (`activityStateUpdates`) and reports its first `ended` or `dismissed` state, with whether the app ended it itself (it remembers the Live Activities that it ends).
At launch, when the saved state says that a Live Activity shows and iOS lists none, the app forgets it with no pause (the limit above).
The cancel is a resume, and it follows the resume rule of decision-55, `ResumePositionRules` (in `TROMECore`), called through `AutoLiveActivityModel.positionForAResume()`, then `AutoLiveActivityRules.resume(state:position:now:onArrival:catalog:)`, which evaluates that position with the arrival rules (as a new arrival) or shows the line when there is none.
iOS sends no new position while the phone stands still (`CLLocationUpdate.liveUpdates` pauses), so the rule uses the last position only when it is precise and at most 15 seconds old.
Otherwise it asks iOS for one with `CLLocationManager.requestLocation()` (`LocationProvider.currentFix()`, in `CoreLocationProvider`) and waits at most 5 seconds; with no answer, it uses the last position when it is precise and at most 2 minutes old.
A position that comes later goes through the usual arrival rules.
The automatic arrival keeps its own 15 seconds.

#### Snooze or turn off the automatic mode

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
- **Back on at a station.** When you cancel the snooze, or turn the switch on, with the app open within about 150 meters of a station, the Live Activity of this station starts at once, with no notification.
  It is a resume, with the same position rule as the cancel of a pause (see [Swipe the Live Activity away](#swipe-the-live-activity-away)),
  and the same small spinner in place of the icon of the row while the app waits for your position.
  Away from every station, nothing starts and the screen says nothing.
  A paused station stays paused.

The first time, the app asks for your location and for notifications.
To get the notification while the app is closed, the app needs the location "Always".
iOS first asks for "While Using the App".
Right after your answer, the app asks iOS for "Always", and iOS asks you if the app can also use your location when you do not use it.
The app asks for notifications only after this second answer.
For developers: `LocationQuestionsRules` (in `TROMECore`) decides when to ask, and `CoreLocationPermission` (in `ios/App/Location/`) applies it.
iOS does not tell the app when you tap "Keep Only While Using", so the app waits until it becomes active again after the question.
When iOS does not show the second question (after "Allow Once", iOS ignores it), the app waits at most 20 seconds, then asks for notifications.
If you keep "While Using the App", the Live Activity starts by itself only while the app is open.
The "Permissions" part of the main screen then says so, with a button to open Settings.

#### Test it with a fake position

- **App open (the Live Activity starts at once).** Open "Testing tools", pick a station (for example Abbesses), and go back. The Live Activity starts. Pick a station near it (for example Pigalle): the Live Activity switches. Tap "Far from any station": the Live Activity ends.
- **App in the background (the notification).** The in-app fake position cannot change while the app is in the background. Use the Simulator location instead:
  1. In "Testing tools", tap "Use the real GPS". In iOS Settings, set the location of TROME to "Always".
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
  Launch the app with `-liveActivityMaximumDuration <seconds>`, for example: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev -liveActivityMaximumDuration 60` (replace `com.example` with your bundle ID prefix if you changed it).
- **Fake trains.** A build with no train data key shows no trains.
  In debug builds, launch the app with `--fake-trains` to get fake next trains instead, with no PRIM call: `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains`.
  The app saves this choice (`FakeTrainsStore`, in `TROMECore`), so the rule is:
  - A launch with launch arguments comes from you or from a test (`xcrun simctl launch` with arguments, XCUITest, the Run button of Xcode when the scheme has arguments).
    It turns the fake trains on with `--fake-trains`, and off without it.
    For example, a launch with only `-liveActivityMaximumDuration 60` has no fake trains.
  - The Run button of Xcode passes no argument with the default scheme, so it keeps the last choice, as a launch by iOS does.
    This matters on your iPhone, where the fake trains then replace the real trains of your key.
    To drop them, run the app once with any other argument in the scheme (Product > Scheme > Edit Scheme > Run > Arguments), or delete the app.
  - A launch with no launch argument comes from iOS itself: the tap on a button of the Live Activity after iOS closed the app, a region wake, a relaunch in the background.
    iOS passes no argument, so the app keeps the last choice.
    So you can close the app (`xcrun simctl terminate "$(make -s simulator)" com.example.trome.dev`), tap the Live Activity, and still see the fake trains.
    While a Live Activity shows, iOS starts the app again in the background a moment after you close it (it keeps getting the position in the background), so the tap often reaches an app that iOS started, not a closed one.
  - `make run` installs the app again, with no saved data, so it starts with no fake trains. `make switch-language` keeps the data of the app, so it keeps the fake trains.
- **Ask the fake trains for a state.** Live trains show some states only by luck: PRIM shows a train at the platform for 20 to 30 seconds, and the app updates the Live Activity only every 2 minutes in the background.
  So, in debug builds, add the name of a state after `--fake-trains`, for example `xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains at-platform`.
  The times start at this launch, the same for each line and each direction of the station (the second direction is one minute later), and the app follows its real rules with them (`FakeTrainsScenario`, in `TROMECore`).
  Then start the Live Activity at once (a fake position, or "Show the Live Activity now" in "Testing tools"), and put the app in the background to look at the lock screen and the Notification Center.
  - `at-platform`: the first box of each strip shows "À quai" for 5 minutes. Then the train leaves, and trains come every 4 minutes, each one 30 seconds at the platform, like real trains.
  - `at-platform-second`: the second box shows "À quai", next to a train that leaves first, for about 3 minutes. Then the first train comes ("0", then "À quai": both boxes), leaves, and the second one leaves 2 minutes later.
  - `at-platform-both`: both boxes show "À quai" for 5 minutes. Then the first train leaves, and the second one 2 minutes later.
  - `ten-to-nine`: trains every 6 minutes. The second box shows 10 or more, and counts down to 9 by itself about 3 to 4 minutes after the launch, then every 6 minutes. Look while the app is in the background, before the next update (at most 2 minutes).
  - A fork with both ends: at a station of lines 7 or 13 before the fork (for example Liège or Poissonnière), the trains go to each end in turn, so each row of the fork group shows two trains of its end, with or without a state.
  - `fork-end-one-train`: at such a station, the second end gets one train only (it leaves 8 minutes after the launch, then that end shows the grey dash), and the first end gets all the others.
  - `fork-end-no-train`: the second end gets no train at all, so its row shows the grey dash "–" in "1er" (the first end has trains).
  - `fork-end-over-an-hour`: the second end gets no train in the hour, and one train 70 minutes after the launch, so it says "> 1 h" for about 10 minutes, then counts down from 60.
  - On a line with no fork, these three states give the trains of the default fake trains, every 4 minutes.
  - The RER lines get the same times. Their rows show "À quai" only when the RER look draws it.
  - Check that the app got the arguments: `ps -axww -o args | grep "TROME.app/TROME"` shows `--fake-trains` and the name.
    When the line ends with `TROME` alone, iOS had already started the app again in the background (it does so while a Live Activity shows), and the launch only brought that app to the front: launch it again.
    On 2026-10-02 (TASK-170), the first launch after `make run` lost its arguments both times, and one or two more launches fixed it.
  - To start the state again, launch the app again with the same arguments. A launch by iOS (no argument) keeps the state and its start time. A name that the app does not know gives no fake trains, so the Live Activity says "No data available".

For developers: the rules are in `AutoLiveActivityRules` (in `TROMECore`), and `AutoLiveActivityModel` applies them.
`AutomaticModeModel` holds the automatic mode (on, snoozed until a date, or off) and saves it.
While the mode is not on, the rules still follow the arrivals, but they do not notify or start.
The buttons of the Live Activity run `SnoozeLiveActivityIntent` (a `LiveActivityIntent`, in `TROMECore` because the app and the widget share it).
iOS runs it in the app, and opens the app in the background if needed.
The intent gets `AutoLiveActivityModel` from `AppDependencyManager` (the app adds it in `TROMEApp`).
It reads the position from `LocationService`, so the fake position works too.
When the app is closed, iOS wakes it with region monitoring (`CLMonitor`, in `ios/App/AutoLiveActivity/CoreLocationStationRegions.swift`).
iOS watches at most 20 regions for each app, so the app watches the 18 nearest stations (150 m), the stop area of the shown station (250 m), and one larger area around you.
When you leave this larger area, the app picks the nearest stations again.
Debug builds log the region monitoring: whether iOS can watch regions, and each region event with its state and its diagnostics (for example `conditionUnsupported`).
They also log the Live Activity: at each launch, the Live Activities that iOS still lists with their state; each state change that iOS sends (`active`, `stale`, `ended`, `dismissed`); each end that the app asks for itself; when the background location starts and stops; and when a pause of a station starts, ends or is cancelled, with the reason (or why a removal set no pause).
So you can see when iOS tells the app that you swiped the Live Activity away (TASK-146, TASK-166).
They also log each content that the app sends to the Live Activity (category `LiveActivityContent`: each shown train with its time, its destination and its state, and at a fork the trains of each end row, after "rows:"),
and each PRIM answer (category `PRIM`: one line per train of the answer, with its destination, its times, its quay, its journey, and whether the app keeps it or drops it, and why).
The PRIM key is never in the log.
So, with live data, you can tell whether a change on the Live Activity comes from PRIM, from the rules of the app (for example the 60 s rule of a metro direction), or from iOS (TASK-169).
To read the log in the Simulator: `xcrun simctl spawn "$(make -s simulator)" log show --last 5m --predicate 'subsystem == "TROME"'`.
On your iPhone, open the Console app on the Mac, choose the iPhone, and search for `subsystem:TROME`.
The name `TROME` of the log is written once, in `Logger.subsystem` (`ios/Packages/TROMECore/Sources/TROMECore/Logging/Logger+Subsystem.swift`).
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
When you swipe it away, iOS tells the app within about 1 second, and the app stops the background location at once and pauses the station (see [Swipe the Live Activity away](#swipe-the-live-activity-away)).
Each time it gets new train times, it asks PRIM once for each stop area of the station and of the other stations of its place (Châtelet: 2 calls, Saint-Lazare: 5 calls).
While the app is open, the app gets the train times of the Live Activity every 30 seconds, unless the next trains screen of the testing tools already gets them for the same station.

Limit: the app gets new train times in the background only while it runs.
It stops running when you close it from the app switcher, when the location is not allowed, or when iOS ends it (for example to free memory).
Then the 45 minute limit applies only when iOS wakes the app again (a region event) or when you open it, and the Live Activity gets no new train times until then.
A free Apple ID has no push notifications, so no server can send new times to the Live Activity instead (see "Later" in the Product Vision).

## The train data key (PRIM)

The app gets train times from the PRIM API of Île-de-France Mobilités. PRIM needs a free key.

This section is about the Debug builds (`make run`, the Run button of Xcode): only they ask PRIM with your key.
A Release build (an archive for TestFlight or the App Store) never holds the PRIM key, even with `LIVE=1`: the Release settings of `ios/project.yml` leave the key out of the app, and the code of a Release build does not read it.
It asks the server of the app for the trains (see [The server](../server/README.md)), with its host and its app token, which go in `ios/Config/Server.xcconfig` (a copy of `ios/Config/Server.example.xcconfig`, ignored by git).
Only the Release builds read this file.
A Release build or an archive fails when this file has no host, a host with more than the host name (for example `https://` or a path), or no app token, and its error names the file and its example: so no build can ship with no train source.
`make live-key-check` proves it with fake values.
**Product > Profile** in Xcode makes a Release build too, so it needs this file as well.
The server gives the PRIM answer as PRIM gave it, and the time when PRIM gave it: the app counts the age of the times from that moment, not from the moment when it got them, and it never shows a train that left in the meantime.
When the server does not answer, gives an error or has no times for now, the refresh fails, and the Live Activity keeps the last times as for any failed refresh (see [Show the next trains on the lock screen (Live Activity)](#show-the-next-trains-on-the-lock-screen-live-activity)).
The app sends the server only the stop and the app token: no position, no identifier of the device or of an account, and no push token.

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

The build output never shows the key. `make live-key-check` proves it with fake keys: it builds with a first key, changes the key file, builds again, and checks that the app has the new key and not the old one. Then it builds without `LIVE=1` and checks that the app has no key.
Then it makes a Release build with a fake key and a fake app token, given the way `LIVE=1` gives the key, and checks that no file of the Release build holds the key, that the app holds the app token and the Live Activity does not, and that no build output or log shows the key or the token. `make check` runs it.

## Install on your iPhone (free Apple ID)

The tutorial "Install the app on your iPhone" of the docs site explains it step by step, for beginners. Run `make docs`, then open http://localhost:4321/trome/en/build/install-on-your-iphone/. The page is `docs/src/content/docs/en/build/install-on-your-iphone.mdx`.

In short: your Team ID and a unique bundle ID prefix go in `ios/Config/Local.xcconfig` (a copy of `ios/Config/Local.example.xcconfig`, ignored by git).
Run `make generate`, open the project `ios/TROME.xcodeproj` in Xcode, choose the scheme `TROME` and your iPhone, and click Run.
With a free Apple ID, the app stops after 7 days: run `make generate` again, then click Run again to renew it.

Your build gets the bundle ID `<prefix>.trome.dev`, and its Live Activity gets `<prefix>.trome.dev.widget`.
These IDs end with `.dev`, so they are never the App Store ID of the app, `io.github.valfur03.trome`, whatever your prefix.
Why: when a free Apple ID signs a build, Apple registers its bundle ID to that Apple ID for good, and the paid account of the app could then never take it.
Only the Release builds (for the App Store) carry `io.github.valfur03.trome` and `io.github.valfur03.trome.widget`, and Xcode never signs them automatically.
So Xcode can show an error for Release in Signing & Capabilities: leave it, and never turn on "Automatically manage signing" for Release, or Xcode registers the App Store ID to your Apple ID.
`make bundle-id-check` (part of `make check`) checks both.
A free Apple ID registers at most 10 bundle IDs in 7 days, and each one expires after 7 days.
When Xcode says "Your maximum App ID limit has been reached" or "No profiles for ... were found", wait, or reuse two bundle IDs that Xcode already registered on your Mac: the tutorial shows the command that lists them, with the date when each one expires.
To reuse them, set `RATP_DEBUG_APP_BUNDLE_ID` and `RATP_DEBUG_WIDGET_BUNDLE_ID` in `ios/Config/Local.xcconfig` (see `ios/Config/Local.example.xcconfig`), then run `make generate`.
`make generate` then prints the two bundle IDs that Xcode will use: check them before you click Run, because a mistyped setting name is ignored.
They are the full bundle IDs of your Debug builds, written as is, and the ID of the Live Activity must start with the ID of the app and a dot; with only the first one set, the Live Activity gets the app ID followed by `.widget`.
`make generate` and `make bundle-id-check` refuse the App Store IDs there, in any capitals, and the git hooks print the same refusal.
A Run in Xcode with no `make` command gets an ID that starts with `SHIPPING_ID_REFUSED` instead, which is not a valid bundle ID.
A build from before the app was called TROME has another bundle ID, so iOS keeps it as a second app: delete it, so that its notifications and its Live Activities stop.

On a device, the Run button of Xcode uses the PRIM key of `ios/Config/Secrets.xcconfig` in the folder that you open. There is no `make` command for a device build.

## Languages

Almost every user of the app is French. The app shows each text in French when the language of the iPhone is French, and in English for any other language (Settings > General > Language & Region). English is the language of the code: each text is written in English in the Swift code.

- The French texts are in String Catalogs: `ios/App/Localizable.xcstrings` (the main screen and the notifications), `ios/App/InfoPlist.xcstrings` (the texts that iOS shows when it asks for the location) and `ios/Widget/Localizable.xcstrings` (the Live Activity and the Dynamic Island).
  Xcode shows them as tables.
  You can also edit the JSON by hand.
- The "Testing tools" screen (debug builds only) stays in English. Its texts are inside `#if DEBUG`, so Xcode keeps them out of the catalog.
- The name of the app, TROME, is written once: `APP_NAME` in `ios/Config/Base.xcconfig`.
  The name on the home screen, the file name of the app, the permission texts that iOS shows and the texts of the app that name it read it from there (a text of the code gets it as `%@`).
  To change the name, change that line and run `make strings-sync`: it puts the new name in the French permission texts of `ios/App/InfoPlist.xcstrings` too.
  `make strings-check` fails when one of these French texts does not say the name, for example after a build in Xcode wrote the new English texts: then write the name in it by hand.
  `make public-text-check` fails when an older name of the app, of its Xcode project or of its module comes back in a file of the repo.
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
| `README.md`, `CLAUDE.md`, `.gitignore`, `.nvmrc` | Files for the whole repo. `.nvmrc` pins the Node version of the Node parts (`docs/` and `server/`). |
| `Makefile` | Runs each `make` command in the folder of its part. It has no build logic. `make check` runs the checks of all parts. |
| `ios/` | The iPhone app, with its own `Makefile`, `project.yml`, `.swiftlint.yml`, build settings and scripts. Its build output goes to `ios/.build/`. |
| `docs/` | The docs site (Starlight), with its own `Makefile` and scripts. |
| `server/` | The server (a Cloudflare Worker in TypeScript), with its own `Makefile`, scripts and `package.json` (see [server/README.md](../server/README.md)). |
| `contracts/` | The files that the app and the server both test against. Today `contracts/prim/`: the recorded PRIM answers of the unit tests. |

Inside `ios/`:

| Folder | What it holds |
|---|---|
| `App/` | The iPhone app (SwiftUI): the entry point, the views, and the adapters to the iOS frameworks. One folder per feature. |
| `Widget/` | The widget extension. It shows the Live Activity. |
| `Packages/TROMECore/` | The rules, the state and the data of the app, shared by the app and the widget, with its unit tests. One folder per feature. |
| `UITests/` | The end-to-end tests (XCUITest). |
| `DocsScreenshots/` | The XCUITest suite that takes the app screenshots of the docs. |
| `RenderCheck/` | The render check of the Live Activity views (`make live-activity-render`): a unit test bundle, and in `Host/` the small app that runs it with the texts of the widget. |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands of the app. |

The feature folders have the same names in `ios/App/`, in the sources of `TROMECore` and in its tests: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`.
`ios/App/` also has `Permissions` and `TestingTools` (debug builds only).
The rules for the code (where each file goes, which module depends on which) are in the CLAUDE.md, section "Code structure of the iOS app".

You can also run the commands of one part in its folder: `make -C ios check` runs only the checks of the app.
