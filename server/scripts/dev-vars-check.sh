#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# The files in git, plus the new files that git does not ignore: a commit would take them, so the check before the
# commit and the gate of the merge (on a clean worktree) see the same files.
found=$(git ls-files --cached --others --exclude-standard -- . | grep -E '(^|/)\.(dev\.vars|env)($|\.)' | grep -v '^\.dev\.vars\.example$' || true)
if [ -n "$found" ]; then
    echo "server/ has a file of local secrets that git tracks or does not ignore. Make git ignore it in .gitignore, and if git tracks it, remove it from git with 'git rm --cached <file>':" >&2
    echo "$found" | sed 's/^/  server\//' >&2
    exit 1
fi
