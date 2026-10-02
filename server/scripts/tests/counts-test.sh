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

mkdir -p "$state/bin"
cat > "$state/bin/curl" <<FAKE
#!/bin/sh
printf '%s\n' "\$*" > "$state/args"
cat > "$state/config"
echo '{"today":"2026-10-02"}'
FAKE
chmod +x "$state/bin/curl"

counts() {
    rm -f "$state/args" "$state/config"
    printf '%s\n' "$2" | PATH="$state/bin:$PATH" "$scripts/counts.sh" "$1" > "$state/out" 2> "$state/err" && echo "reads" || echo "refuses"
}

expect "it reads the counts with a token" "$(counts https://server.test/ owner-token-123)" "reads"
expect "it prints the answer of the server" "$(cat "$state/out")" '{"today":"2026-10-02"}'
expect "it asks the counts address of the server" "$(grep -c 'https://server.test/v1/owner/counts$' "$state/args")" "1"
expect "it gives the token to curl in a header" "$(cat "$state/config")" 'header = "Authorization: Bearer owner-token-123"'
expect "the token is not in the arguments of curl" "$(grep -c owner-token-123 "$state/args" || true)" "0"
expect "it refuses with no address" "$(counts "" owner-token-123)" "refuses"
expect "it refuses with no token" "$(counts https://server.test "")" "refuses"
expect "it does not call curl with no token" "$(cat "$state/args" 2> /dev/null || echo "not called")" "not called"

[ "$failures" -eq 0 ]
