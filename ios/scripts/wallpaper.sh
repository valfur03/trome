#!/bin/sh
set -eu

# The wallpaper of the pictures, set once on the shared Simulator and kept.
# The Simulator has no command for a wallpaper, so `set` runs the UI test SetTheWallpaperTests,
# and `check` reads what iOS wrote on disk (its wallpaper database), with no Simulator job.

usage() {
    echo "Usage: $0 id                  The gallery id of the wallpaper, from ios/DocsScreenshots/Wallpaper.swift" >&2
    echo "       $0 list [udid]         The wallpapers of the lock screen on disk, one per line: <uuid> <gallery id> <in use: 1 or 0>" >&2
    echo "       $0 check [udid]        Fails, with one line, when the Simulator does not show the wallpaper of the pictures" >&2
    echo "       $0 set <result bundle> <xcodebuild command...>" >&2
    echo "              Sets it, when the check fails. Run it through the Simulator lock, in ios/:" >&2
    echo "              ./scripts/sim-lock.sh job ./scripts/simulator.sh reset ./scripts/simulator.sh with-destination $0 set ..." >&2
    echo "The udid is the shared Simulator by default. TROME_SIM_DEVICES is the folder of the Simulators (for a test)." >&2
    exit 1
}

scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/.." && pwd)
devices=${TROME_SIM_DEVICES:-$HOME/Library/Developer/CoreSimulator/Devices}
target=TROMEDocsScreenshots
set_command="make simulator-wallpaper"
role=PRPosterRoleLockScreen
write_wait_seconds=${TROME_WALLPAPER_WAIT_SECONDS:-10}

wallpaper_id() {
    id=$(sed -n 's/^ *static let galleryID = "\([^"]*\)"$/\1/p' "$root/DocsScreenshots/Wallpaper.swift")
    [ -n "$id" ] || { echo "No galleryID in ios/DocsScreenshots/Wallpaper.swift" >&2; exit 1; }
    echo "$id"
}

# The folder of the wallpaper database: its name is a version number of iOS, so take the one that holds it.
store_of() {
    store=
    for candidate in "$devices/$1/data/Library/Application Support/PRBPosterExtensionDataStore"/*/; do
        [ -f "${candidate}PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3" ] && store=${candidate%/}
    done
    echo "$store"
}

list() {
    store=$(store_of "$1")
    [ -n "$store" ] || return 0
    sqlite3 -separator ' ' "file:$store/PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3?mode=ro" \
        "SELECT p.UUID, p.providerId, COALESCE(a.attributePayload, '0')
         FROM posterRoleMembership m JOIN poster p ON p.UUID = m.posterUUID
         LEFT JOIN posterAttributes a ON a.posterUUID = p.UUID AND a.roleId = m.roleId AND a.attributeIdentifier = 'SELECTED'
         WHERE m.roleId = '$role' ORDER BY m.roleSortKey;" \
        | while read -r uuid provider selected; do
            descriptor_file="$store/Extensions/$provider/configurations/$uuid/com.apple.posterkit.provider.descriptor.identifier"
            descriptor=$(cat "$descriptor_file" 2> /dev/null || echo unknown)
            echo "$uuid $provider:$descriptor $selected"
        done
}

udid_or_shared() {
    udid=${1:-$("$scripts/simulator.sh" find)}
    if [ -z "$udid" ]; then
        echo "No shared Simulator yet, so no wallpaper of the pictures: run $set_command" >&2
        exit 1
    fi
    echo "$udid"
}

is_set() {
    list "$1" | grep -q " $(wallpaper_id) 1$"
}

check() {
    udid=$(udid_or_shared "${1:-}")
    is_set "$udid" && return 0
    echo "The Simulator does not show the wallpaper of the pictures ($(wallpaper_id)): run $set_command" >&2
    exit 1
}

set_wallpaper() {
    result=$1
    shift
    udid=$("$scripts/simulator.sh" boot)
    id=$(wallpaper_id)
    if is_set "$udid"; then
        echo "Wallpaper $id: already set, nothing to do"
        return 0
    fi
    # The switcher may hold it, not in use: choose it, so that the Simulator never gets a second copy.
    uuid=$(list "$udid" | awk -v id="$id" '$2 == id { print $1; exit }')
    rm -rf "$result"
    env TEST_RUNNER_SET_THE_WALLPAPER=1 TEST_RUNNER_WALLPAPER_UUID="$uuid" "$@" -resultBundlePath "$result" \
        -only-testing:"$target/SetTheWallpaperTests" test-without-building \
        || {
            status=$?
            "$scripts/e2e-failures.py" "$result"
            exit $status
        }
    # iOS writes its database a moment after the wallpaper shows.
    waited=0
    while :; do
        if is_set "$udid"; then
            echo "Wallpaper $id: set ($([ -n "$uuid" ] && echo "chosen in the switcher" || echo "added"))"
            list "$udid"
            return 0
        fi
        [ "$waited" -lt "$write_wait_seconds" ] || break
        sleep 1
        waited=$((waited + 1))
    done
    echo "The test passed, but iOS does not show the wallpaper $id. The wallpapers of the lock screen:" >&2
    list "$udid" >&2
    exit 1
}

[ $# -ge 1 ] || usage
command=$1
shift
case "$command" in
    id) wallpaper_id ;;
    list)
        udid=$(udid_or_shared "${1:-}")
        list "$udid"
        ;;
    check) check "${1:-}" ;;
    set)
        [ $# -ge 2 ] || usage
        set_wallpaper "$@"
        ;;
    *) usage ;;
esac
