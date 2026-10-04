---
paths:
  - "docs/**"
commands:
  - '^(\S*/)?make\b.*\sdocs(-[a-z-]+)?(\s|$)'
---
# The docs site (`docs/`)

These rules are for every change to the docs site and every run of its commands.
`docs/README.md` explains the docs site and its commands (section "Run the site").
The rules on writing are in `CLAUDE.md` and in `.claude/rules/writing.md`: they hold for the whole repo, not only for `docs/`.

- **Node 24.** Each Bash call starts a new shell with the old default Node.
  Run the docs commands like this: `. "$HOME/.nvm/nvm.sh" && nvm use && make docs-check`.
  The same goes for `make check` when your task changes `docs/`.
- **Install `docs/node_modules` only when your task touches the docs.** It takes about 300 MB.
  `make check` runs `make docs-check` only when your branch changes `docs/`, so the other tasks never install it.
- **Use your own port.** The default port 4321 is for the prompter.
  Run `make docs PORT=<n>` or `make docs-dev PORT=<n>` with a port that no other agent uses (for example 4300 plus your task number).
- **Stop the docs server when your job ends.** For agents, Astro starts the server in the background and the command returns at once.
  Run `make docs-stop` in your worktree before you end.
- **Screenshots.** Show each app screenshot with the `Screenshot` component (`docs/src/components/Screenshot.astro`), never with a Markdown image or the `Image` component.
  Put screenshots side by side inside `Screenshots`.
  Take each screenshot full screen on a shared iPhone 17 Simulator (`make docs-screenshots` does), so all have the same size.
  Each file in git stays under the budget of `docs/README.md` (section "Make the pictures again").
  The script checks the size and the budget.
