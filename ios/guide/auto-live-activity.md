# When the Live Activity starts and stops by itself

Near a metro or RER station, the app starts the Live Activity for the rider, switches it when they reach another station, and ends it when they leave.
This page holds the rules (distances, times, snooze and pause), the order of the permission questions, and what keeps the app running in the background.
The rules are pure functions of a state, a position and a clock in `AutoLiveActivityRules`, so `make test` checks each one with no Simulator and no train data key.
To try them in the Simulator, use a fake position: [Test the automatic start](testing-tools.md#test-the-automatic-start-of-the-live-activity).

## Find the code for your change

The code is in `ios/Packages/TROMECore/Sources/TROMECore/AutoLiveActivity/`, and its adapters to iOS are in `ios/App/AutoLiveActivity/`.

| You want to change | Look in | Its tests |
|---|---|---|
| Arrival, switch, stop, the 45 minutes | `AutoLiveActivityRules.decide`; `AutoLiveActivityModel` applies the answer | `AutoLiveActivityRulesTests*`, `AutoLiveActivityModelTests` |
| A wake by iOS for the area of a station | `ReportedArrivalRules`, `AutoLiveActivityModel+ReportedArrival` | `ReportedArrivalRulesTests`, `AutoLiveActivityRestartTests` |
| Its second chance, after a refusal for lack of a trusted position | `ArrivalSecondChance`, `AutoLiveActivityModel+SecondChance` | `ArrivalSecondChanceTests`, `AutoLiveActivitySecondChanceTests` |
| Snooze, the switch, the buttons | `AutomaticMode`, `AutomaticModeModel`, `SnoozeLiveActivityIntent` | `AutomaticMode*Tests`, `AutoLiveActivitySnoozeTests` |
| The pause after a swipe | `AutoLiveActivityRules.outcome(of:shown:now:)`, `StationPause`, `AutoLiveActivityModel+Pause`; `ActivityKitStationLiveActivityClient` (`ios/App/LiveActivity/`) reports each end, and whether the app ended it | `AutoLiveActivityRemovalRulesTests`, `AutoLiveActivityPauseTests` |
| The position of a resume | `ResumePositionRules`, `AutoLiveActivityModel+Resume` | `ResumePositionRulesTests`, `AutoLiveActivityRiderResumeTests` |
| The permission questions | `LocationQuestionsRules` (`Location/`), `CoreLocationPermission` (`ios/App/Location/`) | `LocationQuestionsRulesTests` |
| The regions that wake the app | `StationRegionPlan`, `CoreLocationStationRegionWatcher` | `StationRegionPlanTests` |
| The notification | `StationArrivalNotifications` | `AutoLiveActivityNotificationTests` |
| The silent start: the start token, the ask to the server, the fallback | `SilentStart`, `ServerLiveActivityStarter`, `LiveActivityStartAnswer`, `AutoLiveActivityModel+SilentStart`; `ActivityKitPushToStartTokenSource` (`ios/App/AutoLiveActivity/`) | `AutoLiveActivitySilentStartTests`, `LiveActivityStartContractTests` |
| The Live Activity that the server started: the app follows it, ends it, and waits for it | `PushedStart`, `AutoLiveActivityModel+SilentStart`; `ActivityKitStationLiveActivityClient` reports each Live Activity that the app did not start | `AutoLiveActivityPushedStartTests` |

The values that a change often needs are constants:

| Value | Constant |
|---|---|
| 150 meters to start or switch | `AutoLiveActivityRules.arrivalRadiusMeters` |
| 250 meters to stop, also the radius of the region of the stop area | `AutoLiveActivityRules.stopRadiusMeters` |
| 45 minutes, and the 8 hours after which a removal is not a swipe | `AutoLiveActivityRules.defaultMaximumDuration`, `systemMaximumDuration` |
| 100 meters of accuracy, and 15 seconds or 2 minutes of age, for a position that the app trusts | `maximumAccuracyMeters`, `maximumPositionAge`, `maximumMonitoredPositionAge` |
| 1 hour of pause | `StationPause.duration` |
| 30 minutes, 1 hour and the rest of the day of a snooze | `SnoozeDuration` |
| 5 seconds of wait for a position when the rider resumes | `ResumePositionRules.maximumWait` |
| 10 seconds of wait for a position when iOS says that the phone entered the area of a station | `ReportedArrivalRules.maximumWait` |
| 10 seconds of wait for the start token and the answer of the server, in the silent start | `SilentStart.answerLimit` |
| 30 seconds of wait for the Live Activity that the server started, with the app open at the station | `PushedStart.landingWait` |
| 2 minutes of second chance, one ask every 5 seconds | `ArrivalSecondChance.limit`, `interval` |
| 20 seconds of wait for the second location question | `LocationQuestionsRules.alwaysQuestionTimeout` |
| 20 regions, 100 meters before the app chooses them again | `StationRegionPlan.maximumRegions`, `replanDistanceMeters` |

The buttons of the Live Activity run `SnoozeLiveActivityIntent`, which is in `TROMECore` because the app and the widget share it.
It gets `AutoLiveActivityModel` from `AppDependencyManager`, which `TROMEApp` fills at launch.

The end-to-end classes that cover this page are `AutoLiveActivityTests`, `ArrivalNotificationTests`, `SwipeAwayTests` and `SnoozeTests` ([what each checks](tests.md#end-to-end-tests)).

## Start, switch and stop

Each rule needs a position that the app trusts: with the real GPS, an accuracy of 100 meters or better and an age of 15 seconds or less (2 minutes when iOS woke the app for a region).
A fake position is always trusted.

| What happens | What the app does |
|---|---|
| The rider comes within 150 meters of a station, and the app is open | The Live Activity of this station starts at once |
| The same, but a system popup covers the app (a permission question) | It waits, and starts when the app is active again; if the app goes to the background first, the notification comes instead |
| The same, with the app in the background or closed | The server starts the Live Activity, with no notification and no tap ([the silent start](#the-silent-start)). When it cannot, one notification, with the station name alone as its title ("Abbesses") and no body, also when Live Activities are off. A tap opens the app and starts the Live Activity |
| The rider opens the app at that station without tapping the notification | The Live Activity starts, and the notification goes away, also when notifications are off |
| A Live Activity that the app started shows, and the rider comes within 150 meters of another station | It switches to the new station, with the app open, in the background or closed: no second Live Activity, no notification. One that the server started ends, and the new station starts its own ([the silent start](#the-silent-start)) |
| The rider moves more than 250 meters from the station of the Live Activity | It ends, once the rider has been within 250 meters of it. So a rider reaches a next station more than 400 meters away with no Live Activity: with the app in the background or closed, that station notifies |
| 45 minutes after the Live Activity started | It ends. A switch does not start the count again |
| The same station again | Nothing, until the rider leaves the station and comes back |

Each arrival gives at most one notification and one automatic start.
The rider sees one arrival notification at a time: the notification of a new station replaces the one that the rider did not open, and it goes away when the rider leaves its station.
When iOS wakes the app because the phone entered the area of a station, the app does not take that as an arrival: iOS also says so when it is wrong, for example for many stations at once after the phone restarts.
It decides on its last position, or asks iOS for a new one and waits up to 10 seconds for it; with no trusted position within 150 meters (250 meters for the station of that area), nothing comes at once, and the [wake log](testing-tools.md#on-your-iphone-see-why-no-notification-came) says why.
When a trusted position of the last 15 seconds puts the phone farther than that, nothing comes for this visit.
When it has no such position (a rough first position, an older one, or none), it asks iOS again every 5 seconds, for up to 2 minutes after the report, with the background location on, and notifies once if a trusted position puts the phone within 150 meters of the station.
It stops sooner when a trusted position puts the phone more than 250 meters away, when iOS says that the phone left the area, or when the rider snoozes or turns off the automatic mode.
Why 2 minutes: a rider crosses the 150-meter area in about that time, and is then often underground, with no GPS.
For its next arrival, a station counts as left when a trusted position is more than 250 meters from it, or when iOS says that the phone left its stop area, even with no position.
An arrival that waits behind a system popup is not done until the app acts on it: if iOS closes the app first, the notification or the start comes once, when the app runs again at that station.
A Live Activity that you start by hand ([Testing tools](testing-tools.md#show-or-stop-the-live-activity-by-hand)) follows the same stop rules, and the 45 minutes apply to every Live Activity.
A debug build can [shorten the 45 minutes](testing-tools.md#make-the-45-minute-limit-shorter).

The notification has two actions, "Not for 1 h" ("Pas pendant 1 h") and "Not today" ("Pas aujourd’hui").
Each one snoozes the automatic mode with no app opened, also when the phone is locked.

### The silent start

At a background arrival, the app asks the server to start the Live Activity, and notifies only as the fallback.
Every Release build does it, the store build too.
A Debug build does it only with `TROME_SILENT_START = YES` in `ios/Config/Local.xcconfig` (then run `make generate`) and a server in `ios/Config/Server.xcconfig`.
Both need a paid Apple Developer Program team, because a free Apple ID cannot sign the push capability; a Debug build with no such setting keeps the notification.
The app sends the start token that iOS gives it to the server (`POST /v1/stations/<id>/live-activity`, [the server side](../../server/guide/how-it-works.md#the-start-of-a-live-activity)).
The Live Activity then comes on the lock screen with no notification and no tap only when the push topic of the server is the bundle ID of this build.
A real server pushes to the bundle ID of the Release build only ([`APNS_BUNDLE_ID`](../../server/guide/deploy.md#the-secrets)), so Apple refuses the start of a Debug build, the server answers refused, and the app sends the notification: a Debug build checks the ask and the fallback, and only a Release build shows the start.
It asks once per arrival, and never while a Live Activity that the app follows shows.
The app follows the Live Activity that the server started as soon as it runs with it on screen: at once when it lands during the ask, otherwise when iOS next wakes the app, at the latest when the phone leaves the 250-meter area of the station.
It then ends it as one that it started: at 250 meters, or 45 minutes after the answer of the server; a swipe pauses the station.
It cannot switch it to the next station, as its updates come on the channel of its station: at the next station, it ends it, and that station starts its own, with the server or by the app when the app is open.
With the app open at the station when the server answers, the app waits 30 seconds for that Live Activity, and only then starts its own.
The notification comes instead, once, when Live Activities are off, when iOS gave no start token, or when the server cannot be reached, refuses, is not set up, or gives no answer within 10 seconds: iOS gives a woken app only seconds to run.
In a Debug build, the [wake log](testing-tools.md#on-your-iphone-see-why-no-notification-came) writes each step.

## Snooze, turn off, and the pause after a swipe

| | Snooze | Turn off | Swipe away |
|---|---|---|---|
| How | **30 min**, **1 h** or **Today** on the Live Activity; **Not for 1 h** or **Not today** on the notification; **Snooze** on the main screen | The switch **Automatic mode** on the main screen | The rider swipes the Live Activity away, on the lock screen or in the Notification Center |
| What stops | Every station: the Live Activity ends at once, and no notification or automatic start comes | Every station: the Live Activity ends at once, with no pause, and no new notification or automatic start comes | The station of the Live Activity only, for 1 hour, with the app open, in the background or closed |
| It ends | After 30 minutes, 1 hour, or at midnight for **Today**; the main screen shows **Snoozed**, the time of return and the time left | When the rider turns the switch on; the app keeps the choice | After the hour, or when the rider cancels it |
| Cancel it | **Cancel the snooze** on the main screen | | **Cancel the pause at <station>** ("Réactiver <station>"); the screen says "Paused at <station> until <time>" ("<station> : en sourdine jusqu’à <time>") |

- **After a snooze**, the app still follows the stations that the rider passes.
  A snooze that ends at a station reached during the snooze does not start the Live Activity: it starts at the next station.
- **Turning the switch off** ends the Live Activity that shows at once, with no pause.
- **One pause at a time.**
  A swipe at another station replaces the pause.
  A tap on the arrival notification of the station, or **Show the Live Activity now** in the Testing tools, ends it.
  A snooze does not change it.
- **What is not a swipe**, so sets no pause: the app ends the Live Activity itself (the snooze buttons, the switch **Automatic mode** turned off, the stop of the Testing tools, the 250 meters, the 45 minutes), the rider turns Live Activities off for the app (in **Settings**, or "Don't Allow" when iOS asks), and iOS ends a Live Activity after 8 hours.
- **The limit of the pause.**
  The app sets the pause only when it runs at the swipe, which is normal while a Live Activity shows, because the app keeps getting the position in the background.
  When the app was not running, iOS starts it in the background right after the swipe, but does not say why, and the app cannot tell this start from a later region wake.
  So it sets no pause, and the Live Activity does not come back until the rider leaves the station and comes back.

### Back on at a station

**Cancel the snooze**, **Cancel the pause**, and turning the switch on are a resume.
So is coming back to the app at a station after turning Live Activities on again in **Settings**: the arrival at this station stayed open while they were off.
When the app is open within 150 meters of a station, the Live Activity of this station starts at once, with no notification.
A station that is still paused stays paused, and away from every station nothing starts.
While a snooze is on, **Cancel the pause** only ends the pause.
The resume needs a position, in this order:

1. The last position of the app, when it is precise and at most 15 seconds old.
   iOS sends no new position while the phone stands still.
2. Otherwise a fresh position that the app asks iOS for, with a wait of at most 5 seconds.
   A small spinner takes the place of the icon of the button meanwhile.
3. With no answer, the last position when it is precise and at most 2 minutes old.
4. With none, the screen says "Can’t find your position for now" ("Position introuvable pour l’instant") until a position comes or the rider leaves the app.

## When iOS refuses to start it

If Live Activities are off for the app (in **Settings**, or "Don't Allow" when iOS asks), the Live Activity does not start.
While they are off and the switch **Automatic mode** is on, the main screen says, as soon as the rider opens the app, at a station or not, "Live Activities are off" ("Activités en direct désactivées"), with an **Open Settings** button.
The message goes when they are on again and the rider comes back to the app; at a station, the Live Activity then starts at once (see [Back on at a station](#back-on-at-a-station)).
Any other failure of ActivityKit says "The lock screen display could not start."

## The questions iOS asks, in order

The app needs the location "Always" to start the Live Activity while it is closed, and notifications for the fallback of the [silent start](#the-silent-start).
`LocationQuestionsRules` asks them in this order:

1. The location, **While Using the App**, at the first launch.
2. The location, **Always**, right after the answer.
   iOS does not say when the rider taps **Keep Only While Using**, so the app waits until it is active again.
   When iOS shows no second question (after **Allow Once**, it ignores it), the app waits at most 20 seconds, from the moment it is active again.
   So the notifications question shows about 21 to 23 seconds after **Allow Once**, or at once when iOS takes the app out of the active state and back for the ignored question.
3. The notifications, only after the second answer.

With **While Using the App** only, the Live Activity starts by itself only while the app is open.
The **Location** row of the main screen is then orange, with the line "Choose Always" ("Choisissez Toujours") and a button to open **Settings**.

## What the main screen shows

The app is the Live Activity, so the main screen shows its state and its controls, and no button to start or stop it.

| The screen shows | When |
|---|---|
| "On the lock screen: <station>" ("Sur l’écran verrouillé : <station>") | A Live Activity shows; otherwise "Nothing on the lock screen" ("Rien sur l’écran verrouillé") |
| "On the lock screen: Châtelet (example)" ("Sur l’écran verrouillé : Châtelet (exemple)") | The example of **See an example** shows |
| **See an example**: a tap puts Châtelet on the lock screen, with sample times, for 10 minutes ([See an example](example.md)) | Always; while the real trains of a station show, it is grey, starts nothing, and its line says "Real trains already showing" ("Vrais passages déjà affichés") |
| The switch **Automatic mode** | Always |
| **Snooze**, with 30 minutes, 1 hour and the rest of today | The automatic mode is on |
| **Snoozed**, the time of return, and **Cancel the snooze** | A snooze is on |
| "Paused at <station> until <time>" and **Cancel the pause at <station>** | After a swipe, also while a snooze is on, but not while the switch is off |
| "No live times until around 9:00" ("Pas d’horaires en direct avant 09:00 environ"), under the name of the app | A Live Activity shows, and the server of the app has no PRIM calls left for its station. The time is when the app asks the server again, in the time format and time zone of the phone. When it is on another day, the line says "No live times until tomorrow" ("Pas d’horaires en direct avant demain"). |
| The **Location** and **Notifications** rows, each with its state as a pill | Always; a refused permission, or a location that is not **Always**, turns the card orange, with a button to fix it, and the line "Choose Always" under a location that is **While Using the App** or **Off**. Notifications not asked yet show a grey pill, since the app asks for them by itself ([the questions, in order](#the-questions-ios-asks-in-order)). |
| **Privacy policy** and **Help and feedback**, which open their web pages in Safari | Always |
| The source of the train data and of the station list, with their links, at the foot | Always |

Each row opens the page of the language of the app, French or English, on the docs site: `DocsSitePage` in `TROMECore` holds the addresses, the same as on the store page.

The screen has one look, a night page, in the light and the dark mode of the phone, as the Live Activity is dark on the lock screen.
Each state is a filled pill: green when it is fine, orange with an "Open Settings" button when you must act.
The colours, the type and the shapes of this look are in `ios/App/NightLook/NightLook.swift`, so that a change of colour is a change in one place.

The server line states a fact and never a fault of the rider, and it never says "soon": the next hour can be out too.

## What keeps the app running in the background

While a Live Activity shows, the app must go on getting the position, to switch or stop it, and the trains, to refresh it.

- **The position.**
  `CoreLocationBackgroundLocationKeeper` runs standard location updates that never pause.
  Without it, iOS pauses the new positions when the phone stands still, and suspends the app about 15 seconds after it leaves the screen.
  With the location "Always", the app hides the blue location indicator; with **While Using the App**, it needs a `CLBackgroundActivitySession`, and iOS then always shows the indicator while the Live Activity shows.
  This costs battery for at most 45 minutes.
  The same runs for at most 2 minutes after iOS reports a station area that no trusted position confirms yet (see [Start, switch and stop](#start-switch-and-stop)).
- **The trains.** [When the app asks again](trains.md#when-the-app-asks-again) says when it asks PRIM in the background.
- **A closed app.**
  iOS wakes it with region monitoring (`CLMonitor`), at most 20 regions for each app.
  The app watches the 18 nearest stations (150 meters), the stop area of the shown or last station (250 meters), and one larger area around the rider.
  When the rider leaves that area, or the app moves 100 meters from where it last chose, it picks the nearest stations again.
  With a fake position, the app watches no region.
  The Simulator cannot watch regions, so check this wake on an iPhone.

**The limit.**
The app gets new times in the background only while it runs.
It stops running when the rider closes it from the app switcher, when the location is not allowed, or when iOS ends it to free memory.
Then the 45 minutes apply only when iOS wakes the app again or the rider opens it, and the Live Activity gets no new times until then.
A Live Activity that the server started is the exception: its times come from the server, on the channel of its station ([the server side](../../server/guide/how-it-works.md#the-start-of-a-live-activity)).
To see what the app does, [read the logs](../README.md#read-the-logs): the categories `LiveActivity` and `BackgroundLocation` log each state, end, pause and background start.
On an iPhone, with no cable, the [wake log](testing-tools.md#on-your-iphone-see-why-no-notification-came) shows each wake by iOS and each arrival decision.
