# Notice

This file says where the data of TROME comes from, which licence covers each part of the repo, and what you must do when you reuse the data.
It is our reading of the licences, not legal advice: the licence texts are what counts.

## The code

The code of TROME is under the [MIT licence](LICENSE).
The data below is not: it keeps its own licence, whatever the licence of the code.

## The station list

The file [`stations.json`](ios/Packages/RATPCore/Sources/RATPCore/Resources/stations.json) lists the metro and RER stations, their lines, the colours of the lines, their stops, and the stations that share one place.
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
The licences above are the ones that the dataset pages showed on 2026-10-02.

TROME adapts the data: it keeps only the metro and RER lines, joins the four datasets, groups the stops of each station, and fixes a few station names.
So `stations.json` is a database made from these datasets, and `stations.json` and every extract of it stay under the ODbL, whatever the licence of the code.

When you share `stations.json`, an extract of it, or a work made from it, in public:

- Say that the data comes from Île-de-France Mobilités and was adapted by TROME, name the two licences, and link to them.
- Give the date of the data, 2026-09-27, as the Licence Ouverte asks.
- Keep any database that you make from it under the ODbL, and let people get it, as the ODbL asks.
  A work that only shows the data, such as a screen or a picture, needs only the notice above.

The app shows this notice for the station list on its main screen, with links to the two licences:

> Station list adapted by TROME from Île-de-France Mobilités data, under the ODbL and the Licence Ouverte v2.0.

## The train times

The app gets the next trains from the "Prochains passages" API of [PRIM](https://prim.iledefrance-mobilites.fr), the portal of Île-de-France Mobilités.
This data is under the [Licence Mobilités](https://prim.iledefrance-mobilites.fr/en/licences).
As this licence asks, the app shows this notice on its main screen, with a link to PRIM on the name of the database and a link to the licence on its name:

> Contains information from the ‘Prochains passages’ database of Île-de-France Mobilités (PRIM), made available under the ‘Licence Mobilités’.

The tests of the app and of the server read recorded PRIM answers: the files in [`contracts/prim/`](contracts/prim/), and the PRIM answers inside the examples of [`contracts/api/`](contracts/api/).
They come from the same database, so they are under the Licence Mobilités too.

## Names and marks

TROME is not an app of RATP or of Île-de-France Mobilités, and neither of them endorses it.
The names, the signs and the colours of the lines belong to their owners.
Apple, App Store and iPhone are trademarks of Apple Inc.
