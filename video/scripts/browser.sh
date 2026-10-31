#!/bin/sh
set -eu

# Prints the path of the headless browser that the renders use, on a Mac: a copy of the one that Remotion downloads
# into node_modules, made once per browser version in a cache outside the repo. Prints nothing on another system.
#
# Why a copy: Chromium starts its GPU process as a process of its own for the privacy checks of macOS, so the access
# that the app which runs the render (a terminal) has to the folder of the repo does not cover it. When the repo is in a protected folder
# (Documents, Desktop, Downloads, iCloud Drive), the GPU process must get its own access to read its program there:
# macOS asks for it in a dialog, and the process waits for the answer, so the render stops at
# "Waiting for root component to load". A copy in ~/Library/Caches needs no access, and asks nothing.
#
# VIDEO_BROWSER_CACHE=<folder> puts the copies in another folder (for the tests).

if [ "$(uname -s)" != Darwin ]; then
    exit 0
fi
cd "$(dirname "$0")/.."

downloads=node_modules/.remotion/chrome-headless-shell
if [ ! -f "$downloads/VERSION" ]; then
    echo "browser.sh: no headless browser in $downloads: run make video-setup" >&2
    exit 1
fi
version=$(cat "$downloads/VERSION")
# One folder per platform (mac-arm64 or mac-x64), as Remotion lays it out.
source=$(find "$downloads" -mindepth 2 -maxdepth 2 -type d -name 'chrome-headless-shell-mac-*' | head -n 1)
if [ -z "$source" ] || [ ! -x "$source/chrome-headless-shell" ]; then
    echo "browser.sh: no chrome-headless-shell in $downloads: run make video-setup" >&2
    exit 1
fi

cache=${VIDEO_BROWSER_CACHE:-$HOME/Library/Caches/TROME-video}
target="$cache/chrome-headless-shell-$version"
if [ ! -x "$target/chrome-headless-shell" ]; then
    mkdir -p "$cache"
    copy=$(mktemp -d "$cache/.copy.XXXXXX")
    # A clone on APFS: instant, and it takes no disk space until one of the two changes.
    cp -cR "$source/." "$copy/" 2>/dev/null || cp -R "$source/." "$copy/"
    # rename() fails when another render made the same copy first: then that copy is used, and this one goes.
    perl -e 'rename($ARGV[0], $ARGV[1]) or exit 1' "$copy" "$target" || rm -rf "$copy"
fi
echo "$target/chrome-headless-shell"
