#!/bin/sh
set -eu

old_names="RATP_BUNDLE_ID_PREFIX RATP_DEBUG_APP_BUNDLE_ID RATP_DEBUG_WIDGET_BUNDLE_ID"

usage() {
    echo "Usage: $0 names     Print the old names of the settings of ios/Config/Local.xcconfig" >&2
    echo "       $0 settings  Refuse an old name in the build settings that xcodebuild -showBuildSettings prints on stdin" >&2
    echo "       $0 xcode     Refuse an old name in the build settings of a build phase of Xcode" >&2
    exit 2
}

refusal() {
    echo "ios/Config/Local.xcconfig sets $1, an old name: change the name only, to TROME_${1#RATP_}, and keep the value."
}

[ $# -eq 1 ] || usage
refused=0
case $1 in
    names)
        echo "$old_names"
        ;;
    settings)
        settings=$(cat)
        for name in $old_names; do
            if printf '%s\n' "$settings" | awk -v name="$name" '$1 == name && $2 == "=" { found = 1 } END { exit !found }'; then
                refusal "$name"
                refused=1
            fi
        done
        ;;
    xcode)
        for name in $old_names; do
            eval "value=\${$name:-}"
            if [ -n "$value" ]; then
                echo "error: $(refusal "$name")"
                refused=1
            fi
        done
        ;;
    *)
        usage
        ;;
esac
exit "$refused"
