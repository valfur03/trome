#!/bin/sh
set -eu

target=${1:-production}
cd "$(dirname "$0")/.."

case "$target" in
    production) env_flag=--env= ;;
    staging) env_flag="--env=staging" ;;
    *)
        echo "Unknown target '$target': use production or staging." >&2
        exit 1
        ;;
esac

names=$(node scripts/secrets.ts required "$target")
echo "This sets the secrets of the $target Worker, one after the other: $(echo $names)."
echo "For each one, wrangler asks 'Enter a secret value:'. Paste the value and press Return (the value does not show)."
echo "The first time, wrangler then asks 'Do you want to create a new Worker with that name and add secrets to it?'. Answer y (yes): it creates an empty Worker that holds the secrets until the first deploy."
echo "Never put a real secret in a file, even if wrangler suggests a secrets file."
for name in $names; do
    echo
    echo "Secret $name:"
    ./node_modules/.bin/wrangler secret put "$name" "$env_flag"
done
