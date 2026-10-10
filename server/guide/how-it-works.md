# How the server works

The server keeps the key of PRIM, the train data service of Île-de-France Mobilités, out of the app, and shares one daily quota of PRIM calls among all riders.
This page is for a developer who changes it: what it answers, how it spends the quota, and what it keeps; [server/README.md](../README.md) shows how to run and test it.

## The API

Each address answers `GET` and `HEAD` only, and the tokens go in the header `Authorization: Bearer <token>`.

| Request | Token | Answer |
|---|---|---|
| `GET /health` | none | `{"status":"ok"}` |
| `GET /v1/stops/{stopRef}/departures` | the app token, which each copy of the app holds | The PRIM answer of that stop, as PRIM gave it, so that the app keeps its own PRIM parser; `Last-Modified` is the time when PRIM gave it. |
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
