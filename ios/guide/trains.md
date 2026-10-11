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
| The app is in the background with a Live Activity | 5 seconds after the first train on it leaves, or at once when a train leaves and the last answer has no train to take its place in its row (so the next train of a fork end comes with the same update; with no answer within 2 seconds, the train that left goes at once), but at least 30 seconds and at most 2 minutes after the last call |
| The Live Activity starts or switches station in the background, or you leave the app before it sent its first times | At once |

In the background, the app asks only while iOS keeps it running.
It stops asking when PRIM refuses the key or says that the quota is used up, in a debug build, or when the server refuses the app token, in a release build.
When the server cannot ask PRIM for a stop, it answers 503 with `"out"` and the time when it asks PRIM again.
The app then makes no call for that stop before that time, also when you open the app or the Live Activity switches station, and asks once at that time.
When the server is still out, the app waits for the new time; when times come back, it shows them at once.
When several stops of a station are out, the app waits for the latest of their times and then asks them all, so that their times come back together.
When one stop is out, or its call fails, while another stop of the station answers, the directions of that stop never show "No trains": they keep their last times or an empty box ([when it cannot show times](live-activity.md#when-it-cannot-show-times)).
It counts that time from the `Retry-After` delay of the answer, not from the clock of the phone, and waits at least 30 seconds, so a phone with a wrong clock never asks again and again.
A debug build calls PRIM directly and never gets this answer: only the fake trains `server-out` and `server-out-tomorrow` give it ([the states of the fake trains](testing-tools.md#ask-for-a-train-at-the-platform-or-another-state)).
When the server is out because PRIM failed (`"prim-failure"`, a minute), the app waits the same way but keeps the usual words below: that cause is not the budget of the app.
It asks again when the Live Activity switches station or the app comes back to the screen.
Any other failure, such as no network or a time-out, fails this call only.

When the server refuses the app token (401 with `{"error": "unauthorized"}`), the app makes no more call, for any station, in the background or on screen, until you open the app or a new Live Activity starts.
The token is part of the build, so asking again could not help: the rider reads **Update the app**.
A 401 with another body, or a 403, is not this refusal (a network that asks to sign in can answer it), and fails this call only.

## What a failed call does to the Live Activity

| Before the call, the Live Activity shows | After it |
|---|---|
| Train times | The same times, still counting down; once the first train has left, the Live Activity shows **Open the app** ([the stale rule](live-activity.md#the-stale-rule)) |
| **No trains** | **Times unavailable**, because **No trains** never gets old on its own |
| No times yet | **Times unavailable** |
| Any of these, and the server is out because its budget of PRIM calls is used up (`"budget"`, or `"prim-limit"`: PRIM said "too many requests") | **Times unavailable**, in place of **Open the app**: opening the app would not help |
| Any of these, and the server refused the app token | **Update the app**, after an orange icon, in place of **Times unavailable** or **Open the app** |

The next call that works shows its times at once.
To see what PRIM answered, train by train, [read the logs](../README.md#read-the-logs).
