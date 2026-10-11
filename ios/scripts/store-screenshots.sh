#!/bin/sh
# The store pictures: four per language, in English and French, from captures of the shared Simulator.
#   capture: takes the captures, in the Simulator lock (make store-screenshots runs it)
#   compose: composes the pictures from the last captures, with no Simulator (make store-screenshots-compose)
set -eu

usage() {
    echo "Usage: $0 capture <result bundle> <log file> <app path> <xcodebuild command...>" >&2
    echo "       $0 compose <composer>" >&2
    echo "Build first with build-for-testing: capture runs test-without-building, so the Simulator lock is not held during the build." >&2
    echo "Run capture through the Simulator lock, in ios/: ./scripts/sim-lock.sh job ./scripts/simulator.sh reset ./scripts/simulator.sh with-destination $0 capture ..." >&2
    exit 1
}

scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/.." && pwd)
out=${STORE_SCREENSHOTS_OUT:-"$root/.build/store-screenshots"}
captures="$out/captures"
languages="en fr"
pictures="1-metro 2-fork 3-rer 4-app"
captured="app app-example-row island-metro lock-metro island-fork lock-fork island-rer lock-rer"
# Apple's iPhone bezel stays out of git: its licence forbids copies. ios/guide/assets.md says how to place it.
bezel=${STORE_BEZEL:-"$HOME/Library/Application Support/TROME/store-bezel.png"}
# The stops of the line: "pictograms" (a small drawing on each stop) or "dots" (plain white dots).
stops=${STORE_STOPS:-pictograms}

capture() {
    [ $# -ge 4 ] || usage
    result=$1
    log=$2
    app=$3
    shift 3
    target=TROMEDocsScreenshots
    udid=$("$scripts/simulator.sh" boot)
    # The cuts show the wallpaper that the Simulator keeps: stop before any capture when it is not there.
    "$scripts/wallpaper.sh" check "$udid"
    exported="$out/exported"
    shown_language=en

    result_of() {
        echo "${result%.xcresult}-$1.xcresult"
    }
    override_status_bar() {
        "$scripts/simulator.sh" status-bar
    }
    show_language() {
        xcrun simctl status_bar "$udid" clear
        # A 12-hour clock: with the 24-hour clock of French, the status bar shows 09:41, not 9:41.
        TROME_SIM_CLOCK=12 RATP_SIM_LANGUAGE=$1 "$scripts/simulator.sh" language
        shown_language=$1
        override_status_bar
    }
    cleanup() {
        if [ "$shown_language" != en ]; then
            RATP_SIM_LANGUAGE=en "$scripts/simulator.sh" language > /dev/null 2>&1 || true
        fi
        xcrun simctl status_bar "$udid" clear 2> /dev/null || true
        xcrun simctl location "$udid" clear 2> /dev/null || true
        rm -rf "$exported"
    }
    trap cleanup EXIT INT TERM

    rm -rf "$exported" "$captures"
    mkdir -p "$captures"
    override_status_bar
    for language in $languages; do
        [ "$language" = "$shown_language" ] || show_language "$language"
        language_result=$(result_of "$language")
        rm -rf "$language_result"
        TEST_RUNNER_STORE_LANGUAGE=$language "$@" -resultBundlePath "$language_result" \
            -only-testing:"$target/StoreScreenshotTests" test-without-building \
            || {
                status=$?
                "$scripts/e2e-failures.py" "$language_result"
                "$scripts/e2e-keep.py" "$language_result" "$log" "$app"
                exit $status
            }
        mkdir -p "$exported/$language"
        xcrun xcresulttool export attachments --path "$language_result" --output-path "$exported/$language" > /dev/null
        # shellcheck disable=SC2086
        python3 - "$exported/$language" "$captures" "$language" $captured <<'PYTHON'
import json
import shutil
import sys
from pathlib import Path

exported, captures, language, names = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4:]
attachments = [a for test in json.loads((exported / "manifest.json").read_text()) for a in test["attachments"]]
for name in names:
    full = f"{name}-{language}"
    matches = [a for a in attachments if a["suggestedHumanReadableName"].startswith((f"{full}_", f"{full}."))]
    if not matches:
        sys.exit(f"The test saved no capture named {full}")
    exported_file = exported / matches[-1]["exportedFileName"]
    suffix = ".png" if exported_file.suffix == ".png" else ".txt"
    shutil.copyfile(exported_file, captures / f"{full}{suffix}")
    print(f"Captured {full}{suffix}")
PYTHON
    done
    if [ "$shown_language" != en ]; then
        RATP_SIM_LANGUAGE=en "$scripts/simulator.sh" language
        shown_language=en
    fi
}

compose() {
    [ $# -eq 1 ] || usage
    composer=$1
    if [ ! -d "$captures" ]; then
        echo "There are no captures in $captures. Run 'make store-screenshots' first." >&2
        exit 1
    fi
    if [ ! -f "$bezel" ]; then
        echo "No bezel at $bezel: the pictures have no frame. To put them in Apple's iPhone bezel, see ios/guide/assets.md."
        bezel=""
    fi
    for language in $languages; do
        rm -f "$out/$language"-*.png
        "$composer" "$captures" "$out" "$language" "$bezel" "$stops"
    done
    for language in $languages; do
        for picture in $pictures; do
            file="$out/$language-$picture.png"
            size=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$file" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} /hasAlpha/ {a=$2} END {print w "x" h " alpha " a}')
            if [ "$size" != "1320x2868 alpha no" ]; then
                echo "$file is $size: the store takes 1320x2868 with no alpha channel" >&2
                exit 1
            fi
            echo "Saved $file"
        done
    done
}

[ $# -ge 1 ] || usage
command=$1
shift
case $command in
    capture) capture "$@" ;;
    compose) compose "$@" ;;
    *) usage ;;
esac
