#!/bin/sh
# Tests change-notes-check.py in throwaway repos: the format of a note, and a change of the app with no note.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

reset_repo() {
    rm -rf "$repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    mkdir -p "$repo/ios/changes"
    printf '# Notes\n' > "$repo/ios/changes/README.md"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "first"
    git -C "$repo" checkout -q -b task
}

write() {
    mkdir -p "$(dirname "$repo/$1")"
    printf '%s\n' "$2" > "$repo/$1"
}

commit() {
    write "$1" "$2"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "${3:-feat: change $1}"
}

check() {
    (cd "$repo/ios" && "$scripts/change-notes-check.py" check) > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

said() {
    grep -c -- "$1" "$state/out" || true
}

hundred=$(printf 'é%.0s' $(seq 1 100))

# The format of a note.
reset_repo
write ios/changes/headline.txt "kind: headline
fr: $hundred
en: The trains of the next station show before you reach it."
write ios/changes/item.txt "kind: item
fr: Le numéro de ligne est bien centré dans son rond.

en: The line number sits in the middle of its badge."
write ios/changes/apple.txt "kind: apple
fr: TROME demande iOS 19 ou plus récent.
en: TROME needs iOS 19 or later."
write ios/changes/builder.txt "kind: builder
en: The release run prints the notes of the next version."
expect "a headline, an item, an apple note and a builder note pass; a headline may have 100 characters" "$(check)" "passes"
expect "it says how many notes it read" "$(said "OK (4 notes in ios/changes/")" "1"

write ios/changes/item.txt "kind: item
en: The line number sits in the middle of its badge."
expect "a rider note with no French line fails" "$(check)" "fails"
expect "the message names the file and the reason" "$(said "^change-notes-check: ios/changes/item.txt: no French line")" "1"

write ios/changes/item.txt "kind: item
fr: Le numéro de ligne est bien centré.
en:"
expect "an empty English line fails" "$(check)" "fails"
expect "it says that the English line is missing" "$(said "item.txt: no English line")" "1"

write ios/changes/item.txt "kind: item
fr: Le numéro de ligne est bien centré.
en: The line number sits in the middle
of its badge."
expect "a language on two lines fails" "$(check)" "fails"
expect "it asks for one line per language" "$(said "item.txt: the English line goes on over more than one line")" "1"

write ios/changes/item.txt "kind: item
fr: Le numéro de ligne est bien centré.
en: The line number is centred.
en: The line number sits in the middle of its badge."
expect "two lines of one language fail" "$(check)" "fails"
expect "it names the doubled field" "$(said "item.txt: two 'en:' lines")" "1"

write ios/changes/item.txt "kind: feature
fr: Le numéro de ligne est bien centré.
en: The line number is centred."
expect "an unknown kind fails" "$(check)" "fails"
expect "it names the kind and the known ones" "$(said "item.txt: unknown kind 'feature': write headline, item, apple or builder")" "1"

write ios/changes/item.txt "fr: Le numéro de ligne est bien centré.
en: The line number is centred."
expect "a note with no kind fails" "$(check)" "fails"
expect "it says how to start" "$(said "item.txt: no kind")" "1"

write ios/changes/item.txt "kind: item
fr: Le numéro de ligne est bien centré.
en: The line number is centred."
write ios/changes/headline.txt "kind: headline
fr: ${hundred}x
en: The trains of the next station show before you reach it."
expect "a headline of 101 characters fails" "$(check)" "fails"
expect "it gives the count and the reason" "$(said "headline.txt: the French headline has 101 characters, more than 100: a headline fits in 2 lines")" "1"
write ios/changes/headline.txt "kind: item
fr: ${hundred}x
en: ${hundred}x"
expect "an item has no limit of 100 characters" "$(check)" "passes"

write ios/changes/builder.txt "kind: builder
fr: La publication écrit les notes.
en: The release run prints the notes of the next version."
expect "a builder note with a French line fails" "$(check)" "fails"
expect "it says that a builder note is in English only" "$(said "builder.txt: a builder note is in English only")" "1"
write ios/changes/builder.txt "kind: builder
en: The release run prints the notes of the next version."

write ios/changes/note.md "kind: item"
expect "a note that is not a .txt file fails; the README of the folder is not a note" "$(check)" "fails"
expect "it says that a note is a .txt file" "$(said "ios/changes/note.md: a note is a .txt file")" "1"
rm "$repo/ios/changes/note.md"
expect "the notes pass again" "$(check)" "passes"

# A change of the app with no note.
reset_repo
commit ios/App/Screen.swift "screen"
expect "a change of the app with no note and no 'no rider change' fails" "$(check)" "fails"
expect "the message names the changed file of the app" "$(said "change the code of the app (ios/App/Screen.swift)")" "1"
expect "the message says the three ways out" \
    "$(said "add its note (ios/changes/README.md says how)") $(said "end the title of one of its commits with \"(no rider change)\"") $(said "git commit --allow-empty -m \"chore: no rider change\"")" "1 1 1"
write ios/changes/screen.txt "kind: item
fr: L'écran montre les trains.
en: The screen shows the trains."
expect "a note that is not committed does not count: only the commits merge" "$(check)" "fails"
git -C "$repo" add -A && git -C "$repo" commit -q -m "docs: note"
expect "the same change with its note committed passes" "$(check)" "passes"
expect "it says that the change has its note" "$(said "change the app and add or edit its note")" "1"

reset_repo
commit ios/Widget/View.swift "view"
expect "a change of the widget with no note fails" "$(check)" "fails"
commit ios/Widget/View.swift "view 2" "docs: the notes check asks for a note or says no rider change"
expect "a title that only talks about 'no rider change' does not count" "$(check)" "fails"
commit ios/Widget/View.swift "view 3" "fix(ios): draw the view again (no rider change)"
expect "a commit title that ends with '(no rider change)' lets it pass" "$(check)" "passes"
expect "it says why it passes" "$(said "say \"no rider change\"")" "1"

