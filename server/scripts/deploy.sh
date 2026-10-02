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
        exec ./node_modules/.bin/wrangler deploy --env=""
        ;;
    staging)
        exec ./node_modules/.bin/wrangler deploy --env staging
        ;;
    *)
        echo "Unknown target '$target': use production or staging." >&2
        exit 1
        ;;
esac
