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
if [ "$TEST_RUNNER_RENDER_LANGUAGE" = fr ]; then
    echo '"Opéra",1,false,lock17,XXXL,200.0,195.0,true' >> "$TEST_RUNNER_RENDER_OUT/heights.csv"
fi
FAKE
chmod +x "$state/fake-xcodebuild"
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

rm -rf "$out/en"
expect "the report fails when a language was not drawn" \
    "$("$scripts/live-activity-render.sh" report "$out" > /dev/null 2>&1 && echo passes || echo fails)" "fails"

[ "$failures" -eq 0 ]
