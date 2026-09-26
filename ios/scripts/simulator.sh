#!/bin/sh
set -eu

name=${RATP_SIM_NAME:-RATP-Shared}
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

device_udid() {
    udid=$(find_udid)
    if [ -z "$udid" ]; then
        udid=$(create_device)
    fi
    echo "$udid"
}

boot_device() {
    udid=$(device_udid)
    xcrun simctl bootstatus "$udid" -b > /dev/null
    echo "$udid"
}

installed_apps() {
    xcrun simctl listapps "$1" \
        | sed -n -E 's/^ *CFBundleIdentifier = "?([^";]*\.RATPActivity)"?;$/\1/p'
}

uninstall_apps() {
    for installed_app in $(installed_apps "$1"); do
        xcrun simctl uninstall "$1" "$installed_app"
    done
}

is_booted() {
    xcrun simctl list devices booted | grep -qF "($1)"
}

reset_device() {
    uninstall_apps "$1"
    xcrun simctl privacy "$1" reset all
    xcrun simctl location "$1" clear
}

delete_old_devices() {
    xcrun simctl list devices \
        | sed -n -E 's/^    (RATP-[^ ]+) \(([0-9A-F-]{36})\) \(([^)]+)\).*/\1 \2 \3/p' \
        | while read -r old_name udid state; do
            if [ "$old_name" = "$name" ]; then
                continue
            fi
            if [ "$state" != Shutdown ]; then
                echo "Kept simulator $old_name: it is not shut down ($state)"
                continue
            fi
            xcrun simctl delete "$udid"
            echo "Deleted simulator $old_name"
        done
}

command=${1:-udid}
[ $# -gt 0 ] && shift

case "$command" in
    udid)
        device_udid
        ;;
    find)
        find_udid
        ;;
    boot)
        boot_device
        ;;
    reset)
        udid=$(boot_device)
        reset_device "$udid"
        if [ $# -gt 0 ]; then
            exec "$@"
        fi
        ;;
    launch)
        app=${1:?Usage: $0 launch <app path>}
        udid=$(boot_device)
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
        open -a Simulator --args -CurrentDeviceUDID "$udid" 2> /dev/null || open -a DeviceHub
        reset_device "$udid"
        xcrun simctl install "$udid" "$app"
        xcrun simctl launch "$udid" "$bundle_id"
        ;;
    uninstall)
        udid=$(find_udid)
        if [ -n "$udid" ] && is_booted "$udid"; then
            uninstall_apps "$udid"
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
    delete-old)
        delete_old_devices
        ;;
    name)
        echo "$name"
        ;;
    *)
        echo "Usage: $0 [udid|find|boot|reset [command...]|launch <app path>|uninstall|delete|delete-old|name]" >&2
        exit 1
        ;;
esac
