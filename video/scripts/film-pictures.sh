#!/bin/sh
# Copies what the key frames show and git does not keep: the captures of the film (make film-captures) and
# Apple's iPhone bezel, whose licence forbids copies in the repo.
# Usage: scripts/film-pictures.sh <bezel PNG> <folder of the captures> <folder of the copies>
set -eu

if [ $# -ne 3 ]; then
    echo "Usage: $0 <bezel PNG> <folder of the captures> <folder of the copies>" >&2
    exit 2
fi
bezel=$1
captures=$2
copies=$3

if [ ! -f "$bezel" ]; then
    echo "No bezel at $bezel. Place Apple's iPhone 18 Pro bezel as ios/guide/assets.md says (The store screenshots), or give its path: BEZEL=<path>." >&2
    exit 1
fi
if ! ls "$captures"/lock-*-fr.png > /dev/null 2>&1 || ! ls "$captures"/lock-*-en.png > /dev/null 2>&1; then
    echo "No captures of the film in $captures. Run 'make film-captures' first." >&2
    exit 1
fi
mkdir -p "$copies/film"
cp "$bezel" "$copies/bezel.png"
cp "$captures"/lock-*.png "$copies/film/"
