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

mkdir -p "$state/repo/server/scripts" "$state/bin"
cp "$scripts/node-check.sh" "$state/repo/server/scripts/"
echo 24 > "$state/repo/.nvmrc"

fake_node() {
    printf '#!/bin/sh\ncase "$1" in -p) echo %s ;; -v) echo v%s.0.0 ;; esac\n' "$1" "$1" > "$state/bin/node"
    chmod +x "$state/bin/node"
}

check() {
    PATH="$state/bin:/usr/bin:/bin" "$state/repo/server/scripts/node-check.sh" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

fake_node 24
expect "Node 24 passes" "$(check)" "passes"

fake_node 26
expect "a newer Node passes" "$(check)" "passes"

fake_node 20
expect "Node 20 fails" "$(check)" "fails"
expect "the message names the Node that is needed and the active one" \
    "$(grep -c "The server needs Node 24 or later, but the active Node is v20.0.0" "$state/out")" "1"
expect "the message says to run nvm use" "$(grep -c "Run 'nvm use'" "$state/out")" "1"

rm "$state/bin/node"
expect "no Node fails" "$(check)" "fails"
expect "the message says to install Node with nvm" "$(grep -c "nvm install" "$state/out")" "1"

[ "$failures" -eq 0 ]
