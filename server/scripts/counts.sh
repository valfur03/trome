#!/bin/sh
set -eu

url=${1:-}
if [ -z "$url" ]; then
    echo "Give the address of the server: make server-counts URL=https://ratp-activity-server.<your subdomain>.workers.dev" >&2
    exit 1
fi

printf 'Owner token (it is not shown): ' >&2
stty -echo 2> /dev/null || true
IFS= read -r token || true
stty echo 2> /dev/null || true
printf '\n' >&2
if [ -z "$token" ]; then
    echo "No owner token given." >&2
    exit 1
fi

status=0
printf 'header = "Authorization: Bearer %s"\n' "$token" | curl --silent --show-error --fail-with-body --config - "${url%/}/v1/owner/counts" || status=$?
echo
exit "$status"
