#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
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

long=$(printf 'word %.0s' $(seq 1 81))
limit=$(printf 'x%.0s' $(seq 1 400))

readme() {
    printf '%s\n' "$@" > "$state/README.md"
}

check() {
    "$scripts/prose-check.py" "$state/README.md" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

readme "# Title" "" "One sentence." "Another sentence." "$limit"
expect "short lines and a line of exactly 400 characters pass" "$(check)" "passes"

readme "# Title" "" "One sentence." "$long"
expect "a line of prose longer than 400 characters fails" "$(check)" "fails"
expect "the message names the file and the line" \
    "$(grep -c "README.md:4: 405 characters, more than 400" "$state/out")" "1"
expect "the message says what to do" "$(grep -c "one sentence per line" "$state/out")" "1"
expect "the message says why" "$(grep -c "git merges by line" "$state/out")" "1"

readme "- An item." "  $long"
expect "a long line of a list item fails" "$(check)" "fails"

readme "Text." "" '```sh' "$long" '```' "" "More text."
expect "a long line in a code block passes" "$(check)" "passes"

readme "- An item:" "" '  ```sh' "  $long" '  ```'
expect "a long line in an indented code block of a list item passes" "$(check)" "passes"

readme '````md' '```' "$long" '```' '````' "$long"
expect "a code block ends only at its own fence" "$(check)" "fails"

readme "| Command | What it does |" "|---|---|" "| \`make\` | $long |"
expect "a long table row passes" "$(check)" "passes"

readme '```sh' "make check" '```' "$long"
expect "a long line after a code block fails" "$(check)" "fails"


"$scripts/prose-check.py" "$state/missing.md" > /dev/null 2>&1 && result="passes" || result="fails"
expect "a missing file fails" "$result" "fails"

"$scripts/prose-check.py" --all > /dev/null 2>&1 && result="passes" || result="fails"
expect "an option fails" "$result" "fails"

repo="$state/repo"
git init -q "$repo"
mkdir "$repo/docs"
in_repo() {
    printf '%s\n' "$2" > "$repo/$1"
    git -C "$repo" add "$1"
}
check_repo() {
    (cd "$repo/docs" && "$scripts/prose-check.py") > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

in_repo README.md "One sentence."
in_repo docs/page.mdx "One sentence."
in_repo CLAUDE.md "One sentence."
in_repo notes.txt "$long"
printf '%s\n' "$long" > "$repo/untracked.md"
expect "with no file, it checks the Markdown and MDX files of the repo, from any folder of it" "$(check_repo)" "passes"
expect "it counts the files that it checked" "$(grep -c "OK (3 files" "$state/out")" "1"

in_repo docs/page.mdx "$long"
expect "a long line of an MDX file of the repo fails" "$(check_repo)" "fails"
expect "the message names the file from the root of the repo" \
    "$(grep -c "^prose-check: docs/page.mdx:1: 405 characters" "$state/out")" "1"

in_repo docs/page.mdx "One sentence."
in_repo docs/guide.md "$long"
expect "a long line of a Markdown file in a folder fails" "$(check_repo)" "fails"

in_repo docs/guide.md "One sentence."
in_repo CLAUDE.md "$long"
expect "CLAUDE.md is checked like every Markdown file" "$(check_repo)" "fails"

(cd "$state" && "$scripts/prose-check.py") > /dev/null 2>&1 && result="passes" || result="fails"
expect "with no file, outside a git repo, it fails" "$result" "fails"

[ "$failures" -eq 0 ]
