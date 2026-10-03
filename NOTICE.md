# Notice

This file says where the data of TROME comes from, which licence covers each part of the repo, and what you must do when you reuse the data.
It is our reading of the licences, not legal advice: the licence texts are what counts.

## The code

The code of TROME is under the [MIT licence](LICENSE).
The data below is not: it keeps its own licence, whatever the licence of the code.

## The station list

The file [`stations.json`](ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json) lists the metro and RER stations, their lines, the colours of the lines, their stops, and the stations that share one place.
The script [`update-stations.py`](ios/scripts/update-stations.py) builds it from four datasets that Île-de-France Mobilités publishes on its open data portal, [data.iledefrance-mobilites.fr](https://data.iledefrance-mobilites.fr):

| Dataset | Identifier | What `stations.json` takes from it | Licence |
|---|---|---|---|
| [Arrêts et lignes associées](https://data.iledefrance-mobilites.fr/explore/dataset/arrets-lignes/) | `arrets-lignes` | the stations, their lines, their stops and their positions | ODbL |
| [Référentiel des lignes de transport en commun d’île-de-France - lignes actives et prochainement actives](https://data.iledefrance-mobilites.fr/explore/dataset/referentiel-des-lignes/) | `referentiel-des-lignes` | the colours of the lines | ODbL |
| [Référentiel des arrêts : Relations](https://data.iledefrance-mobilites.fr/explore/dataset/relations/) | `relations` | the stations that share one place | Licence Ouverte v2.0 |
| [Référentiel des arrêts : Arrêts](https://data.iledefrance-mobilites.fr/explore/dataset/arrets/) | `arrets` | the stop area of each metro stop | Licence Ouverte v2.0 |

- **ODbL** is the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
  Île-de-France Mobilités publishes these datasets under its [French version](https://doc.transport.data.gouv.fr/le-point-d-acces-national/cadre-juridique/conditions-dutilisation-des-donnees/licence-odbl).
- **Licence Ouverte v2.0** is the [Licence Ouverte / Open Licence 2.0 of Etalab](https://www.data.gouv.fr/pages/legal/licences/etalab-2.0).

The data of `stations.json` dates from 2026-09-27, the last time the script downloaded the four datasets.
The file gives this date in its `date` field, and the app shows it.
The licences above are the ones that the dataset pages showed on 2026-10-02.

TROME adapts the data: it keeps only the metro and RER lines, joins the four datasets, groups the stops of each station, and fixes a few station names.
So `stations.json` is a database made from these datasets, and `stations.json` and every extract of it stay under the ODbL, whatever the licence of the code.

When you share `stations.json`, an extract of it, or a work made from it, in public:

- Say that the data comes from Île-de-France Mobilités and was adapted by TROME, name the two licences, and link to them.
- Give the date of the last update of the data, as the Licence Ouverte asks: 2026-09-27.
  It is the date of our copy, the day the script downloaded the four datasets, so `stations.json` holds what the datasets held that day.
  The dataset pages may show a later date, because Île-de-France Mobilités updates these datasets almost every day.
  That date is for newer data than `stations.json` holds: do not give it for `stations.json`.
- If you make a new database from it, keep that database under the ODbL, and offer a copy of it to the people who use it or a work made from it, as the ODbL asks.

A work that only shows the data, such as an app screen or a picture, may have any licence, but it still needs the first two points.

The app shows this notice for the station list on its main screen, with links to the two licences.
It writes the date the way the phone writes dates, so on an iPhone in English with the region United States it reads:

> Station list adapted by TROME from Île-de-France Mobilités data of September 27, 2026, under the ODbL and the Licence Ouverte v2.0.

## The train times

The app and the server in [`server/`](server/) get the next trains from the "Prochains passages" API of [PRIM](https://prim.iledefrance-mobilites.fr), the portal of Île-de-France Mobilités.
This data is under the [Licence Mobilités](https://prim.iledefrance-mobilites.fr/en/licences).
As this licence asks, the app shows this notice on its main screen, with a link to PRIM on the name of the database and a link to the licence on its name:

> Contains information from the ‘Prochains passages’ database of Île-de-France Mobilités (PRIM), made available under the ‘Licence Mobilités’.

The tests of the app and of the server read recorded PRIM answers: the files in [`contracts/prim/`](contracts/prim/), and the PRIM answers inside the examples of [`contracts/api/`](contracts/api/).
They come from the same database, so they are under the Licence Mobilités too.

## The server's day shape

The server shares its daily budget of PRIM calls among the 24 hours of the day, so that the morning peak cannot spend the calls of the evening.
The share of each hour, the day shape, is `dayShapePercents` in [`relay-settings.ts`](server/src/core/config/relay-settings.ts).
It is made from one dataset that Île-de-France Mobilités publishes on its open data portal:

| Dataset | Identifier | What the day shape takes from it | Licence |
|---|---|---|---|
| [Validations sur le réseau ferré : Profils horaires par jour type (2ème trimestre 2026)](https://data.iledefrance-mobilites.fr/explore/dataset/validations-sur-le-reseau-ferre-profils-horaires-par-jour-type-2eme-trimestre/) | `validations-sur-le-reseau-ferre-profils-horaires-par-jour-type-2eme-trimestre` | the share of rail validations in each hour, for each stop and each type of day | [Licence Ouverte v2.0](https://www.data.gouv.fr/pages/legal/licences/etalab-2.0) |

The dataset covers the 2nd quarter of 2026, and its page gives 2026-09-22 as the date of its last update.
The licence and the date above are the ones that the dataset page showed on 2026-10-03.

TROME adapts the data, so the numbers of the day shape are ours, not numbers of the dataset.
For each hour, TROME takes the mean of the shares of all rail stops (each stop counts the same), over a week of 5 weekdays out of the school holidays, 1 Saturday and 1 Sunday, and rounds it to 0.1%.
Then it raises each hour below 0.5% to 0.5%, takes the extra share from the other hours in proportion, and fixes the last digits so that the 24 hours add up to 100%.

The day shape is a setting, and it will change: after two weeks of real use, the share of each hour in the calls of TROME's own riders will replace it.
From then on, the day shape no longer comes from this dataset.

The Licence Ouverte lets anyone reuse the data and a work made from it, also for a commercial use.
It asks for two things in return: name the source, and give the date of the last update of the data.
The day shape is a work made from the data, and it is in the code: a copy of `relay-settings.ts` shares it too.
When you share the day shape, or a work made from it, in public:

- Say that the data comes from Île-de-France Mobilités and was adapted by TROME, so that no one takes our numbers for theirs.
- Give the date of the last update of the data: 2026-09-22.
- Name the Licence Ouverte v2.0, and link to it.
  The licence does not ask for this, but it tells the next person what they may do with the data.

For example:

> Day shape adapted by TROME from the Île-de-France Mobilités dataset “Validations sur le réseau ferré : Profils horaires par jour type (2ème trimestre 2026)”, last updated 2026-09-22, under the Licence Ouverte v2.0.

## Names and marks

TROME is not an app of RATP or of Île-de-France Mobilités, and neither of them endorses it.
The names, the signs and the colours of the lines belong to their owners.
Apple, App Store and iPhone are trademarks of Apple Inc.
