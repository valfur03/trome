# Where the station list comes from, and how to update it

The app finds the nearest metro or RER station offline: it reads one file that ships inside the app, `stations.json`.
This page says what the file holds and where its data comes from, so that you can update it, fix a station name, or understand why a station shows the lines of its neighbours.
Run the commands from the root of the repo; the paths on this page start there too.

## What the file holds

`ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json` lists every metro station (lines 1 to 14, 3bis and 7bis) and every RER station (lines A to E), with no bus, tram or Transilien stop.
Here is one station, Abbesses, on line 12:

```json
{"id": "IDFM:22059", "name": "Abbesses", "latitude": 48.884388, "longitude": 2.338381, "lines": [{"mode": "metro", "name": "12", "stopIds": ["IDFM:22059", "IDFM:463116"], "stopAreaIds": ["IDFM:monomodalStopPlace:42155"], "color": {"background": "00643c", "text": "ffffff"}}]}
```

| Field | What it holds |
|---|---|
| `date` | At the top of the file: the day it was downloaded. The app shows it in the data notice at the bottom of its main screen. |
| `id`, `name`, `latitude`, `longitude` | The station. |
| `lines` | Each line of the station: its `mode`, `metro` or `rer`, and its `name`, such as `12` or `A`. |
| `stopIds` | For a metro line, its two platforms, one for each direction, which PRIM calls quays. For an RER line, the stop of the station. |
| `stopAreaIds` | For a metro line, the stop area: the group of all the platforms of the station, which PRIM answers for in one call. A metro line has none when the data gives no stop area for its platforms. |
| `color` | The colour of the line and of the text on it, as hex RGB, in the version that Île-de-France Mobilités gives for screens. The Live Activity uses only these colours for the lines. |
| `hubId` | Only on a station that shares its place with another station of the list, such as Châtelet and Châtelet - Les Halles (see [below](#a-station-shows-the-lines-of-its-neighbours)). |

To browse the list in the app, open **Testing tools** and tap **All stations** ([the Testing tools](testing-tools.md)).

## Where the data comes from

The file is made from four open datasets of Île-de-France Mobilités, under two licences, the ODbL and the Licence Ouverte v2.0.
[NOTICE.md](../../NOTICE.md#the-station-list) names each dataset and what the file takes from it, and says what you must do when you reuse the list.

## Download the list again

Download it when a station or a line opens, closes or changes its name.
You need Python 3, and no API key.

1. Run:

   ```sh
   make stations
   ```

   The script, `ios/scripts/update-stations.py`, downloads the four datasets, writes `stations.json` with today's date, and prints that date.
2. Write the same date in [NOTICE.md](../../NOTICE.md), three times:
   - as the script prints it, for example 2026-09-27, in the sentence on the date of the data;
   - the same way, in the list of what to give when you share the list;
   - as the app writes it in English, for example September 27, 2026, in the quote of the app's notice.

   `make test` fails when a date in NOTICE.md differs from the date of the file.
3. Open the four dataset pages that NOTICE.md links, check that they still show the same licences, and write the day of this check in NOTICE.md.
4. Run `make test`, and commit `stations.json` and NOTICE.md together.

## A station shows the lines of its neighbours

Some places have several stations with different names, such as Châtelet for the metro and Châtelet - Les Halles for the RER.
The script gives them the same `hubId`, from the "pôles d'échange" of Île-de-France Mobilités, so that the Live Activity of one shows the trains of all.
`StationCatalog.hubStations(of:)` gives the stations whose lines show for a station: the station itself, then the other stations of its place, nearest first, each with only the lines that the stations before it lack.
A station with no `hubId` shows only its own lines.

Each station of a place costs its own calls to the train data service: see [one call for each stop area](trains.md#one-call-for-each-stop-area).

## A unit test says that two stations look like the same station

Some names in the open data are wrong, or spelled in two ways, so one station can come out twice.
`make test` then fails with "<name> and <name> look like the same station".
Add the wrong name to the table `STATION_NAMES` in `ios/scripts/update-stations.py`, with the right name, and run `make stations` again.
