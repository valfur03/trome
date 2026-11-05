#!/bin/sh
# The check of the signed archive of the release workflow (release-archive-number.py), on throwaway archives: it passes
# when the app and its widget have the version of the repo and the build number of the run, fails on any other, and
# never prints another value of an Info.plist (the store build holds the server and its token there).
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
state=$(mktemp -d)
archive="$state/TROME.xcarchive"
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

# info <bundle folder> <version> <build>: an Info.plist with these numbers, in binary as Xcode writes it, and a token.
info() {
    mkdir -p "$1"
    python3 -c 'import plistlib, sys
plistlib.dump({"CFBundleShortVersionString": sys.argv[2], "CFBundleVersion": sys.argv[3],
               "TrainServerAppToken": "secret-token-of-the-test"}, open(sys.argv[1], "wb"), fmt=plistlib.FMT_BINARY)' \
        "$1/Info.plist" "$2" "$3"
}

make_archive() {
    rm -rf "$archive"
    info "$archive/Products/Applications/TROME.app" "$1" "$2"
    info "$archive/Products/Applications/TROME.app/PlugIns/TROMEWidget.appex" "$3" "$4"
}

check() {
    status=0
    "$ios/scripts/release-archive-number.py" "$archive" 1.0.0 6 > "$state/out" 2>&1 || status=$?
    echo "$status: $(cat "$state/out")"
}

make_archive 1.0.0 6 1.0.0 6
expect "the app and its widget of the version and the build of the run pass" "$(check)" \
    "0: release-archive-number: OK (TROME.app, TROMEWidget.appex: version 1.0.0, build 6)"

make_archive 1.0.0 5 1.0.0 5
expect "an archive with the number of Base.xcconfig fails" "$(check)" \
    "1: release-archive-number: FAILED: TROME.app has CFBundleVersion '5', not '6'
release-archive-number: FAILED: TROMEWidget.appex has CFBundleVersion '5', not '6'"

make_archive 1.0.1 6 1.0.0 6
expect "an app of another version fails" "$(check)" \
    "1: release-archive-number: FAILED: TROME.app has CFBundleShortVersionString '1.0.1', not '1.0.0'"

make_archive 1.0.0 6 1.0.0 7
expect "a widget of another build fails" "$(check)" \
    "1: release-archive-number: FAILED: TROMEWidget.appex has CFBundleVersion '7', not '6'"

rm -rf "$archive"
mkdir -p "$archive/Products/Applications"
expect "an archive with no app fails" "$(check)" \
    "1: release-archive-number: FAILED: the archive has 0 apps in Products/Applications, not one"

make_archive 1.0.1 5 1.0.1 5
check > /dev/null
expect "no other value of the Info.plist is printed" "$(grep -c "secret-token" "$state/out" || true)" 0

if [ "$failures" -ne 0 ]; then
    echo "release-archive-number-test: $failures FAILED"
    exit 1
fi
echo "release-archive-number-test: OK"
