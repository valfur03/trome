# Build, run and test the iPhone app

This folder holds the iPhone app of TROME, its Live Activity, and their tests.
This page gets you from a clone to the app in the Simulator, and to a change that passes the checks; [CONTRIBUTING.md](../CONTRIBUTING.md) says how to propose one.
Run every `make` command from the root of the repo.
[Project layout](#project-layout), at the end of this page, maps the folders of the code.

## Set up and run the app

You need a Mac with Xcode 27 and its iOS Simulator (select it with `xcode-select` if you have several versions), and [Homebrew](https://brew.sh).
Then, in your clone:

```sh
make setup
make run
```

`make setup` installs XcodeGen, SwiftLint and pngquant, and creates the Xcode project, `ios/TROME.xcodeproj`.
`make run` builds the app and opens it in the Simulator.
The first build takes several minutes: it compiles the modules of the iOS SDK once, into a cache that all your clones share.

The app shows no real train times until you add your own free key ([The train data key (PRIM)](#the-train-data-key-prim)), but it can show [fake trains](guide/testing-tools.md#get-fake-trains-with-no-key).
To try it at a station without going there, tap **Testing tools** at the top right, and pick a fake position ([Try the app at any station, without going there](guide/testing-tools.md)).
To put the app on your own iPhone, see [Install on your iPhone](#install-on-your-iphone-free-apple-id).

## The commands you use every day

| Command | What it does |
|---|---|
| `make run` | Builds the app and opens it in the Simulator. Add `SMALL=1` for the smallest iPhone (an iPhone SE), or `LANGUAGE=fr` for a Simulator in French. |
| `make test` | Runs the unit tests on your Mac, with no Simulator. |
| `make e2e ONLY=<class>` | Runs one class of end-to-end tests in the Simulator; with no `ONLY`, all of them. |
| `make strings-sync` | Adds the new texts of the code to the String Catalogs, where you write their French text ([Add or change a text in English and French](guide/languages.md)). |
| `make check` | Runs the checks of a change that need no Simulator: run it before each commit. |
| `make simulator-shutdown` | Removes the app from the Simulator, and frees it for your other clones. |

`make help` lists every command.

## One Simulator for all your clones

The `make` commands run the app on one shared Simulator, `RATP-Shared`, and only one of them uses it at a time, in any clone or git worktree of the repo.
A second command waits, and prints `Waiting for the Simulator lock`: let it wait.
After `make run`, the Simulator stays yours, and the other commands wait, until you run `make simulator-shutdown`.
Each command starts from a clean app: it removes the app and its data, and resets the permissions (notifications included), the text size, the appearance and the language of the Simulator.
In your own `xcrun simctl` commands, use the ID that `make -s simulator` prints.

To run the app from the **Run** button of Xcode instead, use a Simulator of your own: the `make` commands shut the shared one down a few minutes after their last job, even with your app open.
Free the shared one and shut it down first, so that only one Simulator runs: `make simulator-shutdown`, then `xcrun simctl shutdown "$(make -s simulator)"`.
Quit your own Simulator before your next `make` command, for the same reason.

## Keep the Xcode project up to date

The Xcode project is not in git: XcodeGen makes it from `ios/project.yml`, so change the settings there, not in Xcode.
The `make` commands update the project before they build, but the **Run** button of Xcode does not, and an old project fails with "Build input file cannot be found".
So run `make generate` before you build in Xcode, after each edit of `ios/project.yml`, `git pull` or change of branch.
To let git run it after a pull or a change of branch, run `make git-hooks` once.

## Before you commit

Run `make check`.
It runs the lint, the checks of the texts and of the app icon, the build, the unit tests and the tests of the scripts, and stops at the first failure, with a message that says what to do.
The build accepts no warning: fix its cause, and never silence it.
When your branch changes `docs/`, `server/` or `contracts/`, `make check` checks them too, which needs Node 24 ([how to install it](../server/README.md#run-and-test-it-locally)).

`make check` runs no end-to-end test: [Test a change to the iPhone app](guide/tests.md) says which tests your change needs, and how to write one.

## The guides

- [tests.md](guide/tests.md): which test a change needs, how to run it and how to write one.
- [testing-tools.md](guide/testing-tools.md): fake the position and the trains of a debug build, to try the app at any station.
- [stations.md](guide/stations.md): where the station list comes from, and how to update it.
- [trains.md](guide/trains.md): where the train times come from, and when they refresh.
- [languages.md](guide/languages.md): add or change a text in English and French.
- [live-activity.md](guide/live-activity.md): what the lock screen and the Dynamic Island show for each state of a train, and when they change.
- [auto-live-activity.md](guide/auto-live-activity.md): when the Live Activity starts and stops by itself, the snooze and the pause, and the permission questions.
- [example.md](guide/example.md): what "See an example" shows, when it ends, and how to make it shorter.
- [render-check.md](guide/render-check.md): `make live-activity-render`, which finds a Live Activity that is too tall or cut.
- [assets.md](guide/assets.md): the docs pictures, the store page and the video that show the app, and how to make each again.

## The train data key (PRIM)

A build of `make run` shows no live train times, because it has no key.
To see live trains in a debug build, use your own free key of PRIM, the train data service of Île-de-France Mobilités.
Release builds never use it: they ask the server of TROME ([where the train times come from](guide/trains.md)).

1. Create a free account on [PRIM](https://prim.iledefrance-mobilites.fr), then an API key for the API **Prochains passages - requête unitaire**.
   These steps were not followed with a new account: if a screen of PRIM differs, open an issue.
2. Copy the example key file, and open the copy:

   ```sh
   cp ios/Config/Secrets.example.xcconfig ios/Config/Secrets.xcconfig
   open -e ios/Config/Secrets.xcconfig
   ```

3. Put your key after the `=`, with no quotes, such as `PRIM_API_KEY = 0123abcd`, and save.
4. Run `make run LIVE=1`.
   In **Testing tools** > **Next trains of a station**, the screen now says **Train data key: set**, and shows live trains.

Add `LIVE=1` each time you want live trains: `make run` alone, `make check` and `make e2e` build with no key, so the tests never spend your daily quota of calls ([what each screen costs](guide/trains.md#one-call-for-each-stop-area)).
The **Run** button of Xcode uses the key file of the folder that you open.
In a git worktree, `make run LIVE=1` reads the key file of the main folder of your clone.

Git ignores the key file, the build output never shows the key, and a Release build never holds it.
`make live-key-check`, part of `make check`, proves it with a fake key.

## Read the logs

Debug builds write what the app does in the log of the phone, under the name `TROME`.
With it, you can tell whether a change on the Live Activity comes from PRIM, from the rules of the app, or from iOS.
Release builds write none of these lines.

| Category | One line for |
|---|---|
| `PRIM` | Each train of each PRIM answer, and whether the app keeps it, and why |
| `LiveActivityContent` | Each content that the app sends to the Live Activity, train by train |
| `LiveActivity` | Each state that iOS sends for a Live Activity, each end that the app asks for, each pause of a station, and each tap on the header that shows the next line |
| `StationRegions` | Whether iOS can watch regions, and each region event |
| `BackgroundLocation` | When the app starts and stops getting the position in the background |

In the Simulator, read the last 5 minutes, or put `log stream` in place of `log show --last 5m` to follow the lines as they come:

```sh
xcrun simctl spawn "$(make -s simulator)" log show --last 5m --predicate 'subsystem == "TROME"'
```

To keep some categories, add them to the filter, such as `AND (category == "PRIM" OR category == "LiveActivityContent")`.
On your iPhone, open the **Console** app on your Mac, choose the iPhone, click **Start**, and search for `subsystem:TROME` (not checked on a device yet).

To write a new line, make its logger with `Logger(category:)` from `TROMECore`, keep the line inside `#if DEBUG`, and mark each value `privacy: .public`, or the log shows `<private>`.

## Install on your iPhone (free Apple ID)

The tutorial "Install the app on your iPhone" of the docs site explains it step by step, for beginners. Run `make docs`, then open http://localhost:4321/en/build/install-on-your-iphone/. The page is `docs/src/content/docs/en/build/install-on-your-iphone.mdx`.

In short: your Team ID and a unique bundle ID prefix go in `ios/Config/Local.xcconfig` (a copy of `ios/Config/Local.example.xcconfig`, ignored by git).
Run `make generate`, open the project `ios/TROME.xcodeproj` in Xcode, choose the scheme `TROME` and your iPhone, and click Run.
With a free Apple ID, the app stops after 7 days: run `make generate` again, then click Run again to renew it.

Your build gets the bundle ID `<prefix>.trome.dev`, and its Live Activity gets `<prefix>.trome.dev.widget`.
These IDs end with `.dev`, so they are never the App Store ID of the app, `io.github.valfur03.trome`, whatever your prefix.
Why: when a free Apple ID signs a build, Apple registers its bundle ID to that Apple ID for good, and the paid account of the app could then never take it.
Only the Release builds (for the App Store) carry `io.github.valfur03.trome` and `io.github.valfur03.trome.widget`, and Xcode never signs them automatically.
So Xcode can show an error for Release in Signing & Capabilities: leave it, and never turn on "Automatically manage signing" for Release, or Xcode registers the App Store ID to your Apple ID.
`make bundle-id-check` (part of `make check`) checks both.
A free Apple ID registers at most 10 bundle IDs in 7 days, and each one expires after 7 days.
When Xcode says "Your maximum App ID limit has been reached" or "No profiles for ... were found", wait, or reuse two bundle IDs that Xcode already registered on your Mac: the tutorial shows the command that lists them, with the date when each one expires.
To reuse them, set `TROME_DEBUG_APP_BUNDLE_ID` and `TROME_DEBUG_WIDGET_BUNDLE_ID` in `ios/Config/Local.xcconfig` (see `ios/Config/Local.example.xcconfig`), then run `make generate`.
`make generate` then prints the two bundle IDs that Xcode will use: check them before you click Run, because a mistyped setting name is ignored.
They are the full bundle IDs of your Debug builds, written as is, and the ID of the Live Activity must start with the ID of the app and a dot; with only the first one set, the Live Activity gets the app ID followed by `.widget`.
`make generate` and `make bundle-id-check` refuse the App Store IDs there, in any capitals, and the git hooks print the same refusal.
A Run in Xcode with no `make` command gets an ID that starts with `SHIPPING_ID_REFUSED` instead, which is not a valid bundle ID.
A build from before the app was called TROME has another bundle ID, so iOS keeps it as a second app: delete it, so that its notifications and its Live Activities stop.

On a device, the Run button of Xcode uses the PRIM key of `ios/Config/Secrets.xcconfig` in the folder that you open. There is no `make` command for a device build.

## Languages

Every text that a rider sees needs its French text, in the same change, or `make check` fails.
[Add or change a text in English and French](guide/languages.md) shows how, and what to do when `make strings-check` fails.

## Project layout

Each part of the repo has its own folder. The root holds only the files of the whole repo.

| Folder or file | What it holds |
|---|---|
| `README.md`, `CLAUDE.md`, `.gitignore`, `.nvmrc` | Files for the whole repo. `.nvmrc` pins the Node version of the Node parts (`docs/` and `server/`). |
| `.claude/` | The rules of Claude Code by topic (`rules/`), and the hook that brings each rule to the work that needs it (`hooks/`). |
| `Makefile` | Runs each `make` command in the folder of its part. It has no build logic. `make check` runs the checks of all parts. |
| `ios/` | The iPhone app, with its own `Makefile`, `project.yml`, `.swiftlint.yml`, build settings and scripts. Its build output goes to `ios/.build/`. |
| `docs/` | The docs site (Starlight), with its own `Makefile` and scripts. |
| `server/` | The server (a Cloudflare Worker in TypeScript), with its own `Makefile`, scripts and `package.json` (see [server/README.md](../server/README.md)). |
| `contracts/` | The files that the app and the server both test against. Today `contracts/prim/`: the recorded PRIM answers of the unit tests. |

Inside `ios/`:

| Folder | What it holds |
|---|---|
| `App/` | The iPhone app (SwiftUI): the entry point, the views, and the adapters to the iOS frameworks. One folder per feature. |
| `Widget/` | The widget extension. It shows the Live Activity. |
| `Packages/TROMECore/` | The rules, the state and the data of the app, shared by the app and the widget, with its unit tests. One folder per feature. |
| `UITests/` | The end-to-end tests (XCUITest). |
| `DocsScreenshots/` | The XCUITest suite that takes the app screenshots of the docs. |
| `RenderCheck/` | The render check of the Live Activity views (`make live-activity-render`): a unit test bundle, and in `Host/` the small app that runs it with the texts of the widget. |
| `Config/` | Build settings. Your key and Team ID go in the local files here. |
| `scripts/` | Helper scripts for the `make` commands of the app. |

The feature folders have the same names in `ios/App/`, in the sources of `TROMECore` and in its tests: `Stations`, `Location`, `Trains`, `LiveActivity`, `AutoLiveActivity`, `Example`.
`ios/App/` also has `Permissions`, `About`, `NightLook` (the look of the main screen) and `TestingTools` (debug builds only).
The app icon is `ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`: one square PNG of 1024 x 1024 pixels, with no transparency and no rounded corners, from which iOS makes every size, the rounded corners and the dark and tinted icons.
`make app-icon-check` checks it.
The rules for the code (where each file goes, which module depends on which) are in [`.claude/rules/ios-code.md`](../.claude/rules/ios-code.md).

You can also run the commands of one part in its folder: `make -C ios check` runs only the checks of the app.
