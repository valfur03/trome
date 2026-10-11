# Deploy the server

This page is for the maintainer, who holds the Cloudflare account of the server and its secrets: a contributor needs none of it, and starts at [server/README.md](../README.md).
It shows how to deploy the server, set its secrets, connect the app to it, read its counts of requests and PRIM calls, and find a problem without keeping the stops of riders.
Run the commands from the root of the repo, with Node 24 active ([server/README.md](../README.md)).

| Command | What it does |
|---|---|
| `make server-login` | Logs in to your Cloudflare account, once on this Mac. |
| `make server-secrets` | Sets each secret of the production Worker, `trome-server`, asking for each value, so that none is in your shell history or in a file. |
| `make server-secret NAME=<name>` | Changes one secret, at once, with no new deploy. |
| `make server-deploy-staging` | Runs `make server-check`, then deploys your folder, also changes that are not committed, to the staging Worker, `trome-server-staging`. |
| `make server-deploy` | Runs `make server-check`, then deploys `main` to the production Worker. It refuses another branch and changes that are not committed. |
| `make server-counts URL=<address>` | Shows the requests and the PRIM calls of the server, a line per day of the last 14 days (`FULL=1`: the whole report), and asks for the owner token. |

Add `STAGING=1` to `make server-secrets` or `make server-secret` for the staging Worker.
Both deploy commands stop when a secret of their Worker is not set, and say which command sets it.

## The secrets

`server/wrangler.jsonc` names the secrets, with no value, and they live only on Cloudflare:

