#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../live-key-check.sh"
state=$(mktemp -d)
cache="$state/cache"
key="LEAKCHECKTEST$$"
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

found() {
    "$script" files-with-key "$cache" "$state/start" "$key" | sed "s|^$cache/||" | sort | tr '\n' ' '
}

mkdir -p "$cache/modules/deep" "$state/outside"
printf 'old %s\n' "$key" > "$cache/modules/before-start"
printf 'moved %s\n' "$key" > "$state/outside/moved"
touch -t 202001010000 "$state/outside/moved"
sleep 1
touch "$state/start"

expect "a file written before the start is not searched" "$(found)" ""

printf 'module\n' > "$cache/modules/clean"
expect "a new file without the key is not reported" "$(found)" ""

printf 'module %s\n' "$key" > "$cache/modules/deep/written"
expect "a new file with the key is reported, in any subfolder" "$(found)" "modules/deep/written "

printf 'module %s\n' "$key" > "$cache/modules/backdated"
touch -t 202001010000 "$cache/modules/backdated"
mv "$state/outside/moved" "$cache/modules/moved"
expect "a file with the key is reported when its date is set back or when it is moved in" \
    "$(found)" "modules/backdated modules/deep/written modules/moved "

ln -s "$cache" "$state/cache-link"
expect "a cache folder that is a symbolic link is searched" \
    "$("$script" files-with-key "$state/cache-link" "$state/start" "$key" | sed "s|^$state/cache-link/||" | sort | tr '\n' ' ')" \
    "modules/backdated modules/deep/written modules/moved "

expect "a missing cache folder reports nothing" \
    "$("$script" files-with-key "$state/missing" "$state/start" "$key")" ""

mkdir -p "$state/unreadable-cache"
printf 'module %s\n' "$key" > "$state/unreadable-cache/locked"
chmod 000 "$state/unreadable-cache/locked"
expect "a search that cannot read a new file fails" \
    "$("$script" files-with-key "$state/unreadable-cache" "$state/start" "$key" 2> /dev/null && echo passed || echo failed)" "failed"

expect "a search with no start file fails" \
    "$("$script" files-with-key "$cache" "$state/missing-start" "$key" 2> /dev/null && echo passed || echo failed)" "failed"

build="$state/build"
logs="$build/DerivedData/Logs/Build"
bundle="$build/DerivedData/Logs/Test/Run.xcresult"

logs_found() {
    "$script" logs-with-key "$build" "$state/start" "$key" | sed "s|^$build/||" | sort | tr '\n' ' '
}

logs_search() {
    "$script" logs-with-key "$1" "$2" "$key" > /dev/null 2>&1 && echo passed || echo failed
}

expect "a missing build folder reports nothing" "$(logs_search "$state/missing-build" "$state/start")" "passed"

mkdir -p "$build"
expect "a build folder with no logs yet reports nothing" "$(logs_search "$build" "$state/start")" "passed"

mkdir -p "$logs" "$bundle/Data"
printf 'build log\n' | gzip > "$logs/clean.xcactivitylog"
printf 'result\n' > "$bundle/Data/clean"
expect "new build logs and result bundles without the key are not reported" "$(logs_found)" ""

printf 'build log %s\n' "$key" | gzip > "$logs/leak.xcactivitylog"
printf 'result %s\n' "$key" > "$bundle/Data/leak"
expect "a new build log and a new result bundle with the key are reported" \
    "$(logs_found)" "DerivedData/Logs/Build/leak.xcactivitylog DerivedData/Logs/Test/Run.xcresult/Data/leak "

rm "$logs/leak.xcactivitylog" "$bundle/Data/leak"
printf 'not gzip %s\n' "$key" > "$logs/broken.xcactivitylog"
expect "a build log that cannot be decompressed fails the search" "$(logs_search "$build" "$state/start")" "failed"
rm "$logs/broken.xcactivitylog"

printf 'build log\n' | gzip > "$logs/locked.xcactivitylog"
chmod 000 "$logs/locked.xcactivitylog"
expect "a build log that cannot be read fails the search" "$(logs_search "$build" "$state/start")" "failed"
rm -f "$logs/locked.xcactivitylog"

printf 'result\n' > "$bundle/Data/locked"
chmod 000 "$bundle/Data/locked"
expect "a result bundle file that cannot be read fails the search" "$(logs_search "$build" "$state/start")" "failed"
rm -f "$bundle/Data/locked"

mkdir -p "$logs/locked-folder"
chmod 000 "$logs/locked-folder"
expect "a logs folder that cannot be read fails the search" "$(logs_search "$build" "$state/start")" "failed"
chmod 755 "$logs/locked-folder"

expect "the search passes again once everything can be read" "$(logs_search "$build" "$state/start")" "passed"

expect "a log search with no start file fails" "$(logs_search "$build" "$state/missing-start")" "failed"

[ "$failures" -eq 0 ]
