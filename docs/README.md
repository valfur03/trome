# Write the docs

This guide is for anyone who writes or reviews a page of this repo: the pages of the docs site in this folder, and the Markdown pages such as the README.
People use it, and so do coding assistants such as Claude Code.
It shows how to run the site and add a page, how to write a page that its reader can use, and what a review of a page looks for.
`CLAUDE.md` and the folder `.claude/` are the exception: they are the manual of Claude Code, and they keep their own style.

## Run the site

The site is built with [Starlight](https://starlight.astro.build), on Astro, and needs Node 24, the version in [`.nvmrc`](../.nvmrc).
Install that version once with a Node version manager that reads this file, then use it for each docs command.
With [nvm](https://github.com/nvm-sh/nvm), run `nvm install` once, then `nvm use` in each new terminal.
With [fnm](https://github.com/Schniz/fnm), run `fnm install` once, then run each command through fnm, for example `fnm exec --using=.nvmrc -- make docs-dev`.
If the active Node is too old, the docs commands stop and say what to run.

Run the docs commands from the root of the repo:

| Command | What it does |
|---|---|
| `make docs-dev` | Serves the site at http://localhost:4321/, and reloads the page each time you save a file. The search box does not work here. |
| `make docs` | Builds the site as it is published, and serves it at http://localhost:4321/, with the search. |
| `make docs-stop` | Stops the server when it runs in the background, which Astro does when the command does not run in a terminal. In a terminal, press Ctrl + C instead. |
| `make docs-check` | Runs the tests of the components, checks the pages, builds the site, and fails on a broken internal link or a warning. |

To use another port, add `PORT=<n>`, for example `make docs-dev PORT=4400`.
The first docs command installs the packages in `docs/node_modules`, about 300 MB.
[`.npmrc`](.npmrc) turns off `legacy-peer-deps`, even when your own npm config turns it on: with it, npm skips `@emnapi/runtime`, a peer dependency that `astro check` needs.
`make check`, the quality gate of the repo, runs `make docs-check` when your branch changes a file in `docs/`.

The build must print no warning, so `make docs` and `make docs-check` stop on one: fix its cause, and never hide it.
The only exception is a bug of a tool that no version fixes yet: [`scripts/known-build-warnings.ts`](scripts/known-build-warnings.ts) lists each one, with its reason and the link of its upstream issue.
When a new version fixes it, the build no longer prints it, and `make docs-check` asks you to remove it from the list.
The install also says that npm found vulnerabilities, and that `npm audit fix --force` fixes them: do not run it, because it replaces Astro with a version from 2023 and breaks the site.
The vulnerabilities come from one package of Astro, `http-cache-semantics`, that has [no fixed version yet](https://github.com/advisories/GHSA-ch52-4w7c-c8xp), and the site does not use the part of it that is affected.

The search is [Pagefind](https://pagefind.app), which Starlight runs at the end of the build.
Pagefind splits a word only at a straight apostrophe, so it would index “l’écran” as one word, and a search for “écran” would find nothing.
So [`src/search-index.ts`](src/search-index.ts) indexes the site again, with a straight apostrophe after l’, d’, qu’ and the other French elisions, and a space before each line break.
The pages keep their apostrophes, but the texts of the search results show the straight ones.
The build fails when this index and the one of Starlight do not have the same version of Pagefind or the same pages in each language, for example after an update of Starlight.
Pagefind can say that it wrote its files before they are on disk, so a file of the index of Starlight can stay empty ([Pagefind issue 1271](https://github.com/Pagefind/pagefind/issues/1271)).
So `src/search-index.ts` builds the index of Starlight again in memory, compares its own index with it there, and writes the files of its own index itself.
When a release of Pagefind fixes that issue, the copy of the index of Starlight can go.
When the version differs, make `pagefind` in `package.json` the version that Starlight uses, as the message says.
When Starlight runs Pagefind in another way, `src/search-index.test.ts` fails: read `dist/integrations/pagefind.js` in `node_modules/@astrojs/starlight`, and give the same options to Pagefind in `src/search-index.ts`.

## Add a page

Each page is an `.mdx` file in [`src/content/docs/`](src/content/docs/), in the folder of its language: `fr/` or `en/`.
Its address is its path, so `fr/support.mdx` is at `/fr/support/`.
The site lives at https://trome.valfur.fr/, with no repo name in the path, and [`astro.config.mjs`](astro.config.mjs) sets this address in one place.
An address with no page shows [`src/pages/404.astro`](src/pages/404.astro), one page in French and English, because the site cannot know the language of a mistyped address.

The sidebar has one section for each reader, set in `astro.config.mjs`:

- **Utiliser TROME** (**Use TROME** in English) lists the riders' pages one by one, so add a new riders' page to its list.
- **Build it yourself** shows each page of `en/build/`.
- **Maintain** shows each page of `en/maintain/`: the pages for the maintainer, who releases the app.

Write a link to another page of the site with its language, for example `[Aide](/fr/support/)`: Astro does not add it.

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

A page for riders has a French page and an English page at the same path, with the same facts, and both come in the same change.
The language menu of each page then opens the same page in the other language.
`make docs-check` fails when a riders' page exists in one language only.
The pages for builders are in English only, in `en/build/`, and the French home links to them.
The pages for the maintainer are in English only too, in `en/maintain/`, and no home links to them.
[`src/site-pages.ts`](src/site-pages.ts) lists these English-only folders.
A page in English only shows no language menu ([`src/components/LanguageSelect.astro`](src/components/LanguageSelect.astro)), because its French page does not exist.
On a phone, Starlight puts the language menu inside the menu of the sidebar, so a page with no sidebar, such as the home, shows it in the header instead ([`src/components/Header.astro`](src/components/Header.astro)).

### The components

| Component | Use it for |
|---|---|
| [`Steps`](https://starlight.astro.build/components/steps/) | a numbered list of actions that the reader does in order |
| [`Aside`](https://starlight.astro.build/components/asides/) | a callout: `type="caution"` or `type="danger"` for a risk, `type="note"` or `type="tip"` for a fact that the reader must not miss |
| [`Checklist`](src/components/Checklist.astro) | around a `Steps` list: a tick box on each step, and a count at the top ("3 of 11 steps done"); add `kind="things"` for a list of things to have ("3 of 8 things ready") |
| [`Screenshot`](src/components/Screenshot.astro) | one picture of the app |
| [`Screenshots`](src/components/Screenshots.astro) | pictures side by side, each in its own `Screenshot` |
| [`Placeholder`](src/components/Placeholder.astro) | a fact that the page still waits for, such as the legal name of the publisher: `<Placeholder>legal name</Placeholder>` shows it highlighted, between brackets |
| [`Unverified`](src/components/Unverified.astro) | at the top of a part that is not final yet, such as the description of a version of the app that is not out: `<Unverified>what is not final, in the reader's words</Unverified>` shows it highlighted, with "Not final" in the language of the page |
| [`DraftNotice`](src/components/DraftNotice.astro) | at the top of a page that is not final yet: it says, in the language of the page, that the page is a draft and that its text can change; a page with a `Placeholder` or an `Unverified` must have it, and `make docs-check` fails when it does not |

Give each `Checklist` its own `id`: the browser saves the ticks of the reader under it.
Show a picture of the app only with `Screenshot`, never with a Markdown image or the `Image` component of Astro.
`Screenshot` shows the picture 300 pixels wide, with the rounded corners of an iPhone screen, and the browser downloads a small file that fits its screen.
On a lock screen picture, `crop="live-activity"` shows only the Live Activity and a little of the wallpaper around it, as wide as the page allows, so that a reader on a phone can read its rows: on the home, a whole lock screen is mostly wallpaper and clock.
The file stays the whole screen, and no pixel changes: the browser hides the rest.
A home shows its first picture beside the headline with `heroScreenshot` in its frontmatter (`file` and `alt`), next to `hero`, and `Screenshot` draws it with the same close-up.
Import the components after the title.
The paths start from the folder of the page, here a page in `en/build/`:

```mdx
import { Aside, Steps } from '@astrojs/starlight/components';
import Checklist from '../../../../components/Checklist.astro';
import Screenshot from '../../../../components/Screenshot.astro';
import appMainScreen from '../../../../assets/screenshots/app-main-screen.png';

<Screenshot src={appMainScreen} alt="The main screen of the app: the button to show the Live Activity of the nearest station, the automatic mode, and the permissions." />
```

## Make the pictures again

The pictures of the app come from a test that runs the app in the iPhone Simulator, so you can make them again each time the app changes.
When a change alters a screen that a page shows, make the pictures again, and commit the new files:

```sh
make docs-screenshots
```

It builds the app with no train data key, gives the Simulator a fixed position (near Champ de Mars Tour Eiffel), a fixed clock and metres, and saves each picture in [`src/assets/screenshots/`](src/assets/screenshots/), under a fixed name.
The lock screen shows the wallpaper of [`Wallpaper.swift`](../ios/DocsScreenshots/Wallpaper.swift), the one file that names the wallpaper of every picture of the app.
The Simulator keeps it: when the command stops at once and asks for it, run `make simulator-wallpaper` once, then run the command again.
The pictures of the app screens are in English.
The pictures of the Live Activity use the fake trains of the app, at three stations (a metro line with one end in each direction, a metro line with a branch, and an RER line), and exist in English and in French: `live-activity-<case>-en.png` and `live-activity-<case>-fr.png`.
A French page shows the French picture, and an English page the English one.
A change of text alone needs no new pictures.

The pictures follow three rules:

- **Full screen, on one iPhone model,** so that pictures side by side have the same size.
  The file of a Live Activity picture holds the whole Notification Center, never a crop.
  A page may still show only the Live Activity, with `crop="live-activity"`.
  The script fails when two pictures do not have the same size.
- **900 pixels wide.** The page shows a picture 300 pixels wide, and the 3x screen of an iPhone needs three times as many pixels.
  The script resizes each picture to this width.
- **At most 500 KB for each file,** because the files stay in the git history for good, and each new run adds them again.
  The script compresses them with no visible loss, and fails when a file is still too large.
  The reader downloads smaller files that Astro makes from them.

To add a picture, add a `saveScreenshot(named:)` call to [the test](../ios/DocsScreenshots/DocsScreenshotTests.swift), and its name to `names` in [the script](../ios/scripts/docs-screenshots.sh).

## Publish the site

A GitHub Actions workflow, [`docs-site.yml`](../.github/workflows/docs-site.yml), publishes the site on GitHub Pages, at the address that [`astro.config.mjs`](astro.config.mjs) sets.
On each push to `main`, it runs `make docs-check` with the Node version of [`.nvmrc`](../.nvmrc), then publishes the site that this check built.
When a check fails, it publishes nothing, and the site stays as it was.
On a pull request, it runs the same check, but it never publishes.
A page with a draft notice is published with it, so the reader sees that the page is not signed off yet.

To see why a run failed, open the **Actions** tab of the repo on GitHub, then the **Docs site** workflow, then the run with a red cross: the step that failed shows its output.
To publish `main` again with no new commit, click **Run workflow** on the same page.

On a free GitHub account, Pages works only on a public repo, so while the repo is private the workflow only runs the check and publishes nothing.
After the repo becomes public, its owner sets **Settings > Pages > Build and deployment > Source** to **GitHub Actions** once, then clicks **Run workflow** to publish the site for the first time.

### The domain of the site

The site is served at its own domain, `trome.valfur.fr`, so its address depends on neither the GitHub account nor the name of the repo.
The app and the App Store page hold this address, and Apple keeps it until a new version: do not change it once they do.
A site that a workflow publishes ignores any `CNAME` file, so the domain is set in the repo, in **Settings > Pages > Custom domain**, never in a file.
That setting needs DNS records at the host of the domain, which the owner of the domain adds:

1. Before the first publish, verify the domain: at github.com/settings/pages, click **Add a domain**, enter `trome.valfur.fr`, and add the TXT record that GitHub shows (named `_github-pages-challenge-<account>.trome`).
   The check protects the domain from a takeover by another GitHub account, and it also covers its subdomains.
   Keep the record afterwards.
2. Add four `A` records and four `AAAA` records at the name `trome`, with the addresses of [GitHub's page on custom domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site).
   Use no `CNAME` here: a name that has a `CNAME` can hold no other record, and the mail of `contact@trome.valfur.fr` needs its own records at the same name.
   GitHub documents `A` records only for an apex domain, and a `CNAME` for a subdomain, so GitHub accepting them here is not proven until the first check.
   Use no wildcard record such as `*.valfur.fr`, which GitHub warns against.
3. Run the **Docs site** workflow once, then enter `trome.valfur.fr` as the custom domain in **Settings > Pages**.
4. When GitHub's DNS check is green, tick **Enforce HTTPS**.
   DNS changes and the HTTPS option can take up to a day.

When the DNS check fails, look at these, in this order:

- The records are at the name `trome`, with no `CNAME` beside the `A` records, and no wildcard record.
- Your DNS host does not proxy them: keep them DNS-only.
- `dig trome.valfur.fr +short` prints the four GitHub addresses.
- The TXT record of the domain check is still there.

If GitHub refuses the `A` records for a subdomain, the fallback is one `CNAME` at `trome` to `<account>.github.io`, and the mail on another name.
The contact address is written in one file ([`src/contact.ts`](src/contact.ts)), so this change stays small.

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

### Write the lines a stranger reads first

A stranger reads the headline or the title of a page, its tagline and its first sentence before anything else, and often instead of anything else.
From those lines, they decide in a few seconds whether to read on.
So write them from the reader's side, and say what the reader gets, in their own words.
Name things that the reader knows, not the kind of product:

- Not: "A weather app with forecasts by the minute."
- But: "Know if rain will catch you on the walk home."

Write at least three candidates from different angles, for example the moment when the reader needs the product, what they see, or what they no longer have to do.
Pick one, and say why in the description of your change, so that the reviewer can judge the choice.
What is true comes first: a line that promises more than the product does is a defect, however well it reads.
Leave out hype, jokes and claims that the reader cannot check, such as "seamless" or "powerful": a fact that they can check persuades more.
Then test the lines as the first point of [Review a page](#review-a-page) says.

### Say what is true today, and what stays true

A page can be right about the app today and still mislead, when the app is about to do something else.
Before you edit a page, read the part of the maker's vision that it touches, and the list of sentences tied to a behaviour that will change (the maintainer keeps both: ask for them).
Say what the rider gets in the terms of the vision, then say once, in one place, how this version does it, in words that stay true when the rest ships.
Quote each new sentence tied to a behaviour that will change in the description of your change, so that the maintainer adds it to the list.
[Review a page](#review-a-page), point 3, is how a reviewer checks this.

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
Short means short enough to read on a phone, never a sentence with no verb.
For a text that sells the app, such as the store text, read [Write marketing text](#write-marketing-text) too.
Link the sentences the way a person speaks, with "so", "but", "then" and "when".
Read each sentence aloud, and rewrite the ones that no person would say.

- Not: "The docs need Node 24. The file `.nvmrc` pins it. Install it one time with a version manager."
- But: "The site needs Node 24, the version in `.nvmrc`, so install it once with a version manager."

Write "you", and use the active voice: "Tap **Allow**", not "Allow must be tapped".
Name each thing the way the reader sees it, with the label of the screen or of the iOS menu, in bold: **Settings > Privacy & Security**.
Use one term for one thing, and the same term as the app: if the app says **Snooze**, do not write "pause" on one page and "mute" on the next.
Leave out filler, such as "please note", "simply" or "easy".

Speak as one person.
One person makes TROME, so where the maker speaks, a page says "I", "me" and "my" (in French "je", "me", "mon", "ma", "mes"), and never "we", "us" or "our" ("nous", "notre", "nos"): they pretend a company that does not exist.
The maker never names himself in the third person either.
Write "I am Valentin Furmanek, and I make TROME", not "TROME is made by Valentin Furmanek", and "write to me", not "contact us".
A sentence that a team would say (a department, "our servers", "we decided") is rewritten for one person, with no pretended company: "my server" is right for the one that the maker runs.
A page that only tells the reader what to do, with "you", needs no "I".
A copyright or licence line, where the law asks for a name, is not speech and stays as it is.
Why: a reader who meets "we" on one page and "I" on the next stops trusting both, and a name in the third person reads as someone else speaking.
`make public-text-check` fails on these words in the prose of every Markdown and MDX file of the repo; code, link addresses and text in double or curly quotes are not checked, so a quotation may keep them.

### Write marketing text

Marketing text is what the reader sees before they have the app: the description and the promotional text of the App Store, the description of TestFlight, and the first lines of a page (its headline, its tagline and its first paragraph).
Its reader decides in a few seconds, and your words are all they have to decide on.
So this text is written for a person, not filled in like a form.

- **Write complete sentences, each with a verb.** A fragment belongs in a list, in a badge, or in a subtitle, which Apple calls a phrase.
  A paragraph is never a row of fragments.
  - Not: "No station to pick. Free, no account, no ads."
  - But: "There is no station to pick, and the app is free, with no account and no ads."
- **The first sentence is the pitch.** The store shows only it before **more**, and a stranger reads only it before they decide.
  Say what the reader gets, in their words, as an invitation and not as a label.
  Then say the honest limit and the price, in full sentences too.
- **Choose the first sentence among three candidates** that come from different angles: the moment when the reader needs the app, what they see, what they no longer do.
  Say in the description of your change which one you picked, and why.
- **Keep it plain, not flat.** Use the words that a rider uses, link the sentences the way a person speaks, and vary their length.
  Leave out hype, jokes, superlatives and any claim that the reader cannot check.
- **Add no claim.** A rewrite for style keeps the facts of the page and the claims that the app can keep: the text that the store reads is checked against the app, as [Say what is true today](#say-what-is-true-today-and-what-stays-true) says.
- **Count the limits.** The store limits each field, in characters or in bytes: count each text again by script after every edit.

Why: a text of fragments reads as unfinished, so the reader trusts it less.
Apple asks for an engaging description, a short paragraph and then a short list, and keeps "phrase" for the subtitle.
The first lines of the store texts that people praise are full sentences with a verb.
The rule "short sentences" was written for steps and for readers who do not have English as their first language, and it does not mean "no verb".

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
| Approaching | À l’approche |
| At the platform | À quai |
| No trains | Pas de train |
| Automatic mode | Mode automatique |
| Snooze | Mettre en pause in the app, Pause on the Live Activity |
| Snoozed | En pause |
| Paused (one station, after a swipe) | En sourdine |
| Cancel the pause at a station | Réactiver |
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
- But: "## The Live Activity does not show".

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

- Not: a note that says "Start with the tutorial": put the link in the first lines.
- Not: a note that says "This page does not cover the App Store": say it in the first lines.

### Give a reason only when the reader needs it

A reason belongs on a page when the reader needs it to act, or to trust the page.
Leave out the history of how the project is made: no dates of decisions, no measurements, no task numbers, and no "I decided".

- Not: "After the tests of September, I chose to ask for Always."
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

Start with the first screen of the page, then read the whole page as its reader would, and go through the other points.
They help your judgement; they are not boxes to tick.
A finding names the reader who would stumble, the place, and why.
For example: "A builder who has never used Terminal stops at step 7: it does not say in which folder to run the command."

1. **The first screen.** Before the rest, read only what the first screen shows, on the device of the page's reader: a phone, 390 pixels wide, for a riders' page.
   Then write three answers in the review: what the page is for, whether it is for you as its reader, and where you go next.
   A wrong or missing answer is a finding that names the reader and the line that lost them.
2. **Reader and job.** The page serves one main reader, and its first lines say what it gives.
   A second reader gets a link, or a page of their own.
3. **True to where TROME is going.** A page can be true today and still mislead: a rider plans around it, and it needs a rewrite when the app changes.
   Read the part of the vision that the page touches, and the list of sentences tied to a behaviour that will change (the maintainer keeps both: ask for them).
   The first lines say what the rider gets, in the terms of the vision, and not how this version gets there.
   Each behaviour that this version does only in part is told once, as how it works today, in words that stay true when the rest ships.
   Each sentence of the list that the page holds is still true: when its event has happened, the page has the new wording.
   No test of the code finds a failure here, so a review that skips this point is incomplete.
4. **Kind and shape.** The page is one kind.
   A tutorial works from a clean start; a how-to has its goal, what you need, the steps and the result; a reference is complete and easy to scan; an explanation has no steps.
   Each step list, section, table and callout is used as [Choose the right shape](#choose-the-right-shape) says.
5. **Headings and the first picture.** Each heading says what the reader finds or does there, so that the headings alone tell the page.
   On a front page or a home, the first picture shows the product at work, close to the headline, with an alt text that says what it shows: never an empty screen.
6. **Each section earns its place.** For each section, ask what this reader would lose without it.
   If the answer is nothing, the section goes.
   No page has a fixed length: it is as long as its reader's job needs, and this point and the first screen decide, not a count of lines.
7. **Nothing for another reader.** No inner workings of how the project is made, no history, no measurements, no task numbers, and a reason only when the reader needs it.
8. **Voice.** A person would say each sentence aloud: read each paragraph aloud, and refuse a sentence with no verb outside a list.
   Marketing text follows [Write marketing text](#write-marketing-text): its first sentence is a pitch with a verb, picked among three candidates, and no paragraph is a row of fragments.
   The page is plain, direct and warm, with no filler, and its terms match the app and iOS.
   One person speaks: where the maker speaks, the page says "I" ("je" in French), and has no "we", "us" or "our" ("nous", "notre"), and his name never speaks about him in the third person.
9. **True.** Each command was run, each link was opened, and the steps were followed as the reader follows them.
   What could not be checked is said once.
10. **Pictures.** They show the current app, and each alt text says what the picture shows, in the language of the page.
11. **One home for each fact.** A fact is on one page, and the other pages link to it.
12. **French.** A riders' page reads as French that a Paris rider would write, and the French and English pages say the same facts.
13. **On a phone first.** Most riders read the site on an iPhone, so read each riders' page at phone width (390 pixels) before you read it on a computer.
    Check that its language menu, its menu and its tables work there.
14. **No sideways scroll.** At the width of its reader (1280 pixels for a maintainer on a laptop, 390 for a rider on a phone), `document.documentElement.scrollWidth` equals `clientWidth`: measure the page, not only its code blocks.
    A table or a long inline code can push the whole page sideways while every block wraps, and a text to paste is then cut at the right.
15. **The checks pass.** `make check` checks the length of the lines, the public text, the internal links of the site, the two languages of each riders' page and the draft notices, and `make docs-screenshots` checks the pictures.
