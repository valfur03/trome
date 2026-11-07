#!/bin/sh
# The check of the silent start in a Release build: it fails when the app loses the push capability, when the app or
# its widget loses the app group, or when the archive has no silent start; a fake xcodebuild gives the settings.
# It also fails when a store archive has the Wake log or its test of the start, or a walk archive has none, or names
# no commit.
# It finds a type by its whole name in the Swift types of the binary, so the app binaries here are compiled Swift.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
# It compiles Swift, which loads the Mac as a build does, so it runs through the build gate, never next to a Simulator test run.
[ -n "${RATP_BUILD_GATE_HELD:-}" ] || exec "$scripts/build-gate.py" build "$0" "$@"
script="$scripts/release-entitlements-check.py"
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# A fake xcodebuild that gives the Release settings of the target that it is asked for, as the project has them.
cat > "$state/xcodebuild" << 'EOF'
#!/bin/sh
target=
previous=
for argument in "$@"; do
    [ "$previous" = -target ] && target=$argument
    previous=$argument
done
case $target in
    TROME) entitlements=${FAKE_APP_ENTITLEMENTS-Config/SilentStart.entitlements} ;;
    TROMEWidget) entitlements=${FAKE_WIDGET_ENTITLEMENTS-Config/AppGroup.entitlements} ;;
    *) exit 65 ;;
esac
printf '[{"target":"%s","buildSettings":{"SRCROOT":"%s","APP_BUNDLE_ID":"io.github.valfur03.trome","CODE_SIGN_ENTITLEMENTS":"%s","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"%s"}}]\n' \
    "$target" "$FAKE_SRCROOT" "$entitlements" "${FAKE_CONDITIONS-SILENT_START}"
EOF
chmod +x "$state/xcodebuild"

# entitlements <file> <push: yes or no> <group>: an entitlements file as the project writes it.
entitlements() {
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<plist version="1.0"><dict>'
        [ "$2" = no ] || echo '<key>aps-environment</key><string>development</string>'
        echo "<key>com.apple.security.application-groups</key><array><string>$3</string></array>"
        echo '</dict></plist>'
    } > "$state/project/Config/$1"
}
mkdir -p "$state/project/Config"
entitlements SilentStart.entitlements yes 'group.$(APP_BUNDLE_ID)'
entitlements AppGroup.entitlements no 'group.$(APP_BUNDLE_ID)'
entitlements NoPush.entitlements no 'group.$(APP_BUNDLE_ID)'
entitlements OtherGroup.entitlements yes 'group.io.example.other'

# binary <name> <Swift code>: an app binary of the module TROME, from a file that keeps the name of the silent start
# type, as a change that renames the type alone leaves it (its #fileID path stays in the binary).
binary() {
    mkdir -p "$state/swift/$1"
    printf '%s\nprint(#fileID)\n' "$2" > "$state/swift/$1/PushRegistrationAppDelegate.swift"
    xcrun swiftc -O -module-name TROME "$state/swift/$1/PushRegistrationAppDelegate.swift" -o "$state/swift/$1.bin"
}
binary silent-start 'final class PushRegistrationAppDelegate {}'
binary renamed 'final class StartTokenAppDelegate { let answered = "PushRegistrationAppDelegate.answered" }'
binary wake-log 'final class PushRegistrationAppDelegate {}
struct WakeLogScreen {}
struct StartTestRow {}'
binary test-start 'final class PushRegistrationAppDelegate {}
struct StartTestRow {}'
binary wake-log-no-test 'final class PushRegistrationAppDelegate {}
struct WakeLogScreen {}'
printf 'binary PushRegistrationAppDelegate code' > "$state/swift/text.bin"

