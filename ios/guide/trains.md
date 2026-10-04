# Where the train times come from, and when they refresh

The app gets its next trains from PRIM, the train data service of Île-de-France Mobilités.
A debug build, the one of `make run`, asks PRIM directly with your own key; with no key, it shows no times, so use [fake trains](testing-tools.md#get-fake-trains-with-no-key), or [add your key](../README.md#the-train-data-key-prim).
A release build asks the server of TROME instead.
This page says which build asks whom, how many calls each station costs, when the app asks again, and what the Live Activity shows when a call fails.
The code is in `ios/Packages/TROMECore/Sources/TROMECore/Trains/`.

## Debug builds ask PRIM, release builds ask the server

| | Debug build | Release build |
|---|---|---|
| Made by | `make run`, the **Run** button of Xcode | **Product > Archive** for TestFlight or the App Store, and **Product > Profile** |
| Asks | PRIM, with your own key | The server of TROME, which keeps the PRIM key and shares its calls among all riders; [server/README.md](../../server/README.md) shows how to run your own |
| Its settings | Your key, in `ios/Config/Secrets.xcconfig` | The host of the server and its app token, in `ios/Config/Server.xcconfig`, a copy of `ios/Config/Server.example.xcconfig` |
| With no settings | It builds and runs, with no train times | The build fails, and its error names the file, so that no app ships with no train source |
| Holds the PRIM key | Yes, when you build it with `make run LIVE=1`, or from Xcode in a folder that has a key file | Never: the Release settings leave the key out, and its code does not read it |

`make run` uses your key only with `LIVE=1`, so that the tests never spend its calls ([live trains in a debug build](../README.md#the-train-data-key-prim)).
Git ignores both settings files, so neither the key nor the token reaches a commit.
`make live-key-check`, part of `make check`, proves with fake values that no build output shows the key, that a Release build never holds it, and that a Release build with no server settings fails.

The server gives the PRIM answer as PRIM gave it, with the time when PRIM gave it.
So the app counts the age of the times from that moment, not from the moment it got them, and never shows a train that left in between.
The app sends the server only the stop and the app token: no position, no identifier of the phone or of an account, and no push token.

In a debug build, the fake trains replace both sources.

## One call for each stop area

A stop area is the group of all the platforms of a station, which PRIM answers for in one call.
Each time the app gets the times of a station, it calls PRIM once for each stop area of the station, and of the other stations of the same place, such as Châtelet and Châtelet - Les Halles ([stations that share a place](stations.md#a-station-shows-the-lines-of-its-neighbours)):

| Station | Calls each time |
|---|---|
| Abbesses, a metro station that shares its place with no other | 1 |
| Châtelet: the metro stop area of Châtelet, with its 10 platforms, and the RER stop of Châtelet - Les Halles | 2 |
| Saint-Lazare, with the stations of its place | 5 |

All the metro lines of a station share one stop area, and an RER stop is one stop area.
A metro line with no stop area in the [station list](stations.md) costs one call for each of its platforms.
A release build makes the same calls, to the server.
An answer can hold trains of lines that the app shows for another station of the place, so the app keeps only the trains of the lines that it asked this stop area for.

Your PRIM key has a daily quota of calls.
While the app is on screen with a Live Activity or **Next trains of a station**, its station costs its calls twice a minute: 4 calls a minute at Châtelet.
In the background, a Live Activity still costs its calls every 30 seconds to 2 minutes, so remove it when you are done with live trains.

## When the app asks again

| When | The app asks |
|---|---|
| The app is open and a Live Activity shows | Every 30 seconds |
| **Next trains of a station** is open | Every 30 seconds; when it shows the station of the Live Activity, the Live Activity uses its answers, with no second call |
| The app is in the background with a Live Activity | 5 seconds after the first train on the Live Activity leaves, but at least 30 seconds and at most 2 minutes after the last call |
| The Live Activity starts or switches station while the app is in the background | At once |
| You leave the app while the Live Activity still says **Loading the next trains…**, or right after the app opened again, before it sent its first times | At once, with no wait for the next background call |

Between two calls, the app draws the Live Activity again each time a train on it changes, for example when a wait goes from 3 to 2 minutes.
In the background, it asks only while iOS keeps it running: a Live Activity keeps it running, but iOS can still end it, and nothing then gets new times until a region event wakes the app or you open it.

In the background, the app stops asking in only two cases, until the Live Activity switches station or the app comes back to the screen:

- in a debug build, when PRIM refuses the key or says that the quota is used up;
- in a release build, when the server refuses the app token.

Any other failure, such as no network, a time-out, or a server with no times for now, fails this call only, and the app asks again at the next moment of the table.

## What a failed call does to the Live Activity

| Before the call, the Live Activity shows | After the failed call, it shows |
|---|---|
| Train times of its station | The same times, still counting down; once the first train on it has left with no new times, iOS hides the times and shows **Open the app for new times.** |
| **No trains**, from an answer with no train | **No data available**, because **No trains** never gets old on its own |
| No times yet: a first call, a switch to another station, or a build with no key | **No data available** |

The next call that works shows its times at once.
[Show the next trains on the lock screen](../README.md#show-the-next-trains-on-the-lock-screen-live-activity) says when iOS hides old times.

## See what PRIM answered

Debug builds write each PRIM answer in the log of the phone, one line for each train, with whether the app kept it and why: see [read the logs](../README.md#read-the-logs).
