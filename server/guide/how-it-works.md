# How the server works

The server keeps the key of PRIM, the train data service of Île-de-France Mobilités, out of the app, and shares one daily quota of PRIM calls among all riders.
This page is for a developer who changes it: what it answers, how it spends the quota, and what it keeps; [server/README.md](../README.md) shows how to run and test it.

## The API

Each address answers `GET` and `HEAD` only, and the tokens go in the header `Authorization: Bearer <token>`.

| Request | Token | Answer |
|---|---|---|
| `GET /health` | none | `{"status":"ok"}` |
| `GET /v1/stops/{stopRef}/departures` | an app token of the server's list: each build of the app holds one, and a new token joins the list without cutting off the builds that hold an older one ([Change the app token](deploy.md#change-the-app-token)) | The PRIM answer of that stop, as PRIM gave it, so that the app keeps its own PRIM parser; `Last-Modified` is the time when PRIM gave it. |
| `GET /v1/owner/counts` | the owner token, which only the maintainer holds | The counts of the server ([Read the counts](deploy.md#read-the-counts)). |
| `GET /metrics` | the owner token | The same totals in the Prometheus text format ([Send the totals to your Prometheus](deploy.md#send-the-totals-to-your-prometheus)). |

`{stopRef}` is `STIF:StopArea:SP:<number>:` or `STIF:StopPoint:Q:<number>:`.
A wrong or missing token gets `401`, and another stop reference gets `400`.
[`contracts/api/`](../../contracts/api/) holds an example of each answer.

When the server cannot ask PRIM, it gives the answer that it holds for the stop, if that answer is less than 5 minutes old.
Otherwise it answers `503`, with `{"status":"out","reason":...,"retryAt":...}` and `Retry-After`:

| `reason` | Why | `retryAt` |
|---|---|---|
| `budget` | The calls of this hour are spent. | The next hour that has calls left, or the next Paris day. |
| `prim-limit` | PRIM answered `429`. | 1 hour later. |
| `prim-failure` | PRIM failed for this stop. | 60 seconds later. |

It never gives an older answer, or a failed one, as times.
After `budget` or `prim-limit`, it adds 0 to 59 seconds to `retryAt`, from the stop, so that the apps of different stops do not all ask at the same second.

## The promise to the builds in the field

A rider updates the app when they choose, so a build can call the server for years after its upload, and it never changes.
So a server change keeps every build that riders may hold working: the server adds what a new build needs next to what the older ones read, and never swaps it.
The builds that riders may hold are the rows of a table in the [release guide](../../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx), section "The builds that riders may hold".

Each of them has a recorded set of promises in [`contracts/builds/`](../../contracts/builds/), one folder per set, written at its upload from the app code at its tag.
Its `promises.json` holds the request that the build sends (the path, the shapes of stop reference, the headers and the token scheme), how it reads each answer, how long it waits for one answer and how often it asks.
Its `prim/` folder holds its own copy of the PRIM answers that the server passes through, so that a new recording elsewhere changes nothing for it.

`make server-check` judges the server against every set, as the build reads each answer, in [`build-promises.test.ts`](../test/cloudflare/build-promises.test.ts):

- The PRIM answer must come back byte for byte, since the build parses it itself.
- Everything else is judged by what the build reads: the class of the status (any `2xx` is times), the headers that it reads and their exact form, the keys and values of the `out` answer, and the reasons that it knows.
  So a change that the build reads the same way passes: another retry time, another age of a held answer, another status that is not `2xx` for `out`.
- The longest wait of the server for PRIM, with room for the wake of a server object and for the phone, stays under the shortest wait of a build ([`wait-of-the-builds.test.ts`](../test/core/relay/wait-of-the-builds.test.ts)).

A set is never edited: [`build-promises-check.ts`](../scripts/build-promises-check.ts) compares each of its files with the version that git first recorded, and fails on any change or deletion.
Only a retirement frees a set: when every build of the set has the status **Retired on `<date>`: `<reason>`** in the table, its folder may change or go.
The check also fails when a build in the field has no set, or two.
Why: a set that a server change could edit to match itself would protect no rider, and editing the example to match the server is the easiest mistake to make.

When the check fails, change the server by adding: a new path, header or field next to the old one, which only the new builds read.
A situation that a set names and the test cannot yet bring about gets its scenario in `build-promises.test.ts`, never an edit of the set.

## Unreadable PRIM answers

Each build parses the PRIM answer itself, so a change of PRIM's format can make the builds in the field show no train while trains run, and the server still sends times.
To see it the same day, the server counts each PRIM answer with a `2xx` status that lacks the shape that the builds read ([`build-shape.ts`](../src/core/relay/build-shape.ts)):

- it has no service delivery (`Siri.ServiceDelivery`);
- it has no list of deliveries, or a delivery with no list of visits (`MonitoredStopVisit`) that is not an error of PRIM for the stop: the builds would show no train at every stop, while an empty list only says that no train comes;
- a field that the builds read has another type, so they cannot read the whole answer;
- it has visits, and none of them gives a line, a time and a destination.

One visit with no time or no destination is normal PRIM data, so it does not count.
The count is a number for each hour, with no stop and no answer: `unreadableAnswers` in the counts, `trome_unreadable_answers_total` and `trome_unreadable_answers_previous_day` in `/metrics`, and a line under the table of `make server-counts` for each day that has some.

When it is not 0:

1. Watch it for an hour: one unreadable answer can be a short fault of PRIM, but a count that grows with the PRIM calls is a change of format.
2. Ask PRIM for one stop with [your own key](../../ios/README.md#the-train-data-key-prim), as a Debug build does, and compare its answer with a recorded one of [`contracts/prim/`](../../contracts/prim/).
3. Record the new answer in `contracts/prim/`, and fix the parser of the app in a new build.
   The builds in the field keep their parser: until their riders update, only a server change can help them, and it changes by adding, as [the promise to the builds in the field](#the-promise-to-the-builds-in-the-field) says.

## How the server shares the PRIM quota

A PRIM key has a quota of 1,000 calls a day, from 00:00 UTC.
The server caps its calls lower, with `PRIM_DAILY_CAP` in `server/wrangler.jsonc`: 800 each Paris day for `trome-server`, and 60 for `trome-server-staging`, so that a test there cannot spend the calls of the riders.
The 1,000 calls are those of your PRIM key, and the staging Worker and an app built with the key (`make run LIVE=1`) use the same key: keep the caps within their shares of [the day of the PRIM key](#the-day-of-the-prim-key), not one of them at 990.
The server counts each call before it makes it, failed calls too, in its storage, so a restart does not reset it.
For each stop, one PRIM answer serves every rider, and the requests that come while a PRIM call is in flight wait for that one call.

The cap is shared among the 24 Paris hours, so that the morning peak cannot spend the calls of the evening, and what an hour does not spend goes to the next one.
The share of each hour, the day shape, follows when Paris rail riders enter a station: it is `dayShapePercents` in [`relay-settings.ts`](../src/core/config/relay-settings.ts), and [NOTICE.md](../../NOTICE.md#the-servers-day-shape) gives its source and its licence.
`make server-check` fails when an hour gets less than 0.5% (a lone rider at 03:00 must still get times), or when the hours from 00:00 to 02:00 get more than 5% or could push one PRIM day over 1,000 calls (the cap can then be at most 990).
With the staging cap, the hours before 06:00 in Paris have 2 calls in all, so test the staging Worker later in the day.

The other settings are in `relaySettings`, in the same file:

| Setting | Value | What it does |
|---|---|---|
| `freshAge` | 60 seconds | Every rider of a stop shares its answer, with no new PRIM call, until it is this old. |
| `agedAnswers` | 2 and 5 minutes | The age of that answer once the hour has spent over 70% and over 90% of its share. |
| `startAge`, `startReserve` | 10 minutes, 5% | The last 5% of each hour go to the stops with no answer younger than 10 minutes: a rider who starts has nothing yet. |
| `heldAge` | 5 minutes | The oldest answer that the server gives when it cannot ask PRIM. |
| `pauseAfterLimit` | 1 hour | No PRIM call for any stop after a `429`. |
| `pauseAfterFailure` | 60 seconds | No PRIM call for a stop after PRIM failed for it. |
| `retrySpread` | 60 seconds | The spread of `retryAt`. |
| `primTimeout` | 10 seconds | How long the server waits for PRIM. |

When you change a setting, change this page in the same commit; when you change the day shape, change its section in NOTICE.md too.

The cap of 800 serves about 50 to 60 riders who each start two Live Activities of about 10 minutes a day: [`relay-whole-day.test.ts`](../test/core/relay/relay-whole-day.test.ts) checks that 50 of them get times for more than 95 in 100 of their Live Activities.
The day shape counts every rider of the rail network: after two weeks of real use, replace it with the share of each hour in the app calls of `make server-counts FULL=1`, on days with few `out` answers, since an app that gets one asks again.

## The day of the PRIM key

The day of the PRIM key: the key has 1,000 calls a day, and PRIM counts its day in UTC.
Each user of the key has a share, and the shares add up to 990 at most.
When the key reaches 1,000 calls, PRIM answers 429, and the production server makes no PRIM call for 1 hour: every rider reads "Times unavailable".

| Who calls PRIM with the key | Calls a day | Who counts them |
|---|---|---|
| The production Worker | 800 | The production Worker (`PRIM_DAILY_CAP`; `make server-counts`) |
| The staging Worker | 60 | The staging Worker (its own `PRIM_DAILY_CAP`) |
| The Debug builds that hold the key (`make run LIVE=1`, your own tests on the Simulator and on your iPhone) | about 130, together | Nothing in the repo: they call PRIM directly. Only your account on the PRIM site shows the calls of the day, and it shows the calls of all the rows together. |
| Total of the shares | 990 at most | |
| Margin, up to the 1,000 calls of the key | 10 | The production Worker: its calls from 00:00 to 02:00 in Paris fall in the PRIM day before, and its day shape keeps them at 8 at most |

When you change a cap, change this table in the same commit, and keep the total of the shares at 990 or less.

## What the server keeps about riders

Nothing.
A request holds only a stop and the app token, and the server reads nothing else of it: no position, no device or account identifier, no push token, no IP address, no user agent, no body.
A test sends all of these, and checks that none is stored or logged.
After the request, the server keeps no stop in its storage or its log lines: the counts and the error lines have none.
Only its memory holds a stop, and only to serve the next requests: the stop of a PRIM call in flight, the latest answer of a stop for 10 minutes, and a stop whose PRIM call failed for its 60 s pause.
The server drops each one at its first request after that time, and Cloudflare empties the memory of an idle server within about 3 minutes after its last request.
