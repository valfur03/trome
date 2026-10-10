#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
shared_name_pattern='RATP-Shared(-Small)?(-[0-9]+)?'
springboard_wait_seconds=${TROME_SPRINGBOARD_WAIT_SECONDS:-60}
widget_host_wait_seconds=${TROME_WIDGET_HOST_WAIT_SECONDS:-240}
widget_host_log_seconds=60
slot=${RATP_SIM_SLOT:-1}

case "$slot" in
    "" | *[!0-9]* | 0)
        echo "Unknown RATP_SIM_SLOT: $slot (use 1, 2, ...)" >&2
        exit 1
        ;;
    1) suffix= ;;
    *) suffix="-$slot" ;;
esac
default_name="RATP-Shared$suffix"
small_name="RATP-Shared-Small$suffix"
slot_names="$default_name $small_name"

case "${RATP_SIM_LANGUAGE:-en}" in
    en)
        language=en
        locale=en_US
        ;;
    fr)
        language=fr
        locale=fr_FR
        ;;
    *)
        echo "Unknown RATP_SIM_LANGUAGE: $RATP_SIM_LANGUAGE (use 'en' or 'fr')" >&2
        exit 1
        ;;
esac

case "${RATP_SIM_SIZE:-}" in
    "")
        name=$default_name
        device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17
        ;;
    small)
        name=$small_name
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
    printf '%s\n' "$1" | grep -Eqx "$shared_name_pattern"
}

booted_shared_udids() {
    booted=$(xcrun simctl list devices booted) || return 1
    for shared_name in $slot_names; do
        printf '%s\n' "$booted" \
            | grep -F "    $shared_name (" \
            | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
    done
}

