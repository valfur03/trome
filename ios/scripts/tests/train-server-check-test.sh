#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../train-server-check.sh"
token="SERVERTOKENTEST$$"
failures=0

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

run() {
    env -i PATH="$PATH" CONFIGURATION=Release "$@" "$script" 2>&1 && echo "status 0" || echo "status $?"
}

outcome() {
    run "$@" | tail -1
}

errors() {
    run "$@" | grep '^error: ' | grep -F 'ios/Config/Server.xcconfig' | grep -cF 'ios/Config/Server.example.xcconfig' || true
}

expect "a build that does not require the server passes with no settings" \
    "$(run)" "status 0"
expect "a Debug build passes with no settings" \
    "$(run RATP_REQUIRE_TRAIN_SERVER=NO RATP_APP_TRAIN_SERVER_HOST= RATP_APP_TRAIN_SERVER_APP_TOKEN=)" "status 0"
expect "a Release build with a host and a token passes, and prints nothing" \
    "$(run RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST=trome.example.workers.dev RATP_APP_TRAIN_SERVER_APP_TOKEN="$token")" "status 0"

expect "a Release build with no settings fails" \
    "$(outcome RATP_REQUIRE_TRAIN_SERVER=YES)" "status 1"
expect "a Release build with no settings names the file and its example, once for each setting" \
    "$(errors RATP_REQUIRE_TRAIN_SERVER=YES)" "2"
expect "a Release build with empty settings fails" \
    "$(outcome RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST= RATP_APP_TRAIN_SERVER_APP_TOKEN=)" "status 1"
expect "a Release build with no host fails" \
    "$(outcome RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_APP_TOKEN="$token")" "status 1"
expect "a Release build with no host names the file and its example" \
    "$(errors RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_APP_TOKEN="$token")" "1"
expect "a Release build with no app token fails" \
    "$(outcome RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST=trome.example.workers.dev)" "status 1"
expect "a Release build with no app token names the file and its example" \
    "$(errors RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST=trome.example.workers.dev)" "1"

for host in "https:" "trome.example.workers.dev/v1" "trome.example.workers.dev:8787" "trome example" ".workers.dev"; do
    expect "a Release build with the host '$host' fails" \
        "$(outcome RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST="$host" RATP_APP_TRAIN_SERVER_APP_TOKEN="$token")" "status 1"
done

expect "a failed Release build never prints the app token" \
    "$(run RATP_REQUIRE_TRAIN_SERVER=YES RATP_APP_TRAIN_SERVER_HOST="https:" RATP_APP_TRAIN_SERVER_APP_TOKEN="$token" | grep -c "$token" || true)" "0"

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo "train-server-check-test: OK"
