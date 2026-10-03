#!/bin/sh
set -eu

link=${1:-}
code=${2:-}
cd "$(dirname "$0")/.."

if [ -n "$link" ] && [ -n "$code" ]; then
    echo "Choose one way to log in: LINK=1 (a link to open in the browser of your choice) or CODE=1 (a code to type on a Cloudflare page), not both." >&2
    exit 1
fi

if [ -n "$code" ]; then
    echo "This command opens no browser. Wrangler shows an address and a code."
    echo "Open the address in the browser of your choice (on this Mac or on another device), log in to Cloudflare, type the code, and allow the access."
    echo "Keep this terminal open: it says when you are logged in."
    exec ./node_modules/.bin/wrangler login --device --browser=false
fi

if [ -n "$link" ]; then
    echo "This command opens no browser. Wrangler shows a link."
    echo "Copy the whole link into the browser of your choice on this Mac, log in to Cloudflare, and allow the access."
    echo "Keep this terminal open: it says when you are logged in."
    exec ./node_modules/.bin/wrangler login --browser=false
fi

exec ./node_modules/.bin/wrangler login
