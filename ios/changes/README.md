# The notes of the changes

Each change of the app that a rider or a builder will notice adds one note here, in the same change.
The notes of a version are gathered from these files at its release: the What's New of the App Store, the TestFlight text, the What's new pages of the site and `CHANGELOG.md`.
`make release-notes` prints them for the next version: the notes that the build on the App Store does not hold, or `no release` when none of them is a headline.
Why: the person who makes a change knows, at that moment, what a rider will notice and in which words.

A change that nobody will notice (a refactor, a test, a tool, the docs) has no note.
When such a change touches the code of the app, the title of one of its commits ends with "(no rider change)", or an empty commit says it: `git commit --allow-empty -m "chore: no rider change"`.

## Write a note

Add one `.txt` file, named after what changes:

```text
kind: item
fr: Le numéro de ligne est bien centré dans son rond.
en: The line number sits in the middle of its badge.
```

Each language has one line, in the words of a rider.
The kind says where the line goes:

| Kind | What it is | Languages |
|---|---|---|
| `headline` | What a rider would tell a friend about, in one line: a new way in, a screen that shows something new or lays out differently, a new place, a fix of a wrong time that riders met. At most 100 characters, so that the French line fits in 2 lines on the card of an iPhone's width. | `fr` and `en` |
| `item` | A detail that a rider notices but that is not new: a number drawn better is an item, never a headline. | `fr` and `en` |
| `apple` | A requirement of Apple that stops the updates, for example a newer minimum iOS. | `fr` and `en` |
| `builder` | A change for the people who build the app. | `en` only |

A later change that fixes or completes the same thing, before its version is out, edits its note: a version tells each thing once.

## How a note is checked

`make change-notes-check`, part of `make check`, refuses a note that breaks this format.
It also refuses a branch whose commits change the code of the app (`ios/App/`, `ios/Widget/`, `ios/Packages/` except their tests) with no note and no such commit.
`make public-text-check` reads the notes too: no personal data, and one person speaks.

The review of a change reads its note against the diff, and confirms the kind of a headline: a headline is never the call of its author alone.
