#!/bin/sh
set -eu

folder=$(basename "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)")
number=$(printf '%s\n' "$folder" | sed -n 's/.*[^0-9]0*\([0-9][0-9]*\)$/\1/p')
echo $((8787 + ${number:-0}))
