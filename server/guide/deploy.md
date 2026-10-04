# Deploy the server

This page is for the maintainer, who holds the Cloudflare account of the server and its secrets: a contributor needs none of it, and starts at [server/README.md](../README.md).
It shows how to deploy the server, set its secrets, connect the app to it, and read its counts of requests and PRIM calls.
Run the commands from the root of the repo, after `nvm use` ([server/README.md](../README.md)).

| Command | What it does |
|---|---|
| `make server-login` | Logs in to your Cloudflare account, once on this Mac. |
| `make server-secrets` | Sets each secret of the production Worker, `trome-server`, asking for each value, so that none is in your shell history or in a file. |
| `make server-secret NAME=<name>` | Changes one secret, at once, with no new deploy. |
| `make server-deploy-staging` | Runs `make server-check`, then deploys your folder, also changes that are not committed, to the staging Worker, `trome-server-staging`. |
| `make server-deploy` | Runs `make server-check`, then deploys `main` to the production Worker. It refuses another branch and changes that are not committed. |
| `make server-counts URL=<address>` | Shows the requests and the PRIM calls of the server, day by day, and asks for the owner token. |

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

## Change the app token

The server takes one app token at a time, and every installed app holds the old one.
So a new token cuts off every installed app until its rider installs a version with the new token: change it only when the old one leaked.
Then set the new one with `make server-secret NAME=APP_TOKEN`, put it in `ios/Config/Server.xcconfig`, and release a new version of the app.

## Read the counts and the logs

```sh
make server-counts URL=https://trome-server.<your subdomain>.workers.dev
```

Paste the owner token when it asks.
It shows, as JSON, the cap and the PRIM calls of today, then each Paris day of the last 30 days, with its app calls, cache hits, held answers, `out` answers, PRIM calls and errors, hour by hour (`parisHour`) and stop by stop.
`errorLines` lists the failed PRIM calls of the last 7 days, with no IP address.
The counts of app calls and cache hits are written at most every 30 seconds, to stay far below the writes that the Free plan allows each day.

Cloudflare keeps no request log of the server: Workers Logs are off in `server/wrangler.jsonc` (`"observability": { "enabled": false }`).
To find a problem, set `enabled` to `true` and deploy, for 3 days at most, which is how long the Free plan keeps them.
To watch the log lines live, without keeping them, run `npx wrangler tail` in `server/`.
