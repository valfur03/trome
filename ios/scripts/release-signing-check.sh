#!/bin/sh
# Proves that Xcode signs a Release build only with the team of ios/Config/Signing.xcconfig.
# With no team there, Xcode must refuse to sign it, also when Xcode or ios/Config/Local.xcconfig knows another team:
# else a free Personal Team that archives the app registers the App Store IDs for good.
# Each build stops at the signing check, before any compile, in a few seconds.
# It never passes -allowProvisioningUpdates, so Xcode never talks to Apple and registers nothing.
# The settings on the command line win over ios/Config/Signing.xcconfig, so the check is the same on every Mac,
# and never prints the team of that file.
set -eu

project=${1:-TROME.xcodeproj}
work=${2:-.build/release-signing-check}
xcodebuild=${XCODEBUILD:-xcodebuild}
# Not a real team: Xcode only needs a value to turn on automatic signing.
sample_team=SAMPLETEAM
failed=0

fail() {
    echo "release-signing-check: FAILED: $1" >&2
    failed=1
}

# sign <name> <setting>...: build Release for a device with these settings; print the error lines of the build.
sign() {
    name=$1
    shift
    mkdir -p "$work"
    log="$work/$name.log"
    if "$xcodebuild" -project "$project" -scheme TROME -configuration Release -destination 'generic/platform=iOS' \
        -derivedDataPath "$work/DerivedData" -clonedSourcePackagesDirPath "$work/SourcePackages" \
        "$@" build > "$log" 2>&1; then
        echo signed
    fi
    grep 'error: ' "$log" | sed 's/.*error: //' || true
}

# refused <name> <label> <setting>...: the build must stop with the error of manual signing with no profile, for the app and its extension.
refused() {
    name=$1
    label=$2
    shift 2
    errors=$(sign "$name" "$@")
    case $errors in
        signed*)
            fail "a Release build with $label signed: Xcode could then register the App Store IDs to any team"
            return ;;
    esac
    for target in TROME TROMEWidget; do
        echo "$errors" | grep -qF "\"$target\" requires a provisioning profile" || {
            fail "a Release build with $label did not stop at the manual signing of the app and its extension; its errors:
$errors
(log: ios/$work/$name.log)"
            return
        }
    done
}

# automatic <setting>...: with a team in TROME_RELEASE_TEAM, Xcode must sign the app and its extension automatically, with their App Store IDs.
automatic() {
    errors=$(sign automatic "$@")
    case $errors in
        signed*)
            fail "a Release build with a sample team signed with no profile of that team"
            return ;;
    esac
    for id in io.github.valfur03.trome io.github.valfur03.trome.widget; do
        echo "$errors" | grep -qF "No profiles for '$id' were found" || {
            fail "a Release build with TROME_RELEASE_TEAM set did not ask for automatic profiles of io.github.valfur03.trome and its extension; its errors:
$errors
(log: ios/$work/automatic.log)"
            return
        }
    done
}

refused no-team "no team" TROME_RELEASE_TEAM=
refused other-team "no TROME_RELEASE_TEAM but a team in DEVELOPMENT_TEAM" TROME_RELEASE_TEAM= DEVELOPMENT_TEAM="$sample_team"
automatic TROME_RELEASE_TEAM="$sample_team"

[ "$failed" -eq 0 ] || exit 1
echo "release-signing-check: OK (with no TROME_RELEASE_TEAM, Xcode refuses to sign a Release build; with one, it signs automatically)"
