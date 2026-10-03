# Run, test and deploy the server

The server stands between the app and PRIM, the train data service of Île-de-France Mobilités.
It holds the PRIM key, so that no copy of the app holds it, and it shares one daily quota of PRIM calls among all riders.
This page shows how to run and test it on your Mac, which needs no account, then how the maintainer deploys it to Cloudflare.
To change the iPhone app instead, see [ios/README.md](../ios/README.md); to propose a change, see [CONTRIBUTING.md](../CONTRIBUTING.md).
Run every `make` command from the root of the repo; the paths on this page start there too.

## What the server does

A Release build of the app, from TestFlight or the App Store, asks the server for the next trains of a stop.
A Debug build, such as the one of `make run`, calls PRIM directly with your own key ([The train data key (PRIM)](../ios/README.md#the-train-data-key-prim)).

The server runs on Cloudflare Workers, on the Free plan.
One Durable Object, a small object with its own SQLite storage, holds the PRIM answers and the counts.
For each stop, one PRIM answer serves every rider: a stop that riders ask for again within 60 seconds, or longer when the calls of the hour run low ([How the server shares the PRIM quota](#how-the-server-shares-the-prim-quota)), costs no new PRIM call, and the requests that come while a PRIM call is in flight wait for that one call.

It keeps nothing about riders.
A request holds only a stop and the app token, and the server reads nothing else of it: no position, no identifier of a device or an account, no push token, no IP address, no user agent, no body.
A test sends all of these, and checks that none is stored or logged.

## Run and test it on your Mac

The server needs Node 24, the version in [`.nvmrc`](../.nvmrc).
Install it once with [nvm](https://github.com/nvm-sh/nvm), then run `nvm use` in each new terminal before a server command:

```sh
nvm install
nvm use
```

When the active Node is too old, the server commands stop and tell you so.

| Command | What it does |
|---|---|
| `make server-check` | Runs every check of the server: no secrets file in git, the generated types up to date, the type check, the lint, the unit tests and the tests of the server scripts. |
| `make server-dev` | Runs the server on your Mac, at the address that it prints. |
| `make server-stop` | Stops the server of this folder when it runs in the background; in a terminal, press Ctrl + C instead. |
| `make server-setup` | Installs the packages in `server/node_modules`, about 300 MB, when they are missing or older than `server/package-lock.json`. The other server commands run it first. |

`make check` runs `make server-check` too, but only when your branch changes a file in `server/` or `contracts/`, so a change to the app alone never installs the packages of the server.

`make server-dev` serves at `http://127.0.0.1:8787` in the main folder of your clone.
In a git worktree, it picks another port, so that two worktrees can each run one; add `PORT=<n>` to choose the port.
To check that it runs, open its `/health` address: it answers `{"status":"ok"}`.

The server on your Mac reads fake secrets from `server/.dev.vars`.
The first `make server-dev` creates this file from `server/.dev.vars.example`, and a later one adds the names that the example has and the file does not.
Git ignores it, and `make server-check` fails when git tracks it.
Keep fake values in it: the server on your Mac never needs the real key.
But a request for the trains of a stop, with the app token of this file, makes it call the real PRIM with the fake key, which only gives an error.
So check the answers for trains in the unit tests, which fake PRIM.

### Where the code and the tests go

The logic is plain TypeScript in `server/src/core/`, and only `server/src/cloudflare/` uses the Cloudflare API: the entry of the Worker (`worker.ts`), the Durable Object, and the adapters.
So `core/` runs on Node, and the server can move to another host without a rewrite.
[CLAUDE.md](../CLAUDE.md#code-structure-of-the-server), the manual of the coding assistant that builds TROME, gives the rules of this structure, and they hold for every change.

- `server/test/core/<feature>/` holds the tests of the logic, which run on Node with a fake clock and a real SQLite database.
  The feature folders have the same names as in `server/src/core/`: `auth`, `budget`, `config`, `http`, `logging`, `relay`, `storage`, `time` and `usage`.
- `server/test/cloudflare/` holds the tests of the Worker and the Durable Object, which run in the Cloudflare runtime.
- `server/scripts/tests/` holds the tests of the server scripts.

The tests read the recorded PRIM answers of `contracts/prim/`, which the tests of the app read too.
The examples of each answer of the server are in `contracts/api/`, and a test checks the server against them.
No test calls the real PRIM.

To run the tests of one folder while you work, use Vitest in `server/`, for example `cd server && npx vitest run test/core/relay`.

`npm run bench`, in `server/`, measures the processor time of a request.
It is small next to the limits of the Free plan: 10 ms for the Worker, 30 seconds for the Durable Object.

## The API

Each address answers `GET` and `HEAD` only.

| Request | Token | Answer |
|---|---|---|
| `GET /health` | none | `{"status":"ok"}` |
| `GET /v1/stops/{stopRef}/departures` | the app token, in the header `Authorization: Bearer <token>` | The PRIM answer of that stop, as PRIM gave it, so that the app keeps its own PRIM parser. The header `Last-Modified` is the time when PRIM gave it. |
| `GET /v1/owner/counts` | the owner token, in the same header | The counts of the server ([Read the counts](#read-the-counts-and-the-logs)). |

`{stopRef}` is a PRIM stop: `STIF:StopArea:SP:<number>:` or `STIF:StopPoint:Q:<number>:`.
A request with no token or a wrong one gets `401`, and a stop that is not a PRIM stop gets `400`.

When the server has no times to give, it answers `503`, with `{"status":"out","reason":...,"retryAt":...}` and the header `Retry-After`: the time when it will ask PRIM again.
The reason is one of these:

| `reason` | Why | `retryAt` |
|---|---|---|
| `budget` | The calls of this hour are spent. | The start of the next hour that has calls left, or of the next Paris day once the day's cap is spent. |
| `prim-limit` | PRIM answered `429`, too many requests. | 1 hour after that answer. |
| `prim-failure` | PRIM gave an error or no answer for this stop. | 60 seconds after the failure. |

Before it answers `503`, the server gives the answer that it holds for the stop when that answer is younger than 5 minutes.
It never gives an older answer as times, and never keeps a failed answer or an error of PRIM as times.
After `budget` or `prim-limit`, the server adds 0 to 59 seconds to `retryAt`, chosen from the stop and that time.
So the apps of different stops do not all ask at the same second, while the riders of one stop still ask together and share one call.

## How the server shares the PRIM quota

A PRIM key has a quota of 1,000 calls a day, counted from 00:00 UTC.
The server caps its own calls lower, in each Worker's `PRIM_DAILY_CAP` in `server/wrangler.jsonc`:

| Worker | Cap of PRIM calls each Paris day |
|---|---|
| `trome-server`, production | 800 |
| `trome-server-staging` | 60, so that a test there cannot spend the calls of the riders |

When the staging Worker and `make run LIVE=1` use the same PRIM key as production, all their calls count in its quota, so keep the two caps together well under 1,000, with room for the calls of `make run LIVE=1`, which no cap limits.
The server counts each call before it makes it, failed calls too, and keeps the count in its storage, so a restart does not reset it.

The cap of a day is shared among its 24 Paris hours, so that the morning peak cannot spend the calls of the evening.
The share of each hour, the day shape, follows the hours when Paris rail riders enter a station, which is when a Live Activity starts.
It is `dayShapePercents` in [`server/src/core/config/relay-settings.ts`](src/core/config/relay-settings.ts), with the other settings of this section, and [NOTICE.md](../NOTICE.md#the-servers-day-shape) gives its source and its licence.
What an hour does not spend goes to the next hour.
`make server-check` fails on a shape or a cap that breaks these rules:

- Each hour gets at least 0.5% of the cap, so that a lone rider at 03:00 still gets times.
- The hours from 00:00 to 02:00 in Paris get at most 5% together, because they fall in the PRIM day that started at 00:00 UTC.
  For the same reason, the cap and these hours of the next Paris day must stay under 1,000 calls in one PRIM day: with this shape, the cap can be at most 990.

With the staging cap of 60, the hours before 03:00 in Paris have no call, and the hours before 06:00 have 2 calls in all, so test the staging Worker later in the day.

When the calls of an hour run low, the server lets its answers get older before it asks PRIM again:

| Share of the hour already spent | Age of an answer before a new PRIM call |
|---|---|
| up to 70% | 60 seconds |
| over 70% | 2 minutes |
| over 90% | 5 minutes |

The last 5% of the share of an hour go first to a stop with no answer younger than 10 minutes: a rider who starts a Live Activity has nothing yet, while a rider who waits for a refresh still has times that count down.
When the share of the hour is gone, the server makes no PRIM call until the next hour.

Each of these times is one setting of `relaySettings` in `relay-settings.ts`:

| Setting | Value | What it is |
|---|---|---|
| `freshAge` | 60 seconds | The age of an answer that every rider shares, with no PRIM call. |
| `agedAnswers` | 2 and 5 minutes | The older ages, past 70% and 90% of the share of the hour. |
| `startAge` | 10 minutes | A stop with no answer younger than this gets the last calls of the hour. |
| `startReserve` | 5% | The part of the share of each hour kept for those stops. |
| `heldAge` | 5 minutes | The oldest answer that the server gives when it cannot ask PRIM. |
| `pauseAfterLimit` | 1 hour | The pause of every stop after PRIM answers `429`. |
| `pauseAfterFailure` | 60 seconds | The pause of one stop after PRIM fails for it. |
| `retrySpread` | 60 seconds | The spread of `retryAt`, from 0 to 59 seconds. |
| `primTimeout` | 10 seconds | How long the server waits for PRIM. |

When you change one of them, change this page in the same commit.

With this shape, the cap of 800 serves about 50 to 60 riders who each start two Live Activities of about 10 minutes a day.
A test of a model day, `server/test/core/relay/relay-whole-day.test.ts`, checks that 50 such riders get times for more than 95 in 100 of their Live Activities.
The shape counts every rider of the rail network, not the riders of TROME.
After two weeks of real use, replace it with the share of each hour in the app calls of `make server-counts`, read on days with few `out` answers, because an app that gets an `out` answer asks again.
When you change the shape, change its section in NOTICE.md in the same commit.

## Deploy the server to Cloudflare

The steps of this section need the Cloudflare account of the server and its secrets.

| Command | What it does |
|---|---|
| `make server-login` | Logs in to your Cloudflare account, once on this Mac. |
| `make server-secrets` | Sets each secret of the production Worker in turn, asking for each value, so that no value is in your shell history or in a file. Add `STAGING=1` for the staging Worker. |
| `make server-secret NAME=<name>` | Changes one secret, for example a new app token. Add `STAGING=1` for the staging Worker. |
| `make server-deploy-staging` | Runs `make server-check`, then deploys this folder to the staging Worker, `trome-server-staging`. |
| `make server-deploy` | Runs `make server-check`, then deploys `main` to the production Worker, `trome-server`. It refuses another branch and changes that are not committed. |
| `make server-counts URL=<address>` | Shows the counts of the server at this address, and asks for the owner token. |

Both deploy commands stop when a secret of their Worker is not set yet, name it, and say which command sets it.

### The secrets

`server/wrangler.jsonc` names the secrets, with no value, and they live only on Cloudflare:

| Secret | Its value |
|---|---|
| `PRIM_API_KEY` | Your PRIM key ([how to get one](../ios/README.md#the-train-data-key-prim)). |
| `APP_TOKEN` | The token that the app sends, so that the server answers only requests that carry it. It keeps casual traffic out, but anyone who takes the app apart can read it: the cap is what protects the quota. Make a new one for each Worker with `openssl rand -hex 32`, and keep it in your password manager. Use `-hex`: the app reads it from a file where `//` starts a comment, so a token made with `-base64` could be cut. |
| `OWNER_TOKEN` | The token with which you read the counts. The app never holds it. Make a new one for each Worker with `openssl rand -base64 32`, and keep it in your password manager. |

Never put a real secret of the server in a file, and never use `wrangler deploy --secrets-file`, even when wrangler suggests it: the real PRIM key must never be on disk.
The one exception is the app token, which a Release build of the app must hold: it goes in `ios/Config/Server.xcconfig`, which git ignores ([Connect the app to the server](#connect-the-app-to-the-server)).
The logs of the server never show a secret either: the logger replaces each secret value with `[secret]`, and a unit test checks it.

`make server-secret` applies the new value at once, with no new deploy.
When a new secret joins the table, run `make server-secret NAME=<its name>` for each Worker that already exists (with `STAGING=1` for the staging Worker), before you deploy the change.

### Deploy for the first time

Wrangler refuses the first deploy of a Worker whose secrets are not set, so set the secrets first.

1. Have the three values ready: your PRIM key, and a new app token and owner token for the staging Worker, made with the commands of [the secrets](#the-secrets).
2. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up, with no card.
3. Run `nvm use`, then `make server-login`, and allow the access in the browser that it opens.
   The login works only in that browser: to use another one, run `make server-login LINK=1`, which opens no browser and shows a link.
   Copy the whole link into the browser of your choice on this Mac, log in to Cloudflare, and allow the access within 2 minutes.
   If it says "Timed out", log in to Cloudflare in that browser first, then run the command again.
   If the link fails, run `make server-login CODE=1`: open the address that it shows in any browser, on any device, log in, and type the code that it shows.
   Keep the terminal open until it says that you are logged in.
4. Run `make server-secrets STAGING=1`.
   It names each secret before wrangler asks "Enter a secret value:": paste that value and press Return (the value does not show).
   After the first value, wrangler asks whether to create a new Worker called "trome-server-staging": answer `y`.
   It creates an empty Worker that holds the secrets until the first deploy.
5. Run `make server-deploy-staging`. It deploys the files of your folder, also changes that are not committed.
   Wrangler shows the address of the staging Worker, `https://trome-server-staging.<your subdomain>.workers.dev`; if your account has no `workers.dev` subdomain yet, it asks you to choose one first.
6. Open `https://trome-server-staging.<your subdomain>.workers.dev/health`: it shows `{"status":"ok"}`.
   This proves that the Worker runs, but not that the PRIM key works: ask for the trains of one stop, which costs one PRIM call, and check that the answer has times:

   ```sh
   curl -H "Authorization: Bearer <app token>" "https://trome-server-staging.<your subdomain>.workers.dev/v1/stops/STIF:StopArea:SP:42155:/departures"
   ```

7. For production, run `make server-secrets` with other tokens, answer `y` to the same question for "trome-server", then run `make server-deploy` in the main folder of your clone, on `main`, with nothing left to commit, and check its `/health` address and one stop in the same way.

### Connect the app to the server

A Release build of the app reads the address and the app token of the server from `ios/Config/Server.xcconfig`, a copy of `ios/Config/Server.example.xcconfig` that git ignores.
Put the host of the production Worker in `TRAIN_SERVER_HOST`, with no `https://`, and its app token in `TRAIN_SERVER_APP_TOKEN`.
[The train data key (PRIM)](../ios/README.md#the-train-data-key-prim) says how the app uses them.

### Change the app token

The server takes one app token at a time, and every installed app holds the old one.
So a new token cuts off every installed app until its rider installs a version with the new token: change it only when the old one leaked.
Then make a new one, set it with `make server-secret NAME=APP_TOKEN`, put it in `ios/Config/Server.xcconfig`, and release a new version of the app.

## Read the counts and the logs

```sh
make server-counts URL=https://trome-server.<your subdomain>.workers.dev
```

Paste the owner token when it asks.
It shows the counts as JSON: the cap and the PRIM calls of today, then each Paris day of the last 30 days, newest first.
Each day has its app calls, its cache hits (an answer shared with no PRIM call), its held answers (an older answer given while the server could not ask PRIM), its `out` answers, its PRIM calls and errors, then the same for each hour (`parisHour`), and the PRIM calls of each stop.
`errorLines` lists the failed PRIM calls of the last 7 days: the time, the stop, the kind and the HTTP status, with no IP address.
The server writes the counts of app calls and cache hits at most every 30 seconds, not at each request, to stay far below the 100,000 rows a day that the Free plan lets it write.

Cloudflare keeps no request log of the server: Workers Logs are off for both Workers (`"observability": { "enabled": false }` in `server/wrangler.jsonc`).
Turn them on only to find a problem, by setting `enabled` to `true` there and deploying, and then for 3 days at most, which is how long the Free plan keeps them.
To watch the log lines live, without keeping them, run `npx wrangler tail` in `server/`.
