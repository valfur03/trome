#!/bin/sh
set -eu

# Tests of scripts/browser.sh and of the browser choice of scripts/render.sh, with a fake browser and a fake
# Simulator lock: no download, no render.
# What they guard: a render on a Mac whose repo is in a protected folder (Documents) hangs when it runs the browser
# from node_modules, so every render must get the copy outside the repo, unless CHROME=<path> names another browser.

if [ "$(uname -s)" != Darwin ]; then
    echo "browser-test: skipped: the copy is for macOS only"
    exit 0
fi

here=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/video-browser-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() {
    echo "browser-test: FAILED: $1" >&2
    exit 1
}

# A video folder of its own: the two scripts, a fake download of Remotion, and a fake lock that prints its command.
mkdir -p "$work/video/scripts" "$work/ios/scripts"
cp "$here/scripts/browser.sh" "$here/scripts/render.sh" "$work/video/scripts/"
downloads="$work/video/node_modules/.remotion/chrome-headless-shell"
mkdir -p "$downloads/mac-arm64/chrome-headless-shell-mac-arm64"
printf '#!/bin/sh\necho fake browser\n' > "$downloads/mac-arm64/chrome-headless-shell-mac-arm64/chrome-headless-shell"
chmod +x "$downloads/mac-arm64/chrome-headless-shell-mac-arm64/chrome-headless-shell"
echo "1.0-test" > "$downloads/VERSION"
printf '#!/bin/sh\nshift\nprintf "%%s\\n" "$@"\n' > "$work/ios/scripts/sim-lock.sh"
chmod +x "$work/ios/scripts/sim-lock.sh"
export VIDEO_BROWSER_CACHE="$work/cache"

# 1. The copy is made outside the video folder, in the folder of its version, and it runs.
path=$("$work/video/scripts/browser.sh")
[ "$path" = "$work/cache/chrome-headless-shell-1.0-test/chrome-headless-shell" ] || fail "the copy is at '$path', not in the cache folder of its version"
[ "$("$path")" = "fake browser" ] || fail "the copy does not run the browser of node_modules"

# 2. A second render uses the same copy, and makes no new one.
touch "$work/cache/chrome-headless-shell-1.0-test/kept"
path2=$("$work/video/scripts/browser.sh")
[ "$path2" = "$path" ] || fail "a second call gave '$path2', not '$path'"
[ -f "$work/cache/chrome-headless-shell-1.0-test/kept" ] || fail "a second call made the copy again"

# 3. A new browser version gets a new copy.
echo "2.0-test" > "$downloads/VERSION"
path3=$("$work/video/scripts/browser.sh")
[ "$path3" = "$work/cache/chrome-headless-shell-2.0-test/chrome-headless-shell" ] || fail "a new version gave '$path3'"

# 4. When another render puts its copy in place between the check and the rename, the rename fails: that folder stays
# as it is, and this half copy goes. The test makes that folder before the call, with no browser in it, so the check
# misses it and the rename meets it.
echo "3.0-test" > "$downloads/VERSION"
mkdir -p "$work/cache/chrome-headless-shell-3.0-test"
echo "other copy" > "$work/cache/chrome-headless-shell-3.0-test/other"
path4=$("$work/video/scripts/browser.sh")
[ "$path4" = "$work/cache/chrome-headless-shell-3.0-test/chrome-headless-shell" ] || fail "a raced copy gave '$path4'"
[ "$(ls -A "$work/cache/chrome-headless-shell-3.0-test")" = other ] || fail "the copy of the other render was changed: $(ls -A "$work/cache/chrome-headless-shell-3.0-test" | tr '\n' ' ')"
leftovers=$(find "$work/cache" -maxdepth 1 -name '.copy.*' | wc -l | tr -d ' ')
[ "$leftovers" = 0 ] || fail "$leftovers half copies stay in the cache"

# 5. With no download, it says what to run, and fails.
rm "$downloads/VERSION"
if message=$("$work/video/scripts/browser.sh" 2>&1); then
    fail "it passed with no download"
fi
echo "$message" | grep -q "make video-setup" || fail "with no download, it said '$message'"
echo "1.0-test" > "$downloads/VERSION"

# 6. A render gets the copy, unless CHROME=<path> (the Makefile's --browser-executable) names another browser.
args=$("$work/video/scripts/render.sh" still Film out/still.png)
echo "$args" | grep -qx -- "--browser-executable=$path" || fail "a render did not get the copy: $args"
args=$("$work/video/scripts/render.sh" still Film out/still.png --browser-executable=/other/chrome)
[ "$(echo "$args" | grep -c -- '--browser-executable')" = 1 ] || fail "a render with CHROME got two browsers: $args"
echo "$args" | grep -qx -- "--browser-executable=/other/chrome" || fail "a render with CHROME lost it: $args"

echo "browser-test: OK (6 cases)"
