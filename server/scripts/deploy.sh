#!/bin/sh
set -eu

# deploy.sh <production|staging> [<commit>]
# With no commit: the deploy of a person, from this folder (make server-deploy-staging, make server-deploy).
# With a commit: the deploy of the GitHub workflow of the server (.github/workflows/server-deploy.yml), on that commit of main.
target=${1:-production}
commit=${2:-}
cd "$(dirname "$0")/.."

# What the Worker is built from: server/, contracts/, and the station list of the app, which the server bundles.
server_files=". ../contracts ../ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json"

case "$target" in
    production)
        branch=$(git rev-parse --abbrev-ref HEAD)
        if [ "$branch" != main ]; then
            echo "make server-deploy deploys main only, and this folder is on '$branch'. Run it in the main folder, on main." >&2
            exit 1
        fi
        # shellcheck disable=SC2086 # the paths of the list have no space
        if [ -n "$(git status --porcelain -- $server_files)" ]; then
            echo "make server-deploy deploys only what is committed, and server/, contracts/ or the station list of the app has changes that are not committed." >&2
            exit 1
        fi
        env_flag=--env=
        secrets_command="make server-secrets"
        secret_command="make server-secret NAME=<name>"
        deploy_command="make server-deploy"
        ;;
    staging)
        env_flag="--env=staging"
        secrets_command="make server-secrets STAGING=1"
        secret_command="make server-secret NAME=<name> STAGING=1"
        deploy_command="make server-deploy-staging"
        ;;
    *)
        echo "Unknown target '$target': use production or staging." >&2
        exit 1
        ;;
esac

never_a_file="Never use a secrets file ('wrangler deploy --secrets-file', which wrangler may suggest): the real PRIM key must never be in a file on disk."
rerun="Then open this run on GitHub and press 'Re-run failed jobs'."

if [ -n "$commit" ]; then
    # A run deploys its own commit, and never older server code over newer: when main has moved on and server/,
    # contracts/ or the station list changed since this commit, the run of that newer commit deploys it.
    head=$(git rev-parse HEAD)
    if [ "$head" != "$commit" ]; then
        echo "This folder is at $head, not at $commit: nothing was deployed." >&2
        exit 1
    fi
    if ! git fetch --quiet --depth=1 origin refs/heads/main; then
        echo "Cannot read the tip of main from origin: nothing was deployed. $rerun" >&2
        exit 1
    fi
    tip=$(git rev-parse FETCH_HEAD)
    # shellcheck disable=SC2086
    if [ "$tip" != "$commit" ] && ! git diff --quiet "$commit" "$tip" -- $server_files; then
        echo "This run deploys $commit, but main is now at $tip, which changes server/, contracts/ or the station list: the run of that newer commit deploys it. Nothing was deployed." >&2
        exit 1
    fi
fi

if listed=$(./node_modules/.bin/wrangler secret list --format json "$env_flag" 2> /dev/null); then
    missing=$(printf '%s' "$listed" | node scripts/secrets.ts missing "$target")
else
    listed=
    missing=$(printf '' | node scripts/secrets.ts missing "$target")
fi
# In a run, a list that wrangler cannot read stops nothing: wrangler deploy checks secrets.required itself, and names each
# missing secret.
if [ -n "$missing" ] && { [ -z "$commit" ] || [ -n "$listed" ]; }; then
    echo "The $target Worker does not have these secrets yet (or it does not exist yet): $(echo $missing)." >&2
    if [ -n "$commit" ]; then
        echo "Set each one from your computer with '$secret_command' (server/guide/deploy.md). $rerun" >&2
    else
        echo "Set the secrets first with '$secrets_command', then run this command again (server/guide/deploy.md)." >&2
        echo "If you are not logged in to Cloudflare, run 'make server-login' first." >&2
    fi
    echo "$never_a_file" >&2
    exit 1
fi
if [ -n "$commit" ] && [ -z "$listed" ]; then
    echo "wrangler could not list the secrets of the $target Worker: the deploy checks them itself." >&2
fi

if [ -n "$commit" ]; then
    # In a run, wrangler answers its own questions 'yes', with no person. With --strict, it stops instead of overriding
    # the settings that someone changed in the Cloudflare dashboard.
    set -- --strict --tag "$commit" --message "main $commit"
else
    set --
fi

if ! ./node_modules/.bin/wrangler deploy "$env_flag" --config wrangler.jsonc "$@"; then
    if [ -n "$commit" ]; then
        echo "The deploy failed. If wrangler says that required secrets have not been set, set each one from your computer with '$secret_command'. $rerun" >&2
        # After a change in the dashboard, wrangler first reads the Worker's settings there, and a token limited to one
        # Worker cannot read all of them (custom domains have no per-Worker role): the run stops before any upload.
        echo "If wrangler aborts because of conflicts, or cannot fetch the metadata from the dashboard, the Worker was changed outside this repo (in the Cloudflare dashboard), even if undone since, and a run never overrides that: put the change in server/wrangler.jsonc on main or undo it, then deploy main once from your computer with '$deploy_command', which shows the difference and asks. $rerun" >&2
    else
        echo "The deploy failed. If wrangler says that required secrets have not been set, run '$secrets_command' first, then deploy again." >&2
    fi
    echo "$never_a_file" >&2
    exit 1
fi
