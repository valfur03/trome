---
paths:
  - "**/*.md"
  - "**/*.mdx"
  - "ios/scripts/prose-check.py"
  - "ios/scripts/public-text-check.py"
  - "ios/scripts/page-date-check.py"
  - "ios/scripts/repo_files.py"
  - "ios/changes/**"
  - "ios/scripts/change-notes-check.py"
  - ".gitignore"
---
# Write in the repo: who writes the pages, and where a change writes its text

These rules are for every change to a Markdown or MDX file of the repo, and for a docs review.
The rules for every file (keep the docs true, one sentence per line, public text) are in `CLAUDE.md`.

- **Who writes the pages.** The Technical Writer writes and rewrites the docs pages (decision-49, section 9).
  A Software Engineer writes only the docs lines that its own change makes false, in the file that the table below names.
  Why: each page is written for one reader and one job (decision-49); a page that grows by the facts of each task stops serving its reader, as the README did.
- **The writing guide and the review bar.** A page follows `docs/README.md` ("Write a page"), and a docs review uses its "Review a page", the public form of the bar of decision-49 section 5.
  These rules for agents stay out of the public pages: `CONTRIBUTING.md` is for an outside contributor, and the checks below explain themselves when they fail.
- **A page is compared with the vision, not only with the code diff.** The checks see the lines that a change makes false, so a page that is true of the code and wrong for the product passes them (the notification told as the way TROME works, on every page, passed every review and QA).
  The ledger of vision-bound sentences lists each sentence that tells a behaviour that the vision will change, with the event that changes it.
  The Product Owner keeps it in doc-6, section "Ledger of vision-bound sentences".
  - The writer reads it before editing a page that it names, writes the behaviour as it works today, once, and tells the Product Owner about each new sentence of that kind, so that it gets a row.
  - The reviewer reads it for any change that touches a page or a behaviour that it names, and uses point 3 of "Review a page" for a docs page.
    A merge that makes a ledger line false and leaves it is refused.
  - A ticket or a decision that changes, ships or defers a behaviour that the vision names (the Live Activity, how it starts, hubs, the Dynamic Island, the permissions, the look of the platform screens) names in its criteria the pages that say it.
    They change in the same merge, or in a docs ticket that merges with it.
    The Product Owner writes that criterion, and the reviewer checks it.
  Why: only a page read against the vision shows that it will mislead; and a swap that nobody owns when the behaviour ships is forgotten.
- **The public text check.** `make public-text-check` applies the rule "Public text" of `CLAUDE.md`.
  Its word list is in `ios/scripts/public-text-check.py`.
  It also fails on the old names of the Xcode project and of its module (in the word list, in any case): only the files that remove what a build of the old name left on a Mac or on the Simulator may write the old project name, and `ALLOWED_TEXTS` lists them with the reason.
  When a hit is a normal word in its place (for example the name of a type), add it to `ALLOWED_TEXTS` in that file, with its path, its text and the reason.
  Only `CLAUDE.md` and `.claude/` may cite the backlog (`INTERNAL_FILES`).
  Every other file passes the whole check, the front page `README.md`, `ios/README.md` and `server/README.md` included: the rewrites of TASK-202, TASK-203 and TASK-204 moved the feature text to `ios/guide/`, so no text for readers is exempt.
  It also fails on a team's voice ("we", "us", "our", "let's"; "nous", "notre", "nos") in the prose of every Markdown and MDX file, `CLAUDE.md` and `.claude/` included, but not in code, link addresses or double or curly quotes: one person makes TROME, so a page says "I" (doc-1, "The voice: one person, I");
  the app texts are not Markdown and the check does not read them, so their review checks the voice.
  The only files that it skips, `SKIPPED_FILES`, are the check itself (its word list), its test (the examples that it must find) and a file that a tool generates, each with its reason.
- **The date line.** A change to the text of a page with a date line ("Last updated", "Dernière mise à jour") sets that line to the day of the change, the same in each language, and `make page-date-check` (part of `make check`) fails when it does not.
- **The scratch folder.** Keep your scratch files (notes, logs, screenshots) in `.review/` at the root of your worktree, and nowhere else in it.
  `.gitignore` ignores that folder, and only that one: `make public-text-check`, `make prose-check` and every check that reads the files of the repo (`ios/scripts/repo_files.py`) read the files of git and the new files that git does not ignore, so a scratch file never changes their result, and `git add -A` never commits it.
  A new file anywhere else, a `.review/` folder inside a part of the repo included, is still checked before its first commit (`ios/scripts/tests/public-text-check-test.sh`).
  Why: the checks read the new files so that a mistake shows before the commit, and they failed on the notes of an agent (TASK-465).
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
  | The notes of a version | a note file in `ios/changes/`, in the same change, or none (`ios/changes/README.md` gives its format and kinds); a change of the app code with no note ends a commit title with "(no rider change)", or `make check` fails. The reviewer of the change confirms a headline, never the author alone: it reads the kind against the test "a rider would tell a friend about it, a one-line story", and the line against the diff. A detail that a rider sees, finer but not new (a number drawn better), is an item, never a headline. A fix of a pending note edits that note, and adds no second line. "What's new" and `CHANGELOG.md` are made from the notes at each release (decision-109) |
  | The server | `server/README.md` or `server/guide/` |
