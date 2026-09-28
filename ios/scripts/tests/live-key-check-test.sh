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

[ "$failures" -eq 0 ]
