# Try the app at any station, without going there

The debug builds of the app have a **Testing tools** screen and a few launch arguments, so that you can try a change at any station from your desk.
To open the screen, run `make run`, or click **Run** in Xcode, then tap **Testing tools** at the top right of the main screen of the app.
Release builds, the ones for the App Store, have none of these tools.

With them, you put the phone at a station, see the next trains of any station, get fake trains when you have no [train data key](../README.md#the-train-data-key-prim), and start or stop the Live Activity by hand.
This page shows each tool, then how to test the automatic start of the Live Activity with them.
Run the commands from the root of the repo; the paths on this page start there too.

## Put the phone at a station

1. In **Testing tools**, choose a fake position:
   - **Pick a station**: a metro or RER station from a list.
   - **Far from any station**: a point in the Fontainebleau forest, far from every metro and RER station, to see what happens when you leave a station.
   - **Coordinates**: type the latitude, then the longitude, for example `48.8584, 2.2945`, and tap **Use these coordinates**.
   - **Address**: type an address, for example `10 rue de Rivoli, Paris`, and tap **Find this address**. This one needs the network.
2. Check the section **Position used by the app**: it shows the position that every feature of the app now uses, and the nearest station.
3. When you are done, tap **Use the real GPS**.

The app keeps the fake position when you close it, and the main screen shows **Fake position** in orange while it is on.
It works in the Simulator and on your iPhone, also when the iPhone is not connected to your Mac.

**When you add a feature that needs the position, read it from `LocationService`**, never from Core Location: every feature does, and that is why the fake position reaches them all.

The fake position stays inside the app, so it cannot change while the app is in the background.
When iOS itself must see the phone move, for example to test the arrival notification, move the Simulator instead (`make -s simulator` prints the ID of the shared Simulator):

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

Tap **Use the real GPS** first, so that the app reads the position of the Simulator.
On your iPhone connected to the Mac, **Debug > Simulate Location** in Xcode does the same.

## Show or stop the Live Activity by hand

The section **Live Activity**, at the top of **Testing tools**, has **Show the Live Activity now**: it shows the Live Activity of the station nearest to you, up to 2 km away, whatever the automatic mode does.
While a Live Activity shows, the section names its station and has **Stop showing on the lock screen** instead.
To show the Live Activity of any station, open **Next trains of a station**, pick the station, and tap **Show on the lock screen**.

A Live Activity that you start by hand far from its station does not end because of the distance; it ends at 250 meters only after you came near its station, and after 45 minutes like every Live Activity.
[The Live Activity starts and stops by itself near a station](../README.md#the-live-activity-starts-and-stops-by-itself-near-a-station) gives the other rules.

## See the next trains of any station

This screen needs no location permission, so it is the quickest way to check the train data.

1. In **Testing tools**, tap **Next trains of a station**, then **Pick a station**.
2. Type part of a name, then tap the station.
   The search ignores capitals, accents and hyphens: `chatelet` finds Châtelet.
3. The screen shows the next trains of each line and destination, in minutes, and asks for new times every 30 seconds while it is open.
4. To see another station, tap **Change station**.

The app remembers the station when you close it.
The screen shows only the trains of the next 60 minutes, because PRIM sometimes announces a train much later, such as in 154 minutes, which is not a real prediction.
A destination with only later trains keeps its row, with **Next train in over 1 hour**.
At the bottom, **Train data key: set** or **not set** tells you whether this build has a key.

When the screen shows no times, its message tells you why:

| The screen says | What happened |
|---|---|
| Live train times are not available: the train data key is not set. | The build has no key: see [live trains in a debug build](../README.md#the-train-data-key-prim), or use fake trains. |
| No live data for this station right now. | PRIM answered, with no train for this station, for example at night. |
| The app cannot reach the train data service. Check your internet connection. | No network, or no answer within 15 seconds. |
| The train data service refused the key. Check the train data key. | PRIM refused the key. |
| The train data service received too many requests today. Try again later. | The key has used up its calls for the day. |
| The train data service does not work right now. The app will try again. | Any other error of the service. |

Each visit costs calls of your key: [one call for each stop area](trains.md#one-call-for-each-stop-area) says how many.

## Get fake trains, with no key

Launch the app with `--fake-trains` to get fake next trains at every station, with no call to PRIM:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains
```

`com.example.trome.dev` is the Debug bundle ID of the app; if you set your own in `ios/Config/Local.xcconfig`, use the one that `make generate` prints.
The first train of each direction comes 3 minutes after the launch, the other direction one minute later, then one train every 4 minutes.
The fake trains go through the real rules of the app, and they replace the live trains, also in a build with a key.

### When the app keeps the fake trains

The app saves the choice, so that a launch by iOS keeps it.
What decides is whether the launch has arguments:

| The launch | The fake trains |
|---|---|
| With `--fake-trains`, from `xcrun simctl launch`, a test, or the **Run** button of Xcode when its scheme has arguments | On |
| With other arguments, but no `--fake-trains`, for example only `-liveActivityMaximumDuration 60` | Off |
| With no argument: iOS starts the app for a button of the Live Activity, a region event or a relaunch in the background | As before the launch |
| The **Run** button of Xcode with the default scheme, which passes no argument | As before the launch |
| `make run`, which installs the app again with no data | Off |
| `make switch-language`, which keeps the data of the app | As before the switch |

So you can close the app, tap the Live Activity, and still see the fake trains.
On your iPhone, this means that fake trains can stay in place of the live trains of your key: to drop them, run the app once with any other argument in the scheme (**Product > Scheme > Edit Scheme > Run > Arguments**), or delete the app.

### Ask for a train at the platform, or another state

Live trains show some states only by luck: a train stays at the platform for 20 to 30 seconds, and in the background the Live Activity gets new times only every 2 minutes or so.
So add the name of a state after `--fake-trains`:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains at-platform
```

The times start at this launch, the same for each line of the station, with the second direction one minute later.
Start the Live Activity at once, with a fake position or **Show the Live Activity now**, then put the app in the background and look at the lock screen or the Notification Center.

| State | What the Live Activity shows |
|---|---|
| `at-platform` | The first box of each strip says **À quai** for 5 minutes; then the train leaves, and a train comes every 4 minutes and waits 30 seconds at the platform, like a real one. |
| `at-platform-second` | The second box says **À quai** for about 3 minutes, next to a train that leaves first; then the first train comes (**0**, then **À quai**, in both boxes) and leaves, and the second one leaves 2 minutes later. |
| `at-platform-both` | Both boxes say **À quai** for 5 minutes; then the first train leaves, and the second one 2 minutes later. |
| `ten-to-nine` | A train every 6 minutes; the second box shows 10 or more, and counts down to 9 by itself 3 to 4 minutes after the launch, then every 6 minutes. Look while the app is in the background, before the next update. |
| `fork-end-one-train` | At a station of line 7 or 13 before the fork, such as Liège or Poissonnière: the second end gets one train only, which leaves 8 minutes after the launch, so that end then shows the grey dash. |
| `fork-end-no-train` | At the same stations: the second end gets no train, so its row shows the grey dash. |
| `fork-end-over-an-hour` | At the same stations: the second end gets one train, 70 minutes after the launch, so it says **> 1 h** for about 10 minutes, then counts down from 60. |

Before a fork, the plain `--fake-trains` and the first four states send the trains to each end in turn, so each row of the fork shows two trains of its end.
On a line with no fork, the three `fork-end-` states give a train every 4 minutes in each direction.
The RER lines get the same times; their rows show **À quai** only when the RER look draws it.
A name that the app does not know gives no fake trains, so the Live Activity says **No data available**.

To start a state again from its beginning, launch the app again with the same arguments; a launch by iOS keeps the state and its start time.

### Check that the app got the arguments

While a Live Activity shows, iOS starts the app again in the background a moment after you close it.
Then `xcrun simctl launch` only brings that app to the front, and your arguments are lost, however often you launch it.
So launch the app with its arguments before you start the Live Activity, and when one already shows, stop it first with **Stop showing on the lock screen**.
To check, run:

```sh
ps -axww -o args | grep "TROME.app/TROME"
```

The line of the app must end with `--fake-trains` and the name of the state.
When it ends with `TROME` alone, stop the Live Activity if one shows, and launch the app again.

## Make the 45-minute limit shorter

A Live Activity ends by itself 45 minutes after it started.
To test that end without waiting, give another limit in seconds:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev -liveActivityMaximumDuration 60
```

## Test the automatic start of the Live Activity

The Live Activity starts by itself when the phone comes within about 150 meters of a station, and ends when it moves about 250 meters away.
When the app is in the background, it shows a notification instead, **Next trains at** and the station: a tap on it starts the Live Activity.

### With the app open

1. In **Testing tools**, pick a station, for example Abbesses, and go back: the Live Activity of Abbesses starts.
2. Pick a station near it, for example Pigalle: the Live Activity switches to Pigalle.
3. Tap **Far from any station**: the Live Activity ends.

### With the app in the background: the arrival notification

In the Simulator, iOS keeps the app running for only about 10 to 25 seconds after you leave it, unless a Live Activity shows.
The Simulator cannot watch regions either, so once iOS suspends the app, nothing wakes it, and no notification comes.
So do steps 3 and 4 one right after the other, within those seconds.

1. In **Testing tools**, tap **Use the real GPS**.
   In the **Settings** app of the Simulator, set the location of TROME to **Always**.
2. Move the Simulator far from any station:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.42,2.63
   ```

3. Go to the home screen, or lock the Simulator.
4. At once, move it to a station, for example Abbesses:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838
   ```

   The notification **Next trains at Abbesses** shows within a few seconds.
5. Tap it, or touch and hold it and tap **Not for 1 h** or **Not today**: then the app does not open, and its main screen shows the snooze.

On your iPhone, iOS watches the regions of the stations, so it also wakes a suspended or closed app: there, iOS can take from a few seconds to a few minutes to notice the move.
Check the arrival of a closed app on your iPhone, with **Debug > Simulate Location** in Xcode.
