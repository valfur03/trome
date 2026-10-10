#!/bin/sh
set -eu

base=${1:-main}
cd "$(dirname "$0")/.."

merge_base=
for ref in "$base" "origin/$base"; do
    if merge_base=$(git merge-base HEAD "$ref" 2> /dev/null); then
        break
    fi
done
if [ -z "$merge_base" ]; then
    echo "No branch '$base' or 'origin/$base' to compare with: the film source is checked as if it changed." >&2
    exit 0
fi

if ! git diff --quiet "$merge_base" -- .; then
    exit 0
fi

[ -n "$(git ls-files --others --exclude-standard -- .)" ]
