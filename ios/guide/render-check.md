# Find a Live Activity that is too tall or cut, with make live-activity-render

`make live-activity-render` draws the Live Activity for every station and page, and reports the drawings that are too tall and the texts that are cut.
Run it before and after a change to the views or to the data that they draw, and compare the two reports.
On a real lock screen, iOS cuts a Live Activity that is too tall, and a rider never sees what it cut, so the check finds these cases before a rider does.
It draws fake trains, so it needs no train data key.
It is a report for a person to read: it is not part of `make check` or `make e2e`, and it fails only when it cannot run, never on a cut text.
It prints a summary and saves its images and lists in `ios/.build/live-activity-render/`.

## Run it

```sh
make live-activity-render
make live-activity-render ENGLISH=1
```

The first command draws in French, the main language of the app, in `ios/.build/live-activity-render/fr/`.
The second draws in French, then in English, in `.../en/`: use it only when your change touches an English text of the Live Activity, because the French texts are longer, and the English run costs about 2 more minutes.
The check is a Simulator job: it builds, then waits for the [shared Simulator](../README.md#one-simulator-for-all-your-clones), draws, and frees it.
The French drawing takes about 3 minutes of Simulator time, and the text recognition on your Mac about a minute more for each language.
It leaves its small host app on the Simulator, and the next job removes it.

## What it draws

| | |
|---|---|
| **Views** | `LockScreenView` at the width of an iPhone 17 (373 points) and an iPhone SE (355 points), and `ExpandedIslandBottomRegion` (338 points), the bottom of the expanded Dynamic Island |
| **Text sizes** | Large (the default) and XXXL, the largest size that iOS uses for a Live Activity |
| **States** | Fresh, and stale (the "Open the app for new times." state) |
| **Data** | The fake trains, for each station of the list with the stations of its place, and for every page of its lines |
| **Made-up pages** | From page 90, each state of a wait on one station: the metro strips at Lamarck - Caulaincourt, the fork group at Liège, the RER rows at Auber and Invalides |
| **Images** | A PNG at 3x for every station that has a hub, and for the stations of `imageStations` in `ios/RenderCheck/LiveActivityRenderCheck.swift` (the longest names, the biggest hubs, forks, RER branches); the other stations are only measured |

The views are drawn with `ImageRenderer` in a unit test bundle, so there is no lock screen.
The bundle runs in a small host app, `ios/RenderCheck/Host/`, that holds the String Catalog of the widget as the widget extension does, so the texts are those that a rider reads.
The test fails when the texts are not in the language that it draws.
An image is named `<station>-p<page>[-stale]-<surface>-<size>.png`, with `_` for each space: `lock17`, `lockSE` or `island17`, then `L` or `XXXL`.

## What it reports

For each language, in its folder, and in a summary that the command prints:

| File | It holds |
|---|---|
| `heights.csv` | The height of each drawing, in points, drawn at 3x as on the iPhone, so a multiple of a third of a point |
| `too-tall.csv` | The drawings taller than their limit, with their count by surface and size in the summary |
| `cut-texts.txt` | Each text of the images that ends with "…" (the text recognition of macOS reads it as "..."). A person reads it and the images: it does not decide if a cut is a bug |
| `breaches.csv` | The breaches of the cut rules below, with their station, page, surface, size and image |
| `texts.json` | The texts that the drawings hold, which the breach check compares with what it reads in the images |

| Surface | Limit at Large | Limit at XXXL |
|---|---|---|
| Lock screen | 160 points: iOS cuts a Live Activity there | 195 points, the tallest that was seen whole, not a proven limit |
| Bottom of the Dynamic Island, a page with one line | 87 points | None: only its images are saved |
| Bottom of the Dynamic Island, a page with several lines | None, because its room was not measured: only its images are saved | None |

## The cut rules

When a row is too narrow, the rider needs first the line and the direction, then the time, then where to walk.
So the text size of a station label gives way first, then the text size of a destination, then the end of a destination.
The check lists a text that cuts more than that, in four kinds of breach:

| Breach | The rule | Why |
|---|---|---|
| Time cut | A time is never cut, for example "dans 3…". A shorter spelling that is whole, "3 min", is not a breach | A cut time loses its number or its unit |
| Destination under 6 | A destination shows at least 6 characters before its "…", or the whole word when it is shorter ("Na…" is a breach) | The first words tell which way the train goes |
| Two directions the same | The two directions of one line never show the same text, for example "Mairie d'…" twice | The rider cannot tell them apart |
| Label cut | The station name of a label, a line of another station of the place, is never cut | It tells the rider where to walk |

It finds them in two steps.
The render test records SwiftUI's own layout of each text (`Text.LayoutKey`): where it is, whether it is cut, and how many characters show.
Then, on the Mac, text recognition reads each cut text in its part of the image, and the command compares it with the texts of the drawn state to know whether it is a time, a destination, a label or the station name.
Cut texts that are none of these, for example "Ouvrez l'app pour mettre à jour les horaires", are counted as other cut texts, and a person reads them.
It looks at the images only, so at the stations that have one, and the summary says how many stations that is.

A breach is a defect: do not hide it, and say it in your pull request.

## When to run it

Run it before and after a change to `ios/Widget/`, to `LinesPage`, `ContentState` or `DynamicIslandWait`.
Write in your pull request, for the two runs, the number of drawings that are too tall, the count of each kind of breach for each language, phone, surface and size, the cut texts that changed, and the images that matter.
Look at each image once.

## What it cannot see

- **The real limits.**
  The heights and widths above were measured on the iOS 27.0 Simulator, with a UI test that opened the real Live Activity and read its frames.
  After a new iOS version, or a new layout of the regions of the Dynamic Island, measure them again and change `surfaces` in `LiveActivityRenderCheck.swift`.
- **The accessibility sizes.**
  iOS draws a Live Activity at XXXL at most: at the accessibility sizes, the rows keep their XXXL size and only the snooze buttons grow wider.
  The check draws XXXL, because the larger sizes would give false alarms.
- **What iOS draws around the views**: the round corner of the Dynamic Island, and the real room of its bottom region, which changes with its leading and center regions.
- **A text that iOS cuts while there is room.**
  The render measures and draws each text in one process, so a text that fits is always drawn whole.
  On a real Live Activity, iOS can give a one-line text a frame a fraction of a point narrower than it needs, and the text ends with "…" ("Opéra" became "Opé…" at XXXL).
  So give every one-line text that can be shown at exactly its own width a `minimumScaleFactor`, and check the tight texts of your change on a real Live Activity at XXXL.
  A text that is whole in the render is not a proof that it is whole there.
- **A state that nobody drew.**
  Each made-up page is a state written in `LiveActivityRenderCheck+StripStates.swift`, `+ForkGroupStates.swift` or `+RERStates.swift`: add one for a new state of a wait.

## Change the check

- The test, the made-up states and the host app are in `ios/RenderCheck/`; the report is in `ios/scripts/live-activity-render.sh`, `live-activity-render-ocr.swift` and `live-activity-render-breaches.swift`, and `make test-scripts` tests the script.
- Keep `LockScreenView(state:isStale:)` and `ExpandedIslandBottomRegion(state:isStale:)` in `ios/Widget/StationLiveActivity.swift` internal, with these parameters: the check draws them.
  A redesign may change what is inside.
- A new String Catalog of the widget goes in the host app too: add it in `ios/project.yml`.
- To see what a page looks like, and why a rule gives these drawings, read [what the lock screen and the Dynamic Island show](live-activity.md).
