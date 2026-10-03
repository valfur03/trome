#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../old-setting-names.sh"
failures=0

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

settings() {
    printf '%s\n' "Build settings for action build and target TROME:" "$@" | "$script" settings && echo "passes" || echo "fails"
}

xcode() {
    env -u RATP_BUNDLE_ID_PREFIX -u RATP_DEBUG_APP_BUNDLE_ID -u RATP_DEBUG_WIDGET_BUNDLE_ID "$@" "$script" xcode \
        && echo "passes" || echo "fails"
}

sentence() {
    echo "ios/Config/Local.xcconfig sets RATP_$1, an old name: change the name only, to TROME_$1, and keep the value."
}

expect "it names the three old settings" "$("$script" names)" \
    "RATP_BUNDLE_ID_PREFIX RATP_DEBUG_APP_BUNDLE_ID RATP_DEBUG_WIDGET_BUNDLE_ID"

expect "the new names pass" \
    "$(settings "    TROME_BUNDLE_ID_PREFIX = io.github.jane" "    TROME_DEBUG_APP_BUNDLE_ID = io.github.jane.OldApp")" "passes"
for name in BUNDLE_ID_PREFIX DEBUG_APP_BUNDLE_ID DEBUG_WIDGET_BUNDLE_ID; do
    expect "the old name RATP_$name in the build settings is refused with one sentence" \
        "$(settings "    RATP_$name = io.github.jane.OldApp")" "$(sentence "$name")
fails"
    expect "the old name RATP_$name in a build of Xcode is refused with the same sentence" \
        "$(xcode "RATP_$name=io.github.jane.OldApp")" "error: $(sentence "$name")
fails"
done
expect "the app and the extension both set are refused, each with its sentence" \
    "$(settings "    RATP_DEBUG_APP_BUNDLE_ID = io.github.jane.OldApp" "    RATP_DEBUG_WIDGET_BUNDLE_ID = io.github.jane.OldApp.Widget")" \
    "$(sentence DEBUG_APP_BUNDLE_ID)
$(sentence DEBUG_WIDGET_BUNDLE_ID)
fails"
expect "the app and the extension both set are refused in a build of Xcode" \
    "$(xcode RATP_DEBUG_APP_BUNDLE_ID=io.github.jane.OldApp RATP_DEBUG_WIDGET_BUNDLE_ID=io.github.jane.OldApp.Widget)" \
    "error: $(sentence DEBUG_APP_BUNDLE_ID)
error: $(sentence DEBUG_WIDGET_BUNDLE_ID)
fails"
expect "a quoted value is refused" \
    "$(settings '    RATP_DEBUG_APP_BUNDLE_ID = "io.github.jane.OldApp"' | tail -1)" "fails"
expect "a quoted value is refused in a build of Xcode" \
    "$(xcode 'RATP_DEBUG_APP_BUNDLE_ID="io.github.jane.OldApp"' | tail -1)" "fails"
expect "a setting whose name only starts with an old name passes" \
    "$(settings "    RATP_DEBUG_APP_BUNDLE_ID_SUFFIX = x" "    MY_RATP_BUNDLE_ID_PREFIX = x")" "passes"
expect "an empty old setting, which changes no ID, passes in a build of Xcode" "$(xcode RATP_DEBUG_APP_BUNDLE_ID=)" "passes"
expect "no old setting passes in a build of Xcode" "$(xcode TROME_DEBUG_APP_BUNDLE_ID=io.github.jane.OldApp)" "passes"

status=0
"$script" > /dev/null 2>&1 || status=$?
expect "no mode is a usage error" "$status" "2"

[ "$failures" -eq 0 ]
