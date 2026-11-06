---
paths:
  - "ios/App/**"
  - "ios/Widget/**"
  - "ios/Packages/**"
  - "ios/UITests/**"
  - "ios/RenderCheck/**"
  - "ios/DocsScreenshots/**"
  - "ios/ReleaseRun/**"
  - "ios/project.yml"
  - "ios/scripts/tests/**"
commands:
  - '^(\S*/)?make\b.*\se2e(\s|$)'
---
# Test levels

These rules are for every job that adds, changes, runs or judges a test of the iPhone app.

The test strategy of this repo is decision-9 in the backlog (`backlog/decisions/decision-9 - What-each-test-level-is-for-and-how-deep-a-change-is-tested.md`).
Read it before you add or change a test: it gives the reasons, the worked examples, and how the QA depth is chosen.
The product is the Live Activity.
The app screen is its small control panel, and the Testing tools are part of the test harness.
For each thing that could go wrong, ask: what could a rider lose, and what is the cheapest check that can really see it?

- **Unit test** (`TROMECore`, on the Mac, seconds).
  Any rule or value that you can write as "this input gives this output": what the Live Activity must show, the start, switch and end rules, the snooze, the PRIM answers (recorded fixtures, in `contracts/prim/`).
- **Code review.** The structure, the wiring, the access control, and the level of each new check.
  A new E2E test or step with no seam, an assert on the app's own echo of its state, a setup through the UI that is not the seam, or a fake of the app's code or of iOS at the seam under test is a medium finding.
- **Render check of the Live Activity** (proposed by decision-9, not built yet).
  How the app's views draw a given ContentState at the extreme cases: the 160 pt limit, cut or wrapped text.
