# Where the station list comes from, and how to update it

The app finds the nearest metro or RER station offline, from one file that ships inside it: `ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json`.
Update it when a station or a line opens, closes or changes its name: `make stations` downloads it again from the open data of Île-de-France Mobilités.
Run the commands from the root of the repo.

## Download the list again

The data is under the ODbL and the Licence Ouverte v2.0, which ask for its date and its licences: [NOTICE.md](../../NOTICE.md#the-station-list) names the four datasets and gives both.
You need Python 3, and no API key.

1. Run `make stations`.
   It downloads the four datasets, writes `stations.json` with today's date, and prints that date.
2. Write that date three times in [NOTICE.md](../../NOTICE.md#the-station-list): twice as the script prints it, such as 2026-09-27, and once in the quote of the app's notice, as the app writes it in English, such as September 27, 2026.
   `make test` fails when a date in NOTICE.md differs from the date of the file.
3. Open the four dataset pages that NOTICE.md links, check that their licences did not change, and write the day of this check in NOTICE.md.
4. Run `make test`, and commit `stations.json` and NOTICE.md together.

## What the file holds

It lists every metro station (lines 1 to 14, 3bis and 7bis) and every RER station (lines A to E), with no bus, tram or Transilien stop.
Here is Abbesses, on line 12:

```json
{"id": "IDFM:22059", "name": "Abbesses", "latitude": 48.884388, "longitude": 2.338381, "lines": [{"mode": "metro", "name": "12", "stopIds": ["IDFM:22059", "IDFM:463116"], "stopAreaIds": ["IDFM:monomodalStopPlace:42155"], "color": {"background": "00643c", "text": "ffffff"}}]}
```

- `stopIds`: for a metro line, its platforms, most often one for each direction, and one at a station that the line passes in one direction only; for an RER line, the stop of the station.
- `stopAreaIds`: for a metro line, its stop area, the group of all the platforms of the station, which PRIM answers for in one call.
- `color`: the colour of the line and of its text, the only colours that the Live Activity uses for lines.
- `hubId`: only on a station that shares its place with another one (see below).
- `date`, at the top of the file: the day of the download, which the app shows in its data notice.

To browse the list in the app, open **Testing tools** and tap **All stations**.

## A station shows the lines of its neighbours

Some places have several stations with different names, such as Châtelet for the metro and Châtelet - Les Halles for the RER.
The script gives them the same `hubId`, from the "pôles d'échange" of Île-de-France Mobilités, so that the Live Activity of one shows the trains of all.
`StationCatalog.hubStations(of:)` picks them: the station itself, then its neighbours, nearest first, each with only the lines that the stations before it lack.
Each of them costs its own [calls to the train data](trains.md#one-call-for-each-stop-area).

## A unit test says that two stations look like the same station

Some names in the open data are wrong, or spelled in two ways, so one station can come out twice, and `make test` fails with "<name> and <name> look like the same station".
Add the wrong name to `STATION_NAMES` in `ios/scripts/update-stations.py`, with the right name, and run `make stations` again.
