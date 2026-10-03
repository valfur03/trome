# The server

The paths on this page start from the root of the repo, where you run the `make` commands.

The folder `server/` holds the server of the app.
It holds the PRIM key, so that no build of the app that goes to another person holds it, and it counts and caps the PRIM calls of all riders in one place (decision-38 and decision-40 in the backlog).
It runs on Cloudflare Workers, on the Free plan, with one Durable Object (a small object with its own SQLite storage) that holds the answers and the counts.
A Release build of the app (TestFlight or the App Store) asks it for the trains.
A Debug build calls PRIM directly, with your own key (see [The train data key (PRIM)](../ios/README.md#the-train-data-key-prim)).

What the server does:

- `GET /v1/stops/{stopRef}/departures`, with the app token in the header `Authorization: Bearer <token>`, gives the next trains of one PRIM stop (`STIF:StopArea:SP:<number>:` or `STIF:StopPoint:Q:<number>:`).
  The body is the PRIM answer of that stop, as PRIM gave it, so the app keeps its own PRIM parser.
  The header `Last-Modified` is the time when PRIM gave it.
  The examples of each answer are in `contracts/api/`, and the server tests check them.
- One answer for each stop serves every rider: a stop asked again while its answer is younger than 60 s gets the same answer, with no PRIM call (older when the budget runs low, see below).
  The requests for a stop that come while its PRIM call is in flight wait for that one call.
- The cap: at most 800 PRIM calls each Paris day (`PRIM_DAILY_CAP` in `server/wrangler.jsonc`; 60 for the staging Worker, so that a test there cannot use the budget of the riders).
  The server adds to its count before each PRIM call, failed calls too, and keeps the count in its storage, so a restart does not reset it.
- The day shape: each Paris hour may spend its share of the day's cap, so that the morning peak cannot use up the evening peak.
  The shares follow the hours when Paris rail riders enter a station, which is when a Live Activity starts: 1.7% at 05:00, 4.3% at 06:00, 9.2% at 07:00, 10.2% at 08:00, 4.6% to 6.1% each hour from 09:00 to 15:00, 7% at 16:00, 8.5% at 17:00, 7.5% at 18:00, then less each hour down to 1.2% at 23:00.
  Each hour gets at least 0.5% (4 calls with the cap of 800), so that a lone rider at 03:00 still gets times: `make server-check` fails on a shape that gives an hour less.
  What an hour does not spend goes to the next hour.
  The hours from 00:00 to 02:00 in Paris may spend at most 5% of the cap together (8 calls with this shape), so that a PRIM day that starts at 00:00 UTC still holds less than 1,000 calls: `make server-check` fails on a shape that gives them more.
  For the same reason, the server refuses a cap that these hours of the next Paris day could take above 1,000 calls in one PRIM day (above 990 with this shape), and `make server-check` fails on such a cap in `server/wrangler.jsonc`.
  The 1,000 calls are those of your PRIM key, and the staging Worker and an app built with the key (`make run LIVE=1`) use the same key: keep the two caps together well under 1,000 (800 and 60 today), not one of them at 990.
  With the staging cap of 60, the hours before 03:00 in Paris have no call, and the hours before 06:00 have 2 calls in total: test the staging Worker later in the day.
  The shape is `dayShapePercents` in `server/src/core/config/relay-settings.ts`, and the ages below are in the same file.
  Its source: the open data of Île-de-France Mobilités, dataset "Validations sur le réseau ferré : Profils horaires par jour type (2ème trimestre 2026)" (`validations-sur-le-reseau-ferre-profils-horaires-par-jour-type-2eme-trimestre`, Licence Ouverte v2.0).
  [NOTICE.md](../NOTICE.md) gives the date of its last update, and says what you must do when you share the shape.
  It is the mean of the hourly percents of every rail stop (each stop counts the same), for a week of 5 weekdays out of the school holidays (`JOHV`), 1 Saturday (`SAHV`) and 1 Sunday (`DIJFP`), rounded to 0.1%.
  It counts every rider of the network, and our riders may start more at the peaks: after two weeks of real use, replace it with the share of each hour in the app calls of `make server-counts` (not its PRIM calls, which follow the shape itself), read on days with few out answers, since an app that gets an out answer asks again.
  When you change the shape, change its section in NOTICE.md in the same commit.
  With this shape, the cap of 800 serves about 60 riders (two Live Activities of about 10 minutes each a day) with fewer than 5 in 100 Live Activities left with no times at all on an average day, and about 50 riders if they start at the peaks as much as the first guess of the shape said (47% of the day from 07:00 to 10:00).
  These are means over 16 model days: with 60 riders, about 1 day in 3 passes 5 in 100, and the worst day leaves about 9 in 100 with no times.
- When the budget runs low, the shared answer gets older before the server asks PRIM again, so the times that a rider sees can come from a PRIM answer that is up to 2 or 5 minutes old.
  The answer may get 60 s old while the hour has spent up to 70% of its share, 120 s old above 70%, and 300 s old above 90%.
  The last 5% of the share of an hour go first to a stop that has no answer younger than 10 minutes (a rider who starts a Live Activity), and not to a stop that only refreshes its answer: a rider who waits for a refresh still has times that count down, and a rider who starts has nothing.
  When the share of the hour is gone, the server makes no PRIM call until the next hour.
- When the share of the hour is gone, for 1 hour after PRIM answers 429, or for 60 s after another PRIM failure of a stop, the server gives the answer that it holds for the stop if it is younger than 5 minutes.
  Otherwise it answers `503`, with `{"status":"out","reason":...,"retryAt":...}` and the header `Retry-After`: the time when it will ask PRIM again.
  When the share of the hour is gone (`"reason":"budget"`), this time is the start of the next hour that has calls left: the next hour, or the next Paris day once the day's cap is spent.
  After the share of the hour or a 429, this time is the same for every stop, so the server adds 0 to 59 seconds that depend on the stop and on that time: the apps of different stops do not all ask at the same second, the same stops do not ask last every hour, and the riders of one stop still ask together and share one call.
  It never gives an answer older than 5 minutes as times, and never keeps a failed answer or a PRIM error body as times.
- `GET /health` answers `{"status":"ok"}`, with no token.

What the server keeps about riders: nothing.
A request holds only a stop reference and the app token.
The server reads nothing else of it (no position, no device or account identifier, no push token, no IP address, no user agent, no body), and a test sends all of these and checks that none is stored or logged.

The server needs Node 24 LTS, like the docs (see [Run the site](../docs/README.md#run-the-site)): run `nvm use` in each new terminal before a server command.
If the active Node is too old, the server commands stop and tell you to run `nvm use`.

| Command | What it does |
|---|---|
| `make server-setup` | Installs the packages in `server/node_modules` (about 300 MB), when they are missing or older than `server/package-lock.json`. The other server commands run it first. |
| `make server-check` | The server quality gate: no local secrets file in git, the generated types up to date, the type check, the lint, the unit tests and the tests of the server scripts. It needs no Simulator and no Cloudflare account. |
| `make server-dev` | Runs the server on your Mac at `http://127.0.0.1:8787` (`/health` answers with no key). Only the main folder uses 8787. Each git worktree uses its own port: 8787 plus the number at the end of its folder name, or a port from 9800 to 9899 when its name ends with no number. `PORT=<n>` uses another port. Press Ctrl + C to stop it. |
| `make server-stop` | Stops the server of this folder, when it runs in the background. |
| `make server-login` | Logs in to your Cloudflare account, once on this Mac. It opens your default browser at once. Add `LINK=1` to log in with another browser: it opens no browser, and shows a link to open in the browser of your choice on this Mac. Add `CODE=1` instead to type a code on a Cloudflare page, in any browser, also on another device. |
| `make server-secrets` | Sets each secret of the production Worker, one after the other (see the table of the secrets below). Run it before the first deploy. It asks for each value, so no value is in your shell history or in a file. Add `STAGING=1` for the staging Worker. |
| `make server-secret NAME=<name>` | Changes one secret of the production Worker (for example a new app token). It asks for the value. Add `STAGING=1` for the staging Worker. |
| `make server-counts URL=<address>` | Shows the counts of the server at this address: today and the last 30 days. It asks for the owner token, so the token is not in your shell history. |
| `make server-deploy-staging` | Runs `make server-check`, then deploys this folder to the staging Worker `trome-server-staging`. It needs your Cloudflare account, and it refuses when a secret of the staging Worker is not set yet. |
| `make server-deploy` | Runs `make server-check`, then deploys `main` to the production Worker `trome-server`. It needs your Cloudflare account, and it refuses another branch, changes that are not committed, or a secret that is not set yet. |

`make check` runs `make server-check` only when your branch changes files in `server/` or `contracts/` (compared with `main`).
So a change of the app only does not install the packages of the server.

The secrets:

- The server has these secrets. `server/wrangler.jsonc` names them, with no value (`secrets.required`), and `make server-secrets` asks for each one of them.

  | Secret | Its value |
  |---|---|
  | `PRIM_API_KEY` | Your PRIM key (see [The train data key (PRIM)](../ios/README.md#the-train-data-key-prim)). |
  | `APP_TOKEN` | The token that the app sends, so that only the app can ask the server. Make a new one for each Worker with `openssl rand -hex 32`, and keep it in your password manager. It also goes in `ios/Config/Server.xcconfig` for the Release builds of the app (see [The train data key (PRIM)](../ios/README.md#the-train-data-key-prim)); in that file, `//` starts a comment, so a token made with `-base64` could be cut. |
  | `OWNER_TOKEN` | The token with which you read the counts of the server (`make server-counts`, below). The app never holds it. Make a new one for each Worker with `openssl rand -base64 32`, and keep it in your password manager. |

- On your Mac, `make server-dev` reads fake values from `server/.dev.vars`.
  The first `make server-dev` creates this file from `server/.dev.vars.example`, and a later one adds the names that the example has and the file does not have.
  Git ignores it, and `make server-check` fails when git tracks it.
  Keep fake values in it: the server on your Mac never needs the real key.
- On Cloudflare, the secrets are set with `make server-secrets` (or `make server-secret` for one) and live only there.
- **Never put a real secret in a file**, and never use `wrangler deploy --secrets-file`, even when wrangler suggests it: the real PRIM key must never be on disk.
- The logs of the server never show a secret: the logger replaces each secret value with `[secret]`, and a unit test checks it.

To put the server on Cloudflare (the first time):

Wrangler refuses the first deploy of a Worker whose secrets are not set yet, so set the secrets first, then deploy.

1. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up (no card).
2. In the main folder, run `nvm use`, then `make server-login`, and allow the access in the browser.
   It opens your default browser at once, and the login fails when you copy that page into another browser.
   To log in with another browser, run `make server-login LINK=1` instead: it opens no browser, and it shows a link.
   Copy the whole link into the browser of your choice on this Mac, log in to Cloudflare, and allow the access.
   You have 2 minutes: if it says "Timed out", log in to Cloudflare in that browser first, then run `make server-login LINK=1` again.
   Keep the terminal open until it says that you are logged in.
   If the login with the link fails, run `make server-login CODE=1`: open the address that it shows in any browser, log in, and type the code that it shows.
3. Run `make server-secrets STAGING=1`.
   For each secret of the table above, wrangler asks "Enter a secret value:": paste the value and press Return (the value does not show).
   After the first value, wrangler asks "There doesn't seem to be a Worker called "trome-server-staging". Do you want to create a new Worker with that name and add secrets to it?": answer `y` (yes).
   It creates an empty Worker that holds the secrets until the first deploy.
4. Run `make server-deploy-staging`. Wrangler shows the address of the staging Worker: `https://trome-server-staging.<your subdomain>.workers.dev`. If your account has no `workers.dev` subdomain yet, the first deploy asks you to choose one.
5. Open `https://trome-server-staging.<your subdomain>.workers.dev/health`. It shows `{"status":"ok"}`.
6. For production, in the main folder on `main`: run `make server-secrets` (with other tokens), answer `y` to the same question for "trome-server", then run `make server-deploy`, and open its `/health` address.

When a new secret is added to the table later, run `make server-secret NAME=<its name>` for each Worker that already exists (add `STAGING=1` for the staging Worker), before you deploy the change.
`make server-deploy-staging` and `make server-deploy` check the secrets before they deploy: when one is missing, they stop, name it, and say which command sets it.

The counts, for you:

- Run `make server-counts URL=https://trome-server.<your subdomain>.workers.dev` and paste the owner token.
  It shows the counts as JSON: the cap and the PRIM calls of today, then each Paris day of the last 30 days, newest first.
  Each day has its app calls, cache hits (an answer shared with no PRIM call), held answers (an older answer given while the server could not ask PRIM), out answers, PRIM calls and errors, then the same for each hour (`parisHour`), and the PRIM calls of each stop.
  `errorLines` lists the failed PRIM calls of the last 7 days: the time, the stop, the kind and the HTTP status, with no IP.
- The server writes the counts of app calls and cache hits at most every 30 s, not at each request, to stay far below the 100,000 rows that the Free plan lets it write each day.
- Cloudflare keeps no request log of the server: Workers Logs are off in `server/wrangler.jsonc` (`"observability": { "enabled": false }`), for both Workers.
  Turn them on only to find a problem, and then for 3 days at most (the Free plan keeps them 3 days).
  `npx wrangler tail` in `server/` shows the log lines live, and keeps none of them.

The CPU time of a request is small next to the limits of the Free plan (10 ms for the Worker, 30 s for the Durable Object): `npm run bench` in `server/` measures it.

The code of the server follows the rules of the CLAUDE.md, section "Code structure of the server": the logic is plain TypeScript in `server/src/core/`, and only `server/src/cloudflare/` uses the Cloudflare API.
So the server can move to another host with a medium task (decision-40).
