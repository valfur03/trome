#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
guide="$scripts/../../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx"
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

# check <wrangler.jsonc text> [guide path]
check() {
    printf '%s\n' "$1" > "$state/wrangler.jsonc"
    node "$scripts/worker-address-check.ts" "$state/wrangler.jsonc" "${2:-$guide}" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

# table <status of build 1> <status of build 2>
table() {
    cat > "$state/guide.mdx" <<EOF
## The builds that riders may hold

| Version (build) | Uploaded | Commit | Where, and until when | Status |
|---|---|---|---|---|
| 1.0.0 (1) | 11 October 2026 | \`ca169af\` | TestFlight | $1 |
| 1.0.0 (2) | 11 October 2026 | \`9d83a8d\` | TestFlight | $2 |

Builds 1 and 2 were tagged after their upload.

## Fix this page
EOF
}

expect "the config of the repo passes" "$(node "$scripts/worker-address-check.ts" > "$state/out" 2>&1 && echo passes || echo fails)" "passes"

kept='"name": "trome-server", "workers_dev": true'

config="{ $kept, // a comment, as in a JSONC file
  \"env\": { \"staging\": { \"name\": \"another-name\", \"workers_dev\": false } } }"
expect "the address kept, with a comment and another staging, passes" "$(check "$config")" "passes"

config='{ "name": "trome-api", "workers_dev": true }'
expect "a new name fails, with the guide of the repo" "$(check "$config")" "fails"
expect "the message names the setting" "$(grep -c '^  name must stay "trome-server"' "$state/out")" "1"
expect "the message names a build in the field" "$(grep -c '1.0.0 (1)' "$state/out")" "1"
expect "the message names the guide section" "$(grep -c "section 'Keep the address of the server'" "$state/out")" "1"

config='{ "workers_dev": true }'
expect "no name fails" "$(check "$config")" "fails"

config='{ "name": "trome-server", "workers_dev": false }'
expect "workers.dev off fails" "$(check "$config")" "fails"
expect "the message names workers_dev" "$(grep -c '^  workers_dev must stay true' "$state/out")" "1"

config='{ "name": "trome-server" }'
expect "no workers_dev fails" "$(check "$config")" "fails"

config='{ "name": "trome-api", "workers_dev": false }'
check "$config" > /dev/null
expect "both changes are named" "$(grep -c '^  ' "$state/out")" "2"

table '**Retired on `9 January 2027`: `its TestFlight date has passed`**' 'In the field'
expect "one build still in the field fails" "$(check "$config" "$state/guide.mdx")" "fails"
expect "the message names that build only" "$(grep -c 'builds in the field: 1.0.0 (2))' "$state/out")" "1"

table '**Retired on `9 January 2027`: `its TestFlight date has passed`**' 'Retired on `9 January 2027`: `its TestFlight date has passed`'
expect "every build retired passes" "$(check "$config" "$state/guide.mdx")" "passes"
expect "it says why it allows the change" "$(grep -c 'allowed, since the release guide lists no build in the field' "$state/out")" "1"

printf '# Release\n\nNo table here.\n' > "$state/guide.mdx"
expect "a guide with no table of builds fails" "$(check "$config" "$state/guide.mdx")" "fails"
expect "the message says the table cannot be read" "$(grep -c 'cannot be read' "$state/out")" "1"

expect "a missing guide fails" "$(check "$config" "$state/no-such-guide.mdx")" "fails"

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All worker address checks passed"
