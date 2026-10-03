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

cat > "$state/xcodebuild" << 'EOF'
#!/bin/sh
prefix=com.example
app_override=${FAKE_LOCAL_APP:-}
widget_override=${FAKE_LOCAL_WIDGET:-}
config=
for argument in "$@"; do
    case $argument in
        RATP_BUNDLE_ID_PREFIX=*) prefix=${argument#*=} ;;
        RATP_DEBUG_APP_BUNDLE_ID=*) app_override=${argument#*=} ;;
        RATP_DEBUG_WIDGET_BUNDLE_ID=*) widget_override=${argument#*=} ;;
        Debug | Release) config=$argument ;;
    esac
done
guard() {
    key=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_')
    if [ "${FAKE_GUARD:-yes}" = yes ] && { [ "$key" = io_github_valfur03_trome ] || [ "$key" = io_github_valfur03_trome_widget ]; }; then
        echo SHIPPING_ID_REFUSED
    else
        echo "$1"
    fi
}
if [ "$config" = Debug ]; then
    app=$(guard "${app_override:-$(printf "$FAKE_DEBUG_APP" "$prefix")}")
    if [ -n "$widget_override" ] && [ "${FAKE_READS_WIDGET:-yes}" = yes ]; then
        widget=$(guard "$widget_override")
    else
        widget=$(printf "$FAKE_DEBUG_WIDGET" "$app")
    fi
    style=Automatic
else
    app=$FAKE_RELEASE_APP
    widget=$app.widget
    style=$FAKE_RELEASE_STYLE
fi
printf 'Build settings for action build and target RATPActivity:\n'
[ -z "$app_override" ] || printf '    RATP_DEBUG_APP_BUNDLE_ID = %s\n' "$app_override"
[ -z "$widget_override" ] || printf '    RATP_DEBUG_WIDGET_BUNDLE_ID = %s\n' "$widget_override"
printf '    APP_BUNDLE_ID = %s\n    WIDGET_BUNDLE_ID = %s\n' "$app" "$widget"
printf '    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$style" "$app"
printf 'Build settings for action build and target RATPActivityWidget:\n    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$style" "$widget"
printf 'Build settings for action build and target RATPActivityUITests:\n    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s.trome.dev.uitests\n' "$style" "$prefix"
EOF
chmod +x "$state/xcodebuild"

check() {
    FAKE_DEBUG_APP=$1 FAKE_DEBUG_WIDGET=$2 FAKE_RELEASE_APP=$3 FAKE_RELEASE_STYLE=$4 XCODEBUILD="$state/xcodebuild" \
        "$scripts/bundle-id-check.sh" > /dev/null 2>&1 && echo passes || echo fails
}

check_local() {
    FAKE_LOCAL_APP=$1 FAKE_LOCAL_WIDGET=$2 FAKE_DEBUG_APP=%s.trome.dev FAKE_DEBUG_WIDGET=%s.widget \
        FAKE_RELEASE_APP=io.github.valfur03.trome FAKE_RELEASE_STYLE=Manual XCODEBUILD="$state/xcodebuild" \
        "$scripts/bundle-id-check.sh" --local > "$state/out" 2>&1 && echo passes || echo fails
}

expect "the IDs of the project pass" \
    "$(check %s.trome.dev %s.widget io.github.valfur03.trome Manual)" passes
expect "a Debug ID built from the prefix alone fails with the prefix of the App Store ID" \
    "$(FAKE_GUARD=no check %s.trome %s.widget io.github.valfur03.trome Manual)" fails
expect "a Debug ID equal to the shipping ID fails" \
    "$(FAKE_GUARD=no check io.github.valfur03.trome %s.widget io.github.valfur03.trome Manual)" fails
expect "a Debug extension ID that does not start with the app ID fails" \
    "$(check %s.trome.dev com.other.widget io.github.valfur03.trome Manual)" fails
