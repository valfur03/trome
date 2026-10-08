# Report a security problem privately

Found a way to read a secret of TROME, to learn where a rider is, or to make the app or the server do what it should not?
Tell me in private: a public report shows everyone how to use the problem.
Do not open an issue or a pull request about it: everyone can read them.
Not sure that it is a security problem? Report it privately anyway.

## Send your report on GitHub

Open [Report a vulnerability](https://github.com/valfur03/trome/security/advisories/new), which is also in the **Security** tab of the repo.
You need a GitHub account, which is free, and only you and I see the report.

In the report, say what the problem is and where it is: the file, the screen, or the request to the server.
Then give the steps that show it, and what someone could do with it.

## What to expect: no promise

TROME is a free app under the MIT licence, which comes with no warranty, and this page makes no promise either.
I read reports on a best-effort basis, with no promise of a reply or a fix.
TROME has no bug bounty, so it pays for no report.

## Test in good faith, and wait 90 days to publish

I take no legal action against research in good faith that keeps to these rules:

- Report the problem privately, as above.
- Do not read, change or keep the data of other people.
- On the server that riders use, send only a few requests by hand, never in a loop, and never run a load test or a scanner.
  All riders share its small daily budget of train data calls, so a heavy test leaves them with no times.
  For more, test your own copy: [the server guide](server/README.md) shows how to run it on your Mac.
- Wait 90 days after you send the report before you publish anything about the problem.

## What the report can be about

- The iPhone app and its Live Activity, in [`ios/`](ios/).
- The train data server, in [`server/`](server/), as it runs for TROME.
- The docs site, in [`docs/`](docs/), at https://trome.valfur.fr/.
- The build and the scripts of this repo, for example a step that could put a key in a log or in a built app.

Check the problem on the latest code of `main`, or on the latest version of the app.
A problem that shows only on the server that riders use is still worth a report: say what you saw.

A problem of iOS, GitHub, Cloudflare or PRIM, the train data service of Île-de-France Mobilités, goes to them: I do not run them.

## What I already know: the app token

Every copy of the app holds the same token, which it sends to the server, so anyone who has the app can pull the token out.
I know this, so a report that shows only this is not needed.
With the token, someone could use up the server's train data calls, and riders would then get no times until the server may call again: the next hour, or the next day at worst.
The token does not give the PRIM key, and the server never makes more train data calls than its daily cap.
A way past that cap, a way to the PRIM key, or a server that answers a wrong or missing token is worth a report.
