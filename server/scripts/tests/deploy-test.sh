#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
server=$(cd "$scripts/.." && pwd)
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

contains() {
    grep -qF -- "$2" "$1" && echo yes || echo no
}

repo="$state/repo"
cloudflare="$state/cloudflare"
mkdir -p "$repo/server/scripts" "$repo/server/node_modules/.bin" "$repo/contracts" "$cloudflare"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
printf 'node_modules/\n' > "$repo/.gitignore"
cp "$scripts/deploy.sh" "$scripts/put-secrets.sh" "$scripts/secrets.ts" "$repo/server/scripts/"
cp "$server/wrangler.jsonc" "$repo/server/"
ln -s "$server/node_modules/typescript" "$repo/server/node_modules/typescript"
cat > "$repo/server/node_modules/.bin/wrangler" << FAKE
#!/bin/sh
cloudflare="$cloudflare"
FAKE
cat >> "$repo/server/node_modules/.bin/wrangler" << 'FAKE'
worker=production
for arg in "$@"; do
    case "$arg" in --env=staging) worker=staging ;; esac
done
mkdir -p "$cloudflare/$worker"
case "$1 $2" in
    "secret list")
        [ -f "$cloudflare/$worker/exists" ] || { echo "Worker not found" >&2; exit 1; }
        printf '['
        separator=
        for secret in "$cloudflare/$worker"/secret-*; do
            [ -f "$secret" ] || continue
            printf '%s{"name": "%s", "type": "secret_text"}' "$separator" "${secret##*/secret-}"
            separator=,
        done
        printf ']\n'
        ;;
    "secret put")
        read -r value
        touch "$cloudflare/$worker/exists"
        echo "$value" > "$cloudflare/$worker/secret-$3"
        ;;
    "deploy --env="* | "deploy --env=staging")
        if [ ! -f "$cloudflare/$worker/exists" ]; then
            echo "The following required secrets have not been set. To deploy a new Worker with secrets, supply them via a secrets file: wrangler deploy --secrets-file <path-to-file>"
            exit 1
        fi
        [ ! -f "$cloudflare/fail-deploy" ] || exit 1
        echo "$*" > "$cloudflare/$worker/deployed"
        ;;
    *)
        echo "unexpected wrangler $*" >&2
        exit 2
        ;;
esac
FAKE
chmod +x "$repo/server/node_modules/.bin/wrangler"
echo '{}' > "$repo/contracts/a.json"
stations=ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json
mkdir -p "$repo/${stations%/*}"
echo '[]' > "$repo/$stations"
git -C "$repo" add -A
git -C "$repo" commit -q -m init

deploy() {
    "$repo/server/scripts/deploy.sh" "$@" > "$state/out" 2>&1 && echo "deploys" || echo "refuses"
}

deployed() {
    cat "$cloudflare/$1/deployed" 2> /dev/null || echo "not deployed"
}

put_secrets() {
    printf '%s\n' "$@" | "$repo/server/scripts/put-secrets.sh" "$target" > "$state/put" 2>&1 && echo "set" || echo "failed"
}

target=staging
expect "staging: a first deploy before the secrets refuses" "$(deploy staging)" "refuses"
expect "staging: it does not call wrangler deploy then" "$(deployed staging)" "not deployed"
expect "staging: the message names the missing secrets" "$(contains "$state/out" "PRIM_API_KEY APP_TOKEN OWNER_TOKEN.")" "yes"
expect "staging: the message says to set them first with make server-secrets STAGING=1" "$(contains "$state/out" "Set the secrets first with 'make server-secrets STAGING=1'")" "yes"
expect "staging: the message warns never to use a secrets file" "$(contains "$state/out" "Never use a secrets file")" "yes"

expect "staging: make server-secrets sets each secret in turn" "$(put_secrets prim-value token-value owner-value)" "set"
expect "staging: it set the PRIM key" "$(cat "$cloudflare/staging/secret-PRIM_API_KEY")" "prim-value"
expect "staging: it set the app token" "$(cat "$cloudflare/staging/secret-APP_TOKEN")" "token-value"
expect "staging: it set the owner token" "$(cat "$cloudflare/staging/secret-OWNER_TOKEN")" "owner-value"
expect "staging: it says to answer yes to the new Worker question" "$(contains "$state/put" "Answer y (yes)")" "yes"
expect "staging: the deploy after the secrets succeeds (the order of server/guide/deploy.md)" "$(deploy staging)" "deploys"
expect "staging: it deploys the staging environment of server/wrangler.jsonc, the file that make server-check checks" "$(deployed staging)" "deploy --env=staging --config wrangler.jsonc"
expect "staging: it never touches production" "$(deployed production)" "not deployed"

target=production
expect "production: the staging secrets do not count for production" "$(deploy production)" "refuses"
expect "production: the message says make server-secrets with no STAGING" "$(contains "$state/out" "Set the secrets first with 'make server-secrets',")" "yes"
printf 'prim-value\n' | "$repo/server/node_modules/.bin/wrangler" secret put PRIM_API_KEY --env= 
expect "production: one secret only still refuses" "$(deploy production)" "refuses"
expect "production: the message names only the missing ones" "$(contains "$state/out" "yet (or it does not exist yet): APP_TOKEN OWNER_TOKEN.")" "yes"
expect "production: make server-secrets, then the deploy (the order of server/guide/deploy.md)" "$(put_secrets prim-value other-token other-owner)$(deploy production)" "setdeploys"
expect "production: it deploys the top-level environment" "$(deployed production)" "deploy --env= --config wrangler.jsonc"

