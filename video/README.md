# The film of TROME

This folder holds the source of a short film of the app, made in code with [Remotion](https://www.remotion.dev/) (React components that render to a video).
It is its own Node project, apart from the docs site and the server.
For now it renders a first test of the film, its signature move, 7 seconds long, and the key frames of the storyboard of the arrival, in two looks.

## What the film shows

The Live Activity on the lock screen, in three captures of the docs site, in the language of the film: metro line 1 at Saint-Paul, RER B at Luxembourg, and line 7 with its fork at Pont Neuf.
Around them, drawings in the style of the store pictures: the line, a metro, a double-deck RER, and a tunnel of white bevelled tiles.
A metro of line 1 goes into the tunnel and comes out as an RER of line B, and the card turns to line B: while the Live Activity shows, the app follows the rider to the next station.
The end card shows the icon of the app and its name.
`make` copies the captures and the icon into `video/public/app/`, so a new docs capture or a new icon reaches the film at the next render.
The key frames of the storyboard show the lock screen of the app at five stations, with its fake trains: line 3 at Parmentier, line 4 at Strasbourg - Saint-Denis, line 7 at Pont Neuf, RER B at Luxembourg and line 6 at Corvisart.
Each is a real capture of the Simulator (`make film-captures`), whole in Apple's iPhone bezel, and the end card shows only the name.
[The list of the pictures and texts that show the app](../ios/guide/assets.md) has the same line.

## Run it

Run each command from the root of the repo, with the Node version of `.nvmrc`, for example through fnm:

```sh
fnm exec --using=.nvmrc -- make video-studio
```

| Command | What it does |
|---|---|
| `make video-studio` | Opens the preview studio in the browser, to play the film and change it live. `PORT=<n>` picks the port, `OPEN=0` opens no browser. Ctrl-C stops it. |
| `make video-still` | Renders one frame to `video/out/still.png`. `FRAME=<n>` picks the frame (60 by default, at 30 frames a second). |
| `make video-clip` | Renders the whole film, with its music, to `video/out/clip.mp4`. |
| `make video-stills` | Renders the key frames of the storyboard, in each look and language, one PNG each, and the storyboard on one page in each language, to `video/out/stills/`. It needs the captures of `make film-captures` and the bezel of the store pictures ([Apple's iPhone bezel](../ios/guide/assets.md#the-store-screenshots)); `BEZEL=<path>` picks another bezel file. |
| `make video-check` | The quality gate of the folder: the type check, the unit tests of the music, and the render of one frame, whose size it checks. `make check` runs it only when a branch changes `video/`. |

The first command installs the packages and the headless browser that renders the frames: about 1.1 GB in `video/node_modules`, once per folder, half of it the browser.

The studio listens on every network of the Mac, not only on the Mac itself, and Remotion has no setting to change this.
So run it on a network that you trust, and stop it when you are done.

## Render

A render is a heavy job: Remotion runs a headless browser and an encoder.
With one browser tab, a render of a few seconds takes about 15 seconds and 1.6 cores.
Next to a Simulator job, the first frame of a render timed out.
So `make video-still`, `make video-stills`, `make video-clip` and `make video-check` render through the lock of the iOS Simulator jobs (`ios/scripts/sim-lock.sh`): one heavy job at a time, with one browser tab (`remotion.config.ts`) and a low priority (`nice`).
When another job holds the lock, the render waits and prints `Waiting for the Simulator lock`, with the job that holds it.

Render with these commands, not with the Render button of the studio or with `npx remotion render`: those skip the lock.
When the headless browser of Remotion does not start (the render stops at `Waiting for root component to load`), `CHROME=<path>` renders with an installed Chrome instead, for example `CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.

## What git keeps

Git keeps the source: the components in `src/`, the music in code in `music/`, and the scripts.
It ignores what the commands make: `video/out/`, the music file `video/public/music.wav`, the copies of the captures, of the bezel and of the icon in `video/public/app/`, and `node_modules`.
A finished film does not go into git either, because a large file stays in the history of the repo forever.

## Licences

- **Remotion** is not open source: its [licence](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) is free for an individual, a non-profit, and a company of up to 3 employees, for personal or commercial videos.
  A larger company needs a paid licence.
  Each person who renders this film checks that the free licence covers them ([the FAQ of the licence](https://www.remotion.dev/docs/license/faq)).
- **Inter**, the font of every text that the film draws, is under the [SIL Open Font License 1.1](https://github.com/rsms/inter/blob/master/LICENSE.txt).
  It comes from the npm package `@fontsource-variable/inter`, with its licence text.
- **The music** is made in code by `music/synth.ts`, with no sample and no loop of anyone else, so it is under the MIT licence of the repo.
- **The tools that Remotion downloads**: Chrome Headless Shell (the BSD licence of Chromium) and FFmpeg (LGPL), in `video/node_modules`.
  React is under the MIT licence.
