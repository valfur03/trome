#!/bin/sh
# Tests release-notes.py in throwaway repos: which notes a release tells (by the tag of the build on the App Store),
# the texts of each place, "no release", and the cases that stop red.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true
guide=docs/src/content/docs/en/maintain/release-on-the-app-store.mdx
# Each commit gets its own minute, so "newest first" never rests on the speed of the machine.
minute=0

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

commit() {
    minute=$((minute + 1))
    git -C "$repo" add -A
    when="$((1793000000 + minute * 60)) +0000"
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$repo" commit -q --allow-empty -m "${1:-change}"
}

# The table of builds, with the Where cell of each row: "store" marks the build on the App Store.
table() {
    mkdir -p "$repo/$(dirname "$guide")"
    {
        printf '# Release\n\n## The builds that riders may hold\n\n'
        printf '| Version (build) | Uploaded | Commit | Where, and until when | Status |\n|---|---|---|---|---|\n'
        for row in "$@"; do
            build=${row%%:*}
            where=TestFlight
            [ "${row#*:}" != store ] || where="App Store"
            printf '| 1.0.0 (%s) | 1 November 2026 | `abc` | %s | In the field |\n' "$build" "$where"
        done
        printf '\n## Fix this page\n'
    } > "$repo/$guide"
}

note() {
    mkdir -p "$repo/ios/changes"
    printf '%s\n' "$2" > "$repo/ios/changes/$1.txt"
}

item() {
    note "$1" "kind: item
fr: Élément $1.
en: Item $1."
}

reset_repo() {
    rm -rf "$repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    mkdir -p "$repo/ios/changes" "$repo/ios/Config"
    printf '# Notes\n' > "$repo/ios/changes/README.md"
    printf 'MARKETING_VERSION = 1.1.0\nCURRENT_PROJECT_VERSION = 3\n' > "$repo/ios/Config/Base.xcconfig"
    table 1 2
    commit "first"
    git -C "$repo" tag builds/1.0.0/1
}

run() {
    status=0
    (cd "$repo/ios" && "$scripts/release-notes.py") > "$state/out" 2>&1 || status=$?
    echo "$status"
}

said() {
    grep -c -F -- "$1" "$state/out" || true
}

# The lines under a heading of the output, up to the next blank line.
section() {
    awk -v title="$1" 'index($0, title) == 1 { on = 1; next } on && $0 == "" { exit } on { print }' "$state/out"
}

# A note that the build on the App Store holds is not told again, even when its commit is the newest: the tag decides,
# never a date.
reset_repo
item old
commit "an item that build 2 ships"
git -C "$repo" tag builds/1.0.0/2
note headline "kind: headline
fr: Les trains s’affichent seuls.
en: The trains show by themselves."
commit "the headline"
item shipped-newer
minute=$((minute + 50))
git -C "$repo" checkout -q builds/1.0.0/2
commit "an item made on build 2"
git -C "$repo" tag -f builds/1.0.0/2 > /dev/null
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-edit builds/1.0.0/2
table 1 2:store
commit "build 2 is on the App Store"
expect "with a headline, the command ends green" "$(run)" "0"
expect "it names the build on the App Store and its tag" "$(said 'the notes since 1.0.0 (2), the build on the App Store (tag builds/1.0.0/2)')" "1"
expect "a note that build 2 holds is not told" "$(said 'Item old')" "0"
expect "a note that build 2 holds is not told, even when its commit is newer than the headline" "$(said 'Item shipped-newer')" "0"
expect "the French What's New is the French headline" "$(section "== App Store, What's New, French")" "Les trains s’affichent seuls."

# The headline first, then the three newest items; the fourth is left out and named.
reset_repo
table 1:store 2
commit "build 1 is on the App Store"
note headline "kind: headline
fr: Les trains s’affichent seuls.
en: The trains show by themselves."
commit "the headline"
for name in one two three four; do
    item "$name"
    commit "item $name"
done
note builder "kind: builder
en: A tool for builders."
commit "a builder note"
expect "a headline with four items ends green" "$(run)" "0"
expected_en="The trains show by themselves.
• Item four.
• Item three.
• Item two."
expect "the English What's New is the headline, then the three newest items" "$(section "== App Store, What's New, English")" "$expected_en"
expect "the oldest item is left out, and named" "$(said '- Item one. (ios/changes/one.txt)')" "1"
expected_fr="Nouveau dans cette version :
Les trains s’affichent seuls.
• Élément four.
• Élément three.
• Élément two.

Pour Paris et l’Île-de-France seulement. Un problème ? Prenez une capture d’écran : TestFlight propose de me l’envoyer."
expect "the French What to Test is the same lines as the What's New, then the lines for testers" "$(awk 'index($0, "== TestFlight, What to Test, French") == 1 { on = 1; next } on && /^== / { exit } on { print }' "$state/out")" "$expected_fr"
expect "the What to Test gives its size in bytes" "$(said "== TestFlight, What to Test, French ($(printf '%s' "$expected_fr" | wc -c | tr -d ' ') bytes of 1000) ==")" "1"
expect "the CHANGELOG entry has the version and the date" "$(grep -c '^## 1.1.0 – [0-9][0-9]* [A-Z][a-z]* 20[0-9][0-9]$' "$state/out" || true)" "1"
expect "the CHANGELOG entry has the builder line" "$(said '- A tool for builders.')" "1"
expect "the builder line is not in the What's New" "$(section "== App Store, What's New, English" | grep -c builders || true)" "0"
expect "no line asks to raise the version, which is newer than the store's" "$(said 'Raise MARKETING_VERSION')" "0"

