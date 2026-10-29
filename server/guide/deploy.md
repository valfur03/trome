# Deploy the server

This page is for the maintainer, who holds the Cloudflare account of the server and its secrets: a contributor needs none of it, and starts at [server/README.md](../README.md).
It shows how the server is deployed, set its secrets, connect the app to it, read its counts of requests and PRIM calls, find a problem without keeping the stops of riders, and keep the address that every build of the app holds.
Run the commands from the root of the repo, with Node 24 active ([server/README.md](../README.md)).

| Command | What it does |
|---|---|
| `make server-login` | Logs in to your Cloudflare account, once on this Mac. |
| `make server-secrets` | Sets each secret of the production Worker, `trome-server`, asking for each value, so that none is in your shell history or in a file. |
| `make server-secret NAME=<name>` | Changes one secret, at once, with no new deploy. |
| `make server-deploy-staging` | Runs `make server-check`, then deploys your folder, also changes that are not committed, to the staging Worker, `trome-server-staging`. A push to `main` also deploys it ([How a deploy happens](#how-a-deploy-happens)). |
| `make server-deploy` | Runs `make server-check`, then deploys `main` to the production Worker. It refuses another branch and changes that are not committed. |
| `make server-counts URL=<address>` | Shows the requests and the PRIM calls of the server, a line per day of the last 14 days (`FULL=1`: the whole report), and asks for the owner token. |

Add `STAGING=1` to `make server-secrets` or `make server-secret` for the staging Worker.
Both deploy commands stop when a secret of their Worker is not set, and say which command sets it.

## How a deploy happens

A push to `main` that changes `server/`, `contracts/` or the station list of the app, which the server bundles, starts the GitHub workflow **Server deploy** (`.github/workflows/server-deploy.yml`), and nobody types a command:

1. It runs `make server-check` on that commit.
2. It deploys the commit to the staging Worker, with the commit as the tag and the message of the new version, which the Worker's **Deployments** page of the Cloudflare dashboard shows.
3. It checks that staging answers: `/health`, then the trains of one stop with the staging app token, which costs at most one PRIM call of the staging cap.

A push that changes neither starts nothing.
The production Worker is still deployed by hand, with `make server-deploy`.

Before the deploy, the run refuses, and deploys nothing:

- when `main` has moved on to a commit that changes one of them: the run of that newer commit deploys it, so an old run never puts older code back;
- when a secret that `server/wrangler.jsonc` requires is not set on the staging Worker: the run names it.

When a run is red, its failed step says why:

- **A secret is not set**: set it with `make server-secret NAME=<name> STAGING=1`, then open the run on GitHub and press **Re-run failed jobs**.
- **wrangler aborts because of conflicts**: someone changed a setting of the Worker in the Cloudflare dashboard, and the run never overrides it with no person to answer.
  Put the setting in `server/wrangler.jsonc`, or undo it in the dashboard, then re-run.
- **The check of staging failed**: the step says which check, and the HTTP status of the answer.
  The new version is live on staging: fix it with a new commit on `main`.

To deploy `main` to staging again with no new commit, open **Actions** > **Server deploy** > **Run workflow** on GitHub, on `main`.
Only a person with write access to the repo can start it.

### The staging token

The run deploys with a Cloudflare **Account API token** with the role **Editor** on the one Worker `trome-server-staging`: it may edit and deploy that Worker only, and cannot create or delete a Worker.
When Cloudflare refuses one Worker, the fallback is the role **Editor** on the Workers product, and then a leak of the token also lets someone deploy the production Worker, `trome-server`.
It has no expiry, so revoking it is the only answer to a leak.
It lives in the GitHub environment `server-staging`, whose branch rule lets only `main` read it, with no reviewer:

| Secret of `server-staging` | Its value |
|---|---|
| `CLOUDFLARE_API_TOKEN` | The token. |
| `CLOUDFLARE_ACCOUNT_ID` | The account ID: in the Cloudflare dashboard, **Workers & Pages**, then the copy button next to **Account ID**. It is a secret, not a variable, so that the public log of a run hides it. |
| `STAGING_APP_TOKEN` | One token of the `APP_TOKEN` list of the staging Worker, for the check of step 3. Before you take that token out of the list, set another one here. |

Set each one from your own terminal, in your clone: `gh secret set <name> --env server-staging`.
It asks for the value and hides it, so the value is in no file and not in your shell history.
Never put one in a file, a chat or a workflow.

Make the token, once:

1. In the Cloudflare dashboard, open **Manage account** > **Account API tokens**, and select **Create Token**, with no template.
2. Give it the role **Editor** on the one Worker `trome-server-staging`, and nothing else.
   If the form refuses one Worker, give the role **Editor** on the Workers product.
3. Leave **Client IP Address Filtering** empty, and give **TTL** no end date.
4. Select **Continue to summary**, then **Create Token**: Cloudflare shows the token only once.
5. Run `gh secret set CLOUDFLARE_API_TOKEN --env server-staging`, and paste it.

The environment, once: on GitHub, **Settings** > **Environments** > **New environment**, named `server-staging`.
Give it no reviewer, choose **Selected branches and tags** for its deployment branches with the one branch `main`, and untick **Allow administrators to bypass configured protection rules**.
Then set its three secrets as above.

Revoke the token in a minute, when it leaked:

1. In the Cloudflare dashboard, open **Manage account** > **Account API tokens**.
2. Next to the token, select the three dot icon > **Roll**, then **Confirm**: the old token stops working at once, and Cloudflare shows a new one with the same access.
   When the menu has no **Roll**, delete the token from it, and make a new one as above.
3. Run `gh secret set CLOUDFLARE_API_TOKEN --env server-staging`, and paste the new token.

To stop every deploy of the run instead, delete the token and make no new one: each run then fails at its deploy step, and deploys nothing.

## The secrets

`server/wrangler.jsonc` names the secrets, with no value, and they live only on Cloudflare:

| Secret | Its value |
|---|---|
| `PRIM_API_KEY` | Your PRIM key ([how to get one](../../ios/README.md#the-train-data-key-prim)). |
| `APP_TOKEN` | The list of the app tokens that the Worker accepts, separated by commas. At first it holds one token, new for each Worker, made with `openssl rand -hex 32` (not `-base64`: in `ios/Config/Server.xcconfig`, where the app reads it, `//` starts a comment). The server answers only requests that carry a token of the list. It keeps casual traffic out, but anyone who takes the app apart can read it: the daily cap of PRIM calls is what protects the quota of the key ([How the server works](how-it-works.md#how-the-server-shares-the-prim-quota)). |
| `OWNER_TOKEN` | A new token for each Worker, made with `openssl rand -base64 32`, to read the counts. The app never holds it. |
| `APNS_TEAM_ID` | The Team ID of your Apple developer account, for the start of a Live Activity. |
| `APNS_BUNDLE_ID` | The bundle identifier of the Release build of the app, the one of TestFlight and the App Store. Apple starts a Live Activity only in a build with this ID: a Debug build has another one, so Apple refuses its start, and the app sends its arrival notification instead. |
| `APNS_PRODUCTION_KEY_ID`, `APNS_PRODUCTION_KEY` | The Key ID and the text of a key of Apple's push service for the **Production** environment: TestFlight and App Store builds use it. Paste the lines between `BEGIN PRIVATE KEY` and `END PRIVATE KEY` of its `.p8` file, as one line. |
| `APNS_SANDBOX_KEY_ID`, `APNS_SANDBOX_KEY` | The same for the **Sandbox** environment, which the builds that Xcode installs use. A key made for both environments may be set for both. |

Keep the tokens in your password manager.
Never put a secret of the server in a file, and never use `wrangler deploy --secrets-file`, even when wrangler suggests it.
The one exception is the app token: a Release build of the app must hold it ([Connect the app](#connect-the-app-to-the-server)), and `ios/Config/BuildTokens.txt` keeps the token of each build that riders may hold.
The logs of the server replace each secret with `[secret]`.
The `APNS_` secrets are optional: `make server-secrets` does not ask for them and no deploy waits for them, so set each with `make server-secret NAME=<name>`; until the team, the app and a key of one environment are set, the start of a Live Activity answers `not-set-up` and calls no one ([How the server works](how-it-works.md#the-start-of-a-live-activity)).
Make the keys in your Apple developer account, under **Certificates, Identifiers & Profiles**, **Keys**, with **Apple Push Notifications service (APNs)** and its environment.
When a new secret joins the table, set it with `make server-secret` on each Worker before you deploy the change.
After every deploy and every change of a secret of the production Worker, run `make release-tokens-check` in the main folder of your clone: it says, one line per build that riders may hold, whether the Worker still accepts its app token ([their tokens](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#the-app-token-of-each-build)).

## Deploy for the first time

1. Have your PRIM key ready, and make an app token and an owner token for the staging Worker.
2. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up, with no card.
3. Run `make server-login`, and allow the access in the browser that it opens.
   To log in with another browser, run `make server-login LINK=1` and open the link that it shows on this Mac, within 2 minutes; or run `make server-login CODE=1`, and type its code on any device.
4. Run `make server-secrets STAGING=1`, and paste each value that it names.
   After the first one, answer `y` when wrangler asks whether to create the Worker "trome-server-staging".
5. Run `make server-deploy-staging`, and note the address that wrangler shows, `https://trome-server-staging.<your subdomain>.workers.dev` (it asks you to choose a subdomain the first time).
   Choose the subdomain with care: every build of the app will hold it for good ([Keep the address of the server](#keep-the-address-of-the-server)).
6. Open that address with `/health`: it shows `{"status":"ok"}`.
   Then check the PRIM key with one stop, which costs one PRIM call; the answer has times:

   ```sh
   curl -H "Authorization: Bearer <app token>" "https://trome-server-staging.<your subdomain>.workers.dev/v1/stops/STIF:StopArea:SP:42155:/departures"
   ```

7. For production, run `make server-secrets` with other tokens, answer `y` for "trome-server", then run `make server-deploy` in the main folder of your clone, on `main`, and check it in the same way.
8. Make the staging token and the environment `server-staging` ([The staging token](#the-staging-token)): from then on, each push to `main` that changes the server deploys it to staging.

## Connect the app to the server

A Release build of the app reads the server from `ios/Config/Server.xcconfig`, a copy of `ios/Config/Server.example.xcconfig` that git ignores.
Put the host of the production Worker in `TRAIN_SERVER_HOST`, with no `https://`, and its app token in `TRAIN_SERVER_APP_TOKEN`.
Then run `make release-server-check` in the main folder of your clone: it asks the production Worker once for the trains of one stop, and says in one line, with neither value in it, whether the Worker accepts them.

## Change the app token

Each build of the app holds the app token that it was built with, and its riders may keep that build for months.
So the server takes a list of app tokens: a new token joins the list, and the old one stays.
Never swap the old token for a new one: every build that holds the old one would lose its times until its rider updates.

### Add a token

Do it for the builds to come, for example when the old token leaked: the daily cap of PRIM calls still bounds what a leaked token can cost.
Do each step on the staging Worker first, with its own tokens, then on the production Worker.

1. In the main folder of your clone, on `main`, run `make server-deploy-staging`, then `make server-deploy`.
   Never skip this step: a server from before the list reads `<old token>,<new token>` as one token, and refuses every app.
2. Make one new token for each Worker with `openssl rand -hex 32`, and keep them in your password manager next to the old ones, with the builds that hold each production token.
   If you no longer have an old production token, take it back from the archive of a build that holds it ([Release on the App Store, step 4](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#4-build-upload-and-check-the-first-build)): never set a list without it.
   If you no longer have the old staging token, make one more new token and use it as the old one in steps 3 and 4: no build that riders hold calls the staging Worker.
3. Run `make server-secret NAME=APP_TOKEN STAGING=1`, and paste every token of the staging list, then its new one, separated by commas: `<old token>,<new token>`.
   The value replaces the whole list, so a token that you leave out is cut off at once.
4. Check that the staging Worker answers both tokens: run the command below once for each, type `Authorization: Bearer <token>`, then press Return and Control-D.
   Curl reads the header as you type it, so the token stays out of your shell history; the two requests cost at most two PRIM calls.

   ```sh
   curl --header @- "https://trome-server-staging.<your subdomain>.workers.dev/v1/stops/STIF:StopArea:SP:42155:/departures"
   ```

   Both answers have times.
   A `{"error":"unauthorized"}` answer means that the list lost a token: set it again, with every token.
   If both answers are `{"error":"unauthorized"}`, the Worker may still run a server from before the list: do step 1 again before you go on.
5. Run `make server-secret NAME=APP_TOKEN`, and paste every token of the production list, then its new one, in the same way.
6. In the main folder of your clone, run `make release-tokens-check`: it asks the production Worker for the token of each build that riders may hold, and every line must say **accepted**.
   If a line says **refused**, run `make server-secret NAME=APP_TOKEN` at once and paste the old list again, with no new token; then find the cause.
   When every line says **accepted**, put the new production token in `TRAIN_SERVER_APP_TOKEN` of `ios/Config/Server.xcconfig`, and run `make release-server-check`: the next build that you upload holds that token.

### Retire a token

A token leaves the list only when no build that riders may hold has it: the table of [the builds that riders may hold](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#the-builds-that-riders-may-hold) says when each build stops being available.
Write the reason next to the token in your password manager, then take it out as in the steps above, on staging first: paste the list with every token but that one, and check that the staging Worker refuses it and still answers the others.
Then run `make release-tokens-check` in the main folder of your clone: every build in the field must still say **accepted** on the production Worker.

An installed app whose token is not on the list shows **Update the app**, with an orange icon, in place of the times on its Live Activity and its main screen ([each state of the Live Activity](../../ios/guide/live-activity.md#when-it-cannot-show-times)).
Updating is all that its rider can do.
That app asks the server again only when its rider opens it or a new Live Activity starts, so the old apps do not call in a loop.

## Read the counts

```sh
make server-counts URL=https://trome-server.<your subdomain>.workers.dev
```

Paste the owner token when it asks.
It shows a table: today so far, then each Paris day of the last 14 days, newest first, with its app calls, PRIM calls, `out` answers, errors, and the Paris hour with the most app calls.
Under the table, a line names each day with PRIM answers that the builds cannot read ([Unreadable PRIM answers](how-it-works.md#unreadable-prim-answers)).
A day with no call is a line of zeros.
When the server keeps no total from 14 days ago, the table starts at its oldest day, and says so.
App calls are the requests for times with the right app token, and the asks of the server for the Live Activities that it started (each start, and each update for 45 minutes): a wrong token, `/health` and this read do not count.

Add `FULL=1` for the whole report, as JSON: the cap and the PRIM calls of today, then each Paris day of the last 30 days, with its app calls, cache hits, held answers, `out` answers, PRIM calls, errors and unreadable PRIM answers, hour by hour (`parisHour`), with no stop.
Its `errorLines` lists the failed PRIM calls of the last 7 days: the time, the kind and the HTTP status, with no stop and no IP address.
The counts of app calls and cache hits are written at most every 10 seconds, to stay far below the writes that the Free plan allows each day.
A timer keeps the server awake until they are written, so that a sleep of the server loses none.

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

Run it once after a quiet time, when no app has asked the server for 6 minutes, for the first call of a rider; then at once again, for a warm server.
Why 6 minutes: the server object stays awake up to 5 minutes after its latest PRIM answer, and sleeps about 10 seconds later ([What the server keeps about riders](how-it-works.md#what-the-server-keeps-about-riders)).
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

## Keep the address of the server

Every build of the app holds the address of the production Worker, `trome-server.<your subdomain>.workers.dev`, from its archive, for good.
A rider updates when they choose, so a build of [the builds that riders may hold](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#the-builds-that-riders-may-hold) can call this address for years.
So while that table has a build in the field, never do any of these in the Cloudflare account of production (Cloudflare's docs, read on 11 October 2026: [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)):

| Never | Where | The way back |
|---|---|---|
| Rename the subdomain of the account, the part of the address after `trome-server.` | **Workers & Pages**, **Change** next to **Your subdomain** | Change it back to the old name, in the same place. |
| Rename or delete the production Worker, `trome-server` | **Workers & Pages**, the Worker, **Settings** | Renamed: give it back the name `trome-server`, in the same place. Deleted: run `make server-secrets` with the same values as before, from your password manager, since a build has only its own app token, then `make server-deploy`. The counts of the deleted Worker are lost, with its count of the day's PRIM calls, so the key may reach its PRIM quota that day. |
| Leave its workers.dev address off | **Workers & Pages**, the Worker, **Settings > Domains & Routes** | Run `make server-deploy`: a deploy turns it on again, since `server/wrangler.jsonc` has `workers_dev` on. |
| Move production to another account, even with the same names | Any other account: its subdomain differs, so the address does too | The builds still call the Worker of the old account: keep it there. If that Worker is gone, run `make server-login` with the old account (choose it when wrangler asks for an account), then deploy it again as for a deleted Worker. |

Each of them costs the same: every build that holds the address shows no times, and no message reaches it, because that address is its only way to the server.
The only way back is to put back what changed, as the last column says.
Do it at once: every build works again as soon as the address answers, with no update.

Turning workers.dev off for a short pause, as in [Stop the server for a while](https://trome.valfur.fr/en/maintain/release-on-the-app-store/#stop-the-server-for-a-while), is fine, as long as you turn it on again.
`make server-check`, and so both deploy commands, fails when `server/wrangler.jsonc` changes the name of the production Worker or turns its `workers_dev` off, until every build of the table is retired.

A new address, for example a name on a domain, is only ever added next to the old one.
The old one stays until the table says that no build holds it.
