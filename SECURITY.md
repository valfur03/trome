# Report a security problem privately

Found a way to read a secret of TROME, to learn where a rider is, or to make the app or the server do what it should not?
Tell us in private, so that we can fix it before anyone uses it.
Do not open an issue or a pull request about it: everyone can read them.
Not sure that it is a security problem? Report it privately anyway.

## Send your report on GitHub

Open [Report a vulnerability](https://github.com/valfur03/trome/security/advisories/new), which is also in the **Security** tab of the repo.
You need a GitHub account, which is free, and only you and the maintainer see the report.

In the report, say what the problem is and where it is: the file, the screen, or the request to the server.
Then give the steps that show it, and what someone could do with it.

## What happens next

We answer in the report within **[answer delay, to be set]**, and tell you whether we can see the problem too.
No answer by then? Add a comment to the report.
While we fix it, we keep you posted in the report, and may ask you to check the fix.
When the fix is out, we publish the report as a security advisory on GitHub, with your name if you want it there.
TROME is a free app with no bug bounty, so we cannot pay for a report.

## What the report can be about

- The iPhone app and its Live Activity, in [`ios/`](ios/).
- The train data server, in [`server/`](server/), as it runs for TROME.
- The docs site, in [`docs/`](docs/), at https://valfur03.github.io/trome/.
- The build and the scripts of this repo, for example a step that could put a key in a log or in a built app.

Check the problem on the latest code of `main`, or on the latest version of the app.
Test the server on your own copy when you can: [the server guide](server/README.md) shows how to run it on your Mac.
Never run a load test or a scanner against the server that riders use: they all share its small daily budget of train data calls, so they would be left with no times.
A problem that shows only on that server is still worth a report: say what you saw.

A problem of iOS, GitHub, Cloudflare or PRIM, the train data service of Île-de-France Mobilités, goes to them: we do not run them.

## What we already know: the app token

Every copy of the app holds the same token, which it sends to the server, so anyone who has the app can pull the token out.
We know this, so a report that shows only this is not needed.
With the token, someone could use up the server's train data calls, and riders would then get no times until the server may call again: the next hour, or the next day at worst.
The token does not give the PRIM key, and the server never makes more train data calls than its daily cap.
A way past that cap, or to the PRIM key, is worth a report.
