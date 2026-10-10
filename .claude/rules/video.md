---
paths:
  - "video/**"
commands:
  - '^(\S*/)?make\b.*\svideo-[a-z-]+(\s|$)'
  - '^\S*remotion\b'
  - '^npx\b.*\sremotion\b'
---
# The film (`video/`)

These rules are for every change to the source of the film and every run of its commands.
`video/README.md` explains the folder, its commands and its licences; decision-74 says what the film is for, and TASK-307 holds the measurements behind these rules.

- **Node 24, through fnm:** `fnm exec --using=.nvmrc -- make video-check`, and the same for `make check` when your task changes `video/`.
  Never run `fnm use`.
- **Install `video/node_modules` only when your task touches the film.** It takes about 1.1 GB (the packages, and 570 MB of headless browser).
  `make check` runs `make video-check` only when your branch changes `video/`.
- **Render only with `make video-still`, `make video-stills`, `make video-clip` or `make video-check`.**
  They take the Simulator lock, use one browser tab and run at a low priority.
  Never run `npx remotion render` or `npx remotion still` yourself, and never use the Render button of the studio: they skip the lock.
  Why: a render takes about 1.6 cores, and next to a Simulator job its first frame timed out (TASK-307); the lock keeps one heavy job at a time on the Mac.
  A render waits for the lock like a Simulator job: run it in the background when a job holds the lock, and a gate task's Simulator job goes first (PO, 2026-10-10).
- **Prefer a still to a clip.** `make video-still FRAME=<n>` shows one frame in seconds; render the clip only for what a still cannot show (motion, sound).
- **The studio:** run `make video-studio PORT=<n> OPEN=0` in the background with a port of your own (for example 4300 plus your task number), and stop it as soon as your check is done.
  It listens on every network of the Mac, so it never runs longer than the check.
- **Renders never go into git** (`video/out/` is ignored); a film for the prompter goes to the review folder of the task.
- **The film shows only what the app does** (decision-74, point 8), and `video/README.md` "What the film shows" and `ios/guide/assets.md` say the same thing.
