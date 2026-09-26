#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
required=$(tr -d '[:space:]v' < "$root/.nvmrc")

if ! command -v node > /dev/null; then
    echo "Node $required is not installed. Install it with nvm: run 'nvm install', then 'nvm use'." >&2
    exit 1
fi

current=$(node -p 'process.versions.node.split(".")[0]')
if [ "$current" -lt "$required" ]; then
    echo "The docs need Node $required or later, but the active Node is $(node -v). Run 'nvm use' in this folder ('nvm install' the first time), then run make again." >&2
    exit 1
fi
