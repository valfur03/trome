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
  Only for a seam where the app's code meets iOS and a fake would lie: ActivityKit starts, switches and ends a real Live Activity; the widget process draws the app's ContentState; iOS runs the intents of the Live Activity buttons; a real notification opens the app; the position from iOS reaches the rules; the permission popups come in order.
  Assert on what the rider or iOS shows (the Live Activity in the Notification Center, the notification, the popup), not on an app label.
  Set up the state with a platform hook (`XCUIDevice.location`) or a launch argument, not through the app screen or the Testing tools.
  Fake only what is not the seam under test (`--fake-trains` replaces PRIM).
  One test per seam.
  Each file in `ios/UITests/` starts with its seam and why a cheaper check cannot see it.
  Keep the test phase of the full suite at a few minutes.
- **QA** (exploratory, the shared Simulator for a whole session).
  What no script can judge: does it look and read right, with real data, in French, over time, in the background.
  The Dynamic Island and the wake of a closed app by region monitoring are checked here and on the prompter's iPhone, not in E2E.
- **No check.** A change that no rider can see, or whose risk another check already covers (the look of the Testing tools, a README text).

## Which E2E tests to run

The E2E tests must make sure that no breaking bug lands on `main`, and that no agent ever sees a failing test because another agent brought a bug.
But a full `make e2e` keeps the shared Simulator for several minutes, and the shared Simulator is the factory's bottleneck.
So the factory runs far fewer E2E tests, at the right time:

**`main` is always green.** It holds only tasks that passed review and QA.
Each fast-forward of `main` lands on a commit where the full E2E suite passed.
The manager runs it on that exact commit, with `make merge`.
This is the only full run of a task.

**App code**, for these rules, is what the E2E tests exercise: `ios/App/`, `ios/Widget/`, `ios/Packages/` (except its unit tests), the E2E tests in `ios/UITests/`, the run of the Release app in `ios/ReleaseRun/`, and what builds or runs them (`ios/project.yml`, `ios/Config/`, the `Makefile` files, `ios/scripts/`).
Docs are not app code: `docs/`, every Markdown or MDX file (`*.md`, `*.mdx`, in any folder, for example `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `ios/README.md`, `ios/guide/`), `LICENSE` at the root, and `.claude/` (the agents' rules and settings).
No E2E test, no build and no script of the E2E suite reads them, and `make check` still checks them.
One exception: a Markdown or MDX file in a folder that the build of the app takes as its sources (`ios/App/`, `ios/Widget/`, `ios/UITests/`, `ios/DocsScreenshots/`, `ios/RenderCheck/`, `ios/ReleaseRun/`, `ios/Packages/` except its unit tests) is app code, because XcodeGen copies it into the app as a resource.
Unit tests (`ios/Packages/TROMECore/Tests/`), the server (`server/`, its `Makefile` included: no E2E test uses it), the film (`video/`, its `Makefile` included), the shared test files of `contracts/`, the notes of `ios/changes/`,
the files of `.github/` (the GitHub workflows and forms: no build and no test of the repo reads them, and GitHub runs the workflows on its own machines) and backlog files are not app code either.
`contracts/` holds only files that tests read: no build of the app or of the server ships one.
A task that makes the app read a file of `contracts/` at run time, or makes the build or an E2E test read one of these docs files, makes it app code, and changes `is_app_code` in `ios/scripts/code-paths.sh` in the same task (`make merge` and the reader of the record of the E2E pass both use it).

- **The implementer** runs only the E2E test classes of the flows that it changed: `make e2e ONLY=SnoozeTests`, or `make e2e ONLY="SnoozeTests LiveActivityTests"` for more than one.
  The class names are the file names in `ios/UITests/`.
  When its change touches no flow of the E2E tests (for example, a rule that only unit tests cover), it runs no E2E test.
- **A reviewer** runs no E2E test, unless it changes app code.
  For example, a review with no change, or a change to the docs (Markdown files included), the unit tests or the backlog files only, runs none.
  A reviewer who changes app code runs only the E2E test classes of the flows that its change touches.
- **The manager** runs `make merge` after QA passed the task (see `.claude/rules/merge.md`).
  It runs the full `make e2e` once, after the rebase onto `main`, on the commit that it fast-forwards `main` to.
  Then it starts the app as the store ships it (`make release-run-check`, about 70 s of the lock), on the same commit.
  A task that changes only docs (Markdown and MDX files, `LICENSE`, `.claude/`), unit tests, the notes of `ios/changes/`, `server/`, `contracts/`, `video/` or `.github/` (no app code) skips both: `main` was green, and the task adds no app code.
  `make merge` sees this by itself.
- **QA** runs no automated tests.
  It explores the app like a real user.

These rules do not change the rule on flaky tests (below): a failing test may be rerun once, to know if it is flaky.
