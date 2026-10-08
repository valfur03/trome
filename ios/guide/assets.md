# The pictures and texts that show the app

Some files show the app outside the app: the docs site, the store page and the store video.
A rider reads them before the install, and App Review refuses a store page that does not show the app.
So when a change makes one of them false, the same change makes it again, except the video (see [The store video](#the-store-video)).

## What each one shows

| Asset | What it shows | How to make it again |
|---|---|---|
| The docs pictures, in [`docs/src/assets/screenshots/`](../../docs/src/assets/screenshots/) | The three permission questions, the app screen and the Testing tools, in English, on the page [Install on your iPhone](../../docs/src/content/docs/en/build/install-on-your-iphone.mdx). The Live Activity at three stations (a metro line, a metro line with a branch, an RER line), in English and in French, on the two home pages. The Dynamic Island, which no page shows yet. | `make docs-screenshots` ([Make the pictures again](../../docs/README.md#make-the-pictures-again)) |
| The Help pages, `support.mdx` in [`docs/src/content/docs/`](../../docs/src/content/docs/) `fr/` and `en/` | What to do when the Live Activity does not show, does not start or stops updating; what each permission is for; the automatic mode, the snooze, the pause and the example. | Edit both pages ([Write a page](../../docs/README.md#write-a-page)) |
| The other pages of the docs site | The home pages, the install guide and the privacy pages describe the screens and what the app sends. | Edit the page |
| The store screenshots | Not made yet. | Not made yet |
| The store text, [`store-text.mdx`](../../docs/src/content/docs/en/maintain/store-text.mdx) | Every text that goes into App Store Connect and TestFlight for the version, in French and in English, except the review notes, which are in English only: the title, the subtitle, the promotional text, the description, the keywords, the review notes and the TestFlight texts. | Edit the page, then count the sizes again, because each field has a limit (the page gives it) and the keywords and the review notes count bytes, not characters. Its table "When the app changes, check these claims" names the guide that holds each claim. Then paste the changed field into App Store Connect: only the promotional text can change with no new version, and every other field waits for the next one. |
| The store video | Not made yet. | Not made yet |

The change that makes a new asset adds its row here: what it shows, and its command.

## The store video

The video costs the most to make again, so it changes only for a big change.
A change is big for the video when a viewer would see another app: the look of the screen, the flow of the first use, the name or the icon, or a feature that the video shows or says is there.
A fix, a new row that the video never shows, or a text in a corner is not.

A change of the app never edits the video.
When it alters what the video shows, the maintainer chooses: make the video again now, make it again with the next big change, or take it off the store page until it is true again.
Why: an old video still shows the app, but a false one shows an app that riders will not get.
