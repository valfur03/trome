#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
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

check() {
    printf '%s\n' "$1" > "$state/wrangler.jsonc"
    node "$scripts/request-log-check.ts" "$state/wrangler.jsonc" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

expect "the config of the repo passes" "$(node "$scripts/request-log-check.ts" > "$state/out" 2>&1 && echo passes || echo fails)" "passes"

off='"observability": { "enabled": false }'
on='"observability": { "enabled": true }'

config="{ $off, // a comment, as in a JSONC file
  \"env\": { \"staging\": { $off } } }"
expect "logs off at the top and in staging, with a comment, passes" "$(check "$config")" "passes"

config='{ "name": "trome-server" }'
expect "no observability block fails" "$(check "$config")" "fails"
expect "the message names the setting" "$(grep -c '^  observability.enabled must be false' "$state/out")" "1"

config="{ $on }"
expect "Workers Logs on fails" "$(check "$config")" "fails"

config='{ "observability": { "enabled": true, "logs": { "invocation_logs": false } } }'
expect "Workers Logs on with no invocation log fails" "$(check "$config")" "fails"

for part in logs traces issues; do
    config="{ \"observability\": { \"enabled\": false, \"$part\": { \"enabled\": true } } }"
    expect "observability.$part on fails" "$(check "$config")" "fails"
    expect "the message names observability.$part" "$(grep -c "^  observability.$part.enabled must not be true" "$state/out")" "1"
done

for part in logs traces; do
    config="{ \"observability\": { \"enabled\": false, \"$part\": { \"destinations\": [\"otel\"] } } }"
    expect "observability.$part sent to a destination fails" "$(check "$config")" "fails"
    expect "the message names observability.$part.destinations" "$(grep -c "^  observability.$part.destinations must be empty" "$state/out")" "1"
done

config='{ "observability": { "enabled": false, "logs": { "destinations": [] } } }'
expect "an empty list of destinations passes" "$(check "$config")" "passes"

config="{ $off, \"env\": { \"staging\": { $on } } }"
expect "Workers Logs on in staging only fails" "$(check "$config")" "fails"
expect "the message names staging" "$(grep -c '^  env.staging.observability.enabled must be false' "$state/out")" "1"

config="{ $off, \"env\": { \"staging\": {} } }"
expect "no observability block in staging fails" "$(check "$config")" "fails"
expect "the message names staging only" "$(grep -c '^  ' "$state/out")" "1"

config="{ $off, \"logpush\": true }"
expect "Logpush on fails" "$(check "$config")" "fails"
expect "the message names logpush" "$(grep -c '^  logpush must not be true' "$state/out")" "1"

for key in tail_consumers streaming_tail_consumers; do
    config="{ $off, \"$key\": [{ \"service\": \"logs\" }] }"
    expect "a worker in $key fails" "$(check "$config")" "fails"
    expect "the message names $key" "$(grep -c "^  $key must be empty" "$state/out")" "1"
done

config="{ $off, \"tail_consumers\": [] }"
expect "an empty list of tail consumers passes" "$(check "$config")" "passes"

config='{ "observability": '
expect "a config that cannot be read fails" "$(check "$config")" "fails"
expect "the message says it cannot read it" "$(grep -c '^Cannot read' "$state/out")" "1"

[ "$failures" -eq 0 ]
