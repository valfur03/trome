#!/bin/sh
# Tests the composition of the store pictures (store-screenshots.sh compose), with made-up captures and bezels.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
# It compiles Swift, which loads the Mac as a build does, so it runs through the build gate, never next to a Simulator test run.
[ -n "${RATP_BUILD_GATE_HELD:-}" ] || exec "$scripts/build-gate.py" build "$0" "$@"
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

swiftc "$scripts/store-screenshots-compose/main.swift" "$scripts/../Packages/TROMECore/Sources/TROMEBadge/LineBadge/LabelInk.swift" \
    -o "$state/compose"
swiftc "$tests/badge-centre.swift" -o "$state/badge-centre"
swiftc "$tests/pixel-colours.swift" -o "$state/pixel-colours"
out="$state/out"
mkdir -p "$out/captures"
for language in en fr; do
    for name in app island-metro lock-metro island-fork lock-fork island-rer lock-rer; do
        "$tests/make-png.py" "$out/captures/$name-$language.png" 1206 2622 opaque
    done
    echo "1900 2000" > "$out/captures/app-help-row-$language.txt"
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
expect "the app picture shows the top of the phone, cut by the bottom edge just under the link Help and feedback" \
    "$(grep -c '^app rows 0-2064 off the bottom edge, the phone starts at y 804, headline centre 402$' "$state/output")" "2"
# The 11 of picture 1 (its badge of 130 px at x 150, y 2194, white on brown) is centred across by the weight of its
# ink, as in the app: centred by its box, its two bars sat 2.7 percent of the diameter to the right.
expect "the 11 of picture 1 is centred by the weight of its ink, within 0.5 percent of the diameter" \
    "$("$state/badge-centre" "$out/en-1-metro.png" 150 2194 130 FFFFFF \
        | awk '{ print ($5 >= -0.5 && $5 <= 0.5) ? "centred" : "off by " $5 " percent" }')" "centred"

# The line is drawn as on a line map (y 2194, the branch of the fork at y 2298). Each stop is a white dot, with no
# drawing in it, in a ring of the colour of the line, also under the light of the train; only the borders, where the
# line changes, have a white circle with a dark ring.
colours() {   # colours <picture> <x,y>...: the colours of these pixels, on one line
    picture=$1
    shift
    "$state/pixel-colours" "$out/$picture" "$@" | tr '\n' ' '
}
stops() {   # stops <picture> <the colour of the line> <x,y>...: "plain" when each stop is a plain white dot in its ring
    picture=$1
    stroke=$2
    shift 2
    for c in "$@"; do
        x=${c%,*}
        y=${c#*,}
        # Near, not equal: the soft shadow of the Dynamic Island cut reaches the stops of the branch a little.
        result=$(colours "$picture" "$c" "$((x - 9)),$y" "$((x + 9)),$y" "$x,$((y - 9))" "$x,$((y + 9))" \
            "$((x - 16)),$y" "$((x + 16)),$y" "$x,$((y - 16))" "$x,$((y + 16))" | awk -v s="$stroke" '
            function channel(hex, k) { return index("0123456789ABCDEF", substr(hex, 2 * k - 1, 1)) * 16 \
                + index("0123456789ABCDEF", substr(hex, 2 * k, 1)) }
            function near(a, b,   k) { for (k = 1; k <= 3; k++) if (channel(a, k) - channel(b, k) > 6 || channel(b, k) - channel(a, k) > 6) return 0; return 1 }
            { for (i = 1; i <= 5; i++) if (!near($i, "FFFFFF")) { print "a dot that is not white: " $0; exit }
              for (i = 6; i <= 9; i++) if (!near($i, s)) { print "a ring that is not the line: " $0; exit }
              print "plain" }')
        if [ "$result" != "plain" ]; then
            echo "the stop at $c has $result"
            return
        fi
    done
    echo "plain"
}
stroke1=$(colours en-1-metro.png 300,2194 | tr -d " ")
stroke2=$(colours en-2-fork.png 100,2194 | tr -d " ")
stroke3=$(colours en-3-rer.png 100,2194 | tr -d " ")
expect "the stops of line 11 are white dots in a ring of its colour, also the one under the light" \
    "$(stops en-1-metro.png "$stroke1" 470,2194 790,2194 1110,2194)" "plain"
expect "the stops of line 7, the fork and the branch included, are white dots in a ring of its colour" \
    "$(stops en-2-fork.png "$stroke2" 560,2194 860,2194 1160,2194 860,2298 1080,2298 1200,2298)" "plain"
expect "the stops of the RER B are white dots in a ring of its colour" \
    "$(stops en-3-rer.png "$stroke3" 560,2194 860,2194 1160,2194)" "plain"
expect "each border, where the line changes, has a white circle in a dark ring" \
    "$(colours en-1-metro.png 1319,2194 1319,2154; colours en-2-fork.png 0,2194 0,2154; colours en-3-rer.png 0,2194 0,2154 1319,2194 1319,2154)" \
    "FFFFFF 05060D FFFFFF 05060D FFFFFF 05060D FFFFFF 05060D "
expect "the branch of the fork has a round end" \
    "$(colours en-2-fork.png 1215,2298 1215,2281 | awk -v s="$stroke2" '{ print ($1 == s && $2 != s) ? "round" : "square: " $0 }')" \
    "round"

# A bezel whose screen is the capture at scale 1, in a body of 1320 x 2742: the whole width shows at scale 1.
"$tests/make-png.py" "$state/bezel.png" 1320 2742 frame 57 60
compose "$state/bezel.png"
expect "a bezel that fits frames the cuts at scale 1" \
    "$(grep -c "^Frame: the bezel $state/bezel.png (1320 x 2742, screen 1206 x 2622, corners 0), at scale 1.000; captures at scale 1.000$" "$state/output")" "2"
expect "the whole top of the bezel shows above the app screen, the headline centred above it" \
    "$(grep -c '^app rows 0-2064 off the bottom edge, the phone starts at y 744, headline centre 372$' "$state/output")" "2"

# Apple's bezel has round corners: the corner of the screen box is outside the body, and the captures are cut to the
# round screen, so their square corners never show past the frame.
"$tests/make-png.py" "$state/round.png" 1320 2742 frame 57 60 230 177
compose "$state/round.png"
expect "a bezel with round corners cuts the captures to its round screen" \
    "$(grep -c "^Frame: the bezel $state/round.png (1320 x 2742, screen 1206 x 2622, corners 167), at scale 1.000; captures at scale 1.000$" "$state/output")" "2"

# A body wider than the picture: the bezel is scaled down so that its whole width shows.
"$tests/make-png.py" "$state/wide.png" 1380 2742 frame 87 60
compose "$state/wide.png"
expect "a wider bezel is scaled down to the width of the picture" \
    "$(grep -c "^Frame: the bezel $state/wide.png (1380 x 2742, screen 1206 x 2622, corners 0), at scale 0.957; captures at scale 0.957$" "$state/output")" "2"

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

echo "2400 2500" > "$out/captures/app-help-row-fr.txt"
compose "$state/no-bezel.png"
expect "an app screen too tall for the headline above it fails" "$(cat "$state/status")" "1"
expect "and says why" "$(grep -c '^The app screen leaves no room for the headline: the phone starts at y 304$' "$state/output")" "1"
rm "$out/captures/app-help-row-fr.txt"
compose "$state/no-bezel.png"
expect "a missing row of the link Help and feedback fails, and names its file" \
    "$(grep -c "^Cannot read $out/captures/app-help-row-fr.txt$" "$state/output")" "1"
echo "1900 2000" > "$out/captures/app-help-row-fr.txt"

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
