# What the lock screen and the Dynamic Island show, and when they change

The Live Activity shows the next trains of one station on the lock screen and in the Dynamic Island, one metro or RER line at a time: each line is a page.
This page says what each place shows for each state of a train, and when the app draws it again, so that you find the rule or the view that your change touches.
`make test` runs the unit tests of every rule here, with no Simulator and no train data key, and to see a state in the Simulator you use [fake trains](testing-tools.md#ask-for-a-train-at-the-platform-or-another-state).
[When it starts and stops](auto-live-activity.md) and [how to check that it fits](render-check.md) have their own pages.

## Find the code for your change

A view holds no rule: it reads a page and draws it.
Put a rule in `TROMECore` (`ios/Packages/TROMECore/Sources/TROMECore/`), with a unit test, and draw it in `ios/Widget/`.

| You want to change | Look in | Its tests |
|---|---|---|
| Which lines and which trains a page holds, the order of the pages | `LinesPage`, `ContentState` (`LiveActivity/`) | `LinesPageTests*`, `StationActivityContentTests*` |
| Which direction a train goes in, how many trains a direction keeps | `LineDirections` (`Trains/`) | `LineDirectionsTests*` |
| When a train is approaching or at the platform, and never at the platform behind a train still on its way | `PlatformStatus` (`Trains/`) | `PlatformStatusTests`, `LineDirectionsTests+OnePlatform` |
| What the compact and minimal views show | the rules in `DynamicIslandWait`; the views `CompactIslandWait`, `MinimalIslandWait`, `IslandNumber` | `DynamicIslandWaitTests` |
| The look of a metro strip, a fork group, an RER row or a header | `PanamStrip`, `PanamBranchEndRows`, `SielRowsView`, `PanamStripsHeader` in `ios/Widget/`; `StationLiveActivity.swift` holds the entry views | [the render check](render-check.md) |
| The header and its tap | `LinesPagerButton`, `ShowNextLinesIntent`, `StationLiveActivityModel.showNextLines()` | `StationLiveActivityModelTests` |
| When the Live Activity is drawn again | `LinesPage.nextRedrawDate`, `StationLiveActivityModel.redraw()`; `BackgroundTrainsRefresh.asksInsteadOfRedrawing`, when a row would lose a train | `LinesPageTests+Redraw`, `StationLiveActivityRedrawTests`, `AutoLiveActivityFeedTests+ForkEnds` |
| How the app starts, updates and ends the Live Activity in iOS | `StationLiveActivityModel` and its protocol `StationLiveActivityClient`; the adapter `ActivityKitStationLiveActivityClient` and the start error `LiveActivityStartError`, in `ios/App/LiveActivity/` | `StationLiveActivityModelTests` |

The values that a change often needs are constants:

| Value | Constant |
|---|---|
| 60 seconds before the arrival, when a train is "approaching" | `PlatformStatus.approachingSeconds` |
| 60 minutes, the limit of "over an hour" | `DepartureBoard.farthestTimeSeconds` |
| 2 trains for a direction, 3 directions for a page, 60 seconds between two metro trains | `LineDirections.timesPerDirection`, `maximumDirections`, `minimumMetroHeadway` |
| More than 2 directions: only the next train of each | `LinesPage.maximumRowsWithTwoTrains` |
| 60 seconds, the stale date of "Loading" | `ContentState.loadingTimeout` |
| 20 points for the number of the compact view, 11 for its words, 60 points before a word wraps | `IslandNumber.font`, `CompactIslandWait.wordFont`, `CompactIslandWait.wordMaximumWidth` |
| A badge of 24 points in the header and the compact view, 20 in a row; in the compact view, an RER square 3 points in from the round end of the island, which would cut its corners | `LineBadgeSurface.diameter`, `StationLiveActivity.rerIslandInset` |

## One line for each page

A page shows one line, so that its strips or rows keep under the 160 points that iOS gives the lock screen.
A station with several lines has one page for each line.
So has a place with several stations: Châtelet, Châtelet - Les Halles and Les Halles are one place, joined underground, and each of them shows the lines of all three.

- **The header** is one button, at least 44 points high.
  It holds the badge of the line of the page, the station name, and at the right "+N >", where N is the number of the other lines.
  A tap anywhere on it shows the next page, and after the last page the first one comes again.
  "+N >" stays at the same place on every page, so that you can tap many times without aiming again.
  The expanded Dynamic Island shows the same header for a station with several lines.
- **The order of the pages** is the lines of the station itself first (metro by number, then RER), then the lines of the other stations of the place, nearest station first.
  A line of another station has a walking icon and the name of that station in place of the station name, so that the rider knows where to walk.
- **The first page** shows when the Live Activity starts or switches to another station.
- **The trains.** A direction keeps its next two trains of the next 60 minutes, and a page keeps at most three directions.
  When a page has more than two directions, each one keeps only its next train, to stay under 160 points.
  PRIM sometimes lists one metro train twice, less than a minute apart: the page keeps the first, because no two metro trains leave a platform that close.
- **The badges** are drawn by the app, in the official colour of the line from the station list, and never grey or hollow: a circle with the number for a metro line, a rounded square with the letter for an RER line.
  The app does not use the RATP or Île-de-France Mobilités pictograms, which it may not share.
  One view, `LineBadgeView` in the `TROMEBadge` module, draws them on the lock screen, in the Dynamic Island and on the app screen, each at its own size.
  It draws the number or letter as the outlines of the bold system font, and centres what it draws, not the box of a text, which would put a digit off the centre by the room that a font keeps for accents and descenders.

### Which direction a train goes in

`LineDirections` splits the trains of a line into two directions, and the rules are pinned by `LineDirectionsTests*`.

- On a metro line, PRIM has one platform (a quay) for each direction, so the quay of a train gives its direction.
  With no quay, the destination decides, from the names of the ends of line in `TransitLine+Ends.swift`.
- A train that ends before the end of the line (at Trocadéro on line 6) stays in the direction of its quay and shows its own destination.
- An RER station has one stop area for both directions, and a quay serves one direction, so the trains of a quay go together.
  A quay gets its direction from the destinations of its trains, and from the `DirectionRef` of PRIM ("Aller" or "Retour") only when PRIM gives both values at that station: on RER A, it gives "Aller" to every train.
- On the trunk of an RER line, before every fork, a train goes in the direction whose branches hold its destination.
  On RER A, D and E, a train that ends at another station of the trunk goes in the direction of that station, from the ordered `trunkStations` of `TransitLine+RERLineEnds.swift` (a La Défense train at Vincennes goes west, a Goussainville train at Gare de Lyon goes toward Creil), even when no quay or `DirectionRef` tells it.
  A train whose direction stays unknown shows in its own row with its destination, but not on the trunk: there it would add a third row that keeps one train only.

## The lock screen

The page decides which look draws it, in `LinesPage.panamStripsLine` and `LinesPage.sielRowsLine`:

| Page | Look |
|---|---|
| A metro line with two directions or fewer, each going to one place (or to the two ends of a fork) | Strips, like the PANAM screens of the metro platforms |
| An RER line | One plate for each direction, with one row for each train, like the SIEL screens |
| Any other metro page: a direction whose next trains go to different places, or a third direction | Rows, as in the expanded Dynamic Island, so that the rider always sees which train goes where |
| Loading, no data | A line of text |

### The waits

| State of a train | Metro strip, fork row | RER row |
|---|---|---|
| In 1 minute or more, within the hour | The minutes, rounded up, as a bare number: "4" means 4 minutes | The same |
| Less than a minute away | "0" | "Approaching" ("À l'approche") |
| At the platform: PRIM says `VehicleAtStop`, or the time is between the arrival and the departure | "At the platform" ("À quai") on one line; at a smaller size when it does not fit, then on two lines | "At the platform" ("À quai") |
| Next train over 60 minutes away | "> 1 h", across both columns | The same, in the box |
| No train listed for the direction | "No trains" ("Pas de train"), grey | The same |
| One train only | The second column is empty | One row |
| Old times: the stale rule, below | The boxes are empty, the ends of line stay, and a line says "Open the app" | One row for each direction, with its name and an empty box |

- On a metro strip, a train after one that has not reached its platform yet shows its minutes, even when PRIM says that it is approaching or at the platform.
  Why: a metro platform holds one train of a direction, and trains do not pass each other there, so "At the platform" behind a train still on its way is wrong, and a rider could run for a train that is minutes away.
  Each platform counts alone: at a fork station where each branch has its own platform, the train of one branch may be at its platform while the other branch waits for its train.
  RER rows keep what PRIM says, as an RER station can have several tracks for one direction.
- The number counts down by itself, also with the app closed, because it is a timer of iOS.
  Counting never reaches "0": "0" is the state of the last minute.
- An RER row never says "0", and draws no other status than the two words: PRIM gives none that a rider can trust.
  The two words share one size, the largest at which the longer one fits the box.
- At a station with one line, the header of a strip page says "1st" and "2nd" ("1er", "2e") above the two columns.
  A page with "+N >" has no such words.
- The end-of-line name shrinks to 70%, then is cut.
  The station name in the header loses the "1st" and "2nd" first, then shrinks to 60%, then goes onto a second line only on a page with one strip or none, then is cut.
  A second line would push a page of two strips over 160 points.

### A fork of metro 7 or 13

Metro 7 and 13 split into two ends.
At each station from which one direction splits into two ends (before the fork, at the fork, and at the end of line on the other side), that direction is one group of two rows on one plate, one row for each end, in the order of the line and never in the order of the trains.
Each row shows the next two trains of its end.
A station after the fork names only the end of its branch, and shows plain strips.
`BranchEndRow` has one state for each case:

| An end with | Its row shows |
|---|---|
| Trains | The waits, as in a strip |
| No train listed, while the other end has some | A grey dash "–" in the first column: the app has no time for this end now, which does not mean that no train comes |
| Its next train over an hour away | "> 1 h", across both columns |
| No train at all, for either end, and none beyond the hour | "No trains" in both rows |

PRIM lists only three or four trains for a direction, for both ends together, so an end with one train, or with none, is the usual look.
The two names have one size: when the longer one does not fit, both shrink to 70%, then both are cut.
When a train goes to neither end (a short trip), the direction cannot be a group, and the page shows rows.

## The Dynamic Island

| View | When | What it shows |
|---|---|---|
| Compact | The island, not touched | The badge of a line on the left of the camera, the wait of its next train on the right |
| Minimal | Another app's Live Activity shares the island | The wait alone, with no badge |
| Expanded | You touch and hold it | The header, the trains as rows, and the snooze buttons |

The compact and minimal views have no button: iOS allows controls only on the lock screen and in the expanded view.

**The line** of the compact view is the one whose next train comes first, among all the lines of the station and of its place, on every page.
So at Châtelet the line changes by itself as trains come and go, and the badge and the number belong to one train.

| State | Compact | Minimal |
|---|---|---|
| In 1 minute or more | A bare amber number, 20 points | The same, with no badge |
| Less than a minute away | "0" | "0" |
| At the platform | "At the platform" ("À quai"), 11 points, on two lines when wider than 60 points | "0" |
| Over 60 minutes away | "> 1 h" | A grey dash |
| No train | "No trains" ("Pas de train"), grey, on two lines | A grey dash |
| Old times, loading, no data | A grey dash, never a number that may be wrong | A grey dash |

The sizes are fixed, because the compact island draws every text style at about the same size.
At a fork, the compact view shows the badge and the wait with no mark of the end.

**The expanded view** draws every line as rows, never as strips:

- A metro row is an arrow in the colour of the line, the destination, and one or two waits in black boxes, such as "4 minutes".
  The box says "Approaching" or "At the platform" for those states.
  When two trains of a direction go to different places, each has its own row.
- An RER row is an arrow, the destination, and the time, as "in 3 min.", with the next one smaller.
  It has no word for "Approaching" or "At the platform".
- A page with one line shows an icon and the station name above the rows; a page with several lines shows the header of the lock screen.
- It tries the page as it is, then with only the next train of each row, then with a smaller text, and keeps the first that fits.
  It keeps 8 points above its bottom edge, so that the last snooze button stays out of the round corner.

## When the Live Activity changes

iOS does not draw a Live Activity again by itself.
So the app sends a new content in these cases:

| When | What the app does |
|---|---|
| New trains arrive | Draws the page with them: [when the app asks again](trains.md#when-the-app-asks-again) |
| In the background, a train on the page starts to approach, arrives or leaves; the soonest train of the station does the same, on any page, for the island | Draws the page again at that moment, with the times it has, and no call to PRIM |
| The rider taps the header | Shows the next page, from the trains it has |

Between two updates the numbers count down by themselves.
Only a few formats do that, so use one of these:

- For "4 minutes", the SwiftUI style `.offset`.
- For a bare number, `PanamMinutes`: the timer of iOS, rounded up like `.offset`, in a box as wide as its digits.
- Never `Date.ComponentsFormatStyle`, which freezes until the next update, and never a format style of your own, which makes iOS draw the whole Live Activity as a grey placeholder.

### The stale rule

The content has a stale date: the time of the first shown train, or, when no train comes within the hour, the moment when the first later train comes within it, or 60 seconds after "Loading".
At that date, iOS hides the waits and the line "Open the app" shows.
iOS does it with no help of the app, also when the app is closed.

iOS never does it sooner than 2 minutes after the last content that the app sent.
Apple does not document this rule.
The log of the Simulator shows it: `liveactivitiesd` plans its task "Marking activities stale" at the later of the two dates.

| The app | What the rider sees |
|---|---|
| Runs | Nothing of the rule: the app sends a new content when the train leaves. With times kept after a failed call, it sends them again marked stale (`isMarkedStale`), and the widget hides the waits at once |
| Does not run, and the last content came more than 2 minutes before the train left | The waits go 1 to 3 seconds after the train left |
| Does not run, and the last content came less than 2 minutes before | The waits stay until 2 minutes after the content: "0" for up to about a minute after the train left, "Approaching" or "At the platform" for up to about 2 minutes |

When no direction has a train within the hour, "> 1 h" goes the same way once the first train comes within the hour.

### When it cannot show times

| The Live Activity says | When |
|---|---|
| "Loading…" | The first call has not answered. After 2 minutes at most, iOS marks it stale |
| "Times unavailable" ("Horaires indisponibles") | The app has no times for the station: no key, a first call that fails, or a switch to a station whose first call fails. Also after a failed call that follows "No trains", because that state never gets old |
| "No trains" on each line | PRIM lists no train at all for the station |
| "Times unavailable", in place of "Open the app" | The server of the app is out because its budget of PRIM calls is used up (see [what a failed call does](trains.md#what-a-failed-call-does-to-the-live-activity)). The times already shown keep counting down until the first shown train has left, then they are hidden and these words show, with the strips and their ends of line. A Live Activity that starts while the server is out shows them too. The Dynamic Island says the same to VoiceOver and shows its dash. No icon, no colour, no alert, no notification and no sound |
| An empty box in a direction, with its end of line, while other lines or directions show times | One stop of the station did not answer while another did: the server is out for that stop, or its call failed. The times that the direction showed before keep counting down until their first train has left, then the box is empty. Never "No trains" or a dash: the app does not know. VoiceOver reads only the end of line. The Dynamic Island shows the next train that the app knows, else its dash, and reads "Times unavailable" |
| The last times, still counting down, then "Open the app" | A call fails while times of this station show: [what each failure does](trains.md#what-a-failed-call-does-to-the-live-activity) |

The other causes keep their words: no network, or a closed app that iOS marks stale.
The app has no timetable, so it cannot tell a line that stopped for the night from a line that is closed: it never says that the service ended.

## VoiceOver

Each strip and each row is one element that reads the end of line and its waits in minutes ("Mairie d'Issy, 4 minutes, then 8 minutes"), or "Approaching", "At the platform", never "zero".
The header reads the line and the station (or "walk to" another station), then "Show the next line" and the number of other lines.
In the compact view the badge reads the line and the number reads the wait; the minimal view reads both.
The short words of the rare states read in full: "> 1 h" reads "In over 1 hour", "Loading…" reads "Loading the next trains…", "Open the app" reads "Open the app for new times.", and "Times unavailable" reads "Times unavailable for now".