- **E2E test** (the shared Simulator, the factory's bottleneck).
  Only for a seam where the app's code meets iOS and a fake would lie: ActivityKit starts, switches and ends a real Live Activity; the widget process draws the app's ContentState; iOS runs the intents of the Live Activity buttons; iOS shows no notification of the app; the position from iOS reaches the rules; the permission popups come in order.
  Assert on what the rider or iOS shows (the Live Activity in the Notification Center, the notification, the popup), not on an app label.
  Set up the state with a platform hook (`XCUIDevice.location`) or a launch argument, not through the app screen or the Testing tools.
  Fake only what is not the seam under test (`--fake-trains` replaces PRIM).
  A new launch argument or Testing tool that changes a rider's path goes in the list of `ios/guide/tests.md` ("The test flags and a rider's path"), with the test that runs that path without it, or why the Simulator cannot (TASK-513: a keep-awake flag hid a pocket switch that never came).
  Each file in `ios/UITests/` starts with its seam and why a cheaper check cannot see it.
- **QA** (exploratory, the shared Simulator for a whole session).
  What no script can judge: does it look and read right, with real data, in French, over time, in the background.
  The Dynamic Island and the wake of a closed app by region monitoring are checked here and on the prompter's iPhone, not in E2E.
- **No check.** A change that no rider can see, or whose risk another check already covers (the look of the Testing tools, a README text).

## Which E2E tests to run

The E2E tests must make sure that no breaking bug lands on `main`, and that no agent ever sees a failing test because another agent brought a bug.
But a full `make e2e` keeps the shared Simulator for several minutes, and the shared Simulator is the factory's bottleneck.
So the factory runs far fewer E2E tests, at the right time:

**`main` is always green.** It holds only tasks that passed review and QA.
Each fast-forward of `main` lands on a commit where the core checks and the E2E tests of the changed paths passed (`make merge`).
The full suite runs on the head of `main` in the daily full run (`make full-run`), which catches what the path map misses, and which alone writes the record that a release reads (decision-126).

**App code**, for these rules, is what the E2E tests exercise: `ios/App/`, `ios/Widget/`, `ios/Packages/` (except its unit tests), the E2E tests in `ios/UITests/`, the run of the Release app in `ios/ReleaseRun/`, and what builds or runs them (`ios/project.yml`, `ios/Config/`, the `Makefile` files, `ios/scripts/`).
Docs are not app code: `docs/`, every Markdown or MDX file (`*.md`, `*.mdx`, in any folder, for example `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `ios/README.md`, `ios/guide/`), `LICENSE` at the root, and `.claude/` (the agents' rules and settings).
No E2E test, no build and no script of the E2E suite reads them, and `make check` still checks them.
One exception: a Markdown or MDX file in a folder that the build of the app takes as its sources (`ios/App/`, `ios/Widget/`, `ios/UITests/`, `ios/DocsScreenshots/`, `ios/RenderCheck/`, `ios/ReleaseRun/`, `ios/Packages/` except its unit tests) is app code, because XcodeGen copies it into the app as a resource.
Unit tests (`ios/Packages/TROMECore/Tests/`), the server (`server/`, its `Makefile` included: no E2E test uses it), the film (`video/`, its `Makefile` included), the shared test files of `contracts/`, the notes of `ios/changes/`,
the files of `.github/` (the GitHub workflows and forms: no build and no test of the repo reads them, and GitHub runs the workflows on its own machines) and backlog files are not app code either.
`contracts/` holds only files that tests read: no build of the app or of the server ships one.
A task that makes the app read a file of `contracts/` at run time, or makes the build or an E2E test read one of these docs files, makes it app code, and changes `is_app_code` in `ios/scripts/code-paths.sh` in the same task (`make merge` and the reader of the record of the E2E pass both use it).

**The core checks and the path map.** The core checks run at every merge of app code, whatever it changed: `LiveActivityTests`, `AutoLiveActivityTests` and `SnoozeTests` (`core_e2e_classes` in `ios/scripts/code-paths.sh`), and `make release-run-check`.
They are the flows where a rider loses the Live Activity at the right station.
The other E2E classes run when the merge changes a file that a line of `ios/scripts/e2e-paths.txt` gives them.
A changed file of app code that no line matches runs the full suite: a doubt never skips a test.
A task that adds an E2E test class adds its line, and a task that makes a test read code of another folder adds that folder to the line of its class (`ios/scripts/tests/e2e-paths-test.sh` checks that every class has a line).

- **The implementer** runs only the E2E test classes of the flows that it changed: `make e2e ONLY=SnoozeTests`, or `make e2e ONLY="SnoozeTests LiveActivityTests"` for more than one.
  The class names are the file names in `ios/UITests/`.
  When its change touches no flow of the E2E tests (for example, a rule that only unit tests cover), it runs no E2E test.
- **A reviewer** runs no E2E test, unless it changes app code.
  For example, a review with no change, or a change to the docs (Markdown files included), the unit tests or the backlog files only, runs none.
  A reviewer who changes app code runs only the E2E test classes of the flows that its change touches.
- **The manager** runs `make merge` after QA passed the task (see `.claude/rules/merge.md`).
  After the rebase onto `main`, on the commit that it fast-forwards `main` to, it runs `make e2e` for the core classes and the classes of the changed paths, and retries a failed test once.
  Then it starts the app as the store ships it (`make release-run-check`, about 40 s of the lock), on the same commit.
  A task that changes only docs (Markdown and MDX files, `LICENSE`, `.claude/`), unit tests, the notes of `ios/changes/`, `server/`, `contracts/`, `video/` or `.github/` (no app code) skips both: `main` was green, and the task adds no app code.
  `make merge` sees this by itself.
  The manager also runs `make full-run` each day on the head of `main`, and before a release on the commit to release.
- **QA** runs no automated tests.
  It explores the app like a real user.

**A test that passes only on its retry.** `make merge` and `make full-run` run `make e2e` with `E2E_RETRY=1`: the runner of Xcode runs a failed test once more (`-retry-tests-on-failure -test-iterations 2`).
A test that fails twice is red.
A test that passes only on its retry is a pass, but the run names it (`E2E flaky:` in the log, and the merge or full-run output), writes `flaky` in its line of the check ledger, and keeps its evidence as for a failure.
The manager then creates or updates its `flaky` bug task ("Flaky tests" in `CLAUDE.md`): no script writes to the backlog.
`make e2e` alone never retries, so the implementer sees each failure; there, a failing test may be rerun once by hand, to know if it is flaky.
