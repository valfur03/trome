#!/bin/sh
set -eu

base=${1:-main}
cd "$(dirname "$0")/../.."

merge_base=
for ref in "$base" "origin/$base"; do
    if merge_base=$(git merge-base HEAD "$ref" 2> /dev/null); then
        break
    fi
done
if [ -z "$merge_base" ]; then
    echo "No branch '$base' or 'origin/$base' to compare with: the server is checked as if it changed." >&2
    exit 0
fi

# The server also bundles the station list of the app, so a change of it alone checks the server too.
watched="server contracts ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json"

# shellcheck disable=SC2086 # the paths of the list have no space
if ! git diff --quiet "$merge_base" -- $watched; then
    exit 0
fi

# shellcheck disable=SC2086
[ -n "$(git ls-files --others --exclude-standard -- $watched)" ]
