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
printf 'server/.dev.vars*\n!server/.dev.vars.example\nserver/.env*\n' > "$repo/.gitignore"
git -C "$repo" add .gitignore server

check() {
    "$repo/server/scripts/dev-vars-check.sh" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

expect "the example file in git passes" "$(check)" "passes"

for file in .dev.vars .dev.vars.staging .env .env.local; do
    printf 'PRIM_API_KEY=real\n' > "$repo/server/$file"
    expect "$file not in git, and ignored by git, passes" "$(check)" "passes"
    git -C "$repo" add -f "server/$file"
    expect "$file in git fails" "$(check)" "fails"
    expect "the message names server/$file" "$(grep -c "^  server/$file$" "$state/out")" "1"
    git -C "$repo" rm -q --cached "server/$file"
done

mkdir -p "$repo/server/src"
printf 'PRIM_API_KEY=real\n' > "$repo/server/src/.env"
expect "a new file of secrets that git does not ignore fails before the commit" "$(check)" "fails"
expect "the message names server/src/.env" "$(grep -c "^  server/src/.env$" "$state/out")" "1"
rm "$repo/server/src/.env"
expect "with the file gone, it passes again" "$(check)" "passes"

[ "$failures" -eq 0 ]
