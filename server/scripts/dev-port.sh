#!/bin/sh
set -eu

cd "$(dirname "$0")"
git_dir=$(git rev-parse --absolute-git-dir)
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
if [ "$(cd "$git_dir" && pwd -P)" = "$common_dir" ]; then
    echo 8787
    exit 0
fi

folder=$(basename "$(git rev-parse --show-toplevel)")
number=$(printf '%s\n' "$folder" | sed -n 's/.*[^0-9]0*\([0-9][0-9]*\)$/\1/p')
if [ -n "$number" ] && [ "$number" -gt 0 ]; then
    echo $((8787 + number))
else
    echo $((9800 + $(printf '%s' "$folder" | cksum | cut -d ' ' -f 1) % 100))
fi