expect "a Release ID that is not the shipping ID fails" \
    "$(check %s.trome.dev %s.widget io.github.valfur03.RATPActivity Manual)" fails
expect "a Release build signed automatically fails" \
    "$(check %s.trome.dev %s.widget io.github.valfur03.trome Automatic)" fails
expect "a project that lets a Debug ID override carry the shipping ID fails" \
    "$(FAKE_GUARD=no check %s.trome.dev %s.widget io.github.valfur03.trome Manual)" fails
expect "a project that does not read the extension ID override fails" \
    "$(FAKE_READS_WIDGET=no check %s.trome.dev %s.widget io.github.valfur03.trome Manual)" fails

expect "no Debug ID set in the local file passes" "$(check_local '' '')" passes
expect "the legacy pair set in the local file passes, as written" \
    "$(check_local io.github.valfur03.RATPActivity io.github.valfur03.RATPActivity.Widget)" passes
expect "only an app ID set in the local file passes" "$(check_local io.github.valfur03.RATPActivity '')" passes
expect "the shipping app ID as the app ID in the local file is refused" \
    "$(check_local io.github.valfur03.trome '')" fails
expect "the refusal says why in one sentence" \
    "$(grep -c 'RATP_DEBUG_APP_BUNDLE_ID in ios/Config/Local.xcconfig is io.github.valfur03.trome, a shipping ID: a free Apple account that signs it registers it for good' "$state/out")" 1
expect "the shipping extension ID as the extension ID in the local file is refused" \
    "$(check_local '' io.github.valfur03.trome.widget)" fails
expect "the shipping ID in capitals in the local file is refused" \
    "$(check_local IO.GITHUB.VALFUR03.TROME '')" fails
expect "the shipping app ID as the extension ID in the local file is refused" \
    "$(check_local io.github.valfur03.RATPActivity io.github.valfur03.trome)" fails
expect "an extension ID that is not under the app ID in the local file is refused" \
    "$(check_local io.github.valfur03.RATPActivity io.github.valfur03.Other.Widget)" fails
expect "an extension ID that only starts with the letters of the app ID is refused" \
    "$(check_local io.github.valfur03.RATPActivity io.github.valfur03.RATPActivityWidget)" fails
expect "an ID that the project reads as the shipping ID is refused" \
    "$(check_local io-github-valfur03-trome '')" fails
expect "the refusal of an ID that the project reads as the shipping ID says why" \
    "$(grep -c 'is too close to a shipping ID, so the project refuses it' "$state/out")" 1
expect "the IDs are not printed without --show" \
    "$(check_local io.github.valfur03.RATPActivity io.github.valfur03.RATPActivity.Widget > /dev/null; grep -c 'Debug bundle IDs' "$state/out")" 0
FAKE_LOCAL_APP=io.github.valfur03.RATPActivity FAKE_LOCAL_WIDGET=io.github.valfur03.RATPActivity.Widget \
    FAKE_DEBUG_APP=%s.trome.dev FAKE_DEBUG_WIDGET=%s.widget XCODEBUILD="$state/xcodebuild" \
    "$scripts/bundle-id-check.sh" --local --show > "$state/out" 2>&1 || true
expect "--show prints the Debug IDs that a build will use, so a mistyped setting name is seen before a Run" \
    "$(cat "$state/out")" "Debug bundle IDs: app io.github.valfur03.RATPActivity, Live Activity io.github.valfur03.RATPActivity.Widget"
FAKE_DEBUG_APP=%s.trome.dev FAKE_DEBUG_WIDGET=%s.widget XCODEBUILD="$state/xcodebuild" \
    "$scripts/bundle-id-check.sh" --local --show > "$state/out" 2>&1 || true
expect "--show prints the default Debug IDs when no Debug ID is set" \
    "$(cat "$state/out")" "Debug bundle IDs: app com.example.trome.dev, Live Activity com.example.trome.dev.widget"

[ "$failures" -eq 0 ]
