#!/bin/sh
set -u

hook=${1:-}
[ $# -gt 0 ] && shift

if [ "$hook" = post-checkout ]; then
    [ "${3:-}" = 1 ] && [ "${1:-}" != "${2:-}" ] || exit 0
fi

git_dir=$(git rev-parse --absolute-git-dir 2> /dev/null) || exit 0
common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || exit 0
[ "$git_dir" = "$common_dir" ] || exit 0

root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -f "$root/ios/project.yml" ] && [ -f "$root/ios/Makefile" ] || exit 0

unset MAKEFLAGS MFLAGS MAKELEVEL SMALL LIVE
if ! output=$(make -C "$root/ios" --no-print-directory project 2>&1); then
    [ -z "$output" ] || printf '%s\n' "$output" >&2
    echo "Git hook $hook: the Xcode project was not created again. Run 'make generate' before you build in Xcode." >&2
fi
exit 0