# archive <app group of the widget> <app binary> [<commit>]: an archive as make release-archive-check makes it, with
# the commit that the build wrote in its Info.plist.
archive() {
    rm -rf "$state/TROME.xcarchive"
    app="$state/TROME.xcarchive/Products/Applications/TROME.app"
    mkdir -p "$app/PlugIns/TROMEWidget.appex"
    plutil -create xml1 "$app/Info.plist"
    plutil -insert TROMEAppGroup -string group.io.github.valfur03.trome "$app/Info.plist"
    [ -z "${3:-}" ] || plutil -insert TROMECommit -string "$3" "$app/Info.plist"
    plutil -create xml1 "$app/PlugIns/TROMEWidget.appex/Info.plist"
    plutil -insert TROMEAppGroup -string "$1" "$app/PlugIns/TROMEWidget.appex/Info.plist"
    cp "$state/swift/$2.bin" "$app/TROME"
}

run() {
    env "$@" XCODEBUILD="$state/xcodebuild" FAKE_SRCROOT="$state/project" \
        "$script" TROME.xcodeproj ${ARCHIVE:+"$ARCHIVE"} > "$state/out" 2>&1 && echo passes || echo fails
}

archive group.io.github.valfur03.trome silent-start
ARCHIVE=
expect "the project as it is passes" "$(run)" passes
expect "an app with no entitlements in Release fails" "$(run FAKE_APP_ENTITLEMENTS=)" fails
expect "an app with no push capability fails" "$(run FAKE_APP_ENTITLEMENTS=Config/NoPush.entitlements)" fails
expect "the failure names the push capability" "$(grep -c 'no push capability' "$state/out")" 1
expect "an app with another app group fails" "$(run FAKE_APP_ENTITLEMENTS=Config/OtherGroup.entitlements)" fails
expect "a widget with no entitlements in Release fails" "$(run FAKE_WIDGET_ENTITLEMENTS=)" fails
expect "a widget with another app group fails" "$(run FAKE_WIDGET_ENTITLEMENTS=Config/OtherGroup.entitlements)" fails
expect "the failure names the widget" "$(grep -c 'TROMEWidget do not name the app group' "$state/out")" 1

ARCHIVE="$state/TROME.xcarchive"
expect "the archive as make release-archive-check makes it passes" "$(run)" passes
archive group.io.example.other silent-start
expect "an archive whose widget reads another app group fails" "$(run)" fails
archive group.io.github.valfur03.trome renamed
expect "an archive whose type is renamed in a file that keeps its old name fails" "$(run)" fails
expect "the failure names the silent start" "$(grep -c 'has no silent start' "$state/out")" 1
archive group.io.github.valfur03.trome text
expect "an app binary that holds the name only as text fails" "$(run)" fails
archive group.io.github.valfur03.trome wake-log 1e2e704
expect "a store archive with the Wake log fails" "$(run)" fails
expect "the failure names the Wake log" "$(grep -c 'has the Wake log' "$state/out")" 1
expect "a walk archive with the Wake log passes" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" passes
expect "the pass says it is not for the store" "$(grep -c 'never for the store' "$state/out")" 1
archive group.io.github.valfur03.trome test-start 1e2e704
expect "a store archive with the test of the start fails" "$(run)" fails
expect "the failure names the test of the start" "$(grep -c 'has the test of the start' "$state/out")" 1
archive group.io.github.valfur03.trome wake-log-no-test 1e2e704
expect "a walk archive with no test of the start fails" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" fails
expect "the failure names the missing test of the start" "$(grep -c 'has no test of the start' "$state/out")" 1
archive group.io.github.valfur03.trome wake-log 1e2e704-dirty
expect "a walk archive made with changes not committed passes" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" passes
archive group.io.github.valfur03.trome wake-log
expect "a walk archive that names no commit fails" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" fails
expect "the failure names the commit" "$(grep -c 'names no commit' "$state/out")" 1
archive group.io.github.valfur03.trome wake-log '$(TROME_COMMIT)'
expect "a walk archive whose commit is no hash fails" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" fails
archive group.io.github.valfur03.trome silent-start
expect "a walk archive with no Wake log fails" "$(run FAKE_CONDITIONS="SILENT_START WAKE_LOG")" fails
expect "the store archive says it has no Wake log" "$(run >/dev/null; grep -c 'with no Wake log' "$state/out")" 1
rm -rf "$state/TROME.xcarchive"
expect "a missing archive fails" "$(run)" fails

[ "$failures" -eq 0 ] || exit 1
echo "release-entitlements-check-test: OK"
