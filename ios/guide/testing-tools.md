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

After `make run`, open the app again with fake trains at every station, with no call to PRIM, also in a build with a key:

```sh
make fake-trains
```

It prints `fake trains: default applied` once the app uses them, or `not applied, launch again`: then run it again.
The first train comes 3 minutes after the launch, the other direction one minute later, then one train every 4 minutes.

The app saves the choice at each launch that has arguments: on with `--fake-trains`, off without it.
A launch with no argument keeps it: a launch by iOS (a tap on the Live Activity, a region event, a start again in the background), the **Run** button of Xcode with the default scheme, and `make switch-language`.
`make fake-trains` also saves the choice before it opens the app, because iOS can start the app again in the background a moment after it is closed, and that launch has no argument.
`make run` installs the app again, so it starts with no fake trains.
So on your iPhone, fake trains can stay in place of your live trains: to drop them, run the app once with any other argument (**Product > Scheme > Edit Scheme > Run > Arguments**), or delete the app.

### Ask for a train at the platform, or another state

A real train stays at the platform for only 20 to 30 seconds, so add the name of a state to get one at once:

```sh
make fake-trains STATE=at-platform
```

The times start at this launch.
Start the Live Activity at once, then put the app in the background and look at the lock screen.

| State | What the Live Activity shows |
|---|---|
| `at-platform` | The first box of each strip says **À quai** for 5 minutes; then a train comes every 4 minutes and waits 30 seconds at the platform. |
| `at-platform-second` | The data puts the second train at the platform before the first train comes: for about 4 minutes, both boxes count their minutes. Then both say **À quai** once the first train is there; the first train leaves, and the second one 2 minutes later. |
| `at-platform-both` | Both boxes say **À quai** for 5 minutes; then the first train leaves, and the second one 2 minutes later. |
| `ten-to-nine` | The second box shows 10 or more, and counts down to 9 by itself 3 to 4 minutes after the launch, then every 6 minutes. Look while the app is in the background. |
| `fork-end-one-train` | At a station of line 7 or 13 before the fork, such as Liège: the second end gets one train, which leaves after 8 minutes, then shows the grey dash. |
| `fork-end-no-train` | At the same stations: the second end gets no train, so its row shows the grey dash. |
| `fork-end-over-an-hour` | At the same stations: the second end gets one train after 70 minutes, so it says **> 1 h**, then counts down from 59. |
| `server-out` | As if the server of the app were out of PRIM calls. Trains every 4 minutes, the first one 3 minutes after the launch. From 1 to 8 minutes after the launch, the fake trains answer "out" with the time 8 minutes after the launch as the time to ask again. The times shown keep counting down, then the Live Activity says **Times unavailable** when the first train leaves, the main screen says when the live times come back, and the times come back 8 minutes after the launch. |
| `app-token-refused` | As if the server refused the app token of this build, from 1 minute after the launch. Trains every 4 minutes, the first one 3 minutes after the launch. The times shown keep counting down, then the Live Activity says **Update the app** when the first train leaves, and the main screen shows the same words on an orange card. A Live Activity that starts later starts with these words. |
| `server-out-tomorrow` | The fake trains answer "out" from the launch until 40 seconds after midnight (the time zone of the phone): the Live Activity starts with **Times unavailable**, and the main screen says that the live times come back tomorrow. |

The states are in `FakeTrainsScenario`; for a name that the app does not know, the command says so.
To start a state again, run the same command again, also while a Live Activity shows.
Each launch writes one `FakeTrains` line in the log of the app ([Read the logs](../README.md#read-the-logs)): its `--fake-trains` argument or no argument, the saved choice, and the trains that the app uses.

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

In the background, the app shows a notification with the name of the station, instead of the Live Activity.
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

   The notification **Abbesses** shows within a few seconds.
   Tap it to start the Live Activity, or touch and hold it to snooze the station.

On your iPhone, iOS also wakes a suspended or closed app near a station, after a few seconds to a few minutes: test that case there, with **Debug > Simulate Location** in Xcode.

### On your iPhone: see why no notification came

**Testing tools** > **Wake log** shows, newest first, what iOS woke the app for and what the app decided, with the time of each line.
It keeps the last 500 lines across launches, with no cable and no Xcode.
At the top, **Phone now** shows the settings that can stop a wake: the location (Always, precise), Background App Refresh, Low Power Mode, the notifications, and a fake position.

Check this before every walk, because a fake position makes the walk test nothing:
the app keeps a fake position across launches, and with it the app watches no area, so iOS wakes nothing.

1. On the main screen of the app, look just under the card with **Location** (**Localisation** in French) and **Notifications**.
   The orange line "Fake position", with a place name, must not be there.
   The Testing tools and this line stay in English on a French phone.
2. In **Wake log**, read the line "Position" of **Phone now**.
   It must say "Position: real GPS", not "Position: fake" with a place name.
3. When either one says fake, go back to **Testing tools** and tap **Use the real GPS**, then open **Wake log** again.
   **Phone now** is read once, when the screen opens, so it shows the change only the second time.

| Icon | A line for |
|---|---|
| Power | Each launch of the app, then the settings of the phone at that launch; each time the app comes on screen or leaves it |
| Location | Each event that iOS sends for an area: entered, left, or a problem that iOS reports; one line for the first state of the new areas |
| Map | Each time the app chooses again the stations that iOS watches |
| Branch | Each arrival that the app decides, with its reason: notified, started, switched, or why not; each end of the Live Activity by its distance or time limit |
| Bell | Each notification that the app hands to iOS, or that iOS refuses, with the notification settings |

"App launched" is written at the start of the launch.
When "App on screen" follows it within 2 seconds, you opened the app; when it does not, iOS launched the app in the background.
Only a line "iOS: entered" a station after it, or "inside" a station in a "first state" line, says that iOS woke the app near that station.
Other area lines can follow any launch: iOS can send the state of each area when the app starts ("left", "not watched"), and "area around you" and "stop area" are not stations.
iOS also launches apps ahead of time, with no reason in the log.
No line at all after a walk near a station means that iOS never woke the app.
A line "No arrival at" a station with a rough position or none is followed by "Second chance at" that station: "asks iOS for a position", then its result: "notified after N s", or "gave up" or "ended" after N s, with the reason.
When the result line never comes, iOS suspended or closed the app before the end of the 2 minutes.
A line "Live Activity ended: N m from" a station, before a line "Notified", says that the rider left that station before reaching the next one, so the next one notified instead of a switch.
After a walk, do not read **Phone now** to know the position of the walk: it shows the state when you opened the screen.
Read the line "App launched" (Power icon) of the walk instead, which says "Position: fake" with a place name, or "Position: real GPS", as it was at that launch.
A walk with a fake position also has, with the Map icon, the line "No region watched: a fake position is on".
Such a log says nothing about a closed app: tap **Use the real GPS**, then walk again.
With the real GPS, a Map line "Watching" some stations (often "Watching 18 stations") shows once the phone has a position; when it does not show, leave the app and open it again.
The line "Region watch on: iOS keeps N regions for the app" is no proof either way: it counts the areas when the app starts, before the app chooses them, so it can say 0 with the real GPS, and more than 0 with a fake position.
A line "iOS keeps N areas for the app, the plan has M" is a problem: iOS does not keep the areas that the app just chose, and past 20 areas iOS refuses new ones, so a station near you may not wake the app.
For a first walk, stand about 2 minutes within 150 meters of a station, because iOS can take a few seconds to a few minutes to report that you entered the area ([the arrival notification](#with-the-app-in-the-background-the-arrival-notification)).
**Share** sends the log as text, and **Clear** empties it.
Release builds record nothing.
