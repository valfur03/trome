# The pictures and texts that show the app

Some files show the app outside the app: the docs site, the store page and the store video.
A rider reads them before the install, and App Review refuses a store page that does not show the app.
So when a change makes one of them false, the same change makes it again, except the video (see [The store video](#the-store-video)).

## What each one shows

| Asset | What it shows | How to make it again |
|---|---|---|
| The docs pictures, in [`docs/src/assets/screenshots/`](../../docs/src/assets/screenshots/) | The three permission questions and the app screen, in English, on the page [Install TROME on your iPhone](../../docs/src/content/docs/en/build/install-on-your-iphone.mdx), and the Testing tools on the page [Add your own train data key](../../docs/src/content/docs/en/build/add-your-train-data-key.mdx). The Live Activity at three stations (a metro line, a metro line with a branch, an RER line), in English and in French, on the two home pages. The Dynamic Island, which no page shows yet. The wallpaper of every picture is named in [`Wallpaper.swift`](../DocsScreenshots/Wallpaper.swift), and `make simulator-wallpaper` sets it once on the Simulator. | `make docs-screenshots` ([Make the pictures again](../../docs/README.md#make-the-pictures-again)) |
| The Help pages, `support.mdx` in [`docs/src/content/docs/`](../../docs/src/content/docs/) `fr/` and `en/` | What to do when the Live Activity does not show, does not start or stops updating; what each permission is for; the automatic mode, the snooze, the pause and the example. | Edit both pages ([Write a page](../../docs/README.md#write-a-page)) |
| The other pages of the docs site | The home pages, the install guide and the privacy pages describe the screens and what the app sends. | Edit the page |
| The store screenshots, in `ios/.build/store-screenshots/` (not in git) | Four pictures per language, in English and French, named by language and order (`fr-1-metro.png` to `fr-4-app.png`): the Live Activity on the lock screen and the Dynamic Island at Goncourt (metro 11), Pont Neuf (metro 7, a line with a branch) and Luxembourg (RER B), with fake trains, then the main screen of the app. Each has a headline, and one line drawing runs across the first three. The fourth shows the top of the phone under its headline, cut by the bottom edge just under the link **Help and feedback**: the settings rows show, the data source footer does not, and the phone hides the line. The headlines are in [`store-screenshots-compose.swift`](../scripts/store-screenshots-compose.swift). | `make store-screenshots` ([The store screenshots](#the-store-screenshots)) |
| The store text, [`store-text.mdx`](../../docs/src/content/docs/en/maintain/store-text.mdx) | Every text that goes into App Store Connect and TestFlight for the version, in French and in English, except the review notes, which are in English only: the title, the subtitle, the promotional text, the description, the keywords, the review notes and the TestFlight texts. | Edit the page, then count the sizes again, because each field has a limit (the page gives it) and the keywords and the review notes count bytes, not characters. Its table "When the app changes, check these claims" names the guide that holds each claim. Then paste the changed field into App Store Connect: only the promotional text can change with no new version, and every other field waits for the next one. |
| The film and its store cut, from [`video/`](../../video/) | The Live Activity on the lock screen (the captures of the docs, in French and in English: metro line 1, RER B, the fork of line 7) and the app icon, around drawings of the line, a metro, an RER and a tunnel. | `make video-clip`, `make video-stills` ([Run it](../../video/README.md#run-it)) |

The change that makes a new asset adds its row here: what it shows, and its command.

## The store screenshots

`make store-screenshots` takes the captures on the shared Simulator, in English and in French, then composes the pictures at 1320 x 2868 pixels, a size of the class "iPhone with Dynamic Island (large display)" (6.9-inch) of App Store Connect, with no alpha channel.
App Store Connect makes the smaller sizes from them, the required medium display included.
It needs no key: the trains are fake.
`make store-screenshots-compose` composes them again from the last captures, with no Simulator, for example after a change of a headline.
`STORE_STOPS=dots` draws plain dots on the stops of the line instead of the small drawings.

The cuts of the screen can sit in Apple's iPhone bezel.
Its licence forbids copies, so the repo does not hold it, and each maintainer places it once:

1. Download, from [Apple Design Resources](https://developer.apple.com/design/resources/), the bezel of the iPhone 18 Pro: its screen has the shape of the Simulator's iPhone 17 (1206 x 2622 pixels).
2. Open the disk image, read and accept the licence.
3. Copy the PNG of the phone in portrait, in a dark colour (`iPhone 18 Pro - Black - Portrait.png`), to `~/Library/Application Support/TROME/store-bezel.png`, or set `STORE_BEZEL` to its path.

The command measures the screen of the bezel, and uses it only when it has the shape of the captures and keeps the Live Activity at nine tenths of its size or more.
Otherwise, or with no bezel file, it says why, and the cuts have rounded corners and no frame.

To publish them, drag the pictures of each language, in the order of their names, to the large display with Dynamic Island (6.9-inch) of the version in App Store Connect.

## The store video

The video costs the most to make again, so it changes only for a big change.
A change is big for the video when a viewer would see another app: the look of the screen, the flow of the first use, the name or the icon, or a feature that the video shows or says is there.
A fix, a new row that the video never shows, or a text in a corner is not.

A change of the app never edits the video.
When it alters what the video shows, the maintainer chooses: make the video again now, make it again with the next big change, or take it off the store page until it is true again.
Why: an old video still shows the app, but a false one shows an app that riders will not get.