touch "$cloudflare/fail-deploy"
expect "a failed deploy refuses" "$(deploy staging)" "refuses"
expect "after a failed deploy, the message says to set the secrets first" "$(contains "$state/out" "run 'make server-secrets STAGING=1' first")" "yes"
expect "after a failed deploy, the message warns never to use a secrets file" "$(contains "$state/out" "Never use a secrets file")" "yes"
rm "$cloudflare/fail-deploy"

rm "$cloudflare/production/deployed"
echo change > "$repo/contracts/a.json"
expect "production refuses changes that are not committed" "$(deploy production)" "refuses"
expect "it does not deploy then" "$(deployed production)" "not deployed"
git -C "$repo" checkout -q -- contracts
echo '[1]' > "$repo/$stations"
expect "production refuses a change of the station list that is not committed (the server bundles it)" "$(deploy production)" "refuses"
expect "the message names the station list" "$(contains "$state/out" "server/, contracts/ or the station list of the app has changes that are not committed")" "yes"
git -C "$repo" checkout -q -- "$stations"

git -C "$repo" switch -q -c task/1
expect "production refuses another branch" "$(deploy production)" "refuses"
expect "the message names the branch" "$(contains "$state/out" "on 'task/1'")" "yes"
expect "it does not deploy then either" "$(deployed production)" "not deployed"

expect "an unknown target refuses" "$(deploy prod)" "refuses"

# The run of the GitHub workflow: deploy.sh <target> <commit>.
git -C "$repo" switch -q main
git init -q --bare -b main "$state/origin.git"
git -C "$repo" remote add origin "$state/origin.git"
git -C "$repo" push -q origin main
commit=$(git -C "$repo" rev-parse HEAD)
rm -f "$cloudflare/staging/deployed"

expect "run: the commit at the tip of main deploys" "$(deploy staging "$commit")" "deploys"
expect "run: the deploy carries the commit as its tag and message, with --strict" "$(deployed staging)" "deploy --env=staging --config wrangler.jsonc --strict --tag $commit --message main $commit"

other=$(mktemp -d)
git clone -q "$state/origin.git" "$other/clone"
git -C "$other/clone" -c user.email=test@example.com -c user.name=test commit -q --allow-empty -m "a change outside server/"
git -C "$other/clone" push -q origin main
rm "$cloudflare/staging/deployed"
expect "run: main has moved on with no change of server/ or contracts/: the commit still deploys" "$(deploy staging "$commit")" "deploys"

echo '[1]' > "$other/clone/$stations"
git -C "$other/clone" -c user.email=test@example.com -c user.name=test commit -q -am "a change of the station list"
git -C "$other/clone" push -q origin main
rm "$cloudflare/staging/deployed"
expect "run: main has moved on with a change of the station list, which the server bundles: the old commit refuses" "$(deploy staging "$commit")" "refuses"
expect "run: it deploys nothing then (station list)" "$(deployed staging)" "not deployed"
touch "$cloudflare/staging/deployed"

echo '{"b":1}' > "$other/clone/contracts/a.json"
git -C "$other/clone" -c user.email=test@example.com -c user.name=test commit -q -am "a change of contracts/"
git -C "$other/clone" push -q origin main
tip=$(git -C "$other/clone" rev-parse HEAD)
rm "$cloudflare/staging/deployed"
expect "run: main has moved on with a change of contracts/: the old commit refuses" "$(deploy staging "$commit")" "refuses"
expect "run: it deploys nothing then" "$(deployed staging)" "not deployed"
expect "run: the message names both commits" "$(contains "$state/out" "This run deploys $commit, but main is now at $tip")" "yes"

git -C "$repo" fetch -q origin main
git -C "$repo" reset -q --hard FETCH_HEAD
expect "run: a commit that is not the one of this folder refuses" "$(deploy staging "$commit")" "refuses"
expect "run: the message says that nothing was deployed" "$(contains "$state/out" "not at $commit: nothing was deployed")" "yes"
rm -rf "$other"

rm "$cloudflare/staging/secret-OWNER_TOKEN"
expect "run: a missing secret refuses" "$(deploy staging "$tip")" "refuses"
expect "run: it deploys nothing then" "$(deployed staging)" "not deployed"
expect "run: the message names the missing secret" "$(contains "$state/out" "yet (or it does not exist yet): OWNER_TOKEN.")" "yes"
expect "run: the message says how to set it, then to re-run" "$(contains "$state/out" "Set each one from your computer with 'make server-secret NAME=<name> STAGING=1' (server/guide/deploy.md). Then open this run on GitHub and press 'Re-run failed jobs'.")" "yes"
expect "run: the message warns never to use a secrets file" "$(contains "$state/out" "Never use a secrets file")" "yes"
printf 'owner-value\n' | "$repo/server/node_modules/.bin/wrangler" secret put OWNER_TOKEN --env=staging
expect "run: once the secret is set, the re-run deploys" "$(deploy staging "$tip")" "deploys"

rm -rf "$cloudflare/staging"
expect "run: when wrangler cannot list the secrets, the deploy checks them itself, and refuses" "$(deploy staging "$tip")" "refuses"
expect "run: it says that it could not list them" "$(contains "$state/out" "wrangler could not list the secrets of the staging Worker")" "yes"
expect "run: it says how to set a secret, then to re-run" "$(contains "$state/out" "set each one from your computer with 'make server-secret NAME=<name> STAGING=1'. Then open this run on GitHub and press 'Re-run failed jobs'.")" "yes"

[ "$failures" -eq 0 ]
