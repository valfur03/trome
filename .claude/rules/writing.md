---
paths:
  - "**/*.md"
  - "**/*.mdx"
  - "ios/scripts/prose-check.py"
  - "ios/scripts/public-text-check.py"
---
# Write in the repo: who writes the pages, and where a change writes its text

These rules are for every change to a Markdown or MDX file of the repo, and for a docs review.
The rules for every file (keep the docs true, one sentence per line, public text) are in `CLAUDE.md`.

- **Who writes the pages.** The Technical Writer writes and rewrites the docs pages (decision-49, section 9).
  A Software Engineer writes only the docs lines that its own change makes false, in the file that the table below names.
  Why: each page is written for one reader and one job (decision-49); a page that grows by the facts of each task stops serving its reader, as the README did.
- **The writing guide and the review bar.** A page follows `docs/README.md` ("Write a page"), and a docs review uses its "Review a page", the public form of the bar of decision-49 section 5.
  These rules for agents stay out of the public pages: `CONTRIBUTING.md` is for an outside contributor, and the checks below explain themselves when they fail.
- **The public text check.** `make public-text-check` applies the rule "Public text" of `CLAUDE.md`.
  Its word list is in `ios/scripts/public-text-check.py`.
  It also fails on the old names of the Xcode project and of its module (in the word list, in any case): only the files that remove what a build of the old name left on a Mac or on the Simulator may write the old project name, and `ALLOWED_TEXTS` lists them with the reason.
  When a hit is a normal word in its place (for example the name of a type), add it to `ALLOWED_TEXTS` in that file, with its path, its text and the reason.
  For now, the check also lets `ios/README.md` cite the backlog, until the rewrites of its feature sections (TASK-203, TASK-204) move them to the files of the table below: the last one removes its line from `INTERNAL_FILES`.
  `server/README.md` passes the whole check since TASK-202.
  The front page, `README.md`, passes the whole check.
- **Where a change writes its text.** Each text lives in one file, chosen by its reader.
  Link to the file that holds a fact, and never copy the fact.
  A text in the wrong file is asked to move in the review, like a code file in the wrong folder.
  Some of these files do not exist yet: until a file exists, edit the section of `ios/README.md` or `server/README.md` on the same topic.
  Never add a command, a step or a rule to the front page, `README.md`: it only says what TROME is, how to get it, and where to go next.

  | Kind of change | The file that the change edits |
  |---|---|
  | A new or changed `make` command | the `help` line of its Makefile, and the guide page of its topic; `CONTRIBUTING.md` only when a command that it names changes |
  | A changed rule that a rider sees (the Live Activity) | the guide file of its feature (`ios/guide/<feature>.md`); a rider page of the docs site only when its summary becomes false |
  | The internals of a type | the doc comment on the type |
  | A new feature folder | a new guide file, a line in `ios/README.md`, a line in `ARCHITECTURE.md` |
  | Structure or dependency direction | `ARCHITECTURE.md` |
  | A screen that the docs site shows | the page of the site, and its screenshots |
  | A rule for Claude Code | the file of its topic in `.claude/rules/`, with the `paths:` or `commands:` that bring it to the jobs that need it; `CLAUDE.md` only for a rule that every job needs |
  | A product rule | the decision in the backlog, outside the repo; the repo states the behaviour and its reason |
  | The notes of a version | not in a change: "What's new" and `CHANGELOG.md` are written at each release |
  | The server | `server/README.md` or `server/guide/` |
