#!/bin/sh
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

cat > "$state/fake-xcodebuild" <<'FAKE'
#!/bin/sh
echo "$TEST_RUNNER_RENDER_LANGUAGE $TEST_RUNNER_RENDER_OUT $*" >> "$FAKE_CALLS"
printf 'station,page,stale,surface,size,height,limit,over\n"Nation",0,false,lock17,L,150.0,160.0,false\n' \
    > "$TEST_RUNNER_RENDER_OUT/heights.csv"
echo '[]' > "$TEST_RUNNER_RENDER_OUT/texts.json"
if [ "$TEST_RUNNER_RENDER_LANGUAGE" = fr ]; then
    echo '"Opéra",1,false,lock17,XXXL,200.0,195.0,true' >> "$TEST_RUNNER_RENDER_OUT/heights.csv"
    cp "$FAKE_TEXTS" "$TEST_RUNNER_RENDER_OUT/texts.json"
fi
FAKE
chmod +x "$state/fake-xcodebuild"
text() {
    printf '{"left":%s,"top":%s,"width":%s,"height":20,"isTruncated":%s,"visibleCharacters":%s,"ocr":"%s"}' "$@"
}
expected() {
    printf '{"kind":"%s","text":"%s","line":%s,"direction":%s}' "$@"
}
render() {
    printf '{"image":"%s","station":"Opéra","page":%s,"isStale":false,"surface":"%s","size":"XXXL","height":180,' "$@"
}
{
    echo '['
    render "Opéra-p2-lock17-XXXL.png" 2 lock17
    echo '"drawn":['
    text 40 40 80 true 12 "* Haussmann Sa..."; echo ,
    text 130 40 30 true 2 "Na..."; echo ,
    text 130 60 30 true 2 "→ Ch..."; echo ,
    text 300 40 70 true 6 "dans 3..."; echo ,
    text 300 60 73 false 10 ""
    echo '],"expected":['
    expected station "Opéra" null null; echo ,
    expected label "Haussmann Saint-Lazare" 0 null; echo ,
    expected destination "Nanterre - Préfecture" 0 0; echo ,
    expected destination "Chessy" 0 1
    echo ']},'
    render "Opéra-p3-lockSE-XXXL.png" 3 lockSE
    echo '"drawn":['
    text 130 40 60 true 9 "→ Mairie d'..."; echo ,
    text 130 60 60 true 9 "Mairie d'"; echo ,
    text 130 80 60 true 6 "Gallie..."; echo ,
    text 130 100 60 false 6 ""; echo ,
    text 130 120 60 false 4 ""; echo ,
    text 100 140 10 true 0 "..."; echo ,
    text 130 160 20 true 1 "C..."; echo ,
    text 40 160 20 true 1 "C..."; echo ,
    text 280 40 75 false 5 ""
    echo '],"expected":['
    expected station "Opéra" null null; echo ,
    expected destination "Mairie d'Issy" 0 0; echo ,
    expected destination "Mairie d'Aubervilliers" 0 1; echo ,
    expected destination "Gallieni" 1 0; echo ,
    expected destination "Nation" 1 1; echo ,
    expected destination "Orly" 2 0; echo ,
    expected destination "Porte de Clignancourt" 2 1; echo ,
    expected label "Châtelet - Les Halles" 3 null; echo ,
    expected destination "Corbeil-Essonnes" 3 0
    echo ']}]'
} > "$state/texts.json"
export FAKE_TEXTS="$state/texts.json"
out="$state/out"
mkdir -p "$out/old"
touch "$out/old/heights.csv"

FAKE_CALLS="$state/calls" "$scripts/live-activity-render.sh" render "$out" "$state/fake-xcodebuild" test-without-building \
    > /dev/null
expect "the render draws in French only by default" "$(cat "$state/calls")" \
    "fr $out/fr test-without-building -testLanguage fr -testRegion FR"
expect "the render starts from an empty folder" "$(test -e "$out/old" && echo kept || echo removed)" "removed"
expect "the report of the default render gives French only" \
    "$("$scripts/live-activity-render.sh" report "$out" | grep '^== Language')" "== Language: fr"

rm "$state/calls"
export RENDER_LANGUAGES="fr en"
FAKE_CALLS="$state/calls" "$scripts/live-activity-render.sh" render "$out" "$state/fake-xcodebuild" test-without-building \
    > /dev/null
expect "with RENDER_LANGUAGES, the render draws in French, then in English, each in its own folder" "$(cat "$state/calls")" \
    "fr $out/fr test-without-building -testLanguage fr -testRegion FR
en $out/en test-without-building -testLanguage en -testRegion US"

report=$("$scripts/live-activity-render.sh" report "$out")
expect "the report gives the too tall renders of each language" \
    "$(echo "$report" | grep -E '^(== Language|Too tall)' | sed "s|$out|OUT|")" \
    "== Language: fr
Too tall for their text size: 1 (list: OUT/fr/too-tall.csv)
== Language: en
Too tall for their text size: 0 (list: OUT/en/too-tall.csv)"

