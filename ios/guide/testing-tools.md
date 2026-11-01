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
When iOS must see the phone move, for example for an arrival in the background, tap **Use the real GPS** and move the Simulator instead:

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
The first train comes 3 minutes after the launch, the other direction one minute later, then one train every 4 minutes, with the app open or in the background.

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

### With the app in the background: no notification

In the background, the app asks the server to start the Live Activity ([the silent start](auto-live-activity.md#the-silent-start)), and sends no notification.
A build of the Simulator has no silent start, so nothing shows: the [wake log](#on-your-iphone-see-why-no-live-activity-came) says why, and the Live Activity starts when you open the app at the station.
With no Live Activity, the app follows no position in the background, and the Simulator cannot watch the areas of the stations, so nothing would reach the app there.
So launch it with `--keep-running-in-background`, which keeps it awake and following the position in the background, in place of the wake for the area of a station.

1. Tap **Use the real GPS**, and in the **Settings** app of the Simulator, set the location of TROME to **Always**.
2. Move the Simulator far from any station:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.42,2.63
   ```

3. Launch the app again, with the argument:

   ```sh
   xcrun simctl launch --terminate-running-process "$(make -s simulator)" com.example.trome.dev --keep-running-in-background
   ```

4. Go to the home screen.
5. Move the Simulator to Abbesses:

   ```sh
   xcrun simctl location "$(make -s simulator)" set 48.88439,2.33838
   ```

   No notification shows.
   **Wake log** has the line "No start at Abbesses, no notification: the silent start is off in this build".
6. Open the app: the Live Activity of Abbesses starts.

On your iPhone, iOS also wakes a suspended or closed app near a station, after a few seconds to a few minutes: test that case there, with **Debug > Simulate Location** in Xcode.

### On your iPhone: see why no Live Activity came

**Testing tools** > **Wake log** shows, newest first, what iOS woke the app for and what the app decided, with the time of each line.
In a Release build for a walk, the list icon at the top right of the main screen opens it ([Record a walk with a TestFlight build](#record-a-walk-with-a-testflight-build)).
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
| Location | Each event that iOS sends for an area: entered, left, or a problem that iOS reports, with where the phone was for a station area, whether iOS launched the app for it, and the background time left; one line for the first state of the areas that iOS did not watch yet, but its own line for each station that the phone is inside |
| Map | Each time the app chooses again the stations that iOS watches |
| Branch | Each arrival that the app decides, with its reason: arrived in the background, started, switched, or why not; each end of the Live Activity by its distance or time limit |
| Bell | Only in a log kept from an earlier build: each arrival notification that it handed to iOS |
| Radio waves | At each launch of a plain `make run` build (not `LIVE=1`), "Silent start off: this build has no server": expected, because that build has no server, so you set up nothing and none of the other lines of this row follow. A `make run LIVE=1` build writes this line only with `TROME_SILENT_START = YES` in `ios/Config/Local.xcconfig` and no server address set up; without that setting it has no silent start and writes none of the lines of this row. With the [silent start](auto-live-activity.md#the-silent-start) on: the start token from iOS, each ask to the server with the background time left, its answer ("started", "already started", "refused", "not set up", "no answer") with the seconds that it took, or "No answer within 10 s" ("No start token from iOS within 10 s" when iOS gave none), one line "No start at" the station, ", no notification:" and the cause when the Live Activity does not come, and "Follows the Live Activity that the server started" when the app finds it on screen |
| Tram | Each call that the app makes for its Live Activity in the background: how old the answer is and the next train of each direction that it hands to iOS (four at most), or why no answer came; then "next ask by" and a time, or "asks no more" |

"App launched" is written at the start of the launch.
When "App on screen" follows it within 2 seconds, you opened the app; when it does not, iOS launched the app in the background.
The line "Phone at launch" after it says the same: "Started by iOS, in the background" or "Started on screen".
Only a line "iOS: entered" a station after it, or "first state of a new area: inside" a station, says that iOS woke the app near that station.
After a station, in an "entered" or "left" line or in a line "first state of a new area: inside", the brackets say where the phone was when iOS sent the event, for example "(phone 85 m away, ±12 m, 4 s old)": the distance from the centre of the station, the accuracy, and the age of the last position that iOS had.
The time of the line is when iOS woke the app: the gap from the time when you crossed the edge of the area is how late iOS was.
The end of the line says "fresh launch, N s ago" when iOS launched the app for this event, or "app already running for" a time when the event came to an app that was running or suspended, then the background time that iOS still gave the app ("no background time limit" on screen).
The app writes this line before it decides, so it is there even when no decision line follows, and "(iOS gave no position)" means that iOS had none to give.
The decision line after it rests on that position, with one exception: after "entered", a position that does not settle the arrival makes the app ask iOS for a new one, for up to 10 seconds, and the decision then rests on the new one.
Other area lines can follow any launch: iOS can send the state of each area when the app starts ("left", "not watched"), and "area around you" and "stop area" are not stations.
iOS also launches apps ahead of time, with no reason in the log.
No line at all after a walk near a station means that iOS never woke the app.
With a Live Activity on the lock screen and the app in the background, no tram line after the time of "next ask by" means that iOS was not running the app.
An old answer, or the same times line after line, comes from the train data; times in the line that the lock screen does not show mean that iOS did not draw them.
A line "No arrival at" a station with a rough position or none is followed by "Second chance at" that station: "asks iOS for a position", then its result: "arrived in the background after N s", or "gave up" or "ended" after N s, with the reason.
When the result line never comes, iOS suspended or closed the app before the end of the 2 minutes.
An answer line or a "No start at" line that ends with "iOS suspended the app" says that the ask lasted past its 10 seconds: iOS stopped the app during the ask.
After a "left" line, "No decision and no new areas" says that iOS gave no recent position, so the app chose no new stations to watch, and the stations further on may not wake it.
A line "Live Activity ended: N m from" a station, before a line "Arrived in the background", says that the rider left that station before reaching the next one, so the next one asked the server instead of a switch.
A switch, or an end by distance, that rests on a position of the real GPS ends with where that position came from.
"(position: stream)" is the position stream, which iOS can stop about 10 seconds after the app leaves the screen, unless the app still counts as in use.
"(position: keeper; stream N s old)" is the background updates that keep the app running while a Live Activity shows, with the age of the last position of the stream.
Both sources often give the same position, and either can come first, so read the age, not the source.
On a ride, a stream a few seconds old shows that iOS still sent it; a stream tens of seconds or minutes old shows that iOS stopped it.
"(position: keeper; no stream position)" says that the stream gave no position since the app started.
A switch or an end with neither rests on a position from a wake of an area, or from one ask to iOS.
After a walk, do not read **Phone now** to know the position of the walk: it shows the state when you opened the screen.
Read the line "App launched" (Power icon) of the walk instead, which says "Position: fake" with a place name, or "Position: real GPS", as it was at that launch.
A walk with a fake position also has, with the Map icon, the line "No region watched: a fake position is on".
Such a log says nothing about a closed app: tap **Use the real GPS**, then walk again.
With the real GPS, a Map line "Watching" some stations (often "Watching 18 stations") shows once the phone has a position; when it does not show, leave the app and open it again.
The line "Region watch on: iOS keeps N regions for the app" is no proof either way: it counts the areas when the app starts, before the app chooses them, so it can say 0 with the real GPS, and more than 0 with a fake position.
A line "iOS keeps N areas for the app, the plan has M" is a problem: iOS does not keep the areas that the app just chose, and past 20 areas iOS refuses new ones, so a station near you may not wake the app.
For a first walk, stand about 2 minutes within 150 meters of a station, because iOS can take a few seconds to a few minutes to report that you entered the area ([with the app in the background](#with-the-app-in-the-background-no-notification)).
To see these area lines at your desk first, play [a walk into Le Parc de Saint-Maur](../App/TestingTools/WalkIntoLeParcDeSaintMaur.gpx) on your iPhone with **Debug** > **Simulate Location** in Xcode: the file has the steps.
**Share** sends the log as text, and **Clear** empties it once you confirm, so a slip next to **Share** keeps the log.
The text holds the lines and **Phone now**, with distances to stations and never a position.
A Release build records nothing, unless it is a build for a walk.

### Record a walk with a TestFlight build

A Release build archived with `TROME_WAKE_LOG_BUILD_<n> = YES` in `ios/Config/Local.xcconfig` has the Wake log, where `<n>` is its build number (`CURRENT_PROJECT_VERSION` in `ios/Config/Base.xcconfig`), for example `TROME_WAKE_LOG_BUILD_5 = YES` for build 5.
The list icon at the top right of the main screen opens it, and nothing else on the screens changes.
It records the same lines as a debug build, on the phone only: the app sends none of them anywhere, and only **Share** gives them to someone.
Use it for a TestFlight build that you walk with, and never submit that build for the App Store.
The next build number turns the Wake log off by itself, so a line left in the file never reaches a store build; remove it after the walk.
`make release-archive-check` fails when the archive has the Wake log while its Release settings do not compile it, and says "a TestFlight build for a walk, never for the store" when they do.
