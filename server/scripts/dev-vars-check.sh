#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

tracked=$(git ls-files -- . | grep -E '(^|/)\.(dev\.vars|env)($|\.)' | grep -v '^\.dev\.vars\.example$' || true)
if [ -n "$tracked" ]; then
    echo "git tracks a file of local secrets in server/. Remove it from git with 'git rm --cached <file>' (git ignores it then):" >&2
    echo "$tracked" | sed 's/^/  server\//' >&2
    exit 1
fi
