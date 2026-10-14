# Rules for agents

This file is the manual of Claude Code for this repo, and every session loads it.
It holds only what every job needs: where to start, the rules that no agent may break, and a map of the other rules, which load where their work is.
The front page, `README.md`, is for a stranger who lands on the repo: it holds no rule and no command.

## Where to start

Read only the part of the docs that your job needs, never a whole long page: every file that you read stays in the context of each later call.
The guides of `ios/guide/` are long: read one only when your job needs it.
`make help` lists every `make` command, with one line each.

| Job | Start with | Size |
|---|---|---|
| Change the iPhone app | `ios/README.md`, from its start to the end of its index "The guides" (setup, everyday commands, the shared Simulator, before you commit, the guides); then only the guide of the feature of the task, in `ios/guide/` | 5 KB, then 3 to 16 KB |
| QA | as above | as above |
| Add or change a test of the app | `ios/guide/tests.md` | 7.2 KB |
| Change the server | `server/README.md`; `server/guide/how-it-works.md` when the API or the quota changes | 2.5 KB; 6.6 KB |
| Review a change | the start file of the part that the diff touches, as above | as above |
| Write or review a docs page | `docs/README.md`, section "Write a page" or "Review a page" | 10.4 KB or 4.1 KB |
| Product Owner, manager | nothing in the repo: this file, the backlog, and the rules that your commands bring | none |
| An outside contributor's view | `CONTRIBUTING.md` | 5.2 KB |

## How the other rules load

Every other rule is in a file of `.claude/rules/`, one file per topic.
A rule file loads by itself where its work is, once per session:

- when you read, write or edit a file that its `paths:` list names, in this folder or in any worktree of the repo;
- when the output of a command shows a diff of such a file (`git diff`, `git show`), or a command reads such a file (`cat`, `sed -n`);
- when you run a command that its `commands:` list names;
- when you start an agent whose type its `agents:` list names.

Claude Code loads a `paths:` rule only for a Read, a Write or an Edit of a file inside the folder where the session started.
The hook `.claude/hooks/rules.py` (set in `.claude/settings.json`) covers the other cases with the same lists: a worktree beside that folder, a command, a diff, an agent.
Before a command, an edit or an agent, the hook stops it once and gives you its rules: read them, then do the same thing again.
After a read or a diff, it adds the rules next to the output.
Why: every call reads the whole context again, so a rule that loads for every job costs on every call of every agent; and a rule that guards a command must reach the agent that runs it, even if that agent never reads a matching file.
When you add a rule, put it in the file of its topic, with a `paths:` or `commands:` list that brings it to every job that needs it; put it here only if every job needs it.
`ios/scripts/tests/claude-rules-test.sh` checks the hook, the lists of every rule file, and the size of this file.

| Rule file | What it holds | It loads when you |
|---|---|---|
| `ios-code.md` | Code structure of the iOS app, the texts in French and English, no warnings | touch `ios/App/`, `ios/Widget/`, `ios/Packages/`, `ios/UITests/`, `ios/RenderCheck/`, `ios/DocsScreenshots/`, `ios/project.yml`, `ios/Config/` |
| `tests.md` | Test levels, which E2E tests to run | touch the same app files or the tests; run `make e2e` |
| `simulator.md` | The shared Simulator, the lock, hold it only while you use it, when your job ends | run a command that uses a Simulator (`make run`, `make e2e`, `make merge`, `sim-lock.sh`, ...); touch the lock scripts |
| `simulator-history.md` | The measurements behind the Simulator rules, and the code of the second slot | touch the lock scripts or `ios/scripts/timing/` |
| `qa.md` | QA: French first | run `make run` or `make switch-language` |
| `live-data.md` | Live train data: who uses `LIVE=1`, the PRIM budget of a QA run | run a `make` command with `LIVE=1`; start a QA agent; touch `ios/Config/`, `ios/scripts/live-key-check.sh` |
| `render-check.md` | The Live Activity render check | run `make live-activity-render`; touch `ios/Widget/`, `ios/RenderCheck/`, the Live Activity code of `TROMECore`, the line badge (`TROMEBadge`), the render scripts |
| `merge.md` | Merge a task into `main` | run `make merge`, `git rebase`, `git merge`, `git pull`; touch `ios/scripts/merge.sh` |
| `github.md` | GitHub secrets, environments, release workflows, the review of a workflow | touch a workflow; run `gh` on them |
| `tooling.md` | The shared build cache, the git hooks | touch `ios/scripts/`, the `Makefile` files |
| `server.md` | Code structure of the server, the server and its commands | touch `server/`, `contracts/`; run `make server-...` |
| `docs-site.md` | The docs site: Node 24, port, screenshots | touch `docs/`; run `make docs...` |
| `video.md` | The film: its renders and its studio | touch `video/`; run `make video-...` |
| `assets.md` | The docs, store page and video stay true to the app; the "Assets:" line of the notes | touch an asset, its source or what it shows; run `make run` |
| `writing.md` | Who writes the pages, where a change writes its text, the public text check | touch a Markdown or MDX file, or the text checks |

## The rules that no agent may break

