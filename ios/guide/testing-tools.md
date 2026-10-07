# Try the app at any station, without going there

Debug builds have a **Testing tools** screen: run `make run`, or click **Run** in Xcode, then tap **Testing tools** at the top right of the app.
With it, you put the phone at any station, see the next trains of any station, and start or stop the Live Activity by hand.
Launch arguments add fake trains, for when you have no [train data key](../README.md#the-train-data-key-prim).
Release builds, the ones for the App Store, have none of these tools; their code is in `ios/App/TestingTools/`, inside `#if DEBUG`.
Run the commands from the root of the repo.

## Put the phone at a station

In **Testing tools**, pick a station, **Far from any station**, coordinates or an address.
The section **Position used by the app** shows the position that the app now uses, and its nearest station.
The app keeps the fake position until you tap **Use the real GPS**, also on an iPhone that is not connected to your Mac, and the main screen shows **Fake position** in orange.

**When you add a feature that needs the position, read it from `LocationService`**, never from Core Location: that is how the fake position reaches every feature.

The fake position stays inside the app, so iOS does not see it.
When iOS must see the phone move, for example for the arrival notification, tap **Use the real GPS** and move the Simulator instead:

```sh
xcrun simctl location "$(make -s simulator)" set 48.8584,2.2945
```

On your iPhone, **Debug > Simulate Location** in Xcode does the same.

## Show or stop the Live Activity by hand

At the top of **Testing tools**, **Show the Live Activity now** shows the Live Activity of the nearest station, up to 2 km away; while one shows, **Stop showing on the lock screen** ends it.
For any other station, open **Next trains of a station**, pick it, and tap **Show on the lock screen**.
A Live Activity that you start far from its station ends at 250 meters only after you came near it, or after 45 minutes like every Live Activity.

## See the next trains of any station

Tap **Next trains of a station**, then **Pick a station**: the screen shows the trains of the next 60 minutes, and asks for new times every 30 seconds.
It needs no location permission, so it is the quickest way to check the train data.
At the bottom, **Train data key: set** or **not set** tells you whether the build has a key; when the screen shows no times, its message says why.
Each visit costs calls of your key: see [one call for each stop area](trains.md#one-call-for-each-stop-area).

## Get fake trains, with no key

Launch the app with `--fake-trains` to get fake trains at every station, with no call to PRIM, also in a build with a key:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains
```

If you set your own bundle ID in `ios/Config/Local.xcconfig`, use the one that `make generate` prints.
The first train comes 3 minutes after the launch, the other direction one minute later, then one train every 4 minutes.

The app saves the choice at each launch that has arguments: on with `--fake-trains`, off without it.
A launch with no argument keeps it: a launch by iOS (a tap on the Live Activity, a region event), the **Run** button of Xcode with the default scheme, and `make switch-language`.
`make run` installs the app again, so it starts with no fake trains.
So on your iPhone, fake trains can stay in place of your live trains: to drop them, run the app once with any other argument (**Product > Scheme > Edit Scheme > Run > Arguments**), or delete the app.

### Ask for a train at the platform, or another state

A real train stays at the platform for only 20 to 30 seconds, so add the name of a state after `--fake-trains` to get one at once:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --fake-trains at-platform
```

The times start at this launch.
Start the Live Activity at once, then put the app in the background and look at the lock screen.

| State | What the Live Activity shows |
|---|---|
| `at-platform` | The first box of each strip says **À quai** for 5 minutes; then a train comes every 4 minutes and waits 30 seconds at the platform. |
| `at-platform-second` | The second box says **À quai** for about 3 minutes, next to a train that leaves first; then the first train comes and leaves, and the second one 2 minutes later. |
| `at-platform-both` | Both boxes say **À quai** for 5 minutes; then the first train leaves, and the second one 2 minutes later. |
| `ten-to-nine` | The second box shows 10 or more, and counts down to 9 by itself 3 to 4 minutes after the launch, then every 6 minutes. Look while the app is in the background. |
| `fork-end-one-train` | At a station of line 7 or 13 before the fork, such as Liège: the second end gets one train, which leaves after 8 minutes, then shows the grey dash. |
| `fork-end-no-train` | At the same stations: the second end gets no train, so its row shows the grey dash. |
| `fork-end-over-an-hour` | At the same stations: the second end gets one train after 70 minutes, so it says **> 1 h**, then counts down from 60. |
| `server-out` | As if the server of the app were out of PRIM calls. Trains every 4 minutes, the first one 3 minutes after the launch. From 1 to 8 minutes after the launch, the fake trains answer "out" with the time 8 minutes after the launch as the time to ask again. The times shown keep counting down, then the Live Activity says **Times unavailable** when the first train leaves, the main screen says when the live times come back, and the times come back 8 minutes after the launch. |
| `server-out-tomorrow` | The fake trains answer "out" from the launch until 40 seconds after midnight (the time zone of the phone): the Live Activity starts with **Times unavailable**, and the main screen says that the live times come back tomorrow. |

The states are in `FakeTrainsScenario`; a name that the app does not know gives no fake trains.
To start a state again, launch the app again with the same arguments.

While a Live Activity shows, iOS starts the app again in the background a moment after you close it, and `xcrun simctl launch` can then bring that app to the front with no arguments.
So launch the app before you start the Live Activity, and check its arguments:

```sh
ps -axww -o args | grep "TROME.app/TROME"
```

When the line ends with `TROME` alone, launch the app again; if a Live Activity shows, stop it first.

## Make the 45-minute limit shorter

To test the end of a Live Activity without waiting 45 minutes, give another limit in seconds:

```sh
xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev -liveActivityMaximumDuration 60
```

## Test the automatic start of the Live Activity

The Live Activity starts by itself within about 150 meters of a station, and ends about 250 meters away.
With the app open, pick Abbesses in **Testing tools** and go back: its Live Activity starts.
Pick Pigalle, near it: the Live Activity switches.
Tap **Far from any station**: it ends.

### With the app in the background: the arrival notification

In the background, the app shows a notification, **Next trains at** and the station, instead of the Live Activity.
In the Simulator, iOS keeps the app running for only about 10 to 25 seconds after you leave it, and nothing wakes it after that: do steps 3 and 4 within those seconds.

1. Tap **Use the real GPS**, and in the **Settings** app of the Simulator, set the location of TROME to **Always**.
2. Move the Simulator far from any station:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.42,2.63
   ```

3. Go to the home screen.
4. At once, move it to Abbesses:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838
   ```

   The notification **Next trains at Abbesses** shows within a few seconds.
   Tap it to start the Live Activity, or touch and hold it to snooze the station.

On your iPhone, iOS also wakes a suspended or closed app near a station, after a few seconds to a few minutes: test that case there, with **Debug > Simulate Location** in Xcode.
