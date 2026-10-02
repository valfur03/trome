#!/bin/sh
set -eu

shipping_app=io.github.valfur03.trome
shipping_widget=$shipping_app.widget
shipping_prefix=io.github.valfur03
app_target=RATPActivity
widget_target=RATPActivityWidget
project=${1:-RATPActivity.xcodeproj}
xcodebuild=${XCODEBUILD:-xcodebuild}
failed=0

fail() {
    echo "bundle-id-check: FAILED: $1" >&2
    failed=1
}

settings() {
    "$xcodebuild" -showBuildSettings -project "$project" -alltargets "$@" 2> /dev/null \
        | awk '
            /^Build settings for action build and target / { target = $NF; sub(/:$/, "", target) }
            /^ +PRODUCT_BUNDLE_IDENTIFIER = / { id[target] = $3 }
            /^ +CODE_SIGN_STYLE = / { style[target] = $3 }
            END { for (t in id) print t, id[t], style[t] }
        '
}

id_of() {
    echo "$1" | awk -v target="$2" '$1 == target { print $2 }'
}

style_of() {
    echo "$1" | awk -v target="$2" '$1 == target { print $3 }'
}

check_debug() {
    label=$1
    shift
    debug=$(settings -configuration Debug "$@")
    [ -n "$debug" ] || { fail "could not read the Debug build settings ($label)"; return; }
    app=$(id_of "$debug" "$app_target")
    widget=$(id_of "$debug" "$widget_target")
    for id in $(echo "$debug" | awk '{ print $2 }'); do
        if [ "$id" = "$shipping_app" ] || [ "$id" = "$shipping_widget" ]; then
            fail "a Debug build ($label) has the shipping bundle ID $id: a free Apple account that signs it registers it for good (decision-43)"
        fi
    done
    case $widget in
        "$app".*) ;;
        *) fail "the Debug ID of the extension ($widget) does not start with the app ID ($app.) ($label)" ;;
    esac
}

check_release() {
    release=$(settings -configuration Release)
    [ -n "$release" ] || { fail "could not read the Release build settings"; return; }
    [ "$(id_of "$release" "$app_target")" = "$shipping_app" ] \
        || fail "the Release ID of the app is $(id_of "$release" "$app_target"), not $shipping_app"
    [ "$(id_of "$release" "$widget_target")" = "$shipping_widget" ] \
        || fail "the Release ID of the extension is $(id_of "$release" "$widget_target"), not $shipping_widget"
    for target in "$app_target" "$widget_target"; do
        [ "$(style_of "$release" "$target")" = Manual ] \
            || fail "Release signs $target automatically: Xcode would register the shipping ID with the team of whoever archives it"
    done
}

check_debug "the prefix set in ios/Config"
check_debug "the prefix $shipping_prefix" RATP_BUNDLE_ID_PREFIX="$shipping_prefix"
check_release

[ "$failed" -eq 0 ] || exit 1
echo "bundle-id-check: OK (Debug builds never carry $shipping_app; Release carries it and is not signed automatically)"
