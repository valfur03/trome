# Write the docs

This guide is for anyone who writes or reviews a page of this repo: the pages of the docs site in this folder, and the Markdown pages such as the README.
People use it, and so do coding assistants such as Claude Code.
It shows how to run the site and add a page, how to write a page that its reader can use, and what a review of a page looks for.
`CLAUDE.md` and the folder `.claude/` are the exception: they are the manual of Claude Code, and they keep their own style.

## Run the site

The site is built with [Starlight](https://starlight.astro.build), on Astro, and needs Node 24, the version in [`.nvmrc`](../.nvmrc).
The first time, install that version with [nvm](https://github.com/nvm-sh/nvm), from the root of the repo:

```sh
nvm install
```

Then run `nvm use` in each new terminal, before a docs command.
If the active Node is too old, the docs commands stop and tell you so.

Run the docs commands from the root of the repo:

| Command | What it does |
|---|---|
| `make docs-dev` | Serves the site at http://localhost:4321, and reloads the page each time you save a file. The search box does not work here. |
| `make docs` | Builds the site as it is published, and serves it at http://localhost:4321, with the search. |
| `make docs-stop` | Stops the server when it runs in the background, which Astro does when the command does not run in a terminal. In a terminal, press Ctrl + C instead. |
| `make docs-check` | Runs the tests of the components, checks the pages, builds the site, and fails on a broken internal link. |

To use another port, add `PORT=<n>`, for example `make docs-dev PORT=4400`.
The first docs command installs the packages in `docs/node_modules`, about 300 MB.
`make check`, the quality gate of the repo, runs `make docs-check` when your branch changes a file in `docs/`.

## Add a page

Each page is an `.mdx` file in [`src/content/docs/`](src/content/docs/).
Its folder gives its section in the sidebar: a page in `tutorial/` shows under **Tutorial**.
A new folder needs a section of its own in [`astro.config.mjs`](astro.config.mjs).
Its address is its path, so `tutorial/install-on-your-iphone.mdx` is at `/tutorial/install-on-your-iphone/`.

Start the file with a title and a description, which search engines and link previews show.
`sidebar.order` sets the place of the page in its section:

```mdx
---
title: Renew the app every 7 days
description: Install the app again from Xcode before it stops, in about 5 minutes.
sidebar:
  order: 2
---
```

A page for riders has a French page and an English page, with the same facts, and both come in the same change.
The site has no French section yet, so for now every page is in English.

### The components

| Component | Use it for |
|---|---|
| [`Steps`](https://starlight.astro.build/components/steps/) | a numbered list of actions that the reader does in order |
| [`Aside`](https://starlight.astro.build/components/asides/) | a callout: `type="caution"` or `type="danger"` for a risk, `type="note"` or `type="tip"` for a fact that the reader must not miss |
| [`Checklist`](src/components/Checklist.astro) | a tick box on each item of a step list, and a count at the top ("3 of 11 steps done"); add `kind="things"` for a list of things to have ("3 of 8 things ready") |
| [`Screenshot`](src/components/Screenshot.astro) | one picture of the app |
| [`Screenshots`](src/components/Screenshots.astro) | pictures side by side, each in its own `Screenshot` |

Give each `Checklist` its own `id`: the browser saves the ticks of the reader under it.
Show a picture of the app only with `Screenshot`, never with a Markdown image or the `Image` component of Astro.
`Screenshot` shows the picture 300 pixels wide, with the rounded corners of an iPhone screen, and the browser downloads a small file that fits its screen:

```mdx
import Screenshot from '../../../components/Screenshot.astro';
import appMainScreen from '../../../assets/screenshots/app-main-screen.png';

<Screenshot src={appMainScreen} alt="The main screen of the app: the button to show the Live Activity of the nearest station, the automatic mode, and the permissions." />
```

## Make the pictures again

The pictures of the app come from a test that runs the app in the iPhone Simulator, so you can make them again each time the app changes.
When a change alters a screen that a page shows, make the pictures again, and commit the new files:

```sh
make docs-screenshots
```

It builds the app with no train data key, gives the Simulator a fixed position (near Champ de Mars Tour Eiffel) and a fixed clock, and saves each picture in [`src/assets/screenshots/`](src/assets/screenshots/), under a fixed name.
A change of text alone needs no new pictures.

The script fails when a picture breaks one of these rules:

- **Full screen, on one iPhone model.** Then all pictures have the same size side by side.
  A picture of the Live Activity shows the whole Notification Center, not a crop.
- **900 pixels wide.** The page shows a picture 300 pixels wide, and the 3x screen of an iPhone needs three times as many pixels.
- **At most 500 KB for each file.** The files stay in the git history for good, and each new run adds them again.
  The script compresses them with no visible loss, and the reader downloads smaller files that Astro makes from them.

To add a picture, add a `saveScreenshot(named:)` call to [the test](../ios/DocsScreenshots/DocsScreenshotTests.swift), and its name to `names` in [the script](../ios/scripts/docs-screenshots.sh).

## Write a page

### Start from the reader

Before you write, name the reader of the page and the job they came to do.
A page serves one main reader.
Other readers may use it, but you do not write it for them.
The readers of this repo are:

- a **visitor**, who found the repo or the site and wants to know what the app is, and whether it is for them;
- a **rider**, who has the app and wants to read the Live Activity, fix a problem, or know what happens to their data;
- a **builder**, who wants the app on their own iPhone without the App Store;
- a **contributor**, who wants to change the code or the docs;
- the **maintainer**, who releases a version and keeps the accounts.

The first lines of the page say what it gives, and to whom, so that the reader knows from the first screen if the page is for them.

- Not: "This page explains the PRIM integration."
- But: "To show live train times, the app that you build needs a free key from PRIM, and this page shows how to get one and add it."

### Pick one kind of page

Each page is one of four kinds ([Diátaxis](https://diataxis.fr/)).
When a page needs another kind, it links to a page of that kind.

| Kind | The reader wants to | The page has | The page does not |
|---|---|---|---|
| Tutorial | learn by doing, from nothing | one path that works from a clean start; each step is one action, then what the reader sees | offer choices, or stop to explain |
| How-to | get one task done | the goal in its title, what you need first, the steps, and the result | teach the basics, or tell the background |
| Reference | look up a fact | complete facts, in tables and lists that are easy to scan | tell a story, or give steps |
| Explanation | understand how or why | the ideas, the reasons and the limits, in prose | give steps |

### Write the way a person speaks

Use short sentences and common words: many readers do not have English as their first language.
But link the sentences the way a person speaks, with "so", "but", "then" and "when".
Read each sentence aloud, and rewrite the ones that no person would say.

- Not: "The docs need Node 24. The file `.nvmrc` pins it. Install it one time with nvm."
- But: "The site needs Node 24, the version in `.nvmrc`, so install it once with nvm."

Write "you", and use the active voice: "Tap **Allow**", not "Allow must be tapped".
Name each thing the way the reader sees it, with the label of the screen or of the iOS menu, in bold: **Settings > Privacy & Security**.
Use one term for one thing, and the same term as the app: if the app says **Snooze**, do not write "pause" on one page and "mute" on the next.
Leave out filler, such as "please note", "simply" or "easy".

### Write the riders' pages in French

Most riders are French.
Write their pages in French first, the way a Paris rider would write them, not as a translation of the English page.
Use the words of the RATP signs and of iOS in French, then write the English page with the same facts.

| English | French |
|---|---|
| Live Activity | activité en direct |
| lock screen | écran verrouillé |
| Notification Center | Centre de notifications |
| Dynamic Island | Dynamic Island |
| next trains | prochains passages |
| Approaching | À l'approche |
| At the platform | À quai |
| No trains | Pas de train |
| Automatic mode | Mode automatique |
| Snooze, Snoozed | Mettre en pause, En pause |
| Permissions | Autorisations |
| Settings | Réglages |
| Tap | Touchez |

For any other label of the app, use its text in the String Catalogs, [of the app](../ios/App/Localizable.xcstrings) and [of the Live Activity](../ios/Widget/Localizable.xcstrings).

### Choose the right shape

**A step list** is only for actions that the reader does in order.
Each step is one action, then what the reader sees.
A list of facts is not a step list.

```mdx
<Steps>

1. On the iPhone, open **Settings > Privacy & Security**.

2. Turn on **Developer Mode**.
   The iPhone asks to restart: tap **Restart**.

</Steps>
```

- Not: a numbered list of facts, such as "1. The app uses PRIM." and "2. PRIM needs a key."

**A section** answers one question of the reader, and its heading is that question or task, in the reader's words.

- Not: "## Notes", or "## About the permissions".
- But: "## The Live Activity does not start by itself".

**A table** is for a behaviour with many states, or for facts that the reader compares.
A sentence that lists six cases is hard to read, and a case is easy to miss:

| The next train | The compact Dynamic Island shows |
|---|---|
| comes in 4 minutes | 4 |
| is approaching | 0 |
| is at the platform | At the platform |
| comes in more than an hour | > 1 h |
| none is announced | No trains |
| the times are old, or not loaded yet | a dash |

**A callout** is only for a risk, or for a fact that the reader would otherwise miss and regret.
Use about one for each screen at most: when everything stands out, nothing does.
A text that belongs in the flow of the page stays in the flow.

```mdx
<Aside type="danger" title="The app stops opening after 7 days">
  With a free Apple ID, the app works for 7 days.
  Install it again from Xcode before that.
</Aside>
```

- Not: a note that says "Start with the tutorial", which is a link in the first lines.
- Not: a note that says "This page does not cover the App Store", which is a sentence of the first lines.

### Give a reason only when the reader needs it

A reason belongs on a page when the reader needs it to act, or to trust the page.
Leave out the history of the team: no dates of decisions, no measurements, no task numbers, and no "we decided".

- Not: "After the tests of September, the team chose to ask for Always."
- But: "Tap **Change to Always Allow**: then the app can tell you when you arrive at a station, even when it is closed."

### Say once what you could not check

Run each command that you write, open each link, and follow your own steps as the reader would, from a clean start when you can.
When you cannot check a part, for example the steps on a real iPhone, say it once, at the top of the page or of the part, and tell the reader what to do when a step is wrong.
Do not repeat it on each step.

- Not: "_No picture: Xcode screen._" under twenty steps.
- But, once at the top: "Nobody has followed these steps on a real iPhone yet: if a step does not match what you see, open an issue."

### Be concrete

Put each command in a code block that the reader can copy.
On the site, inline code never breaks across two lines, so keep it under about 30 characters, and put a longer command in a code block.
After a step, say what the reader should see.

Show the current app, with `Screenshot`.
Its alt text says what the picture shows, in the language of the page, for a reader who cannot see it.

- Not: `alt="Screenshot"`, or `alt="Main screen"`.
- But: `alt="The iPhone asks: Allow the app to use your location? The buttons are Allow Once, Allow While Using App, and Don't Allow."`

### Give each fact one home

Each fact lives on one page, the page of the reader who needs it, and the other pages link to it.
A copy goes out of date the first time the fact changes, and then nobody knows which copy is right.
For example, a tutorial says in one line that the app stops after 7 days, and links to the page that shows how to renew it.

### Write one sentence per line

Write each sentence of a Markdown or MDX file on its own line, and never reflow a paragraph: a change to one sentence then shows as a change to one line, and the review sees what changed.

## Review a page

Read the page as its reader would, then go through these points.
They help your judgement; they are not boxes to tick.
A finding names the reader who would stumble, the place, and why.
For example: "A builder who has never used Terminal stops at step 7: it does not say in which folder to run the command."

1. **Reader and job.** The page serves one main reader, and its first lines say what it gives.
   A second reader gets a link, or a page of their own.
2. **Kind.** The page is one kind.
   A tutorial works from a clean start; a how-to has its goal, what you need, the steps and the result; a reference is complete and easy to scan; an explanation has no steps.
3. **Each section earns its place.** For each section, ask what this reader would lose without it.
   If the answer is nothing, the section goes.
4. **Nothing for another reader.** No inner workings of the team, no history, no measurements, no task numbers, and a reason only when the reader needs it.
5. **Voice.** A person would say each sentence aloud.
   The page is plain, direct and warm, with no filler, and its terms match the app and iOS.
6. **True.** Each command was run, each link was opened, and the steps were followed as the reader follows them.
   What could not be checked is said once.
7. **Pictures.** They show the current app, and each alt text says what the picture shows, in the language of the page.
8. **One home for each fact.** A fact is on one page, and the other pages link to it.
9. **French.** A riders' page reads as French that a Paris rider would write, and the French and English pages say the same facts.
10. **The checks pass.** `make check` checks the length of the lines, the public text and the internal links of the site, and `make docs-screenshots` checks the pictures.