expect "the report counts each kind of breach of the cut rules, for each phone, surface and size, 0 included" \
    "$(echo "$report" | grep -E '^(Breaches|  iPhone)' | sed "s|$out|OUT|")" \
    "Breaches of the cut rules (texts cut too much), in the images of 1 stations: 8 (list: OUT/fr/breaches.csv)
  iPhone 17, lock screen, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone 17, lock screen, XXXL: time cut 1, destination under 6 2, two directions the same 0, label cut 1
  iPhone SE, lock screen, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone SE, lock screen, XXXL: time cut 0, destination under 6 2, two directions the same 1, label cut 1
  iPhone 17, island, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone 17, island, XXXL: time cut 0, destination under 6 0, two directions the same 0, label cut 0
Breaches of the cut rules (texts cut too much), in the images of 0 stations: 0 (list: OUT/en/breaches.csv)
  iPhone 17, lock screen, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone 17, lock screen, XXXL: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone SE, lock screen, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone SE, lock screen, XXXL: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone 17, island, L: time cut 0, destination under 6 0, two directions the same 0, label cut 0
  iPhone 17, island, XXXL: time cut 0, destination under 6 0, two directions the same 0, label cut 0"
expect "the list gives each breach, and a cut text that can be a label or a destination is named by its column with its station, page, surface and image" \
    "$(sed 1d "$out/fr/breaches.csv")" \
    "destination-under-6,\"Opéra\",2,false,lock17,XXXL,\"Opéra-p2-lock17-XXXL.png\",\"Na…\"
destination-under-6,\"Opéra\",2,false,lock17,XXXL,\"Opéra-p2-lock17-XXXL.png\",\"Ch…\"
destination-under-6,\"Opéra\",3,false,lockSE,XXXL,\"Opéra-p3-lockSE-XXXL.png\",\"…\"
destination-under-6,\"Opéra\",3,false,lockSE,XXXL,\"Opéra-p3-lockSE-XXXL.png\",\"C…\"
label-cut,\"Opéra\",2,false,lock17,XXXL,\"Opéra-p2-lock17-XXXL.png\",\"Haussmann Sa…\"
label-cut,\"Opéra\",3,false,lockSE,XXXL,\"Opéra-p3-lockSE-XXXL.png\",\"C…\"
same-two-directions,\"Opéra\",3,false,lockSE,XXXL,\"Opéra-p3-lockSE-XXXL.png\",\"Mairie d'… / Mairie d'…\"
time-cut,\"Opéra\",2,false,lock17,XXXL,\"Opéra-p2-lock17-XXXL.png\",\"dans 3…\""

rm "$out/fr/texts.json"
expect "the report fails when the render wrote no texts.json" \
    "$("$scripts/live-activity-render.sh" report "$out" > /dev/null 2>&1 && echo passes || echo fails)" "fails"
{
    echo '['
    render "Nation-p0-lock17-XXXL.png" 0 lock17
    echo '"drawn":[{"left":0,"top":0,"width":50,"height":20,"isTruncated":true,"visibleCharacters":3}],"expected":[]}]'
} > "$out/fr/texts.json"
expect "the report fails when it cannot read an image of texts.json" \
    "$("$scripts/live-activity-render.sh" report "$out" > /dev/null 2>&1 && echo passes || echo fails)" "fails"
cp "$FAKE_TEXTS" "$out/fr/texts.json"

# A Mac whose text recognition fails (as in a virtual machine with no device for it) must not report "0 cut texts".
mkdir -p "$state/failing-ocr"
real_swift=$(command -v swift)
cat > "$state/failing-ocr/swift" <<FAKE
#!/bin/sh
case "\$1" in
    *live-activity-render-ocr.swift) echo "Error raised at top level: nilError" >&2; exit 1 ;;
    *) exec "$real_swift" "\$@" ;;
esac
FAKE
chmod +x "$state/failing-ocr/swift"
echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' \
    | base64 -d > "$out/fr/Opéra-p2-lock17-XXXL.png"
failed=$(PATH="$state/failing-ocr:$PATH" "$scripts/live-activity-render.sh" report "$out" 2>&1 && echo passes || echo fails)
rm "$out/fr/Opéra-p2-lock17-XXXL.png"
expect "the report fails when the text recognition fails, after the too tall renders, and says why, with no count of cut texts or breaches" \
    "$(echo "$failed" | grep -E '^(Too tall|Cut texts|Breaches|The text recognition|fails)' | sed "s|$out|OUT|")" \
    "Too tall for their text size: 1 (list: OUT/fr/too-tall.csv)
The text recognition of this Mac failed, so the cut texts and the breaches cannot be listed
fails"

rm -rf "$out/en"
expect "the report fails when a language was not drawn" \
    "$("$scripts/live-activity-render.sh" report "$out" > /dev/null 2>&1 && echo passes || echo fails)" "fails"

[ "$failures" -eq 0 ]
