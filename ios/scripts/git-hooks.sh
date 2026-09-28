#!/bin/sh
set -eu

hooks_path=ios/scripts/git-hooks

fail() {
    echo "make git-hooks: $1" >&2
    exit 1
}

turn_on() {
    current=$(git config --get core.hooksPath || true)
    [ "$current" = "$hooks_path" ] && { echo "The git hooks are already on (core.hooksPath = $hooks_path)."; return; }
    [ -z "$current" ] || fail "core.hooksPath is already '$current'. Git runs only one hooks folder. Remove that setting first (git config --unset core.hooksPath), or keep your hooks."
    own_hooks=$(find "$(git rev-parse --path-format=absolute --git-common-dir)/hooks" -type f ! -name '*.sample' 2> /dev/null | sort)
    [ -z "$own_hooks" ] || fail "git would stop running these hooks: $own_hooks. Move them away first."
    git config core.hooksPath "$hooks_path"
    echo "The git hooks are on (core.hooksPath = $hooks_path). After a git pull or a checkout in the main folder, the Xcode project is created again."
}

turn_off() {
    current=$(git config --get core.hooksPath || true)
    [ "$current" = "$hooks_path" ] || { echo "The git hooks of the repo are not on. Nothing to do."; return; }
    git config --unset core.hooksPath
    echo "The git hooks are off. Run 'make generate' after each git pull, before you build in Xcode."
}

case ${1:-} in
    on) turn_on ;;
    off) turn_off ;;
    *) echo "Usage: $0 on|off" >&2; exit 1 ;;
esac
