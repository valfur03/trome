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
config=
for argument in "$@"; do
    case $argument in
        RATP_BUNDLE_ID_PREFIX=*) prefix=${argument#*=} ;;
        Debug | Release) config=$argument ;;
    esac
done
if [ "$config" = Debug ]; then
    app=$(printf "$FAKE_DEBUG_APP" "$prefix")
    widget=$(printf "$FAKE_DEBUG_WIDGET" "$prefix")
    style=Automatic
else
    app=$FAKE_RELEASE_APP
    widget=$app.widget
    style=$FAKE_RELEASE_STYLE
fi
printf 'Build settings for action build and target RATPActivity:\n    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$style" "$app"
printf 'Build settings for action build and target RATPActivityWidget:\n    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$style" "$widget"
printf 'Build settings for action build and target RATPActivityUITests:\n    CODE_SIGN_STYLE = %s\n    PRODUCT_BUNDLE_IDENTIFIER = %s.trome.dev.uitests\n' "$style" "$prefix"
EOF
chmod +x "$state/xcodebuild"

check() {
    FAKE_DEBUG_APP=$1 FAKE_DEBUG_WIDGET=$2 FAKE_RELEASE_APP=$3 FAKE_RELEASE_STYLE=$4 XCODEBUILD="$state/xcodebuild" \
        "$scripts/bundle-id-check.sh" > /dev/null 2>&1 && echo passes || echo fails
}

expect "the IDs of the project pass" \
    "$(check %s.trome.dev %s.trome.dev.widget io.github.valfur03.trome Manual)" passes
expect "a Debug ID built from the prefix alone fails with the prefix of the prompter" \
    "$(check %s.trome %s.trome.widget io.github.valfur03.trome Manual)" fails
expect "a Debug ID equal to the shipping ID fails" \
    "$(check io.github.valfur03.trome io.github.valfur03.trome.widget io.github.valfur03.trome Manual)" fails
expect "a Debug extension ID that does not start with the app ID fails" \
    "$(check %s.trome.dev %s.widget io.github.valfur03.trome Manual)" fails
expect "a Release ID that is not the shipping ID fails" \
    "$(check %s.trome.dev %s.trome.dev.widget io.github.valfur03.RATPActivity Manual)" fails
expect "a Release build signed automatically fails" \
    "$(check %s.trome.dev %s.trome.dev.widget io.github.valfur03.trome Automatic)" fails

[ "$failures" -eq 0 ]
