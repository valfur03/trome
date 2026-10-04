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
        files_with_key "$@" || exit
        exit
        ;;
    logs-with-key)
        shift
        logs_with_key "$@" || exit
        exit
        ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/.build"
work="$build/live-key-check"
app_name=$(sed -n -E 's/^APP_NAME = (.+)$/\1/p' "$root/Config/Base.xcconfig")
app_plist="$build/DerivedData/Build/Products/Debug-iphonesimulator/$app_name.app/Info.plist"
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

release_key="${fake_prefix}RELEASEKEY"
release_token="${fake_prefix}TOKEN"
release_products="$build/DerivedData/Build/Products/Release-iphonesimulator"
release_app="$release_products/$app_name.app"

build_release() {
    release_settings="$work/$1-$(date +%s)-$$.xcconfig"
    printf 'PRIM_API_KEY = %s\nTRAIN_SERVER_HOST = %s\nTRAIN_SERVER_APP_TOKEN = %s\n' \
        "$release_key" "$2" "$3" > "$release_settings"
    (cd "$root" && xcodebuild -quiet \
        -project TROME.xcodeproj -scheme TROME -configuration Release \
        -destination 'generic/platform=iOS Simulator' ARCHS="$(uname -m)" \
        -derivedDataPath "$build/DerivedData" -clonedSourcePackagesDirPath "$build/SourcePackages" \
        COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO \
        -xcconfig "$release_settings" build) > "$work/$1.log" 2>&1
}

refused_release() {
    missing=$1
    shift
    if build_release "$@"; then
        fail "a Release build with no $missing succeeded: it must fail, so that no build ships with no train source"
    fi
    grep -F 'ios/Config/Server.xcconfig' "$work/$1.log" | grep -qF 'ios/Config/Server.example.xcconfig' || {
        cat "$work/$1.log" >&2
        fail "the Release build with no $missing failed, but its output does not name ios/Config/Server.xcconfig and its example"
    }
    ! grep -qF "$fake_prefix" "$work/$1.log" || fail "the output of the Release build with no $missing shows the key or the app token"
}

rm -rf "$release_products"
build_release release live-key-check.invalid "$release_token" || {
    cat "$work/release.log" >&2
    fail "the Release build failed"
}
! grep -qF "$fake_prefix" "$work/release.log" || fail "the output of the Release build shows the key or the app token"
[ -f "$release_app/Info.plist" ] || fail "the Release build made no app at $release_app"
if release_leaks=$(grep -rlF -- "$release_key" "$release_products"); then
    fail "the Release build put the PRIM key in: $release_leaks"
elif [ $? -gt 1 ]; then
    fail "could not search the whole Release build in $release_products"
fi
grep -qF "$release_token" "$release_app/Info.plist" || fail "the Release build did not put the app token of the server in the app"
grep -qF "live-key-check.invalid" "$release_app/Info.plist" || fail "the Release build did not put the server host in the app"
if widget_leaks=$(grep -rlF -- "$release_token" "$release_app/PlugIns"); then
    fail "the Release build put the app token in the Live Activity: $widget_leaks"
elif [ $? -gt 1 ]; then
    fail "could not search the Live Activity of the Release build"
fi
! grep -qF "$release_token" "$app_plist" || fail "a Debug build holds the app token of the server"
"$root/scripts/upload-check.py" "$release_app" || fail "the Release build would not pass the upload checks of App Store Connect (see above)"

refused_release "server host" release-no-host "" "$release_token"
refused_release "app token" release-no-token live-key-check.invalid ""

cache_leaks=$(files_with_key "$shared_cache" "$work/start" "$fake_prefix") || fail "could not search the whole shared build cache $shared_cache"
[ -z "$cache_leaks" ] || fail "the shared build cache $shared_cache holds the key in: $cache_leaks"

leaks=$(logs_with_key "$build" "$work/start" "$fake_prefix") || fail "could not search all the new build logs and result bundles in $build"
[ -z "$leaks" ] || fail "these build logs or result bundles show the key: $leaks"

git -C "$root" check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore ios/Config/Secrets.xcconfig"
git -C "$root" check-ignore -q Config/Server.xcconfig || fail "git does not ignore ios/Config/Server.xcconfig"
git -C "$root/.." check-ignore -q Config/Secrets.xcconfig || fail "git does not ignore the old path Config/Secrets.xcconfig"

rm -rf "$work"
echo "live-key-check: OK (a LIVE=1 build puts the key in the app only, a new key replaces the old one, a build without LIVE=1 removes it, a Release build holds the app token and never the key, a Release build with no server host or no app token fails, the Release build passes the upload checks of upload-check.py, and no build output or log shows the key or the token)"
