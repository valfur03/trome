#!/bin/sh
# The check of the silent start in a Release build: it fails when the app loses the push capability, when the app or
# its widget loses the app group, or when the archive has no silent start; a fake xcodebuild gives the settings.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-entitlements-check.py"
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
printf '[{"target":"%s","buildSettings":{"SRCROOT":"%s","APP_BUNDLE_ID":"io.github.valfur03.trome","CODE_SIGN_ENTITLEMENTS":"%s"}}]\n' \
    "$target" "$FAKE_SRCROOT" "$entitlements"
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

# archive <app group of the widget> <a type in the app binary>: an archive as make release-archive-check makes it.
archive() {
    rm -rf "$state/TROME.xcarchive"
    app="$state/TROME.xcarchive/Products/Applications/TROME.app"
    mkdir -p "$app/PlugIns/TROMEWidget.appex"
    plutil -create xml1 "$app/Info.plist"
    plutil -insert TROMEAppGroup -string group.io.github.valfur03.trome "$app/Info.plist"
    plutil -create xml1 "$app/PlugIns/TROMEWidget.appex/Info.plist"
    plutil -insert TROMEAppGroup -string "$1" "$app/PlugIns/TROMEWidget.appex/Info.plist"
    printf 'binary %s code' "$2" > "$app/TROME"
}

run() {
    env "$@" XCODEBUILD="$state/xcodebuild" FAKE_SRCROOT="$state/project" \
        "$script" TROME.xcodeproj ${ARCHIVE:+"$ARCHIVE"} > "$state/out" 2>&1 && echo passes || echo fails
}

archive group.io.github.valfur03.trome ActivityKitPushToStartTokenSource
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
archive group.io.example.other ActivityKitPushToStartTokenSource
expect "an archive whose widget reads another app group fails" "$(run)" fails
archive group.io.github.valfur03.trome NotificationOnly
expect "an archive with no silent start compiled fails" "$(run)" fails
expect "the failure names the silent start" "$(grep -c 'has no silent start' "$state/out")" 1
rm -rf "$state/TROME.xcarchive"
expect "a missing archive fails" "$(run)" fails

[ "$failures" -eq 0 ] || exit 1
echo "release-entitlements-check-test: OK"
