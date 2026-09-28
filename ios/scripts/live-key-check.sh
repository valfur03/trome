#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/.build"
work="$build/live-key-check"
app_plist="$build/DerivedData/Build/Products/Debug-iphonesimulator/RATPActivity.app/Info.plist"
fake_prefix="LEAKCHECK$(date +%s)$$"
old_fake="${fake_prefix}A"
fake="${fake_prefix}B"
shared_cache="${RATP_SHARED_CACHE:?}"

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
    ! grep -qF "$fake_prefix" "$log" || fail "the build output shows the key ($*)"
}

new_logs_show_key() {
    find "$build/DerivedData/Logs" -newer "$work/start" -name '*.xcactivitylog' 2> /dev/null | while read -r activity_log; do
        if gzip -dc "$activity_log" | grep -qF "$fake_prefix"; then
            echo "$activity_log"
        fi
    done
    find "$build" -newer "$work/start" -name '*.xcresult' -prune -exec grep -rlF "$fake_prefix" {} + 2> /dev/null || true
}

rm -rf "$work"
mkdir -p "$work"
touch "$work/start"

printf 'PRIM_API_KEY = %s\n' "$old_fake" > "$work/Secrets.xcconfig"
build_app live-old LIVE=1 PRIM_SECRETS="$work/Secrets.xcconfig"
grep -qF "$old_fake" "$app_plist" || fail "the LIVE=1 build did not put the key in the app"

printf 'PRIM_API_KEY = %s\n' "$fake" > "$work/Secrets.xcconfig"
build_app live LIVE=1 PRIM_SECRETS="$work/Secrets.xcconfig"
grep -qF "$fake" "$app_plist" || fail "after a change of the key file, the LIVE=1 build did not put the new key in the app"
! grep -qF "$old_fake" "$app_plist" || fail "after a change of the key file, the LIVE=1 build kept the old key in the app"
! grep -rqF "$fake_prefix" "$shared_cache" 2> /dev/null || fail "the shared build cache $shared_cache holds the key"

build_app normal LIVE= PRIM_SECRETS="$work/Secrets.xcconfig"
! grep -qF "$fake_prefix" "$app_plist" || fail "the build without LIVE=1 kept the key in the app"

leaks=$(new_logs_show_key)
[ -z "$leaks" ] || fail "these build logs or result bundles show the key: $leaks"

git -C "$root" check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore ios/Config/Secrets.xcconfig"
git -C "$root/.." check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore the old path Config/Secrets.xcconfig"

rm -rf "$work"
echo "live-key-check: OK (a LIVE=1 build puts the key in the app only, a new key replaces the old one, and a build without LIVE=1 removes it)"
