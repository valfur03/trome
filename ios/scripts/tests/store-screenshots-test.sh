#!/bin/sh
# Tests the composition of the store pictures (store-screenshots.sh compose), with made-up captures and bezels.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

swiftc "$scripts/store-screenshots-compose.swift" -o "$state/compose"
out="$state/out"
mkdir -p "$out/captures"
for language in en fr; do
    for name in app island-metro lock-metro island-fork lock-fork island-rer lock-rer; do
        "$tests/make-png.py" "$out/captures/$name-$language.png" 1206 2622 opaque
    done
    echo "730 952" > "$out/captures/app-example-row-$language.txt"
done

compose() {   # compose <bezel path>: the output of the command, and its status in $state/status
    status=0
    STORE_SCREENSHOTS_OUT=$out STORE_BEZEL=$1 "$scripts/store-screenshots.sh" compose "$state/compose" > "$state/output" 2>&1 \
        || status=$?
    echo "$status" > "$state/status"
}

compose "$state/no-bezel.png"
expect "with no bezel file, it composes" "$(cat "$state/status")" "0"
expect "it says that the bezel is missing and where to put it" \
    "$(grep -c "^No bezel at $state/no-bezel.png: the pictures have no frame" "$state/output")" "1"
expect "it says that the cuts have no frame, for each language" "$(grep -c '^Frame: none, because no bezel file was given' "$state/output")" "2"
expect "it saves the 8 pictures, with the language and the order in their names" \
    "$(grep '^Saved ' "$state/output" | sed "s|^Saved $out/||" | tr '\n' ' ')" \
    "en-1-metro.png en-2-fork.png en-3-rer.png en-4-app.png fr-1-metro.png fr-2-fork.png fr-3-rer.png fr-4-app.png "
expect "each is 1320 x 2868 with no alpha channel" \
    "$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$out"/*-*.png | grep -c -E 'pixelWidth: 1320|pixelHeight: 2868|hasAlpha: no')" "24"
cp "$out/en-1-metro.png" "$state/pictograms.png"

STORE_STOPS=dots STORE_SCREENSHOTS_OUT=$out STORE_BEZEL="$state/no-bezel.png" "$scripts/store-screenshots.sh" compose "$state/compose" > "$state/output"
expect "the plain dots are another picture" "$(cmp -s "$out/en-1-metro.png" "$state/pictograms.png" && echo same || echo different)" "different"
expect "it says which stops it drew" "$(grep -c '^Headlines: SF bold [0-9]*; stops: dots$' "$state/output")" "2"

# A bezel whose screen is the capture at scale 1, in a body of 1320 x 2742: the whole width shows at scale 1.
"$tests/make-png.py" "$state/bezel.png" 1320 2742 frame 57 60
compose "$state/bezel.png"
expect "a bezel that fits frames the cuts at scale 1" \
    "$(grep -c "^Frame: the bezel $state/bezel.png (1320 x 2742, screen 1206 x 2622), at scale 1.000; captures at scale 1.000$" "$state/output")" "2"

# A body wider than the picture: the bezel is scaled down so that its whole width shows.
"$tests/make-png.py" "$state/wide.png" 1380 2742 frame 87 60
compose "$state/wide.png"
expect "a wider bezel is scaled down to the width of the picture" \
    "$(grep -c "^Frame: the bezel $state/wide.png (1380 x 2742, screen 1206 x 2622), at scale 0.957; captures at scale 0.957$" "$state/output")" "2"

# Under 0.9, the card would shrink too much: no frame.
"$tests/make-png.py" "$state/too-wide.png" 1600 2742 frame 197 60
compose "$state/too-wide.png"
expect "a bezel that would shrink the card under 0.9 is not used" \
    "$(grep -c '^Frame: none, because with the whole bezel in the width, the captures would be at scale 0.825' "$state/output")" "2"

# A screen of another shape: another iPhone.
"$tests/make-png.py" "$state/other.png" 1320 2400 frame 57 60
compose "$state/other.png"
expect "a bezel of another iPhone is not used" \
    "$(grep -c '^Frame: none, because the screen of the bezel is 1206 x 2280, not the shape of the captures' "$state/output")" "2"
expect "it still makes the pictures" "$(cat "$state/status")" "0"

rm "$out/captures/lock-rer-fr.png"
compose "$state/no-bezel.png"
expect "a missing capture fails" "$(cat "$state/status")" "1"
expect "and names it" "$(grep -c "Cannot read the picture $out/captures/lock-rer-fr.png" "$state/output")" "1"

"$tests/make-png.py" "$out/captures/lock-rer-fr.png" 1206 2600 opaque
compose "$state/no-bezel.png"
expect "a capture of another size fails" "$(grep -c 'lock-rer-fr.png is 1206 x 2600, not a capture of the iPhone 17 Simulator' "$state/output")" "1"

rm -rf "$out/captures"
compose "$state/no-bezel.png"
expect "with no captures, it says to take them" "$(grep -c "^There are no captures in $out/captures. Run 'make store-screenshots' first.$" "$state/output")" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
