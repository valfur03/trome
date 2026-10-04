#!/bin/sh
set -eu

target=${1:-production}
cd "$(dirname "$0")/.."

case "$target" in
    production)
        branch=$(git rev-parse --abbrev-ref HEAD)
        if [ "$branch" != main ]; then
            echo "make server-deploy deploys main only, and this folder is on '$branch'. Run it in the main folder, on main." >&2
            exit 1
        fi
        if [ -n "$(git status --porcelain -- . ../contracts)" ]; then
            echo "make server-deploy deploys only what is committed, and server/ or contracts/ has changes that are not committed." >&2
            exit 1
        fi
        env_flag=--env=
        secrets_command="make server-secrets"
        ;;
    staging)
        env_flag="--env=staging"
        secrets_command="make server-secrets STAGING=1"
        ;;
    *)
        echo "Unknown target '$target': use production or staging." >&2
        exit 1
        ;;
esac

never_a_file="Never use a secrets file ('wrangler deploy --secrets-file', which wrangler may suggest): the real PRIM key must never be in a file on disk."

missing=$( (./node_modules/.bin/wrangler secret list --format json "$env_flag" 2> /dev/null || true) | node scripts/secrets.ts missing "$target")
if [ -n "$missing" ]; then
    echo "The $target Worker does not have these secrets yet (or it does not exist yet): $(echo $missing)." >&2
    echo "Set the secrets first with '$secrets_command', then run this command again (server/guide/deploy.md)." >&2
    echo "If you are not logged in to Cloudflare, run 'make server-login' first." >&2
    echo "$never_a_file" >&2
    exit 1
fi

if ! ./node_modules/.bin/wrangler deploy "$env_flag" --config wrangler.jsonc; then
    echo "The deploy failed. If wrangler says that required secrets have not been set, run '$secrets_command' first, then deploy again." >&2
    echo "$never_a_file" >&2
    exit 1
fi
