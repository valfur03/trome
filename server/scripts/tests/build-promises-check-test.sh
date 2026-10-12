#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
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

check() {
    node "$scripts/build-promises-check.ts" "${1:-$repo}" "${1:-$repo}/guide.mdx" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

# table <status of build 1> <status of build 2> [a third row]
table() {
    cat > "$repo/guide.mdx" <<EOF
## The builds that riders may hold

| Version (build) | Uploaded | Commit | Where, and until when | Status |
|---|---|---|---|---|
| 1.0.0 (1) | 11 October 2026 | \`ca169af\` | TestFlight | $1 |
| 1.0.0 (2) | 11 October 2026 | \`9d83a8d\` | TestFlight | $2 |
${3:-}

## Fix this page
EOF
}

# set <folder> <builds as JSON strings>
set_of() {
    mkdir -p "$repo/contracts/builds/$1/prim"
    printf '{ "builds": [%s], "answers": [] }\n' "$2" > "$repo/contracts/builds/$1/promises.json"
    printf '{ "Siri": {} }\n' > "$repo/contracts/builds/$1/prim/answer.json"
}

commit() {
    git -C "$repo" add -A
    git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q -m "$1"
}

expect "the sets of the repo pass" "$(node "$scripts/build-promises-check.ts" > "$state/out" 2>&1 && echo passes || echo fails)" "passes"

git init -q "$repo"
table 'In the field' 'In the field'
set_of 1.0.0-1-2 '"1.0.0 (1)", "1.0.0 (2)"'
expect "a new set, not yet committed, passes" "$(check)" "passes"
commit "record the set"
expect "a recorded set, as recorded, passes" "$(check)" "passes"

printf '{ "builds": ["1.0.0 (1)", "1.0.0 (2)"], "answers": [], "edited": true }\n' > "$repo/contracts/builds/1.0.0-1-2/promises.json"
expect "an edit of a recorded set fails" "$(check)" "fails"
expect "the message names the file" "$(grep -c 'contracts/builds/1.0.0-1-2/promises.json changed' "$state/out")" "1"
expect "the message names the builds in the field" "$(grep -c 'its builds 1.0.0 (1), 1.0.0 (2) are not retired' "$state/out")" "1"
commit "edit the set"
expect "a committed edit fails too" "$(check)" "fails"
git -C "$repo" checkout -q HEAD~1 -- contracts
commit "put the set back"
expect "a set put back as recorded passes" "$(check)" "passes"

rm "$repo/contracts/builds/1.0.0-1-2/prim/answer.json"
expect "a deleted recording fails" "$(check)" "fails"
expect "the message says it is gone" "$(grep -c 'prim/answer.json is gone' "$state/out")" "1"
git -C "$repo" checkout -q -- contracts

rm -r "$repo/contracts/builds/1.0.0-1-2"
expect "a deleted set fails" "$(check)" "fails"
expect "the message says that a build has no set" "$(grep -c 'The build 1.0.0 (1) is in the field but has no recorded set' "$state/out")" "1"
git -C "$repo" checkout -q -- contracts

rm -r "$repo/contracts/builds/1.0.0-1-2"
set_of 1.0.0-1-and-2 '"1.0.0 (1)", "1.0.0 (2)"'
expect "a set swapped for a new one under another name fails" "$(check)" "fails"
rm -r "$repo/contracts/builds/1.0.0-1-and-2"
git -C "$repo" checkout -q -- contracts

printf '{ "builds": ["1.0.0 (1)", "1.0.0 (2)"], "answers": [], "edited": true }\n' > "$repo/contracts/builds/1.0.0-1-2/promises.json"
table '**Retired on `9 January 2027`: `its TestFlight date has passed`**' 'In the field'
expect "an edit with one build of the set still in the field fails" "$(check)" "fails"
expect "the message names that build only" "$(grep -c 'its builds 1.0.0 (2) are not retired' "$state/out")" "1"

table 'Retired on 9 January 2027' 'Retired on 9 January 2027'
expect "a retirement with no reason does not free the set" "$(check)" "fails"

table '**Retired on `9 January 2027`: `its TestFlight date has passed`**' 'Retired on `9 January 2027`: `its TestFlight date has passed`'
expect "an edit once every build of the set is retired passes" "$(check)" "passes"
rm -r "$repo/contracts/builds/1.0.0-1-2"
expect "a deletion once every build of the set is retired passes" "$(check)" "passes"
git -C "$repo" checkout -q -- contracts

table 'In the field' 'In the field' '| 1.0.0 (3) | 20 October 2026 | `abcdef1` | TestFlight | In the field |'
expect "a new row with no set fails" "$(check)" "fails"
expect "the message names the new build" "$(grep -c 'The build 1.0.0 (3) is in the field but has no recorded set' "$state/out")" "1"
set_of 1.0.0-3 '"1.0.0 (3)"'
expect "a new row with its own new set passes" "$(check)" "passes"
rm -r "$repo/contracts/builds/1.0.0-3"

set_of 1.0.0-2-again '"1.0.0 (2)"'
table 'In the field' 'In the field'
expect "a second set for a build fails" "$(check)" "fails"
expect "the message names both sets" "$(grep -c '1.0.0 (2) has 2 recorded sets' "$state/out")" "1"
rm -r "$repo/contracts/builds/1.0.0-2-again"

set_of 1.0.0-4 '"1.0.0 (4)"'
expect "a set of a build that the table does not list fails" "$(check)" "fails"
rm -r "$repo/contracts/builds/1.0.0-4"

mkdir -p "$repo/contracts/builds/no-builds"
printf '{ "answers": [] }\n' > "$repo/contracts/builds/no-builds/promises.json"
expect "a set with no list of builds fails" "$(check)" "fails"
rm -r "$repo/contracts/builds/no-builds"

printf '# Release\n\nNo table here.\n' > "$repo/guide.mdx"
expect "a guide with no table fails" "$(check)" "fails"
expect "the message says the table cannot be read" "$(grep -c 'cannot be read' "$state/out")" "1"

table 'In the field' 'In the field'
printf 'more\n' > "$repo/notes.txt"
commit "a later commit"
git clone -q --depth 1 "file://$repo" "$state/shallow"
expect "a shallow clone fails" "$(check "$state/shallow")" "fails"
expect "the message asks for the whole history" "$(grep -c 'git fetch --unshallow' "$state/out")" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All build promises checks passed"
