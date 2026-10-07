#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../app-icon-check.py"
state=$(mktemp -d)
icons="$state/AppIcon.appiconset"
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

passes() {
    if "$script" "$icons" > "$state/out" 2>&1; then echo yes; else echo no; fi
}

says() {
    if grep -qF -- "$1" "$state/out"; then echo yes; else cat "$state/out"; echo no; fi
}

contents() {
    printf '{"images":[%s],"info":{"author":"xcode","version":1}}' "$1" > "$icons/Contents.json"
}

store_icon='{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}'

expect "an app with no icon set fails" "$(passes)" no
expect "it says that the app has no icon" "$(says 'the app has no icon')" yes

mkdir -p "$icons"
contents ""
expect "an icon set with no image fails" "$(passes)" no
expect "it asks for a 1024 x 1024 PNG image" "$(says 'Add a 1024 x 1024 PNG image')" yes

contents '{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"Dark.png","idiom":"universal","platform":"ios","size":"1024x1024"}'
expect "an icon set with only a dark icon fails" "$(passes)" no

contents "$store_icon"
expect "an icon set whose image file is missing fails" "$(passes)" no
expect "it says that the file is missing" "$(says 'the icon file is missing')" yes

"$tests/make-png.py" "$icons/AppIcon.png" 1024 1024 opaque
expect "a 1024 x 1024 PNG with no alpha channel passes" "$(passes)" yes

"$tests/make-png.py" "$icons/AppIcon.png" 512 512 opaque
expect "a 512 x 512 PNG fails" "$(passes)" no
expect "it gives the size and the size that the App Store needs" "$(says 'the icon is 512 x 512 pixels; the App Store needs a square of 1024 x 1024')" yes

"$tests/make-png.py" "$icons/AppIcon.png" 1024 1000 opaque
expect "a PNG that is not square fails" "$(passes)" no

for kind in alpha clear trns; do
    "$tests/make-png.py" "$icons/AppIcon.png" 1024 1024 "$kind"
    expect "a PNG with an alpha channel ($kind) fails" "$(passes)" no
done
expect "it says that the App Store refuses an alpha channel" "$(says 'the icon has an alpha channel (transparency); the App Store refuses it')" yes

printf 'not a png' > "$icons/AppIcon.png"
expect "a file that is not a PNG fails" "$(passes)" no
expect "it says that the icon is not a PNG" "$(says 'the icon is not a PNG image')" yes

[ "$failures" -eq 0 ] || exit 1
