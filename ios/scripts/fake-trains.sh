#!/bin/sh
# Launch the app of the Simulator with fake trains, in a state or with the default times, and check in the log of the
# app that the process that runs now uses them.
# Why not a plain 'xcrun simctl launch ... --fake-trains <state>': while the app keeps the position in the background,
# iOS starts it again with no argument a moment after it is closed, and the launch then only brings that process to
# the front, with its old choice. So this script also saves the choice in the preferences of the app, where a launch
# with no argument reads it (FakeTrainsStore), then closes the app again, so that the process that runs started after
# the save.
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
attempts=${TROME_FAKE_TRAINS_ATTEMPTS:-3}
log_wait_seconds=${TROME_FAKE_TRAINS_LOG_WAIT_SECONDS:-15}

app=${1:?Usage: $0 <app path> [state]}
state=${2:-}
shown=${state:-default}
# The key and the JSON of FakeTrainsStore.Choice: FakeTrainsStoreTests reads this same JSON.
key=testingTools.fakeTrains

udid=$("$scripts/simulator.sh" udid)
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
if ! container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data 2> /dev/null); then
    echo "The app is not in the Simulator. Run 'make run' first." >&2
    exit 1
fi

choice_hex() {
    # JSONEncoder writes a Date as its seconds since 2001-01-01.
    start=$(($(date +%s) - 978307200))
    if [ -n "$state" ]; then
        printf '{"scenario":"%s","start":%s}' "$state" "$start"
    else
        printf '{"start":%s}' "$start"
    fi | od -An -v -tx1 | tr -d ' \n'
}

app_line() {
    xcrun simctl spawn "$udid" log show --last 2m --style syslog \
        --predicate 'subsystem == "TROME" AND category == "FakeTrains"' 2> /dev/null \
        | grep -F "[$1]" | tail -n 1 || true
}

attempt=1
line=
while [ "$attempt" -le "$attempts" ]; do
    xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
    xcrun simctl spawn "$udid" defaults write "$container/Library/Preferences/$bundle_id" "$key" -data "$(choice_hex)"
    xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
    launched=$(xcrun simctl launch "$udid" "$bundle_id" --fake-trains ${state:+"$state"})
    pid=${launched##*: }
    waited=0
    line=$(app_line "$pid")
    while [ -z "$line" ] && [ "$waited" -lt "$log_wait_seconds" ]; do
        sleep 1
        waited=$((waited + 1))
        line=$(app_line "$pid")
    done
    case "$line" in
        *"(unknown state)"*)
            echo "fake trains: $shown not applied: the app knows no such state (FakeTrainsScenario)" >&2
            exit 1
            ;;
        *"uses: fake trains $shown from "*)
            echo "fake trains: $shown applied"
            exit 0
            ;;
    esac
    attempt=$((attempt + 1))
done

echo "fake trains: $shown not applied, launch again" >&2
echo "The last line of the app: ${line:-none, the app wrote no line}" >&2
exit 1
