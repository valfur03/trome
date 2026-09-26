#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/.build"
work="$build/live-key-check"
app_plist="$build/DerivedData/Build/Products/Debug-iphonesimulator/RATPActivity.app/Info.plist"
fake="LEAKCHECK$(date +%s)$$"
shared_cache="${SHARED_CACHE:?}"

fail() {
    echo "live-key-check: FAILED: $1" >&2
    exit 1
}

build_app() {
    log="$work/$1.log"
    shift
    make -C "$root" --no-print-directory build "$@" > "$log" 2>&1 || {
        cat "$log" >&2
        fail "the build failed ($*)"
    }
    ! grep -qF "$fake" "$log" || fail "the build output shows the key ($*)"
}

new_logs_show_key() {
    find "$build/DerivedData/Logs" -newer "$work/start" -name '*.xcactivitylog' 2> /dev/null | while read -r activity_log; do
        if gzip -dc "$activity_log" | grep -qF "$fake"; then
            echo "$activity_log"
        fi
    done
    find "$build" -newer "$work/start" -name '*.xcresult' -prune -exec grep -rlF "$fake" {} + 2> /dev/null || true
}

rm -rf "$work"
mkdir -p "$work"
printf 'PRIM_API_KEY = %s\n' "$fake" > "$work/Secrets.xcconfig"
touch "$work/start"

build_app live LIVE=1 PRIM_SECRETS="$work/Secrets.xcconfig"
grep -qF "$fake" "$app_plist" || fail "the LIVE=1 build did not put the key in the app"
[ ! -e "$build/Live.xcconfig" ] || fail "the LIVE=1 build left .build/Live.xcconfig behind"
! grep -rqF "$fake" "$shared_cache" 2> /dev/null || fail "the shared build cache $shared_cache holds the key"

build_app normal LIVE= PRIM_SECRETS="$work/Secrets.xcconfig"
! grep -qF "$fake" "$app_plist" || fail "the build without LIVE=1 kept the key in the app"

leaks=$(new_logs_show_key)
[ -z "$leaks" ] || fail "these build logs or result bundles show the key: $leaks"

git -C "$root" check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore ios/Config/Secrets.xcconfig"
git -C "$root/.." check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore the old path Config/Secrets.xcconfig"

rm -rf "$work"
echo "live-key-check: OK (a LIVE=1 build puts the key in the app only, and a build without LIVE=1 removes it)"
