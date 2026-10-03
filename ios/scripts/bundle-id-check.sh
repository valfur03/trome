#!/bin/sh
set -eu

shipping_app=io.github.valfur03.trome
shipping_widget=$shipping_app.widget
shipping_prefix=io.github.valfur03
app_target=RATPActivity
widget_target=RATPActivityWidget
app_override=RATP_DEBUG_APP_BUNDLE_ID
widget_override=RATP_DEBUG_WIDGET_BUNDLE_ID
sample_app=io.github.valfur03.RATPActivity
sample_widget=$sample_app.Widget
mode=all
show=no
if [ "${1:-}" = --local ]; then
    mode=local
    shift
fi
if [ "$mode" = local ] && [ "${1:-}" = --show ]; then
    show=yes
    shift
fi
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

is_shipping() {
    lowered=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ "$lowered" = "$shipping_app" ] || [ "$lowered" = "$shipping_widget" ]
}

check_local() {
    configured=$("$xcodebuild" -showBuildSettings -project "$project" -target "$app_target" -configuration Debug 2> /dev/null \
        | awk -v app="$app_override" -v widget="$widget_override" '
            $1 == app || $1 == widget || $1 == "APP_BUNDLE_ID" || $1 == "WIDGET_BUNDLE_ID" { print $1, $3 }
        ')
    [ -n "$configured" ] || { fail "could not read the Debug build settings of $app_target"; return; }
    for setting in "$app_override" "$widget_override"; do
        value=$(echo "$configured" | awk -v name="$setting" '$1 == name { print $2 }')
        if [ -n "$value" ] && is_shipping "$value"; then
            fail "$setting in ios/Config/Local.xcconfig is $value, a shipping ID: a free Apple account that signs it registers it for good, and the paid account can never take it"
        fi
    done
    [ "$failed" -eq 0 ] || return 0
    app=$(echo "$configured" | awk '$1 == "APP_BUNDLE_ID" { print $2 }')
    widget=$(echo "$configured" | awk '$1 == "WIDGET_BUNDLE_ID" { print $2 }')
    case "$app $widget" in
        *SHIPPING_ID_REFUSED*)
            fail "a Debug ID in ios/Config/Local.xcconfig is too close to a shipping ID, so the project refuses it (app $app, extension $widget): use another ID"
            return 0 ;;
    esac
    case $widget in
        "$app".*) ;;
        *) fail "the Debug ID of the extension ($widget) does not start with the Debug ID of the app ($app) and a dot: iOS installs an extension only under the ID of its app (set $widget_override in ios/Config/Local.xcconfig to $app.<name>, or remove it)" ;;
    esac
}

check_debug() {
    label=$1
    shift
    debug=$(settings -configuration Debug "$@")
    [ -n "$debug" ] || { fail "could not read the Debug build settings ($label)"; return; }
    app=$(id_of "$debug" "$app_target")
    widget=$(id_of "$debug" "$widget_target")
    for id in $(echo "$debug" | awk '{ print $2 }'); do
        if is_shipping "$id"; then
            fail "a Debug build ($label) has the shipping bundle ID $id: a free Apple account that signs it registers it for good, and the paid account can never take it"
        fi
    done
    case $widget in
        "$app".*) ;;
        *) fail "the Debug ID of the extension ($widget) does not start with the app ID ($app.) ($label)" ;;
    esac
}

check_override_refused() {
    label=$1
    shift
    debug=$(settings -configuration Debug "$@")
    [ -n "$debug" ] || { fail "could not read the Debug build settings ($label)"; return; }
    for id in $(echo "$debug" | awk '{ print $2 }'); do
        if is_shipping "$id"; then
            fail "a Debug build with $label has the shipping bundle ID $id: the project must refuse it also when Xcode builds with no make command"
        fi
    done
}

check_override_used() {
    label=$1
    expected_app=$2
    expected_widget=$3
    shift 3
    debug=$(settings -configuration Debug "$@")
    [ -n "$debug" ] || { fail "could not read the Debug build settings ($label)"; return; }
    [ "$(id_of "$debug" "$app_target")" = "$expected_app" ] \
        || fail "a Debug build with $label has the app ID $(id_of "$debug" "$app_target"), not $expected_app"
    [ "$(id_of "$debug" "$widget_target")" = "$expected_widget" ] \
        || fail "a Debug build with $label has the extension ID $(id_of "$debug" "$widget_target"), not $expected_widget"
}

check_release() {
    label=$1
    shift
    release=$(settings -configuration Release "$@")
    [ -n "$release" ] || { fail "could not read the Release build settings ($label)"; return; }
    [ "$(id_of "$release" "$app_target")" = "$shipping_app" ] \
        || fail "the Release ID of the app is $(id_of "$release" "$app_target"), not $shipping_app ($label)"
    [ "$(id_of "$release" "$widget_target")" = "$shipping_widget" ] \
        || fail "the Release ID of the extension is $(id_of "$release" "$widget_target"), not $shipping_widget ($label)"
    for target in "$app_target" "$widget_target"; do
        [ "$(style_of "$release" "$target")" = Manual ] \
            || fail "Release signs $target automatically: Xcode would register the shipping ID with the team of whoever archives it ($label)"
    done
}

check_local
if [ "$mode" = local ]; then
    [ "$failed" -eq 0 ] || exit 1
    [ "$show" = no ] || echo "Debug bundle IDs: app $app, Live Activity $widget"
    exit 0
fi

upper_app=$(echo "$shipping_app" | tr '[:lower:]' '[:upper:]')
upper_widget=$(echo "$shipping_widget" | tr '[:lower:]' '[:upper:]')
check_debug "the IDs set in ios/Config"
check_debug "the prefix $shipping_prefix" RATP_BUNDLE_ID_PREFIX="$shipping_prefix"
check_override_refused "the shipping app ID as the app ID" "$app_override=$shipping_app"
check_override_refused "the shipping extension ID as the extension ID" "$widget_override=$shipping_widget"
check_override_refused "the shipping IDs in capitals" "$app_override=$upper_app" "$widget_override=$upper_widget"
check_override_refused "the shipping IDs swapped" "$app_override=$shipping_widget" "$widget_override=$shipping_app"
check_override_used "only an app ID set" "$sample_app" "$sample_app.widget" "$app_override=$sample_app"
check_override_used "both IDs set" "$sample_app" "$sample_widget" "$app_override=$sample_app" "$widget_override=$sample_widget"
check_release "the IDs set in ios/Config"
check_release "Debug IDs set" "$app_override=$sample_app" "$widget_override=$sample_widget"

[ "$failed" -eq 0 ] || exit 1
echo "bundle-id-check: OK (Debug builds never carry $shipping_app, also with Debug IDs set; Release carries it and is not signed automatically)"
