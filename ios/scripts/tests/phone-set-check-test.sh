#!/bin/sh
# The recorded phone sets stay as each build wrote them (phone-set-check.py check, in make check),
# and the release refuses a newest build in the field with no set (phone-set-check.py release), on fake repos and guides.
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
    "$scripts/phone-set-check.py" check "${1:-$repo}" "${1:-$repo}/guide.mdx" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

release() {
    "$scripts/phone-set-check.py" release "$repo" "$repo/guide.mdx" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

said() {
    grep -c -F -- "$1" "$state/out" || true
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

# set_of <folder>: a set as make phone-set-record writes it, a state and a content of the Live Activity.
set_of() {
    mkdir -p "$repo/contracts/phone/$1/states/automatic-off" "$repo/contracts/phone/$1/live-activity"
    printf '{"turnedOff":{}}\n' > "$repo/contracts/phone/$1/states/automatic-off/autoLiveActivity.mode.json"
    printf '{"stationName":"Abbesses"}\n' > "$repo/contracts/phone/$1/live-activity/abbesses.json"
}

commit() {
    git -C "$repo" add -A
    git -C "$repo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$1"
}

expect "the sets of the repo pass" "$("$scripts/phone-set-check.py" check > "$state/out" 2>&1 && echo passes || echo fails)" "passes"
expect "the newest build in the field of the repo has its set" "$("$scripts/phone-set-check.py" release > "$state/out" 2>&1 && echo passes || echo fails)" "passes"

git init -q "$repo"
table 'In the field' 'In the field'
set_of 1.0.0-1
set_of 1.0.0-2
expect "new sets, not yet committed, pass" "$(check)" "passes"
commit "record the sets"
expect "recorded sets, as recorded, pass" "$(check)" "passes"
off=contracts/phone/1.0.0-1/states/automatic-off/autoLiveActivity.mode.json

# A changed file.
printf '{"off":{}}\n' > "$repo/$off"
expect "an edit of a recorded set fails" "$(check)" "fails"
expect "the message names the file and the reason" "$(said "$off changed (recorded in ")" "1"
expect "the message names the set and says that its build is in the field" \
    "$(said 'the recorded phone set contracts/phone/1.0.0-1/ changed, but its build is not retired')" "1"
expect "the message names no other set" "$(said 'contracts/phone/1.0.0-2/')" "0"
commit "edit the set"
expect "a committed edit fails too" "$(check)" "fails"
git -C "$repo" checkout -q HEAD~1 -- contracts
commit "put the set back"
expect "a set put back as recorded passes" "$(check)" "passes"

# A file that goes, or moves.
rm "$repo/$off"
expect "a deleted file fails" "$(check)" "fails"
expect "the message says that it is gone" "$(said "$off is gone (recorded in ")" "1"
git -C "$repo" checkout -q -- contracts

git -C "$repo" mv "$off" contracts/phone/1.0.0-1/states/automatic-off/mode.json
expect "a moved file fails" "$(check)" "fails"
expect "the message says that the old path is gone" "$(said "$off is gone")" "1"
expect "the message names the new path" "$(said 'contracts/phone/1.0.0-1/states/automatic-off/mode.json is new')" "1"
git -C "$repo" reset -q --hard

git -C "$repo" mv contracts/phone/1.0.0-1 contracts/phone/1.0.0-01
expect "a renamed set fails" "$(check)" "fails"
expect "the message names the set that went" "$(said "$off is gone")" "1"
git -C "$repo" reset -q --hard

rm -r "$repo/contracts/phone/1.0.0-2"
expect "a deleted set fails" "$(check)" "fails"
git -C "$repo" checkout -q -- contracts

# A file added to a recorded set: a set is never edited, also by an addition.
printf '{}\n' > "$repo/contracts/phone/1.0.0-1/live-activity/new-case.json"
expect "a file added to a recorded set fails" "$(check)" "fails"
expect "the message says that it is new" "$(said 'contracts/phone/1.0.0-1/live-activity/new-case.json is new, and not committed, in the set recorded in')" "1"
commit "add a case to an old set"
expect "a committed addition fails too" "$(check)" "fails"
expect "the message names its commit" "$(said 'contracts/phone/1.0.0-1/live-activity/new-case.json was added in ')" "1"
git -C "$repo" rm -q contracts/phone/1.0.0-1/live-activity/new-case.json
commit "take the case away"
expect "the addition taken away passes" "$(check)" "passes"

printf 'Finder\n' > "$repo/contracts/phone/1.0.0-1/.DS_Store"
printf '.DS_Store\n' > "$repo/.gitignore"
expect "a file that git ignores is no addition" "$(check)" "passes"
rm "$repo/contracts/phone/1.0.0-1/.DS_Store" "$repo/.gitignore"

# Retirement frees a set, only with a reason, and only the set of the retired build.
printf '{"off":{}}\n' > "$repo/$off"
table 'Retired on 9 January 2027' 'In the field'
expect "a retirement with no reason does not free the set" "$(check)" "fails"
table '**Retired on `9 January 2027`: `its TestFlight date has passed`**' 'In the field'
expect "an edit of the set of a retired build passes" "$(check)" "passes"
rm -r "$repo/contracts/phone/1.0.0-1"
expect "a deletion of the set of a retired build passes" "$(check)" "passes"
printf '{"off":{}}\n' > "$repo/contracts/phone/1.0.0-2/live-activity/abbesses.json"
expect "an edit of the set of a build still in the field fails" "$(check)" "fails"
expect "the message names that set only" "$(said 'the recorded phone set contracts/phone/1.0.0-')" "1"
git -C "$repo" checkout -q -- contracts
table 'In the field' 'In the field'

# A new build gets a new folder.
table 'In the field' 'In the field' '| 1.0.0 (3) | 20 October 2026 | `abcdef1` | TestFlight | In the field |'
set_of 1.0.0-3
commit "build 3 and its set"
expect "a new set in its own folder passes" "$(check)" "passes"

printf '# Release\n\nNo table here.\n' > "$repo/guide.mdx"
expect "a guide with no table fails" "$(check)" "fails"
expect "the message says the table cannot be read" "$(said 'cannot be read')" "1"
git -C "$repo" checkout -q -- guide.mdx

git clone -q --depth 1 "file://$repo" "$state/shallow"
expect "a shallow clone fails" "$(check "$state/shallow")" "fails"
expect "the message asks for the whole history" "$(said 'git fetch --unshallow')" "1"

# The release: the newest build in the field, the last row that is not retired.
expect "the newest build with its set passes" "$(release)" "passes"
expect "its line says found" "$(cat "$state/out")" "Phone set of 1.0.0 (3): found"

table 'In the field' 'In the field' '| 1.0.0 (4) | 30 October 2026 | `abcdef2` | TestFlight | In the field |'
expect "the newest build with no set fails" "$(release)" "fails"
expect "its line says missing, and how to record it" "$(cat "$state/out")" \
    "Phone set of 1.0.0 (4): missing (no contracts/phone/1.0.0-4/: record it with make phone-set-record BUILD=1.0.0-4)"
set_of 1.0.0-4
expect "a set that git does not hold yet does not count" "$(release)" "fails"
commit "build 4 and its set"
expect "the set committed passes" "$(release)" "passes"

table 'In the field' 'In the field' '| 1.0.0 (5) | 31 October 2026 | `abcdef3` | TestFlight | Retired on 31 October 2026: never sent to testers |'
expect "a retired newest row is not the newest build in the field" "$(release)" "passes"
expect "its line names the build before it" "$(cat "$state/out")" "Phone set of 1.0.0 (2): found"

table 'Retired on 9 January 2027: gone' 'Retired on 9 January 2027: gone'
expect "no build in the field passes" "$(release)" "passes"
expect "its line says so" "$(cat "$state/out")" "Phone set: no build in the field"

printf '# Release\n\nNo table here.\n' > "$repo/guide.mdx"
expect "a guide with no table fails the release" "$(release)" "fails"
expect "its line says missing, and why" "$(said 'Phone set: missing (the table "The builds that riders may hold" of')" "1"

table 'In the field' 'In the field' '| 1.0.0 (5) | 31 October 2026 | `abcdef3` | TestFlight | In the field |'
GITHUB_STEP_SUMMARY="$state/summary" release > /dev/null
expect "in a workflow, the summary says 'missing'" "$(cat "$state/summary")" \
    "- Phone set of 1.0.0 (5): missing (no contracts/phone/1.0.0-5/: record it with make phone-set-record BUILD=1.0.0-5)"

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All phone set checks passed"
