# Contributing to TROME

Thanks for helping TROME, the iPhone app that shows the next metro and RER trains of the nearest Paris station on the lock screen.
Whether you want to report a bug, ask a question, or change the code or the docs, this page shows your first step and what happens next.

## Report a bug or ask a question

The trains do not show on your lock screen?
[Help](https://trome.valfur.fr/en/support/) lists each problem and its fix ([Aide](https://trome.valfur.fr/fr/support/) in French), so start there.

Open an issue in the **Issues** tab of the repo.
You can write it in French or in English.

For a bug, say what you did, what you saw and what you expected, with your iPhone model, your iOS version and the station.
A screenshot of the lock screen helps a lot.

A security problem never goes in an issue: report it privately, as [SECURITY.md](SECURITY.md) shows.

## Ask before you change something

TROME does one thing on purpose: it shows when the next trains come, on the lock screen.
It does not plan routes, show maps, cover other cities or other kinds of transport, or copy the transport apps that riders already use.

So before you start a pull request, open an issue that says what you want to change and why, and wait for an answer.
That way I can tell you yes or no first, and you do not lose a day on a change that I cannot accept.

## Use AI tools, and answer for your change

I build TROME with Claude Code, Anthropic's coding assistant: it writes most of the code and the docs, and I direct the work.
That is why the repo has a [CLAUDE.md](CLAUDE.md) and a [.claude](.claude/rules) folder: they are the manual that Claude Code reads, and they are public so that you can read them too.
If you use Claude Code, it reads them by itself: `CLAUDE.md` in every session, and each file of `.claude/rules/` when the work touches its topic.

You may use any tool, AI included.
But read and run your change before you send it, be ready to explain it, and answer for it in the review.
I do not accept a large change that you cannot explain, or that you did not run.

## Set up

[Build, run and test the iPhone app](ios/README.md) takes you from a clone to the app in the iPhone Simulator, in two commands.
With no train data key, the app shows no live times: [The train data key](ios/README.md#the-train-data-key-prim) shows how to add your own free key.
`make help` lists every command.

## Make your change

### Find where the code goes

The iPhone app is in `ios/` and the server is in `server/`: [Project layout](ios/README.md#project-layout) maps the folders.
In the app, the rules and the state live in the `TROMECore` package, with their unit tests, and the screens and the Live Activity only show them.
Where each file goes, and which part may use which, is in the rules of Claude Code, for [the app](.claude/rules/ios-code.md) and for [the server](.claude/rules/server.md).
These rules hold for every change, and the review checks them.

### Give every text a French version

Most riders are French, so each text that a rider sees gets its French version in the same change.
Write the text in English in the code, then run `make strings-sync`: it adds the text to the String Catalog, where you write the French text.
Write it the way a Paris rider would say it, with the words of the RATP signs and of iOS ("Prochains passages", "Réglages").
Commit the catalog with your change.
A missing French text is the most common reason why a first change fails `make check`.
[Add or change a text in English and French](ios/guide/languages.md) explains the catalogs.

### Update the docs in the same change

When your change makes a step, a command or a screen of the docs false, fix the docs in the same change.
[Write the docs](docs/README.md) shows how to run the docs site, take the pictures again, and write a page.

### Check your change

Run `make check` from the root of the repo before each commit.
It lints the code, builds the app, and runs the unit tests and the other checks of the repo.
It fails on any build warning.
When a check fails, its message says what is wrong and where the rule is.
When your change touches `docs/`, `make check` builds the site too, which needs Node 24 (see [Run the site](docs/README.md#run-the-site)).

`make test` runs only the unit tests, on the Mac with no Simulator, and `make e2e` runs the end-to-end tests in the Simulator: [Test a change to the iPhone app](ios/guide/tests.md) shows which test your change needs.

### Write the commit title

Start each commit title with the kind of change, then say what the change does, in lower case:

```text
feat: show the source notice of the PRIM train data at the foot of the app screen
fix: keep the box of a stale fork row black
```

The kinds are `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `chore` and `perf`.
The changelog for developers will be made from these titles, so the kind says where your change goes.

## Send your change

Push your branch to your fork, and open a pull request that links the issue where I said yes to the change.
Say what you changed and how you checked it.
The repo has no automatic checks on pull requests yet, so also say that `make check` passes.

Then the change gets a review, which may ask for changes: push them to the same branch, and the pull request updates.
When I accept the change, it lands on `main`.

## Licence

The code of TROME is under the [MIT licence](LICENSE).
When you send a change, you agree that it is under the same licence.
The data in the repo, such as the station list, keeps its own licences: see [NOTICE.md](NOTICE.md).
