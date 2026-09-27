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

french() {
    printf '{"localizations": {"fr": {"stringUnit": {"state": "%s", "value": "%s"}}}}' "$1" "$2"
}

catalog() {
    printf '{"sourceLanguage": "en", "version": "1.0", "strings": {%s}}' "$1" > "$state/Localizable.xcstrings"
}

stringsdata() {
    printf '{"source": "%s", "tables": {"Localizable": [%s]}}' "$1" "$2" > "$state/$3.stringsdata"
}

key() {
    printf '{"comment": "", "key": "%s"}' "$1"
}

code_check() {
    "$scripts/strings-check.py" code "$state/Localizable.xcstrings" "$state"/*.stringsdata > /dev/null 2>&1 \
        && echo "passes" || echo "fails"
}

touch "$state/View.swift"
stringsdata "$state/View.swift" "$(key "Open Settings"), $(key "Next trains at %@")" View

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@')"
expect "a catalog with each used text in French passes" "$(code_check)" "passes"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages')"
expect "a used text that is not in the catalog fails" "$(code_check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": {}"
expect "a text with no French fails" "$(code_check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french needs_review 'Prochains passages à %@')"
expect "a French text that is not marked translated fails" "$(code_check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": {\"shouldTranslate\": false}"
expect "a text marked as not to translate passes" "$(code_check)" "passes"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@'), \"Old text\": $(french translated 'Vieux texte')"
expect "a text that is no longer in the code fails" "$(code_check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@'), \"Manual\": {\"extractionState\": \"manual\", \"localizations\": {\"fr\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"Manuel\"}}}}"
expect "a text added by hand passes" "$(code_check)" "passes"

catalog "\"%lld stations\": {\"localizations\": {\"fr\": {\"variations\": {\"plural\": {\"one\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"%lld station\"}}, \"other\": {\"stringUnit\": {\"state\": \"new\", \"value\": \"\"}}}}}}}, \"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@')"
stringsdata "$state/View.swift" "$(key "Open Settings"), $(key "Next trains at %@"), $(key "%lld stations")" View
expect "a plural with one case not translated fails" "$(code_check)" "fails"

stringsdata "$state/View.swift" "$(key "Open Settings"), $(key "Next trains at %@")" View
stringsdata "$state/Removed.swift" "$(key "Removed text")" Removed
catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@')"
expect "the texts of a source file that no longer exists are ignored" "$(code_check)" "passes"

plist() {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>%s</dict></plist>\n' "$1" > "$state/Info.plist"
}

info_catalog() {
    printf '{"sourceLanguage": "en", "version": "1.0", "strings": {"NSLocationWhenInUseUsageDescription": {"localizations": {"en": {"stringUnit": {"state": "new", "value": "%s"}}, "fr": {"stringUnit": {"state": "%s", "value": "Pour trouver la station"}}}}}}' "$1" "$2" > "$state/InfoPlist.xcstrings"
}

info_check() {
    "$scripts/strings-check.py" info-plist "$state/InfoPlist.xcstrings" "$state/Info.plist" > /dev/null 2>&1 \
        && echo "passes" || echo "fails"
}

plist '<key>CFBundleDisplayName</key><string>RATP Activity</string><key>NSLocationWhenInUseUsageDescription</key><string>To find the station</string>'
info_catalog "To find the station" translated
expect "a permission text with its French text passes" "$(info_check)" "passes"

info_catalog "To find the station" new
expect "a permission text with no French text fails" "$(info_check)" "fails"

info_catalog "An old English text" translated
expect "a permission text whose English is not the one of the Info.plist fails" "$(info_check)" "fails"

plist '<key>NSLocationWhenInUseUsageDescription</key><string>To find the station</string><key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>Also when closed</string>'
info_catalog "To find the station" translated
expect "a permission text that is not in the catalog fails" "$(info_check)" "fails"

plist '<key>CFBundleDisplayName</key><string>RATP Activity</string>'
expect "a catalog text that is not in the Info.plist fails" "$(info_check)" "fails"

[ "$failures" -eq 0 ]
