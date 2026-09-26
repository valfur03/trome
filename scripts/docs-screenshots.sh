#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 <result bundle> <test command...>" >&2
    echo "Run it through the Simulator lock: ./scripts/sim-lock.sh job ./scripts/simulator.sh reset $0 ..." >&2
    exit 1
}

[ $# -ge 2 ] || usage
if ! command -v pngquant > /dev/null; then
    echo "pngquant is not installed. Run 'make setup' to install it." >&2
    exit 1
fi

result=$1
shift

scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/.." && pwd)
screenshots="$root/docs/src/assets/screenshots"
names="app-main-screen live-activity-notification-center"
fake_position=48.8584,2.2945
screenshot_width=600
udid=$("$scripts/simulator.sh" boot)
exported="$root/.build/docs-screenshots"

cleanup() {
    xcrun simctl status_bar "$udid" clear 2> /dev/null || true
    xcrun simctl location "$udid" clear 2> /dev/null || true
    rm -rf "$exported"
}
trap cleanup EXIT INT TERM

rm -rf "$result" "$exported"
xcrun simctl location "$udid" set "$fake_position"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3
"$@" -resultBundlePath "$result" test \
    || { status=$?; "$scripts/e2e-failures.py" "$result"; exit $status; }

mkdir -p "$exported"
xcrun xcresulttool export attachments --path "$result" --output-path "$exported" --filter "*.png" > /dev/null
mkdir -p "$screenshots"
python3 - "$exported" "$screenshots" $names <<'PYTHON'
import json
import shutil
import sys
from pathlib import Path

exported, screenshots, names = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:]
attachments = [
    attachment
    for test in json.loads((exported / "manifest.json").read_text())
    for attachment in test["attachments"]
]
for name in names:
    matches = [
        attachment
        for attachment in attachments
        if attachment["suggestedHumanReadableName"].startswith((f"{name}_", f"{name}."))
    ]
    if not matches:
        sys.exit(f"The tests saved no screenshot named {name}")
    shutil.copyfile(exported / matches[-1]["exportedFileName"], screenshots / f"{name}.png")
PYTHON

for name in $names; do
    file="$screenshots/$name.png"
    sips --resampleWidth "$screenshot_width" "$file" > /dev/null
    pngquant --force --strip --ext .png -- "$file"
    echo "Saved docs/src/assets/screenshots/$name.png ($(($(wc -c < "$file") / 1024)) KB)"
done
