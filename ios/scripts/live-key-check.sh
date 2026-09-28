#!/bin/sh
set -eu

files_with_key() {
    [ -e "$1" ] || return 0
    find -H "$1" -type f -cnewer "$2" -exec sh -c '
        key=$1
        shift
        status=0
        for file do
            if grep -qsF -- "$key" "$file"; then
                echo "$file"
            elif [ $? -gt 1 ] && [ -e "$file" ]; then
                echo "live-key-check: cannot read $file" >&2
                status=1
            fi
        done
        exit "$status"
    ' sh "$3" {} +
}

logs_with_key() {
    status=0
    if [ -e "$1/DerivedData/Logs" ]; then
        find -H "$1/DerivedData/Logs" -type f -name '*.xcactivitylog' -newer "$2" -exec sh -c '
            key=$1
            shift
            status=0
            for log do
                if ! gzip -t -- "$log" 2> /dev/null; then
                    if [ -e "$log" ]; then
                        echo "live-key-check: cannot read the build log $log" >&2
                        status=1
                    fi
                elif gzip -dc -- "$log" | grep -qF -- "$key"; then
                    echo "$log"
                fi
            done
            exit "$status"
        ' sh "$3" {} + || status=1
    fi
    if [ -e "$1" ]; then
        find -H "$1" -name '*.xcresult' -newer "$2" -prune -exec sh -c '
            key=$1
            shift
            status=0
            for bundle do
                grep -rlF -- "$key" "$bundle" || {
                    if [ $? -gt 1 ] && [ -e "$bundle" ]; then
                        echo "live-key-check: cannot read the result bundle $bundle" >&2
                        status=1
                    fi
                }
            done
            exit "$status"
        ' sh "$3" {} + || status=1
    fi
    return "$status"
}

case "${1:-}" in
    files-with-key)
        shift
        files_with_key "$@"
        exit
        ;;
    logs-with-key)
        shift
        logs_with_key "$@"
        exit
        ;;
esac

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

build_app normal LIVE= PRIM_SECRETS="$work/Secrets.xcconfig"
! grep -qF "$fake_prefix" "$app_plist" || fail "the build without LIVE=1 kept the key in the app"

cache_leaks=$(files_with_key "$shared_cache" "$work/start" "$fake_prefix") || fail "could not search the whole shared build cache $shared_cache"
[ -z "$cache_leaks" ] || fail "the shared build cache $shared_cache holds the key in: $cache_leaks"

leaks=$(logs_with_key "$build" "$work/start" "$fake_prefix") || fail "could not search all the new build logs and result bundles in $build"
[ -z "$leaks" ] || fail "these build logs or result bundles show the key: $leaks"

git -C "$root" check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore ios/Config/Secrets.xcconfig"
git -C "$root/.." check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore the old path Config/Secrets.xcconfig"

rm -rf "$work"
echo "live-key-check: OK (a LIVE=1 build puts the key in the app only, a new key replaces the old one, and a build without LIVE=1 removes it)"
