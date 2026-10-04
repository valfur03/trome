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
| Snooze, the switch, the buttons | `AutomaticMode`, `AutomaticModeModel`, `SnoozeLiveActivityIntent` | `AutomaticMode*Tests`, `AutoLiveActivitySnoozeTests` |
| The pause after a swipe | `AutoLiveActivityRules.outcome(of:shown:now:)`, `StationPause`, `AutoLiveActivityModel+Pause` | `AutoLiveActivityRemovalRulesTests`, `AutoLiveActivityPauseTests` |
| The position of a resume | `ResumePositionRules`, `AutoLiveActivityModel+Resume` | `ResumePositionRulesTests`, `AutoLiveActivityRiderResumeTests` |
| The permission questions | `LocationQuestionsRules` (`Location/`), `CoreLocationPermission` (`ios/App/Location/`) | `LocationQuestionsRulesTests` |
| The regions that wake the app | `StationRegionPlan`, `CoreLocationStationRegionWatcher` | `StationRegionPlanTests` |
| The notification | `StationArrivalNotifications` | `AutoLiveActivityNotificationTests` |

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
| The same, with the app in the background or closed | One notification, "Next trains at <station>" ("<station> : prochains passages"). A tap opens the app and starts the Live Activity |
| The rider opens the app at that station without tapping the notification | The Live Activity starts, and the notification goes away, also when notifications are off |
| A Live Activity shows, and the rider comes within 150 meters of another station | It switches to the new station: no second Live Activity, no second notification |
| The rider moves more than 250 meters from the station of the Live Activity | It ends, once the rider has been within 250 meters of it |
| 45 minutes after the Live Activity started | It ends. A switch does not start the count again |
| The same station again | Nothing, until the rider leaves (more than 250 meters, with no station within 150 meters) and comes back |

Each arrival gives at most one notification and one automatic start.
A Live Activity that you start by hand ([Testing tools](testing-tools.md#show-or-stop-the-live-activity-by-hand)) follows the same stop rules, and the 45 minutes apply to every Live Activity.
A debug build can [shorten the 45 minutes](testing-tools.md#make-the-45-minute-limit-shorter).

The notification has two actions, "Not for 1 h" ("Pas pendant 1 h") and "Not today" ("Pas aujourd’hui").
Each one snoozes the automatic mode with no app opened, also when the phone is locked.

## Snooze, turn off, and the pause after a swipe

| | Snooze | Turn off | Swipe away |
|---|---|---|---|
| How | **30 min**, **1 h** or **Today** on the Live Activity; **Not for 1 h** or **Not today** on the notification; **Snooze** on the main screen | The switch **Automatic mode** on the main screen | The rider swipes the Live Activity away, on the lock screen or in the Notification Center |
| What stops | Every station: the Live Activity ends at once, and no notification or automatic start comes | Every station: no new notification or automatic start | The station of the Live Activity only, for 1 hour, with the app open, in the background or closed |
| It ends | After 30 minutes, 1 hour, or at midnight for **Today**; the main screen shows **Snoozed**, the time of return and the time left | When the rider turns the switch on; the app keeps the choice | After the hour, or when the rider cancels it |
| Cancel it | **Cancel the snooze** on the main screen | | **Cancel the pause at <station>** ("Réactiver <station>"); the screen says "Paused at <station> until <time>" ("<station> : en sourdine jusqu’à <time>") |

- **After a snooze**, the app still follows the stations that the rider passes.
  A snooze that ends at a station reached during the snooze does not start the Live Activity: it starts at the next station.
- **Turning the switch off** does not end a Live Activity that already shows.
- **One pause at a time.**
  A swipe at another station replaces the pause.
  A tap on the arrival notification of the station, or **Show the Live Activity now** in the Testing tools, ends it.
  A snooze does not change it.
- **What is not a swipe**, so sets no pause: the app ends the Live Activity itself (the snooze buttons, the stop of the Testing tools, the 250 meters, the 45 minutes), the rider turns Live Activities off for the app, and iOS ends a Live Activity after 8 hours.
- **The limit of the pause.**
  The app sets the pause only when it runs at the swipe, which is normal while a Live Activity shows, because the app keeps getting the position in the background.
  When the app was not running, iOS starts it in the background right after the swipe, but does not say why, and the app cannot tell this start from a later region wake.
  So it sets no pause, and the Live Activity does not come back until the rider leaves the station and comes back.

### Back on at a station

**Cancel the snooze**, **Cancel the pause**, and turning the switch on are a resume.
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

If Live Activities are off for the app, in **Settings**, the Live Activity does not start.
The main screen says "Live Activities are turned off for this app. Turn them on in Settings > TROME.", with an **Open Settings** button.
The message goes when they are on again and the rider comes back to the app.
Any other failure of ActivityKit says "The lock screen display could not start."

## The questions iOS asks, in order

The app needs the location "Always" to start the Live Activity while it is closed, and notifications to tell the rider that it can.
`LocationQuestionsRules` asks them in this order:

1. The location, **While Using the App**, at the first launch.
2. The location, **Always**, right after the answer.
   iOS does not say when the rider taps **Keep Only While Using**, so the app waits until it is active again.
   When iOS shows no second question (after **Allow Once**, it ignores it), the app waits at most 20 seconds.
3. The notifications, only after the second answer.

With **While Using the App** only, the Live Activity starts by itself only while the app is open.
The **Permissions** part of the main screen says so, with a button to open **Settings**.

## What the main screen shows

The app is the Live Activity, so the main screen shows its state and its controls, and no button to start or stop it.

| The screen shows | When |
|---|---|
| "On the lock screen: <station>" ("Sur l’écran verrouillé : <station>") | A Live Activity shows; otherwise a line that says what the Live Activity does |
| The switch **Automatic mode** | Always |
| **Snooze**, with 30 minutes, 1 hour and the rest of today | The automatic mode is on |
| **Snoozed**, the time of return, and **Cancel the snooze** | A snooze is on |
| "Paused at <station> until <time>" and **Cancel the pause at <station>** | After a swipe, also while a snooze is on, but not while the switch is off |
| **Permissions** | Always; it says what a missing or refused permission breaks |

## What keeps the app running in the background

While a Live Activity shows, the app must go on getting the position, to switch or stop it, and the trains, to refresh it.

- **The position.**
  `CoreLocationBackgroundLocationKeeper` runs standard location updates that never pause.
  Without it, iOS pauses the new positions when the phone stands still, and suspends the app about 15 seconds after it leaves the screen.
  With the location "Always", the app hides the blue location indicator; with **While Using the App**, it needs a `CLBackgroundActivitySession`, and iOS then always shows the indicator while the Live Activity shows.
  This costs battery for at most 45 minutes.
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
The app sends no push update, so no server can refresh a Live Activity of an app that does not run.
To see what the app does, [read the logs](../README.md#read-the-logs): the categories `LiveActivity` and `BackgroundLocation` log each state, end, pause and background start.
