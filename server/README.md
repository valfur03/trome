# Run, test and deploy the server

This folder holds the server of TROME: it stands between the app and PRIM, the train data service of Île-de-France Mobilités.
It holds the PRIM key, so that no copy of the app holds it, shares one daily quota of PRIM calls among all riders, and keeps nothing about them.
A Release build of the app asks it for the trains; a Debug build calls PRIM directly, with your own key ([The train data key (PRIM)](../ios/README.md#the-train-data-key-prim)).
It runs on Cloudflare Workers.

## Run and test it locally

You need Node 24, the version in [`.nvmrc`](../.nvmrc): install it once with a Node version manager that reads this file, then use it for each server command.
With [nvm](https://github.com/nvm-sh/nvm), run `nvm install` once, then `nvm use` in each new terminal.
With [fnm](https://github.com/Schniz/fnm), run `fnm install` once, then run each command through fnm, for example `fnm exec --using=.nvmrc -- make server-check`.
From the root of the repo:

```sh
make server-check
make server-dev
```

`make server-check` installs the packages (about 300 MB, in `server/node_modules`), checks that `server/wrangler.jsonc` keeps no request log at Cloudflare ([Find a problem](guide/deploy.md#find-a-problem)) and keeps the address of the production Worker ([Keep the address of the server](guide/deploy.md#keep-the-address-of-the-server)),
checks that each build in the field has its recorded set of promises, never edited ([The promise to the builds in the field](guide/how-it-works.md#the-promise-to-the-builds-in-the-field)),
then runs the type check, the lint, the unit tests, which judge the server against every recorded set, and the tests of the scripts.
`make server-dev` runs the server locally, at the address that it prints, where `/health` answers `{"status":"ok"}`; `make server-stop` stops it.
Neither needs a Cloudflare account.

The local server uses fake secrets, from `server/.dev.vars`, which it creates and git ignores.
So it never gets real trains: PRIM refuses its fake key, and you check the answers for trains in the unit tests, which fake PRIM.
`make check` runs `make server-check` when your branch changes `server/` or `contracts/`.

## Find your way in the code

- `server/src/core/` holds the logic, in plain TypeScript that runs on Node; `server/src/cloudflare/` holds the entry of the Worker, the Durable Object and the adapters to Cloudflare ([the rules of this structure](../.claude/rules/server.md)).
- `server/test/core/<feature>/` tests the logic on Node, `server/test/cloudflare/` tests the Worker in the Cloudflare runtime, and `server/scripts/tests/` tests the scripts.
  To run one folder while you work: `cd server && npx vitest run test/core/relay`.
- `contracts/prim/` holds recorded PRIM answers, which the tests of the app read too, and `contracts/api/` holds an example of each answer of the server, which a test checks.
- `contracts/builds/` holds what each build that riders may hold sends and reads: the server keeps every answer of it, and nobody edits it ([The promise to the builds in the field](guide/how-it-works.md#the-promise-to-the-builds-in-the-field)).
- `server/src/core/config/relay-settings.ts` holds the settings of the quota.

## The guides

- [How the server works](guide/how-it-works.md): its API, how it shares the PRIM quota, and what it keeps about riders.
- [Deploy the server](guide/deploy.md), for the maintainer: the Cloudflare account, the secrets, the deploy, the list of app tokens, which keeps every installed build working when a new token comes, the counts, the totals for your Prometheus and the logs.
