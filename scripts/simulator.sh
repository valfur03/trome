#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
path_hash=$(printf '%s' "$root" | shasum | cut -c1-8)
name="RATP-$(basename "$root")-$path_hash"
device_type=${SIM_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17}

find_udid() {
    xcrun simctl list devices available \
        | grep -F "    $name (" \
        | head -n 1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

create_device() {
    runtime=$(xcrun simctl list runtimes available \
        | grep '^iOS ' \
        | tail -n 1 \
        | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+).*/\1/')
    if [ -z "$runtime" ]; then
        echo "No iOS Simulator runtime found. Run: xcodebuild -downloadPlatform iOS" >&2
        exit 1
    fi
    xcrun simctl create "$name" "$device_type" "$runtime"
}

command=${1:-udid}

case "$command" in
    udid)
        udid=$(find_udid)
        if [ -z "$udid" ]; then
            udid=$(create_device)
        fi
        echo "$udid"
        ;;
    boot)
        udid=$("$0" udid)
        xcrun simctl bootstatus "$udid" -b > /dev/null
        echo "$udid"
        ;;
    launch)
        app=${2:?Usage: $0 launch <app path>}
        udid=$("$0" boot)
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
        open -a Simulator --args -CurrentDeviceUDID "$udid" 2> /dev/null || open -a DeviceHub
        xcrun simctl install "$udid" "$app"
        xcrun simctl launch "$udid" "$bundle_id"
        ;;
    shutdown)
        udid=$(find_udid)
        if [ -n "$udid" ]; then
            xcrun simctl shutdown "$udid" 2> /dev/null || true
        fi
        ;;
    delete)
        udid=$(find_udid)
        if [ -n "$udid" ]; then
            xcrun simctl shutdown "$udid" 2> /dev/null || true
            xcrun simctl delete "$udid"
            echo "Deleted simulator $name"
        fi
        ;;
    name)
        echo "$name"
        ;;
    *)
        echo "Usage: $0 [udid|boot|launch <app path>|shutdown|delete|name]" >&2
        exit 1
        ;;
esac
