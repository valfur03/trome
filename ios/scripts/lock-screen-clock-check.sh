#!/bin/sh
# Checks that each lock screen picture of the docs shows the clock of the status bar override, 9:41.
# The lock screen sometimes draws the real time and date instead, with no error, so two runs would give other pictures.
# It reads each picture with the text recognition of the Mac: the label of the lock screen clock for VoiceOver
# gives the real time even when the picture shows 9:41, so a UI test cannot see it.
set -eu

if [ $# -lt 2 ]; then
    echo "Usage: $0 <folder> <picture name>...   Checks <folder>/<picture name>.png" >&2
    exit 1
fi

scripts=$(cd "$(dirname "$0")" && pwd)
clock=9:41
folder=$1
shift
pictures=""
for name in "$@"; do
    pictures="$pictures $name.png"
done

read_texts=$(mktemp)
trap 'rm -f "$read_texts"' EXIT
# Run from the folder, so that each picture is a plain name (the text recognition prints the name, not the path).
(cd "$folder" && swift "$scripts/live-activity-render-ocr.swift" $pictures) > "$read_texts"

# A time is a line of digits such as 9:41 or 19:41, with nothing else.
awk -F '\t' -v clock="$clock" -v pictures="$pictures" '
    $2 ~ /^[0-9]?[0-9]:[0-9][0-9]$/ { times[$1] = times[$1] " " $2; if ($2 == clock) { right[$1] = 1 } }
    END {
        count = split(pictures, names, " ")
        for (i = 1; i <= count; i++) {
            name = names[i]
            if (right[name]) {
                continue
            }
            shown = times[name] == "" ? "no time" : "the time" times[name]
            printf "%s: the lock screen clock shows %s, not %s\n", name, shown, clock > "/dev/stderr"
            wrong++
        }
        if (wrong) {
            print "The lock screen did not draw the 9:41 of the status bar override, so no picture of the docs was changed (docs/README.md, \"Make the pictures again\")." > "/dev/stderr"
            exit 1
        }
    }
' "$read_texts"
