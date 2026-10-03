#!/bin/sh
set -eu

project_yml=$1
xcode_version=${2#Xcode }
[ -n "$xcode_version" ] || {
    echo "recommended-settings-check: could not read the Xcode version (is Xcode selected with xcode-select?)" >&2
    exit 1
}

version_number() {
    major=$(echo "$1" | cut -d. -f1)
    minor=$(echo "$1" | cut -s -d. -f2)
    echo $((major * 1000 + ${minor:-0}))
}

checked_version=$(sed -n -E 's/^  xcodeVersion: "?([0-9.]+)"?$/\1/p' "$project_yml")
[ -n "$checked_version" ] || {
    echo "recommended-settings-check: $project_yml has no options.xcodeVersion" >&2
    exit 1
}

if [ "$(version_number "$xcode_version")" -gt "$(version_number "$checked_version")" ]; then
    echo "recommended-settings-check: FAILED: Xcode $xcode_version may recommend new project settings." >&2
    echo "The project was last checked with Xcode $checked_version (options.xcodeVersion in ios/project.yml)." >&2
    echo "Open ios/TROME.xcodeproj in Xcode and click the warning \"Update to recommended settings\"." >&2
    echo "Add each setting that Xcode proposes to ios/project.yml (do not click \"Perform Changes\": make generate would undo it)." >&2
    echo "Then set options.xcodeVersion to \"$xcode_version\" and run make generate." >&2
    exit 1
fi
echo "recommended-settings-check: OK (the project settings were checked with Xcode $checked_version)"
