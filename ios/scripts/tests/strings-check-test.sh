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

check() {
    "$scripts/strings-check.py" "$state/Localizable.xcstrings" > /dev/null 2>&1 && echo "passes" || echo "fails"
}

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated 'Prochains passages à %@')"
expect "a catalog with each text in French passes" "$(check)" "passes"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": {}"
expect "a new text with no French fails" "$(check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french needs_review 'Prochains passages à %@')"
expect "a French text that is not marked translated fails" "$(check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Next trains at %@\": $(french translated '')"
expect "an empty French text fails" "$(check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"RATP Activity\": {\"shouldTranslate\": false}"
expect "a text marked as not to translate passes" "$(check)" "passes"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Old text\": {\"extractionState\": \"stale\", \"localizations\": {\"fr\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"Vieux texte\"}}}}"
expect "a text that is no longer in the code fails" "$(check)" "fails"

catalog "\"Open Settings\": $(french translated 'Ouvrir Réglages'), \"Manual\": {\"extractionState\": \"manual\", \"localizations\": {\"fr\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"Manuel\"}}}}"
expect "a text added by hand passes" "$(check)" "passes"

catalog "\"%lld stations\": {\"localizations\": {\"fr\": {\"variations\": {\"plural\": {\"one\": {\"stringUnit\": {\"state\": \"translated\", \"value\": \"%lld station\"}}, \"other\": {\"stringUnit\": {\"state\": \"new\", \"value\": \"\"}}}}}}}"
expect "a plural with one case not translated fails" "$(check)" "fails"

printf '{"sourceLanguage": "en", "version": "1.0", "strings": {"Open Settings": %s}}' "$(french translated 'Ouvrir Réglages')" > "$state/Widget.xcstrings"
catalog "\"Next trains at %@\": {}"
expect "each catalog given is checked" \
    "$("$scripts/strings-check.py" "$state/Widget.xcstrings" "$state/Localizable.xcstrings" > /dev/null 2>&1 && echo "passes" || echo "fails")" "fails"

folder="$state/ios"
mkdir -p "$folder/App" "$folder/.build/Localizations"
printf 'committed' > "$folder/App/Localizable.xcstrings"
printf 'build output' > "$folder/.build/Localizations/Localizable.xcstrings"

sync() {
    (cd "$folder" && "$scripts/strings-sync.sh" "$@" > /dev/null 2>&1) && echo "passes" || echo "fails"
}

content() {
    cat "$1" 2> /dev/null || echo "missing"
}

expect "the check passes when Xcode changes no catalog" "$(sync check true)" "passes"
expect "the check fails when Xcode changes a catalog" "$(sync check sh -c 'printf synced > App/Localizable.xcstrings')" "fails"
expect "the check puts the catalog back as it was" "$(content "$folder/App/Localizable.xcstrings")" "committed"
expect "the check fails when Xcode adds a catalog" "$(sync check sh -c 'printf new > App/InfoPlist.xcstrings')" "fails"
expect "the check removes the catalog that Xcode added" "$(content "$folder/App/InfoPlist.xcstrings")" "missing"
expect "the check fails when Xcode removes a catalog" "$(sync check rm App/Localizable.xcstrings)" "fails"
expect "the check puts back the catalog that Xcode removed" "$(content "$folder/App/Localizable.xcstrings")" "committed"
expect "the check ignores the build folder" "$(sync check sh -c 'printf other > .build/Localizations/Localizable.xcstrings')" "passes"
expect "the check fails when the Xcode command fails" "$(sync check sh -c 'printf half > App/Localizable.xcstrings; exit 1')" "fails"
expect "a failed Xcode command leaves the catalog as it was" "$(content "$folder/App/Localizable.xcstrings")" "committed"
stop_check() {
    rm -f "$folder/.build/started"
    (cd "$folder" && exec "$scripts/strings-sync.sh" check sh -c \
        'printf synced > App/Localizable.xcstrings; printf new > App/InfoPlist.xcstrings; touch .build/started; sleep 1') \
        > /dev/null 2>&1 &
    check_pid=$!
    tries=0
    while [ ! -f "$folder/.build/started" ] && [ "$tries" -lt 100 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    kill -TERM "$check_pid"
    wait "$check_pid" && echo "passes" || echo "fails"
}

expect "a stopped check fails" "$(stop_check)" "fails"
expect "a stopped check puts the catalog back as it was" "$(content "$folder/App/Localizable.xcstrings")" "committed"
expect "a stopped check removes the catalog that Xcode added" "$(content "$folder/App/InfoPlist.xcstrings")" "missing"
expect "the sync passes when Xcode changes a catalog" "$(sync sync sh -c 'printf synced > App/Localizable.xcstrings')" "passes"
expect "the sync keeps the change of Xcode" "$(content "$folder/App/Localizable.xcstrings")" "synced"
expect "the sync fails when the Xcode command fails" "$(sync sync false)" "fails"
expect "an unknown mode fails" "$(sync format true)" "fails"

[ "$failures" -eq 0 ]
