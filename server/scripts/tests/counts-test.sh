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
if [ -f "$state/refused" ]; then
    echo '{"error":"unauthorized"}'
    exit 22
fi
echo '{"today":"2026-10-02","days":[{"day":"2026-10-02","appCalls":3,"primCalls":1,"outAnswers":0,"errors":0,"hours":[{"parisHour":"08:00","appCalls":3}]}]}'
FAKE
chmod +x "$state/bin/curl"

counts() {
    rm -f "$state/args" "$state/config"
    printf '%s\n' "$2" | PATH="$state/bin:$PATH" "$scripts/counts.sh" "$1" ${3:-} > "$state/out" 2> "$state/err" && echo "reads" || echo "refuses"
}

expect "it reads the counts with a token" "$(counts https://server.test/ owner-token-123)" "reads"
expect "it prints a table, today first" "$(sed -n 2p "$state/out")" "Today (so far)          3           1            0       0  08:00 (3 calls)"
expect "it says where the table starts" "$(tail -n 1 "$state/out")" "No total before Fri 2026-10-02, so the table starts there."
expect "it prints the whole report with full" "$(counts https://server.test/ owner-token-123 full; grep -c '"parisHour": "08:00"' "$state/out")" "reads
1"
touch "$state/refused"
expect "it fails when the server refuses" "$(counts https://server.test/ owner-token-123)" "refuses"
expect "it prints the refusal of the server" "$(cat "$state/out")" '{"error":"unauthorized"}'
rm "$state/refused"
expect "it asks the counts address of the server" "$(grep -c 'https://server.test/v1/owner/counts$' "$state/args")" "1"
expect "it gives the token to curl in a header" "$(cat "$state/config")" 'header = "Authorization: Bearer owner-token-123"'
expect "the token is not in the arguments of curl" "$(grep -c owner-token-123 "$state/args" || true)" "0"
counts https://server.test/ owner-token-123 > /dev/null
expect "the token is never printed" "$(cat "$state/out" "$state/err" | grep -c owner-token-123 || true)" "0"
expect "it refuses with no address" "$(counts "" owner-token-123)" "refuses"
expect "it refuses with no token" "$(counts https://server.test "")" "refuses"
expect "it does not call curl with no token" "$(cat "$state/args" 2> /dev/null || echo "not called")" "not called"

[ "$failures" -eq 0 ]
