#!/bin/sh
export PS4='+ \t '
exec sh -x "$(cd "$(dirname "$0")/../.." && pwd)/scripts/simulator.sh" "$@"
