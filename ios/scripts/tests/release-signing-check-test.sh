#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-signing-check.sh"
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

# A fake xcodebuild that signs like the project: manual with no TROME_RELEASE_TEAM, automatic with one.
# FAKE_STYLE forces a style, as a project change could; FAKE_SIGNS makes every build sign.
cat > "$state/xcodebuild" << 'EOF'
#!/bin/sh
team=
for argument in "$@"; do
    case $argument in
        TROME_RELEASE_TEAM=*) team=${argument#*=} ;;
        -allowProvisioningUpdates) echo "$argument" >> "$FAKE_CALLS" ;;
    esac
done
style=${FAKE_STYLE:-$([ -n "$team" ] && echo Automatic || echo Manual)}
[ "${FAKE_SIGNS:-no}" = no ] || exit 0
for pair in TROME=io.github.valfur03.trome TROMEWidget=io.github.valfur03.trome.widget; do
    target=${pair%%=*}
    id=${pair#*=}
    if [ "$style" = Manual ]; then
        echo "TROME.xcodeproj: error: \"$target\" requires a provisioning profile. Select a provisioning profile in the Signing & Capabilities editor."
    elif [ -z "$team" ]; then
        echo "TROME.xcodeproj: error: Signing for \"$target\" requires a development team."
    else
        echo "TROME.xcodeproj: error: No profiles for '$id' were found: Automatic signing is disabled and unable to generate a profile."
    fi
done
exit 65
EOF
chmod +x "$state/xcodebuild"

run() {
    env "$@" FAKE_CALLS="$state/calls" XCODEBUILD="$state/xcodebuild" \
        "$script" TROME.xcodeproj "$state/work" > "$state/out" 2>&1 && echo passes || echo fails
}

expect "the project as it is passes" "$(run)" passes
expect "a Release build that signs with no team fails the check" "$(run FAKE_SIGNS=yes)" fails
expect "a Release build that signs automatically with no team fails the check" "$(run FAKE_STYLE=Automatic)" fails
expect "a Release build that ignores TROME_RELEASE_TEAM fails the check" "$(run FAKE_STYLE=Manual)" fails
expect "a failure prints the errors of the build" "$(grep -c 'requires a provisioning profile' "$state/out")" 2
expect "the check never lets Xcode talk to Apple" "$(cat "$state/calls" 2> /dev/null | wc -l | tr -d ' ')" 0

[ "$failures" -eq 0 ] || exit 1
echo "release-signing-check-test: OK"
