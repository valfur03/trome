# See an example

The main screen has the row "See an example", so that anyone, far from Paris or with no permission, can see what the app does.
This page says what the example shows, when it ends, and how to try it quickly.

## What it shows

A tap shows the Live Activity of Châtelet, with sample times, for 10 minutes.
The main screen then says "On the lock screen: Châtelet (example)".

- It shows all the metro and RER lines of the Châtelet hub, in both directions, on the pages of the Live Activity.
- No train leaves in the first 5 minutes, and a train of the first page is in its last minute after about 4 minutes (see below).
- The sample times are made in the app (`ExampleTimetable` in `TROMECore`): no position, no permission, no network and no train data are needed, so the example makes no call to the train data service or to the server.
- The Live Activity has no mark of its own: it looks like a real one.

## While the app is suspended

The sample times count down and renew while the app runs.
When iOS suspends the app (the phone locked, the app in the background), the app cannot update the Live Activity any more.
So no train of the example leaves in the first 5 minutes 20 seconds after the tap: until then, the lock screen counts down with no update.
After that, the Live Activity shows "Open the app", as a real one does.
When the app comes back to the front while the example shows, stale or not, the sample starts again, as with a second tap: once the phone locks, the lock screen counts down for 5 more minutes.
So "Open the app" keeps its promise, also when the rider locks the phone at once.
A tap on the arrow of the Live Activity runs the app for a moment, so its next page shows renewed times.
Why: the example has no server to push new times, and it must not use the position to keep the app running.

## When it ends

- It ends 10 minutes after its last start: the tap, or the last return of the app to the front.
  When iOS suspended the app until then, it ends at the next launch of the app, and starts nothing.
- A second tap starts it again, with fresh times.
- A swipe ends it, with no pause.
- A snooze button of the Live Activity ends it, with no snooze.
- An arrival at a station replaces it with the real trains of that station.
- Once it has ended, for any of these reasons, the app at the front does not start it again: only a tap does.
- It never changes the automatic mode, a snooze or a pause, and the app keeps nothing of it once it ends.

While the real trains of a station show, the row starts nothing and says which station shows.
When Live Activities are off for the app, a tap shows the line that says so, with "Open Settings".

## Try it quickly

In a debug build, the launch argument `-exampleDuration <seconds>` makes the example shorter, for example:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev -exampleDuration 60
```

Replace `com.example` with your bundle ID prefix if you changed it.