reset_repo
commit ios/Packages/Core/Sources/Rule.swift "rule"
git -C "$repo" commit -q --allow-empty -m "chore: No rider change"
expect "an empty commit that says it, in any case, lets a change of a package pass" "$(check)" "passes"
git -C "$repo" checkout -q main
commit ios/scripts/other.sh "other" "build: a change on main"
git -C "$repo" checkout -q task
git -C "$repo" rebase -q main
expect "the empty commit stays after a rebase onto a newer main, as make merge does" "$(check)" "passes"

reset_repo
commit ios/App/Screen.swift "screen"
git -C "$repo" commit -q --allow-empty -m "refactor(ios): split the screen

No rider change."
expect "a line 'No rider change.' in the body of a commit counts too" "$(check)" "passes"

reset_repo
commit ios/Packages/Core/Tests/RuleTests.swift "test"
commit ios/scripts/tool.sh "tool"
commit docs/page.md "page"
expect "unit tests, scripts and docs are not the code of the app: no note needed" "$(check)" "passes"
commit ios/Packages/Core/Package.swift "package"
expect "the manifest of a package goes into the app: a note is needed" "$(check)" "fails"

reset_repo
git -C "$repo" checkout -q main
commit ios/changes/pause.txt "kind: item
fr: Une pause de 30 minutes.
en: A pause of 30 minutes."
commit ios/App/Pause.swift "pause"
expect "on main itself, there is no change to judge" "$(check)" "passes"
git -C "$repo" checkout -q -b fix
commit ios/App/Pause.swift "pause fixed"
commit ios/changes/pause.txt "kind: item
fr: Une pause de 30 minutes ou d'une heure.
en: A pause of 30 minutes or 1 hour."
expect "a fix that edits the earlier note of the same thing passes" "$(check)" "passes"

reset_repo
commit ios/App/Screen.swift "screen"
git -C "$repo" branch -q -m main old
expect "with no main to compare with, the change is not judged, and it says so" "$(check) $(said "no branch 'main' or 'origin/main' to compare with")" "passes 1"

"$scripts/change-notes-check.py" > /dev/null 2>&1 && result="passes" || result="fails"
expect "with no mode, it prints its usage and fails" "$result" "fails"

if [ "$failures" -gt 0 ]; then
    echo "change-notes-check: $failures failure(s)"
    exit 1
fi
echo "change-notes-check: all tests passed"
