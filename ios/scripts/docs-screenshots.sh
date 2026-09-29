#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 <result bundle> <xcodebuild command...>" >&2
    echo "Build first with build-for-testing: the script runs test-without-building, so the Simulator lock is not held during the build." >&2
    echo "Run it through the Simulator lock, in ios/: ./scripts/sim-lock.sh job ./scripts/simulator.sh reset ./scripts/simulator.sh with-destination $0 ..." >&2
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
screenshots="$root/../docs/src/assets/screenshots"
names="app-location-permission app-always-permission app-notification-permission app-main-screen live-activity-notification-center app-testing-tools"
fake_position=48.8584,2.2945
screenshot_width=900
pngquant_quality=85-100
budget_kb=500
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
xcrun simctl status_bar "$udid" override --time 9:41 --operatorName '' --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3
"$@" -resultBundlePath "$result" test-without-building \
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
    pngquant --force --strip --quality "$pngquant_quality" --speed 1 --ext .png -- "$file" || {
        status=$?
        if [ "$status" -eq 99 ]; then
            echo "$name.png: pngquant cannot keep the quality $pngquant_quality. Lower the floor of pngquant_quality in $0, or check the image." >&2
        else
            echo "$name.png: pngquant failed (exit $status)." >&2
        fi
        exit "$status"
    }
done
python3 - "$screenshots" "$budget_kb" $names <<'PYTHON'
import struct
import sys
from pathlib import Path

screenshots, budget_kb, names = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
sizes = {}
for name in names:
    file = screenshots / f"{name}.png"
    width, height = struct.unpack(">II", file.read_bytes()[16:24])
    size = file.stat().st_size
    kilobytes = size / 1024
    sizes[name] = (width, height)
    print(f"Saved docs/src/assets/screenshots/{name}.png ({width}x{height} px, {kilobytes:.1f} KB)")
    if size > budget_kb * 1024:
        sys.exit(f"{name}.png is {kilobytes:.1f} KB: more than the budget of {budget_kb} KB")
if len(set(sizes.values())) > 1:
    sys.exit(f"The screenshots do not all have the same size: {sizes}")
PYTHON