- **Never a second Simulator on this Mac.** On 2026-09-28, the prompter decided that no design may boot or keep a second Simulator running on this Mac, for any reason: a faster job, a Simulator for QA, a Simulator for `make run`, or the second job slot (doc-3, "no second Simulator on this Mac"; doc-1, section "Testing").
  Why: the boot of a second Simulator next to a booted one, even with no job running, already takes the Mac to an unsafe load (234 to 333, TASK-106; the measurements are in `.claude/rules/simulator-history.md`).
  This is a closed decision, not a trial on pause.
  Only the prompter, in person, can open it again, and only with a new reason (for example, a different Mac).
  Never propose, build or measure a new design with a second Simulator.
  This also covers the two iPhone sizes: every job and every `make run`, `make run SMALL=1` included, uses one shared Simulator at a time (TASK-119, see `.claude/rules/simulator.md`).
- **At most one Simulator job** runs at a time on the machine.
  A lock enforces it: run every command that boots or uses a Simulator through it (`.claude/rules/simulator.md`).
  Why: on 2026-09-26, each worktree booted its own iOS Simulator, and seven Simulators ran at once on the 8-core Mac.
  The load average went above 600, and the prompter could not work.
- **The factory runs at most 3 Software Engineers** in parallel for this repo.
  Why 3: the cap was 2 after that day.
  Two checks now protect the Mac, so the prompter set it back to 3 (2026-09-26).
  The factory starts a new agent only when at least 25% of the CPU is idle.
  The Simulator lock and the shared Simulator keep the Simulator jobs to one at a time.
- **Never read, print, copy or commit the PRIM key.** The real key is in the main repo folder only, in `ios/Config/Secrets.xcconfig` (or at its old place, `Config/Secrets.xcconfig`, until the prompter moves it).
  Worktrees do not have it.
  Do not open `ios/Config/Secrets.xcconfig` or `Config/Secrets.xcconfig`.
  Do not copy it into a worktree.
  Never inspect a build made with `LIVE=1` (in `ios/.build/`, or installed in the Simulator): the key is inside.
  Only QA uses `make run LIVE=1`; Software Engineers and the quality gate never do (`.claude/rules/live-data.md`).
- **Never run `make git-hooks` or `make git-hooks-off`.** They change `core.hooksPath` in the git config, and all the worktrees share it with the prompter's main folder.
  Only the prompter turns the hooks on or off.
- **No deploy and no account.** Only the prompter runs `make server-login`, `make server-secrets`, `make server-secret`, `make server-deploy-staging`, `make server-deploy` and `make server-counts` on a deployed server, with his Cloudflare account and his owner token.
  An agent never runs them, never logs in to Cloudflare, and never reads the real secrets.
- **The shared build cache.** Only the prompter runs `make clean-shared-cache`.
  Never delete `~/Library/Caches/TROME/` by hand: a build that runs at that moment fails.
- **The prompter's main folder.** No agent commits, stashes or discards the changes of the prompter's main folder without the prompter.

## Flaky tests

A flaky test (it fails, then passes with no change) is a bug.
Rerun a failing test at most once, to know if it is flaky.
Then fix the cause in your task if the test covers your code.
Otherwise, create a `bug` task with the test name, how often it failed, the error, and the evidence folder that the failed run printed.
That task is priority high, and it is fixed before new work (the prompter's order of 2026-10-07).
Never fix it with retries or longer timeouts alone: find the cause (a race, a shared state, a missing wait for a condition).

## Repo layout

Each part of the repo has its own folder: `ios/` (the iPhone app, with its config and scripts), `docs/` (the docs site), `server/` (the server, a Cloudflare Worker, decision-40), `video/` (the film) and `contracts/` (the files that the app and the server both test against, decision-6 section 3).
The root holds only the files of the whole repo: `README.md`, `CLAUDE.md`, `Makefile`, `.gitignore`, `.nvmrc`, `.claude/` (the rules and the hook of Claude Code), and `.github/` (the GitHub workflows, which GitHub reads only at the root).

- Run the `make` commands from the root.
  The root `Makefile` has no build logic: it runs each command in the `Makefile` of its part (`make e2e` runs `make -C ios e2e`).
  A new command goes in the `Makefile` of its part, and its name goes in the list of the root `Makefile`.
- A file goes in the folder of the part it serves: its scripts in `<part>/scripts/`, its config and its build output in its folder.
  Never add a file of one part at the root.
- The paths in this file and in `.claude/rules/` are from the root.

## Write in the repo

- **Keep the docs true.** A task that changes a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task.
  Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images.
  A docs text change alone needs no new screenshots.
  The reviewer checks it.
  `.claude/rules/writing.md` says which file a change edits; it loads when you open a Markdown file.
- **One sentence per line.** Write each sentence of a Markdown or MDX file of the repo on its own line.
  When one sentence is longer than 400 characters, break the line after a comma, a colon or a semicolon.
  When a change makes a sentence false, edit only that sentence, and never reflow a paragraph.
  Tables and code blocks may have long lines.
  Why: git merges by line, so two tasks that change two sentences of one long line conflict (TASK-173).
  `make prose-check` (part of `make check`) fails on a line of prose longer than 400 characters.
- **Public text.** The repo is public: anyone can read the README, the docs and the code.
  So a file of the repo has no backlog id, no word of the team's own way of working (the prompter, the factory, the manager, agents), no personal data (for example an email address that is not an example one), no local path of a computer, and not the old name of the app.
  Write the rule and its reason instead.
  Why: a stranger cannot open a private task, but they can read a reason.
  `make public-text-check` (part of `make check`) fails on each of these, and prints the file, the line and the reason (its details: `.claude/rules/writing.md`).
  `CLAUDE.md` and `.claude/` are the manual of Claude Code: they may cite the backlog, but never personal data or a local path.
