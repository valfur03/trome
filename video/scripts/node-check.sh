#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
required=$(tr -d '[:space:]v' < "$root/.nvmrc")
# Any Node version manager that reads .nvmrc works; fnm is the example, as its exec command needs no shell setup.
how="Run the make command again with that Node, for example: fnm exec --using=.nvmrc -- make ... (run 'fnm install' once before)."

if ! command -v node > /dev/null; then
    echo "No Node is on the PATH, but the film needs Node $required (see .nvmrc). $how" >&2
    exit 1
fi

current=$(node -p 'process.versions.node.split(".")[0]')
if [ "$current" -lt "$required" ]; then
    echo "The film needs Node $required or later (see .nvmrc), but the active Node is $(node -v). $how" >&2
    exit 1
fi
