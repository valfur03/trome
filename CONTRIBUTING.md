# Contributing to TROME

TROME shows the next metro and RER trains of the nearest Paris station on the iPhone lock screen.
This page is for people who change its code or its docs.

## Issues and pull requests

Issues are welcome: a bug, a question or an idea.
If you want to send a pull request, open an issue first and ask.
Why: the app is small and shaped by one owner, and a pull request that the team cannot take would cost you a day of work.

## Before you start

The [README](README.md) explains, for now, what you need, the first setup and the everyday commands.
`make help` lists every command.

## How a change lands

Make your change on a branch, and run `make check` (the quality gate) before each commit.
Another person reviews the change, then it lands on `main` by a rebase and a fast-forward, so the history stays linear.

## One sentence per line

Write each sentence of a Markdown or MDX file on its own line.
When one sentence is longer than 400 characters, break the line after a comma, a colon or a semicolon.
When a change makes a sentence false, edit only that sentence, and never reflow a paragraph.
Why: git merges by line, so two changes to two sentences of one long line conflict.
`make prose-check` (part of `make check`) fails on a line of prose longer than 400 characters.
Tables and code blocks may have long lines.

## Public text

This repo is public: anyone can read the README, the docs and the code.
So a file of the repo has no number or name from the team's private task list, no word of the team's own way of working, no personal data and no local path of a computer.
Write the rule and its reason instead: a stranger cannot open a private task, but they can read a reason.
`make public-text-check` (part of `make check`) fails on each of these, and prints the file, the line and the reason.
Its word list is in `ios/scripts/public-text-check.py`.
When a hit is a normal word in its place (for example the name of a type), add it to `ALLOWED_TEXTS` in that file, with its path, its text and the reason.
`CLAUDE.md` and the folder `.claude/` are the manual of Claude Code, the coding assistant that works on this repo.
They may cite the private task list, but never personal data or a local path.
For now, the check also lets `README.md` cite it, until its sections move to the files of the table below.

## Where a change writes its text

Each text lives in one file, chosen by its reader.
Link to the file that holds a fact, and never copy the fact.
A text in the wrong file is asked to move in the review, like a code file in the wrong folder.

| Kind of change | The file that the change edits |
|---|---|
| A new or changed `make` command | the `help` line of its Makefile, and the guide page of its topic; `CONTRIBUTING.md` only when one of its everyday commands changes |
| A changed rule that a rider sees (the Live Activity) | the guide file of its feature (`ios/guide/<feature>.md`); a rider page of the docs site only when its summary becomes false |
| The internals of a type | the doc comment on the type |
| A new feature folder | a new guide file, a line in `ios/README.md`, a line in `ARCHITECTURE.md` |
| Structure or dependency direction | `ARCHITECTURE.md` |
| A screen that the docs site shows | the page of the site, and its screenshots |
| A rule for Claude Code | the file of its topic in `.claude/rules/` |
| A product rule | the team's decision record, outside the repo; the repo states the behaviour and its reason |
| The notes of a version | not in a change: "What's new" and `CHANGELOG.md` are written at each release |
| The server | `server/README.md` or `server/guide/` |

Some of these files do not exist yet.
Until a file exists, edit the section of `README.md` (or of `CLAUDE.md`, for a rule for Claude Code) on the same topic.
