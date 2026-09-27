#!/bin/sh
set -eu

base=${1:-main}
cd "$(dirname "$0")/.."

if ! merge_base=$(git merge-base HEAD "$base" 2> /dev/null); then
    echo "No branch '$base' to compare with: the docs are checked as if they changed." >&2
    exit 0
fi

if ! git diff --quiet "$merge_base" -- .; then
    exit 0
fi

[ -n "$(git ls-files --others --exclude-standard -- .)" ]
