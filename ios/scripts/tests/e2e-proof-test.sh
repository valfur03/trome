#!/bin/sh
# The record of a full E2E pass on the Mac, and its reader: the release must refuse a commit of main whose tree the
# full E2E suite never passed on, and must accept one that make merge tested, or that changes no app code since.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
proof="$tests/../e2e-proof.sh"
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GITHUB_STEP_SUMMARY GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true
export PATH="$tests/bin:$PATH" FAKE_GH_STATE="$state/gh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir "$FAKE_GH_STATE"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

commit() {
    mkdir -p "$repo/$(dirname "$1")"
    echo "$2" > "$repo/$1"
    git -C "$repo" add "$1"
    git -C "$repo" commit -q -m "change $1"
    git -C "$repo" rev-parse HEAD
}

# The output and the exit status of the reader on the commit $1.
read_proof() {
    (cd "$repo" && "$proof" read "$1" > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?")
}

line() {
    grep "^$1: " "$state/out" || echo "no line"
}

publish() {
    (cd "$repo" && "$proof" publish "$@")
}

# A status of the commit $1 by $2, as GitHub keeps it (the newest first).
status() {
    file="$FAKE_GH_STATE/statuses/$1.json"
    old=$(cat "$file" 2> /dev/null || echo '[]')
    printf '%s' "$old" | jq --arg login "$2" --arg state "$3" --arg context "$4" --arg description "$5" \
        '[{state: $state, context: $context, description: $description, creator: {login: $login}}] + .' > "$file.new"
    mv "$file.new" "$file"
}

tree() {
    git -C "$repo" rev-parse "$1^{tree}"
}

git init -q -b main "$repo"
mkdir -p "$FAKE_GH_STATE/statuses"
first=$(commit ios/App/First.swift first)

expect "a commit with no record is refused" "$(read_proof "$first")" "exit 1"
expect "its line says that the proof is missing, and why" "$(line "E2E proof")" \
    "E2E proof: missing ($(git -C "$repo" rev-parse --short "$first") changes app code, and has no record of a full E2E pass on the Mac)"
expect "with no record, the render counts are missing" "$(line "render counts")" "render counts: missing"

publish "$first" "too tall 1, cut texts 4, breaches 2"
expect "make merge writes one status named 'E2E on the Mac', a success" \
    "$(jq -r '.[] | [.context, .state] | @tsv' "$FAKE_GH_STATE/statuses/$first.json")" "$(printf 'E2E on the Mac\tsuccess')"
expect "its text names the tree of the commit, and the render counts" "$(jq -r '.[0].description' "$FAKE_GH_STATE/statuses/$first.json")" \
    "Full E2E passed on tree $(tree "$first"). Render: too tall 1, cut texts 4, breaches 2."
expect "its text fits the 140 characters of a status of GitHub, with the largest counts" \
    "$(cd "$repo" && "$proof" publish "$first" "too tall 999, cut texts 999, breaches 999" && jq -r '.[0].description | length <= 140' "$FAKE_GH_STATE/statuses/$first.json")" "true"
rm "$FAKE_GH_STATE/statuses/$first.json"
publish "$first" "too tall 1, cut texts 4, breaches 2"
expect "a commit with the record of the owner is accepted" "$(read_proof "$first")" "exit 0"
expect "its line says that the proof is found, on this tree" "$(line "E2E proof")" \
    "E2E proof: found (the full E2E suite passed on the Mac on this tree)"
expect "the render counts of the record are shown" "$(line "render counts")" \
    "render counts: too tall 1, cut texts 4, breaches 2 (drawn on the Mac on $(git -C "$repo" rev-parse --short "$first"))"

docs=$(commit docs/page.md docs)
claude=$(commit .claude/rules/rule.md rule)
expect "a commit that changes no app code since a tested commit is accepted (make merge skips the suite for it)" "$(read_proof "$claude")" "exit 0"
expect "its line names the tested commit and the commits since" "$(line "E2E proof")" \
    "E2E proof: found (the full E2E suite passed on the Mac on $(git -C "$repo" rev-parse --short "$first"); the 2 commits since change no app code)"
expect "it shows the render counts of the tested commit" "$(line "render counts")" \
    "render counts: too tall 1, cut texts 4, breaches 2 (drawn on the Mac on $(git -C "$repo" rev-parse --short "$first"))"

app=$(commit ios/App/Second.swift second)
expect "a commit that changes app code after the tested commit, with no record, is refused" "$(read_proof "$app")" "exit 1"
expect "a later change to main makes the old record not count" "$(line "E2E proof")" \
    "E2E proof: missing ($(git -C "$repo" rev-parse --short "$app") changes app code, and has no record of a full E2E pass on the Mac)"
expect "app code that the views do not draw keeps the render counts of the tested commit" "$(line "render counts")" \
    "render counts: too tall 1, cut texts 4, breaches 2 (drawn on the Mac on $(git -C "$repo" rev-parse --short "$first"))"

status "$app" owner success "E2E on the Mac" "Full E2E passed on tree $(tree "$app"). Render: not drawn."
expect "a record whose merge did not draw the views is a proof" "$(read_proof "$app")" "exit 0"
expect "its render counts are the ones of the last drawing" "$(line "render counts")" \
    "render counts: too tall 1, cut texts 4, breaches 2 (drawn on the Mac on $(git -C "$repo" rev-parse --short "$first"))"

widget=$(commit ios/Widget/View.swift view)
status "$widget" owner success "E2E on the Mac" "Full E2E passed on tree $(tree "$widget"). Render: not drawn."
expect "a change of the views with no drawing: the proof is found" "$(read_proof "$widget")" "exit 0"
expect "but the render counts are missing" "$(line "render counts")" "render counts: missing"

forged=$(commit ios/App/Third.swift third)
status "$forged" "github-actions[bot]" success "E2E on the Mac" "Full E2E passed on tree $(tree "$forged"). Render: not drawn."
status "$forged" someone success "E2E on the Mac" "Full E2E passed on tree $(tree "$forged"). Render: not drawn."
expect "a record written by a workflow or by another account than the owner does not count" "$(read_proof "$forged")" "exit 1"
status "$forged" owner failure "E2E on the Mac" "Full E2E passed on tree $(tree "$forged"). Render: not drawn."
status "$forged" owner success "Another check" "Full E2E passed on tree $(tree "$forged"). Render: not drawn."
expect "a status of the owner that is not a success, or of another name, does not count" "$(read_proof "$forged")" "exit 1"
status "$forged" owner success "E2E on the Mac" "Full E2E passed on tree $(tree "$first"). Render: not drawn."
expect "a record that names another tree does not count" "$(read_proof "$forged")" "exit 1"
status "$forged" owner success "E2E on the Mac" "Full E2E passed on tree $(tree "$forged"). Render: not drawn."
expect "the record of the owner, on the tree of the commit, counts among the others" "$(read_proof "$forged")" "exit 0"

tests_only=$(commit ios/Packages/TROMECore/Tests/RuleTests.swift test)
expect "a change of the unit tests only is not app code" "$(read_proof "$tests_only")" "exit 0"

touch "$FAKE_GH_STATE/fail"
expect "when GitHub cannot be read, the proof is missing, with exit 2" "$(read_proof "$forged")" "exit 2"
expect "its line says why" "$(line "E2E proof")" "E2E proof: missing (GitHub could not be read: error connecting to api.github.com)"
rm "$FAKE_GH_STATE/fail"

export GITHUB_STEP_SUMMARY="$state/summary.md"
read_proof "$app" > /dev/null
expect "in a workflow, the summary says 'E2E proof: found'" "$(grep -c '^- E2E proof: found ' "$GITHUB_STEP_SUMMARY")" "1"
expect "and gives the render counts, shown and not compared" "$(grep -c -e '^- render counts: too tall 1' -e '^- The render counts are shown, not compared' "$GITHUB_STEP_SUMMARY")" "2"
: > "$GITHUB_STEP_SUMMARY"
read_proof "$(commit ios/App/Fourth.swift fourth)" > /dev/null
expect "in a workflow, the summary says 'E2E proof: missing'" "$(grep -c '^- E2E proof: missing ' "$GITHUB_STEP_SUMMARY")" "1"
unset GITHUB_STEP_SUMMARY

: > "$FAKE_GH_STATE/calls"
long=$(commit docs/0.md 0)
i=1
while [ "$i" -le 4 ]; do
    long=$(commit "docs/$i.md" "$i")
    i=$((i + 1))
done
expect "the reader looks back at most TROME_E2E_PROOF_MAX_WALK commits" \
    "$(cd "$repo" && TROME_E2E_PROOF_MAX_WALK=3 "$proof" read "$long" | head -n 1)" "E2E proof: missing (no record in the last 3 commits)"
expect "and asks GitHub once per commit, plus once for the owner" "$(wc -l < "$FAKE_GH_STATE/calls" | tr -d ' ')" "4"

cat > "$state/render.txt" << 'EOF'
== Language: fr
Renders: 410 (every station and page). Images: 410, in /x
Too tall for their text size, in fr: 2 (list: /x/too-tall.csv)
      2 lock XXXL (limit 160 pt)
Cut texts in the images (OCR, for a person to read): 17 (list: /x/cut-texts.txt)
Breaches of the cut rules (texts cut too much), in the images of 30 stations: 3 (list: /x/breaches.txt)
Other cut texts (not a time, a destination, a label or a station name; a person reads them): 1
EOF
expect "the counts are read from the output of the render check" "$("$proof" render-counts "$state/render.txt")" "too tall 2, cut texts 17, breaches 3"
sed '/^Cut texts/d' "$state/render.txt" > "$state/render-no-ocr.txt"
expect "an output with no cut texts (the text recognition failed) gives no counts" "$("$proof" render-counts "$state/render-no-ocr.txt")" ""

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "e2e-proof: all tests passed"
