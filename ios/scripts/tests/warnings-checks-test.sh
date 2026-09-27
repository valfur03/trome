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

build_warnings() {
    echo "$1" | "$scripts/build-warnings.py" > /dev/null 2>&1 && echo "passes" || echo "fails"
}

settings_check() {
    printf 'name: RATPActivity\n\noptions:\n  xcodeVersion: "%s"\n' "$1" > "$state/project.yml"
    "$scripts/recommended-settings-check.sh" "$state/project.yml" "Xcode $2" > /dev/null 2>&1 && echo "passes" || echo "fails"
}

expect "a build with no warning passes" "$(build_warnings '{"warnings": [], "analyzerWarnings": [], "errors": []}')" "passes"
expect "a build with a warning fails" "$(build_warnings '{"warnings": [{"issueType": "Swift Compiler Warning", "message": "unused"}], "analyzerWarnings": []}')" "fails"
expect "a build with an analyzer warning fails" "$(build_warnings '{"warnings": [], "analyzerWarnings": [{"issueType": "Analyzer", "message": "leak"}]}')" "fails"
expect "unreadable build results fail" "$(build_warnings '')" "fails"
expect "the warning shows its file and line" \
    "$(echo '{"warnings": [{"issueType": "Swift Compiler Warning", "message": "unused", "targetName": "RATPActivity", "sourceURL": "file:///repo/App/ContentView.swift#EndingLineNumber=11&StartingLineNumber=11"}]}' | "$scripts/build-warnings.py" 2> /dev/null || true)" \
    "warning: [RATPActivity] ContentView.swift:12: unused"

expect "the settings check passes with the Xcode that checked the settings" "$(settings_check 27.0 27.0)" "passes"
expect "the settings check passes with a bug fix release of that Xcode" "$(settings_check 27.0 27.0.1)" "passes"
expect "the settings check passes with an older Xcode" "$(settings_check 27.0 26.4)" "passes"
expect "the settings check fails with a newer minor Xcode" "$(settings_check 27.0 27.1)" "fails"
expect "the settings check fails with a newer major Xcode" "$(settings_check 27.0 28.0)" "fails"
printf 'name: RATPActivity\n' > "$state/project.yml"
expect "the settings check fails when project.yml has no xcodeVersion" \
    "$("$scripts/recommended-settings-check.sh" "$state/project.yml" "Xcode 27.0" > /dev/null 2>&1 && echo "passes" || echo "fails")" "fails"

[ "$failures" -eq 0 ]