| Secret | Its value |
|---|---|
| `PRIM_API_KEY` | Your PRIM key ([how to get one](../../ios/README.md#the-train-data-key-prim)). |
| `APP_TOKEN` | A new token for each Worker, made with `openssl rand -hex 32` (not `-base64`: in `ios/Config/Server.xcconfig`, where the app reads it, `//` starts a comment). The server answers only requests that carry it. It keeps casual traffic out, but anyone who takes the app apart can read it: the daily cap of PRIM calls is what protects the quota of the key ([How the server works](how-it-works.md#how-the-server-shares-the-prim-quota)). |
| `OWNER_TOKEN` | A new token for each Worker, made with `openssl rand -base64 32`, to read the counts. The app never holds it. |

Keep the tokens in your password manager.
Never put a secret of the server in a file, and never use `wrangler deploy --secrets-file`, even when wrangler suggests it.
The one exception is the app token, which a Release build of the app must hold ([Connect the app](#connect-the-app-to-the-server)).
The logs of the server replace each secret with `[secret]`.
When a new secret joins the table, set it with `make server-secret` on each Worker before you deploy the change.

## Deploy for the first time

1. Have your PRIM key ready, and make an app token and an owner token for the staging Worker.
2. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up, with no card.
3. Run `make server-login`, and allow the access in the browser that it opens.
   To log in with another browser, run `make server-login LINK=1` and open the link that it shows on this Mac, within 2 minutes; or run `make server-login CODE=1`, and type its code on any device.
4. Run `make server-secrets STAGING=1`, and paste each value that it names.
   After the first one, answer `y` when wrangler asks whether to create the Worker "trome-server-staging".
5. Run `make server-deploy-staging`, and note the address that wrangler shows, `https://trome-server-staging.<your subdomain>.workers.dev` (it asks you to choose a subdomain the first time).
6. Open that address with `/health`: it shows `{"status":"ok"}`.
   Then check the PRIM key with one stop, which costs one PRIM call; the answer has times:

   ```sh
   curl -H "Authorization: Bearer <app token>" "https://trome-server-staging.<your subdomain>.workers.dev/v1/stops/STIF:StopArea:SP:42155:/departures"
   ```

7. For production, run `make server-secrets` with other tokens, answer `y` for "trome-server", then run `make server-deploy` in the main folder of your clone, on `main`, and check it in the same way.

## Connect the app to the server

A Release build of the app reads the server from `ios/Config/Server.xcconfig`, a copy of `ios/Config/Server.example.xcconfig` that git ignores.
Put the host of the production Worker in `TRAIN_SERVER_HOST`, with no `https://`, and its app token in `TRAIN_SERVER_APP_TOKEN`.
Then run `make release-server-check` in the main folder of your clone: it asks the production Worker once for the trains of one stop, and says in one line, with neither value in it, whether the Worker accepts them.

## Change the app token

The server takes one app token at a time, and every installed app holds the old one.
So a new token cuts off every installed app until its rider installs a version with the new token: change it only when the old one leaked.
[The release guide lists the builds that riders may hold](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#the-builds-that-riders-may-hold): a server change keeps each of them working.
Then set the new one with `make server-secret NAME=APP_TOKEN`, put it in `ios/Config/Server.xcconfig`, check it with `make release-server-check`, and release a new version of the app.

An installed app with the old token then shows **Update the app**, with an orange icon, in place of the times on its Live Activity and its main screen ([each state of the Live Activity](../../ios/guide/live-activity.md#when-it-cannot-show-times)).
Updating is all that its rider can do, so release the new version as close as you can to the change of the token.
That app asks the server again only when its rider opens it or a new Live Activity starts, so the old apps do not call in a loop.

## Read the counts

```sh
make server-counts URL=https://trome-server.<your subdomain>.workers.dev
```

Paste the owner token when it asks.
It shows a table: today so far, then each Paris day of the last 14 days, newest first, with its app calls, PRIM calls, `out` answers, errors, and the Paris hour with the most app calls.
A day with no call is a line of zeros.
When the server keeps no total from 14 days ago, the table starts at its oldest day, and says so.
App calls are the requests for times with the right app token: a wrong token, `/health` and this read do not count.

Add `FULL=1` for the whole report, as JSON: the cap and the PRIM calls of today, then each Paris day of the last 30 days, with its app calls, cache hits, held answers, `out` answers, PRIM calls and errors, hour by hour (`parisHour`), with no stop.
Its `errorLines` lists the failed PRIM calls of the last 7 days: the time, the kind and the HTTP status, with no stop and no IP address.
The counts of app calls and cache hits are written at most every 30 seconds, to stay far below the writes that the Free plan allows each day.

## Send the totals to your Prometheus

The server also gives its totals at `GET /metrics`, in the Prometheus text format, to the owner token, so that your own Prometheus keeps them longer than the server's 30 days.
The token reads only totals, with no stop and no identifier: a leaked token shows numbers and nothing about riders.
Prometheus only makes outgoing calls, so nothing opens at your home.

1. Put the owner token, alone on one line, in a file that your secret store writes on the Prometheus host, for example `/run/secrets/trome_owner_token`: never in `prometheus.yml` or in git.
   The user that runs Prometheus must be able to read this file: it is `nobody` (user 65534) in the `prom/prometheus` image.
   A Docker Compose secret (`file:`) keeps the owner and the mode of the host file, so a file that only root can read makes the job `DOWN` with a permission error on the credentials file.
   Give the file to that user and keep it private to it: `sudo chown 65534:65534 /run/secrets/trome_owner_token`, then `sudo chmod 400 /run/secrets/trome_owner_token`.
2. Mount that file in the Prometheus container, at the same path.
3. Add this job under `scrape_configs:` in `prometheus.yml`:

   ```yaml
   - job_name: trome
     scheme: https
     scrape_interval: 2m
     static_configs:
       - targets: ["trome-server.<your subdomain>.workers.dev"]
     authorization:
       credentials_file: /run/secrets/trome_owner_token
   ```

4. Add `--storage.tsdb.retention.time=395d` to the command of Prometheus: 13 months, as its default of 15 days is shorter than the server's 30 days.
5. Recreate Prometheus, so that it takes the new mount, flag and job: with Docker Compose, run `docker compose up -d`, with `--build` when your image copies `prometheus.yml`.
   `docker compose restart` applies neither the new mount nor the new flag, and it does not rebuild an image.
   Then open its Targets page: the `trome` job shows `UP`.
6. Query `trome_app_calls_previous_day`: it gives the app calls of yesterday, the same as yesterday's line of `make server-counts`.

Use 2 minutes: on a day where every PRIM call fails, one scrape a minute would read about a quarter of the SQLite rows that the Free plan allows each day, and beyond about 5 minutes Prometheus draws gaps.
The `_total` counters count since 00:00 in Paris and start again from 0 there, which `rate()` and `increase()` read as a restart; the `_previous_day` gauges give each whole Paris day exactly.
To cut the access, give the server a new owner token with `make server-secret NAME=OWNER_TOKEN`, then write it in your file.
The Metrics page of the Worker in the Cloudflare dashboard is a free extra: it counts every request, refused ones and these scrapes too, so it is never the source of the totals.

## Measure the time of a call

```sh
make release-server-timing
```

Run it in the main folder of your clone, which holds `ios/Config/Server.xcconfig` ([Connect the app to the server](#connect-the-app-to-the-server)).
It asks the production Worker for the trains of one stop as a rider who opens it and waits 30 seconds, each call on a new connection, and prints neither the host nor the token.
It makes at most 2 PRIM calls, as that rider would: one for the first call, and one 30 seconds later if the server forgot its answer.
It prints a line per call, with the Cloudflare data center that answered, then the parts of a call:

| Part | How it is measured |
|---|---|
| The connection to Cloudflare | DNS, TCP and TLS, which the app pays only on a new connection |
| The Worker alone | The wait for `/health`, which never reaches the server object: one network round trip and the Worker |
| The hop to the server object | The wait for a held answer, minus the wait for `/health` |
| The wait for PRIM | The first call, when it made the server ask PRIM, minus the wait for a held answer; it also holds the wake of a server object that slept, which no other call can split |

Run it once after a quiet time, when no app has asked the server for 5 minutes, for the first call of a rider; then at once again, for a warm server.
Its last lines say whether the server still held its answer 30 seconds later: when it forgot it, each refresh of the app costs a PRIM call.
Each call also pays the network of the computer that runs it: run it on the network that your riders use, for example your phone's connection shared with the computer.

## Find a problem

The app promises that the server keeps no stop of a rider: its App Store privacy label says "Data Not Collected", and its privacy policy says the same.
So Workers Logs, the logs that Cloudflare keeps for you, stay off on each Worker of the server: `server/wrangler.jsonc` sets `"observability": { "enabled": false }` for both.

With Workers Logs on, Cloudflare keeps a log of each request for 3 days on the Free plan, 7 days on a paid plan.
That log holds the request URL, so the stop (`/v1/stops/<stop>/departures`), and the metadata of the request, such as the country and the city that Cloudflare finds for it.
Turning off only that log (`"invocation_logs": false`) is not enough: Cloudflare still gives each line that the server writes the URL of its request.
**If you turn Workers Logs on, the App Store label and the privacy policy are false for each day that Cloudflare keeps them, for every rider of those days: so never turn them on, not even to find a problem.**
Never turn them on in the Cloudflare dashboard either, on the Observability page of a Worker.
`make server-check`, and so both deploy commands, fails when `server/wrangler.jsonc` turns on Workers Logs, traces, an export of them to another service, Logpush or a Tail Worker, as each of them keeps or sends the request URL.

To find a problem, use these ways, which keep nothing at Cloudflare:

- `make server-counts FULL=1` and its `errorLines` ([Read the counts](#read-the-counts)): the failed PRIM calls of the last 7 days, with their time, kind and HTTP status.
- `npx wrangler tail` in `server/` (`npx wrangler tail --env staging` for the staging Worker), after `make server-login`: it shows each request and the lines of the server live, and Cloudflare keeps none of it.
  It shows the request URL, so the stop, on your screen: never save its output in a file, and stop it as soon as you have seen the problem.
- A test that makes the failure again: the tests fake PRIM with recorded answers (`contracts/prim/`), so a new test can play the answer that failed, with no rider and no PRIM call ([server/README.md](../README.md)).
