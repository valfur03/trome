#!/bin/sh
# Writes the commit of the build in the Info.plist of the app (TROMECommit), so that the Wake log of a walk says
# which build was walked: its short hash, with -dirty when the files of the app (this folder) had changes that were
# not committed. With no git (a folder with no history), it writes no commit, and the Wake log says "commit unknown".
# Xcode runs it at each build and archive; `make release-archive-check` refuses a build for a walk with no commit.
set -eu

plist="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
source_root="${SRCROOT:?}"

if hash=$(git -C "$source_root" rev-parse --short=7 HEAD 2>/dev/null); then
    if [ -n "$(git -C "$source_root" status --porcelain -- . 2>/dev/null)" ]; then
        hash="$hash-dirty"
    fi
    plutil -replace TROMECommit -string "$hash" "$plist"
else
    plutil -remove TROMECommit "$plist" 2>/dev/null || true
    echo "note: no git history: the build names no commit"
fi
