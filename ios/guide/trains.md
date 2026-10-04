# Where the train times come from, and when they refresh

The app gets its next trains from PRIM, the train data service of Île-de-France Mobilités.
A debug build, the one of `make run`, asks PRIM with your own key; with no key it shows no times, so use [fake trains](testing-tools.md#get-fake-trains-with-no-key) or [add your key](../README.md#the-train-data-key-prim).
A release build asks the server of TROME instead.
This page also says what each station costs in calls, when the app asks again, and what the Live Activity shows when a call fails.
The code is in `ios/Packages/TROMECore/Sources/TROMECore/Trains/`.

## Debug builds ask PRIM, release builds ask the server

| | Debug build | Release build |
|---|---|---|
| Made by | `make run`, the **Run** button of Xcode | **Product > Archive**, and **Product > Profile**, which also builds Release |
| Asks | PRIM, with your key | The server of TROME, which holds the PRIM key and gives one answer to all riders; [server/README.md](../../server/README.md) shows how to run your own |
| Its settings | `ios/Config/Secrets.xcconfig` | `ios/Config/Server.xcconfig`, a copy of `ios/Config/Server.example.xcconfig` |
| With no settings | It runs, with no train times | The build fails, so that no app ships with no train source |
| Holds the PRIM key | Only when built with your key | Never |

Git ignores both settings files.
The server sends the PRIM answer as PRIM gave it, with its time, so the app counts the age of the times from that time.
The app sends the server only the stop and the app token: no position, and no identifier of the phone or of a person.

## One call for each stop area

A stop area is the group of all the platforms of a station.
Each time the app gets the times of a station, it makes one call for each stop area of the station and of the [other stations of its place](stations.md#a-station-shows-the-lines-of-its-neighbours):

| Station | Calls each time |
|---|---|
| Abbesses, a metro station alone in its place | 1 |
| Châtelet: the metro stop area, and the RER stop of Châtelet - Les Halles | 2 |
| Saint-Lazare, with the stations of its place | 5 |

Your PRIM key has a daily quota of calls.
On screen, a station costs its calls twice a minute: 4 calls a minute at Châtelet.
In the background, a Live Activity still costs its calls every 30 seconds to 2 minutes, so remove it when you are done with live trains.

## When the app asks again

| When | The app asks |
|---|---|
| The app is open with a Live Activity, or with **Next trains of a station** | Every 30 seconds, one call for both when they show the same station |
| The app is in the background with a Live Activity | 5 seconds after the first train on it leaves, but at least 30 seconds and at most 2 minutes after the last call |
| The Live Activity starts or switches station in the background, or you leave the app before it sent its first times | At once |

In the background, the app asks only while iOS keeps it running.
It stops asking when PRIM refuses the key or says that the quota is used up, in a debug build, or when the server refuses the app token, in a release build.
It asks again when the Live Activity switches station or the app comes back to the screen.
Any other failure, such as no network or a time-out, fails this call only.

## What a failed call does to the Live Activity

| Before the call, the Live Activity shows | After it |
|---|---|
| Train times | The same times, still counting down; once the first train has left, iOS shows **Open the app for new times.** |
| **No trains** | **No data available**, because **No trains** never gets old on its own |
| No times yet | **No data available** |

The next call that works shows its times at once.
To see what PRIM answered, train by train, [read the logs](../README.md#read-the-logs).
