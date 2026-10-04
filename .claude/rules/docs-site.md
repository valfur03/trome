## The docs site (`docs/`)

`docs/README.md` explains the docs site and its commands (section "Run the site").

The rules on writing (who writes the pages, the writing guide, one sentence per line, public text, where a change writes its text) hold for the whole repo, not only for `docs/`.

- **Keep the docs true.** A task that changes a step, a `make` command, a setting or a screen that the docs show also updates the docs, in the same task.
  Run `make docs-screenshots` only when a screen that the docs show changed, and commit the new images.
  A docs text change alone needs no new screenshots.
  The reviewer checks it.
- **Who writes the pages.** The Technical Writer writes and rewrites the docs pages (decision-49, section 9).
  A Software Engineer writes only the docs lines that its own change makes false, in the file that the table below names.
  Why: each page is written for one reader and one job (decision-49); a page that grows by the facts of each task stops serving its reader, as the README did.
- **The writing guide and the review bar.** A page follows `docs/README.md` ("Write a page"), and a docs review uses its "Review a page", the public form of the bar of decision-49 section 5.
  These rules for agents stay out of the public pages: `CONTRIBUTING.md` is for an outside contributor, and the checks below explain themselves when they fail.
- **One sentence per line.** Write each sentence of a Markdown or MDX file of the repo on its own line.
  When one sentence is longer than 400 characters, break the line after a comma, a colon or a semicolon.
  When a change makes a sentence false, edit only that sentence, and never reflow a paragraph.
  Tables and code blocks may have long lines.
  Why: git merges by line, so two tasks that change two sentences of one long line conflict (TASK-173).
  `make prose-check` (part of `make check`) fails on a line of prose longer than 400 characters (CLAUDE.md is skipped until it is split by topic).
- **Public text.** The repo is public: anyone can read the README, the docs and the code.
  So a file of the repo has no backlog id, no word of the team's own way of working (the prompter, the factory, the manager, agents), no personal data (for example an email address that is not an example one), no local path of a computer, and not the old name of the app.
  Write the rule and its reason instead.
  Why: a stranger cannot open a private task, but they can read a reason.
  `make public-text-check` (part of `make check`) fails on each of these, and prints the file, the line and the reason.
  Its word list is in `ios/scripts/public-text-check.py`.
  It also fails on the old names of the Xcode project and of its module (in the word list, in any case): only the files that remove what a build of the old name left on a Mac or on the Simulator may write the old project name, and `ALLOWED_TEXTS` lists them with the reason.
  When a hit is a normal word in its place (for example the name of a type), add it to `ALLOWED_TEXTS` in that file, with its path, its text and the reason.
  `CLAUDE.md` and `.claude/` are the manual of Claude Code: they may cite the backlog, but never personal data or a local path.
  For now, the check also lets `ios/README.md` cite the backlog, until the rewrites of its feature sections (TASK-203, TASK-204) move them to the files of the table below: the last one removes its line from `INTERNAL_FILES`.
  `server/README.md` passes the whole check since TASK-202.
  The front page, `README.md`, passes the whole check.
- **Where a change writes its text.** Each text lives in one file, chosen by its reader.
  Link to the file that holds a fact, and never copy the fact.
  A text in the wrong file is asked to move in the review, like a code file in the wrong folder.
  Some of these files do not exist yet: until a file exists, edit the section of `ios/README.md` or `server/README.md` (or of `CLAUDE.md`, for a rule for Claude Code) on the same topic.
  Never add a command, a step or a rule to the front page, `README.md`: it only says what TROME is, how to get it, and where to go next.

  | Kind of change | The file that the change edits |
  |---|---|
  | A new or changed `make` command | the `help` line of its Makefile, and the guide page of its topic; `CONTRIBUTING.md` only when a command that it names changes |
  | A changed rule that a rider sees (the Live Activity) | the guide file of its feature (`ios/guide/<feature>.md`); a rider page of the docs site only when its summary becomes false |
  | The internals of a type | the doc comment on the type |
  | A new feature folder | a new guide file, a line in `ios/README.md`, a line in `ARCHITECTURE.md` |
  | Structure or dependency direction | `ARCHITECTURE.md` |
  | A screen that the docs site shows | the page of the site, and its screenshots |
  | A rule for Claude Code | the file of its topic in `.claude/rules/` |
  | A product rule | the decision in the backlog, outside the repo; the repo states the behaviour and its reason |
  | The notes of a version | not in a change: "What's new" and `CHANGELOG.md` are written at each release |
  | The server | `server/README.md` or `server/guide/` |
- **Node 24.** Each Bash call starts a new shell with the old default Node.
  Run the docs commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make docs-check`.
  The same goes for `make check` when your task changes `docs/`.
- **Install `docs/node_modules` only when your task touches the docs.** It takes about 300 MB.
  `make check` runs `make docs-check` only when your branch changes `docs/`, so the other tasks never install it.
- **Use your own port.** The default port 4321 is for the prompter.
  Run `make docs PORT=<n>` or `make docs-dev PORT=<n>` with a port that no other agent uses (for example 4300 plus your task number).
- **Stop the docs server when your job ends.** For agents, Astro starts the server in the background and the command returns at once.
  Run `make docs-stop` in your worktree before you end.
- **Screenshots.** Show each app screenshot with the `Screenshot` component (`docs/src/components/Screenshot.astro`), never with a Markdown image or the `Image` component.
  Put screenshots side by side inside `Screenshots`.
  Take each screenshot full screen on a shared iPhone 17 Simulator (`make docs-screenshots` does), so all have the same size.
  Each file in git stays under the budget of `docs/README.md` (section "Make the pictures again").
  The script checks the size and the budget.
