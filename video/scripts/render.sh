#!/bin/sh
set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 still|render <arguments of remotion still or remotion render...>" >&2
    echo "       Renders through the Simulator lock of the repo, one heavy job at a time, at a low priority." >&2
    exit 2
fi
kind=$1
shift
cd "$(dirname "$0")/.."

# The browser: the one of CHROME=<path> (the Makefile passes it), or else the copy of Remotion's own that
# scripts/browser.sh makes outside the repo (it says why).
case " $* " in
    *" --browser-executable"*) ;;
    *)
        browser=$(./scripts/browser.sh)
        if [ -n "$browser" ]; then
            set -- "$@" --browser-executable="$browser"
        fi
        ;;
esac

# A render takes about 1.6 cores with one browser tab (concurrency 1, in remotion.config.ts).
# Next to a Simulator job, its first frame timed out: so it waits for the lock that the Simulator jobs use,
# and prints "Waiting for the Simulator lock" with the job that holds it while it waits.
RATP_SIM_KIND="video-$kind" exec ../ios/scripts/sim-lock.sh job nice -n 10 npx --no-install remotion "$kind" "$@"
