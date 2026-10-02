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
mkdir -p "$repo/server/scripts" "$repo/server/node_modules/.bin" "$repo/contracts"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
printf 'node_modules/\n' > "$repo/.gitignore"
cp "$scripts/deploy.sh" "$repo/server/scripts/"
printf '#!/bin/sh\necho "wrangler $*" > "%s/wrangler-args"\n' "$state" > "$repo/server/node_modules/.bin/wrangler"
chmod +x "$repo/server/node_modules/.bin/wrangler"
echo '{}' > "$repo/contracts/a.json"
git -C "$repo" add -A
git -C "$repo" commit -q -m init

deploy() {
    rm -f "$state/wrangler-args"
    "$repo/server/scripts/deploy.sh" "$@" > "$state/out" 2>&1 && echo "deploys" || echo "refuses"
}

called() {
    cat "$state/wrangler-args" 2> /dev/null || echo "not called"
}

expect "production deploys a clean main" "$(deploy production)" "deploys"
expect "production runs wrangler deploy on the top-level environment" "$(called)" "wrangler deploy --env="

echo change > "$repo/contracts/a.json"
expect "production refuses changes that are not committed" "$(deploy production)" "refuses"
expect "it does not call wrangler then" "$(called)" "not called"
git -C "$repo" checkout -q -- contracts

git -C "$repo" switch -q -c task/1
expect "production refuses another branch" "$(deploy production)" "refuses"
expect "the message names the branch" "$(grep -c "on 'task/1'" "$state/out")" "1"
expect "it does not call wrangler then either" "$(called)" "not called"

expect "staging deploys any branch" "$(deploy staging)" "deploys"
expect "staging runs wrangler deploy --env staging" "$(called)" "wrangler deploy --env staging"

expect "an unknown target refuses" "$(deploy prod)" "refuses"

[ "$failures" -eq 0 ]
