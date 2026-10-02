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

repo="$state/repo"
mkdir -p "$repo/server/scripts"
git -C "$repo" init -q
cp "$scripts/dev-vars-check.sh" "$repo/server/scripts/"
printf 'PRIM_API_KEY=fake\n' > "$repo/server/.dev.vars.example"
git -C "$repo" add server

check() {
    "$repo/server/scripts/dev-vars-check.sh" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

expect "the example file in git passes" "$(check)" "passes"

for file in .dev.vars .dev.vars.staging .env .env.local; do
    printf 'PRIM_API_KEY=real\n' > "$repo/server/$file"
    expect "$file not in git passes" "$(check)" "passes"
    git -C "$repo" add -f "server/$file"
    expect "$file in git fails" "$(check)" "fails"
    expect "the message names server/$file" "$(grep -c "^  server/$file$" "$state/out")" "1"
    git -C "$repo" rm -q --cached "server/$file"
done

[ "$failures" -eq 0 ]