# The version of the build on the App Store is still in the config.
printf 'MARKETING_VERSION = 1.0.0\n' > "$repo/ios/Config/Base.xcconfig"
commit "the version is not raised"
run > /dev/null
expect "it asks to raise the version when it is the version on the App Store" "$(said 'Raise MARKETING_VERSION in ios/Config/Base.xcconfig: 1.0.0 is the version on the App Store.')" "1"

# No headline and no note of Apple: no release, and the lines that wait are listed.
reset_repo
table 1:store 2
commit "build 1 is on the App Store"
item small
note builder "kind: builder
en: A tool for builders."
commit "an item and a builder note"
expect "items and builder notes alone end green" "$(run)" "0"
expect "they say no release, since the build on the App Store" "$(head -1 "$state/out")" "no release: nothing a rider notices since 1.0.0 (1)."
expect "the item waits" "$(said '- item: Item small. (ios/changes/small.txt)')" "1"
expect "the builder note waits" "$(said '- builder: A tool for builders. (ios/changes/builder.txt)')" "1"
expect "no What's New is printed" "$(said "What's New")" "0"
expect "the What to Test of a TestFlight build still has the item" "$(section "== TestFlight, What to Test, English")" "New in this version:
• Item small."

for name in two three four; do
    item "$name"
    commit "item $name"
done
run > /dev/null
expect "on a quiet week, the What to Test has the three newest items" "$(section "== TestFlight, What to Test, English")" "New in this version:
• Item four.
• Item three.
• Item two."
expect "and every item that waits is listed" "$(grep -c '^- item: ' "$state/out" || true)" "4"

reset_repo
table 1:store 2
commit "build 1 is on the App Store"
note builder "kind: builder
en: A tool for builders."
commit "a builder note"
run > /dev/null
expect "a builder note alone makes no release" "$(head -1 "$state/out")" "no release: nothing a rider notices since 1.0.0 (1)."

# A requirement of Apple that stops the updates makes a release, with no headline.
note apple "kind: apple
fr: TROME demande maintenant iOS 19.
en: TROME now needs iOS 19."
commit "an apple note"
expect "an apple note alone makes a release" "$(run)" "0"
expect "it leads the What's New" "$(section "== App Store, What's New, English")" "TROME now needs iOS 19."
expect "it is named as the requirement of Apple" "$(said 'the requirement of Apple and 0 items')" "1"

# Two headlines stop red.
reset_repo
table 1:store 2
commit "build 1 is on the App Store"
note first "kind: headline
fr: Un.
en: One."
note second "kind: headline
fr: Deux.
en: Two."
commit "two headlines"
expect "two headlines stop red" "$(run)" "1"
expect "it says two headlines, with both files" "$(said 'two headlines wait (ios/changes/first.txt, ios/changes/second.txt)')" "1"
expect "it prints no text to paste" "$(said '==')" "0"

# A What to Test over 1,000 bytes stops red.
reset_repo
table 1:store 2
commit "build 1 is on the App Store"
long=$(printf 'é%.0s' $(seq 1 150))
note headline "kind: headline
fr: Un.
en: One."
for name in a b c; do
    note "$name" "kind: item
fr: $long
en: Item."
done
commit "long items"
expect "a French What to Test over 1,000 bytes stops red" "$(run)" "1"
expect "it says which text and its size" "$(grep -c 'the French What to Test has [0-9]* bytes, more than 1000' "$state/out" || true)" "1"

# A note that breaks its format stops red.
reset_repo
note broken "kind: headline
fr: Un."
commit "a broken note"
expect "a broken note stops red" "$(run)" "1"
expect "it names the note and the problem" "$(said 'ios/changes/broken.txt: no English line')" "1"

# Before the first store release, the notes are counted from the first build of the table.
reset_repo
note headline "kind: headline
fr: Un.
en: One."
commit "the headline"
expect "with no build on the App Store, it ends green" "$(run)" "0"
expect "it counts from the first build, and says why" "$(said 'the notes since 1.0.0 (1), the first build, as no build is on the App Store yet (tag builds/1.0.0/1)')" "1"
expect "it says that the first version has no What's New" "$(said 'The first version has no What')" "1"

# The build on the App Store has no tag.
table 1 2:store
commit "build 2 is on the App Store, with no tag"
expect "a build on the App Store with no tag stops red" "$(run)" "1"
expect "it names the missing tag" "$(said 'the build 1.0.0 (2) has no tag builds/1.0.0/2')" "1"

# The commit does not hold the build on the App Store.
git -C "$repo" checkout -q -b old builds/1.0.0/1
git -C "$repo" tag builds/1.0.0/2 main
table 1 2:store
commit "a branch from build 1"
expect "a commit that does not hold the build on the App Store stops red" "$(run)" "1"
expect "it says to run it from main" "$(said 'this commit does not hold the build 1.0.0 (2) (builds/1.0.0/2): run the command from main')" "1"

if [ "$failures" -ne 0 ]; then
    echo "release-notes: $failures test(s) failed"
    exit 1
fi
echo "release-notes: all tests passed"
