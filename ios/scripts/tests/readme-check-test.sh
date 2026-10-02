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

long=$(printf 'word %.0s' $(seq 1 81))
limit=$(printf 'x%.0s' $(seq 1 400))

readme() {
    printf '%s\n' "$@" > "$state/README.md"
}

check() {
    "$scripts/readme-check.py" "$state/README.md" > "$state/out" 2>&1 && echo "passes" || echo "fails"
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

"$scripts/readme-check.py" > /dev/null 2>&1 && result="passes" || result="fails"
expect "no file given fails" "$result" "fails"

"$scripts/readme-check.py" "$state/missing.md" > /dev/null 2>&1 && result="passes" || result="fails"
expect "a missing file fails" "$result" "fails"

[ "$failures" -eq 0 ]
