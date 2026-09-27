#!/bin/sh
set -eu

shared_names="RATP-Shared RATP-Shared-Small"
springboard_wait_seconds=${RATP_SPRINGBOARD_WAIT_SECONDS:-60}

case "${RATP_SIM_SIZE:-}" in
    "")
        name=RATP-Shared
        device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17
        ;;
    small)
        name=RATP-Shared-Small
        device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation
        ;;
    *)
        echo "Unknown RATP_SIM_SIZE: $RATP_SIM_SIZE (use 'small', or leave it empty)" >&2
        exit 1
        ;;
esac

udid_of() {
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | head -n 1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

find_udid() {
    udid_of "$name"
}

is_shared_name() {
    for shared_name in $shared_names; do
        [ "$1" = "$shared_name" ] && return 0
    done
    return 1
}

booted_shared_udids() {
    booted=$(xcrun simctl list devices booted) || return 1
    for shared_name in $shared_names; do
        printf '%s\n' "$booted" \
            | grep -F "    $shared_name (" \
            | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
    done
}

shut_down_other_shared() {
    others=$(booted_shared_udids) || return 1
    for other in $others; do
        if [ "$other" != "$1" ] && ! xcrun simctl shutdown "$other" 2> /dev/null && is_booted "$other"; then
            echo "Could not shut down the other shared Simulator ($other), so this job does not boot a second one" >&2
            return 1
        fi
    done
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
    shut_down_other_shared "$udid" || exit 1
    xcrun simctl bootstatus "$udid" -b > /dev/null
    echo "$udid"
}

installed_apps() {
    xcrun simctl listapps "$1" \
        | sed -n -E 's/^ *CFBundleIdentifier = "?([^";]*\.RATPActivity)"?;$/\1/p'
}

left_preference_domains() {
    xcrun simctl spawn "$1" defaults domains \
        | tr ',' '\n' \
        | sed -n -E 's/^ *([^ ]*\.RATPActivity[A-Za-z.]*) *$/\1/p'
}

uninstall_apps() {
    for installed_app in $(installed_apps "$1"); do
        xcrun simctl uninstall "$1" "$installed_app"
    done
    for domain in $(left_preference_domains "$1"); do
        xcrun simctl spawn "$1" defaults delete "$domain" 2> /dev/null || true
    done
}

is_booted() {
    xcrun simctl list devices booted | grep -qF "($1)"
}

springboard_is_ready() {
    xcrun simctl spawn "$1" launchctl print user/foreground/com.apple.SpringBoard 2> /dev/null \
        | awk '/"com\.apple\.springboard\.services" = \{/ { found = 1 } found && /active = / { exit !($3 == 1) } END { if (!found) exit 1 }'
}

wait_for_springboard() {
    tries=0
    until springboard_is_ready "$1"; do
        tries=$((tries + 1))
        if [ "$tries" -ge "$springboard_wait_seconds" ]; then
            echo "SpringBoard did not say it is ready after $springboard_wait_seconds s; going on" >&2
            return 0
        fi
        sleep 1
    done
}

reset_device() {
    uninstall_apps "$1"
    xcrun simctl privacy "$1" reset all
    xcrun simctl spawn "$1" launchctl kickstart -k user/foreground/com.apple.SpringBoard
    xcrun simctl spawn "$1" launchctl kickstart -k user/foreground/com.apple.locationd
    xcrun simctl location "$1" clear
    wait_for_springboard "$1"
}

grant_location_while_using() {
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$2/Info.plist")
    xcrun simctl install "$1" "$2"
    xcrun simctl privacy "$1" grant location "$bundle_id"
}

delete_old_devices() {
    xcrun simctl list devices \
        | sed -n -E 's/^    (RATP-[^ ]+) \(([0-9A-F-]{36})\) \(([^)]+)\).*/\1 \2 \3/p' \
        | while read -r old_name udid state; do
            if is_shared_name "$old_name"; then
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
    grant-location)
        app=${1:?Usage: $0 grant-location <app path> [command...]}
        shift
        grant_location_while_using "$(boot_device)" "$app"
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
        udid=${1:-$(find_udid)}
        if [ -n "$udid" ] && is_booted "$udid"; then
            uninstall_apps "$udid"
        fi
        ;;
    shutdown-if-not-default)
        udid=${1:?Usage: $0 shutdown-if-not-default <udid>}
        if [ "$udid" != "$(udid_of RATP-Shared)" ]; then
            xcrun simctl shutdown "$udid" 2> /dev/null || true
        fi
        ;;
    booted)
        booted_shared_udids
        ;;
    delete)
        for shared_name in $shared_names; do
            udid=$(udid_of "$shared_name")
            if [ -n "$udid" ]; then
                xcrun simctl shutdown "$udid" 2> /dev/null || true
                xcrun simctl delete "$udid"
                echo "Deleted simulator $shared_name"
            fi
        done
        ;;
    delete-old)
        delete_old_devices
        ;;
    name)
        echo "$name"
        ;;
    *)
        echo "Usage: $0 [udid|find|boot|reset [command...]|grant-location <app path> [command...]|launch <app path>|uninstall [udid]|shutdown-if-not-default <udid>|booted|delete|delete-old|name]" >&2
        echo "RATP_SIM_SIZE=small uses the small shared Simulator (RATP-Shared-Small, an iPhone SE) instead of RATP-Shared" >&2
        exit 1
        ;;
esac