shut_down_other_shared() {
    others=$(booted_shared_udids) || return 1
    for other in $others; do
        if [ "$other" != "$1" ] && ! xcrun simctl shutdown "$other" 2> /dev/null && is_booted "$other"; then
            echo "Could not shut down the other shared Simulator of slot $slot ($other), so this job does not boot a second one in its slot" >&2
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

# The apps of the builds of this repo: the Debug app and its test hosts, the apps of the old name, and the Release app
# of make run RELEASE=1, which has the App Store bundle ID of project.yml.
installed_apps() {
    xcrun simctl listapps "$1" \
        | sed -n -E 's/^ *CFBundleIdentifier = "?([^";]*\.(trome\.dev(\.render-check-host)?|RATPActivity[A-Za-z]*(\.xctrunner)?)|io\.github\.valfur03\.trome)"?;$/\1/p'
}

left_preference_domains() {
    xcrun simctl spawn "$1" defaults domains \
        | tr ',' '\n' \
        | sed -n -E 's/^ *([^ ]*\.(trome\.dev[a-z.-]*|RATPActivity[A-Za-z.]*)|io\.github\.valfur03\.trome(\.[a-z.]+)?) *$/\1/p'
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

widget_host_state() {
    xcrun simctl spawn "$1" log show --style compact --last "${widget_host_log_seconds}s" \
        --predicate 'process == "chronod" AND category == "taskservice"' 2> /dev/null \
        | awk '
            /No tasks pending/ || /pendingTasks\.count = 0([^0-9]|$)/ { state = "idle"; next }
            /No available queue to process pending tasks/ || /all extensions are busy/ || /pendingTasks\.count = [1-9]/ { state = "busy" }
            END { print (state == "busy" ? "busy" : "idle") }
        '
}

# After some cold boots, the widget host of the Simulator (chronod, the iOS service that draws widgets and
# Live Activities) first works through a queue of tasks for all the system widgets, for minutes on a busy Mac.
# Until it reads the widget of the new install, at the end of that queue, a Live Activity that the app starts
# shows nowhere, and the first test of a run that looks for one fails. So the jobs wait until its log says that
# the queue is empty. A newer iOS may change these log messages: then the jobs no longer wait.
wait_for_widget_host() {
    deadline=$(($(date +%s) + widget_host_wait_seconds))
    waited=
    while [ "$(widget_host_state "$1")" = busy ]; do
        if [ -z "$waited" ]; then
            echo "Waiting for the widget host of the Simulator (chronod) to finish the work queued at boot" >&2
            waited=yes
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "The widget host of the Simulator (chronod) still had work queued after $widget_host_wait_seconds s; going on" >&2
            return 0
        fi
        sleep 2
    done
}

set_language() {
    xcrun simctl spawn "$1" defaults write -g AppleLanguages -array "$language"
    xcrun simctl spawn "$1" defaults write -g AppleLocale -string "$locale"
    xcrun simctl spawn "$1" defaults write -g AppleMetricUnits -bool true
    xcrun simctl spawn "$1" defaults write -g AppleMeasurementUnits -string Centimeters
    for clock_override in AppleICUForce24HourTime AppleICUForce12HourTime; do
        xcrun simctl spawn "$1" defaults delete -g "$clock_override" 2> /dev/null || true
    done
    # The lock screen draws the time of 'simctl status_bar override' only with a 12-hour clock:
    # with a 24-hour clock (French), it shows the real time, so a picture would change at each run.
    if [ "${TROME_SIM_CLOCK:-}" = 12 ]; then
        xcrun simctl spawn "$1" defaults write -g AppleICUForce12HourTime -bool true
    fi
}

# A restart of SpringBoard leaves the process that draws the Live Activities (a renderer of chronod) running.
# The new SpringBoard shows the Live Activities of that old renderer, but XCTest cannot read them: the
# Live Activity holds only a RemotePlaceholder, and XCTest logs kAXErrorServerNotFound, so a test finds none
# of its texts. So after each restart of SpringBoard, stop the renderer too: iOS starts a new one at once.
restart_live_activity_renderer() {
    xcrun simctl terminate "$1" com.apple.chrono.WidgetRenderer-Activities 2> /dev/null || true
}

restart_springboard_in_language() {
    set_language "$1"
    xcrun simctl spawn "$1" launchctl kickstart -k user/foreground/com.apple.SpringBoard
    wait_for_springboard "$1"
    restart_live_activity_renderer "$1"
    wait_for_widget_host "$1"
}

reset_display() {
    xcrun simctl ui "$1" content_size large
    xcrun simctl ui "$1" appearance light
}

# Each job starts from the same Simulator, whatever an earlier job or a person left in it:
# - A removed app can leave its saved settings outside its data, and the next install reads them.
# - A check of large text or dark mode changes them for the whole Simulator. With a very large text,
#   the main screen scrolls over several pages, and the E2E tests no longer find their buttons.
# - A system popup of the removed app ("Change to Always Allow", the notification question) stays on screen
#   and covers the new app, until SpringBoard restarts.
# - When the app is removed while iOS shows its "Change to Always Allow" popup, the location service keeps
#   that popup in flight and ignores every new location request of the app, until it restarts.
# - The notification setting of the removed app ("Allow") stays when the app is removed just after a cold boot:
#   SpringBoard misses the removal, so it never forgets the setting, and the next install of the app is allowed with no
#   question. 'simctl privacy' does not cover notifications, so the reset removes the setting from the file that
#   SpringBoard reads when it starts, just before it restarts SpringBoard.
reset_device() {
    uninstall_apps "$1"
    xcrun simctl privacy "$1" reset all
    set_language "$1"
    reset_display "$1"
    data=$(xcrun simctl getenv "$1" HOME)
    "$scripts/simulator-notifications.py" forget "$data"
    xcrun simctl spawn "$1" launchctl kickstart -k user/foreground/com.apple.SpringBoard
    xcrun simctl spawn "$1" launchctl kickstart -k user/foreground/com.apple.locationd
    xcrun simctl location "$1" clear
    wait_for_springboard "$1"
    restart_live_activity_renderer "$1"
    if ! remembered=$("$scripts/simulator-notifications.py" remembered "$data"); then
        echo "The Simulator still keeps the notification setting of $remembered after the reset, so the app would get no notification question." >&2
        exit 1
    fi
}

grant_location_while_using() {
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$2/Info.plist")
    xcrun simctl install "$1" "$2"
    xcrun simctl privacy "$1" grant location "$bundle_id"
}

delete_shared_devices() {
    xcrun simctl list devices \
        | sed -n -E 's/^    (RATP-[^ ]+) \(([0-9A-F-]{36})\).*/\1 \2/p' \
        | while read -r shared_name udid; do
            if ! is_shared_name "$shared_name"; then
                continue
            fi
            xcrun simctl shutdown "$udid" 2> /dev/null || true
            xcrun simctl delete "$udid"
            echo "Deleted simulator $shared_name"
        done
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
    wait-for-widget-host)
        wait_for_widget_host "$(boot_device)"
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
        wait_for_widget_host "$udid"
        xcrun simctl install "$udid" "$app"
        xcrun simctl launch "$udid" "$bundle_id"
        ;;
    language)
        restart_springboard_in_language "$(boot_device)"
        ;;
    switch-language)
        app=${1:?Usage: $0 switch-language <app path>}
        udid=$(boot_device)
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
        if ! xcrun simctl get_app_container "$udid" "$bundle_id" > /dev/null 2>&1; then
            echo "The app is not in the Simulator. Run 'make run' first." >&2
            exit 1
        fi
        xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
        set_language "$udid"
        xcrun simctl spawn "$udid" launchctl kickstart -k user/foreground/com.apple.SpringBoard
        wait_for_springboard "$udid"
        restart_live_activity_renderer "$udid"
        xcrun simctl launch "$udid" "$bundle_id"
        ;;
    uninstall)
        udid=${1:-$(find_udid)}
        if [ -n "$udid" ] && is_booted "$udid"; then
            uninstall_apps "$udid"
        fi
        ;;
    booted)
        booted_shared_udids
        ;;
    booted-others)
        udid=$(find_udid)
        if [ -n "$udid" ]; then
            for other in $(booted_shared_udids); do
                [ "$other" = "$udid" ] || echo "$other"
            done
        fi
        ;;
    with-destination)
        [ $# -gt 0 ] || { echo "Usage: $0 with-destination <xcodebuild command...>" >&2; exit 1; }
        udid=$(device_udid)
        exec "$@" -destination "platform=iOS Simulator,id=$udid"
        ;;
    delete)
        delete_shared_devices
        ;;
    delete-old)
        delete_old_devices
        ;;
    *)
        echo "Usage: $0 [udid|find|boot|reset [command...]|wait-for-widget-host [command...]|grant-location <app path> [command...]|launch <app path>|language|switch-language <app path>|uninstall [udid]|booted-others|with-destination <xcodebuild command...>|booted|delete|delete-old]" >&2
        echo "RATP_SIM_SLOT=<n> uses the shared Simulators of slot n (RATP-Shared-<n>, RATP-Shared-Small-<n>); slot 1 (the default) uses RATP-Shared and RATP-Shared-Small" >&2
        echo "RATP_SIM_LANGUAGE=fr sets the language of the Simulator to French (with 'reset', 'launch', 'language' and 'switch-language'); the default is English (en)" >&2
        echo "TROME_SIM_CLOCK=12 forces a 12-hour clock (with 'language'), so that the lock screen shows the time of the status bar override; every other command sets the clock of the language" >&2
        echo "RATP_SIM_SIZE=small uses the small shared Simulator of the slot (an iPhone SE) instead of its iPhone 17" >&2
        exit 1
        ;;
esac
