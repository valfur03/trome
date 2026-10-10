#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" TROME_SIM_DEVICES="$state/devices" TROME_WALLPAPER_WAIT_SECONDS=1

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

udid=11111111-1111-1111-1111-111111111111
echo "RATP-Shared Booted" > "$state/device.$udid"
store="$state/devices/$udid/data/Library/Application Support/PRBPosterExtensionDataStore/61"
database="$store/PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3"
original=67F8CF9C-0000-0000-0000-000000000000
added=A6055A2B-0000-0000-0000-000000000000

# A wallpaper as iOS writes it: a row in its database, and a folder with the descriptor of the gallery.
# The fake test run (it records its call, and adds or chooses the wallpaper as iOS would, unless told not to) uses the same functions, so they are in a file that both read.
cat > "$state/posters.sh" <<'POSTERS'
poster() {
    sqlite3 "$database" "INSERT INTO poster (UUID, providerId) VALUES ('$1', 'com.apple.MercuryPoster');
        INSERT INTO posterRoleMembership VALUES ('$1', '$3', (SELECT count(*) FROM posterRoleMembership));"
    mkdir -p "$store/Extensions/com.apple.MercuryPoster/configurations/$1"
    printf '%s' "$2" > "$store/Extensions/com.apple.MercuryPoster/configurations/$1/com.apple.posterkit.provider.descriptor.identifier"
}

select_poster() {
    sqlite3 "$database" "DELETE FROM posterAttributes WHERE attributeIdentifier = 'SELECTED' AND roleId = 'PRPosterRoleLockScreen';
        INSERT INTO posterAttributes VALUES ('$1', 'PRPosterRoleLockScreen', 'SELECTED', '1');"
}
POSTERS
export store database FAKE_ADDED="$added"
. "$state/posters.sh"

new_simulator() {
    rm -rf "$state/devices"
    mkdir -p "$store"
    sqlite3 "$database" "CREATE TABLE poster (posterId INTEGER PRIMARY KEY AUTOINCREMENT, UUID TEXT UNIQUE, providerId TEXT NOT NULL);
        CREATE TABLE posterRoleMembership (posterUUID TEXT NOT NULL, roleId TEXT NOT NULL, roleSortKey INTEGER NOT NULL);
        CREATE TABLE posterAttributes (posterUUID TEXT NOT NULL, roleId TEXT NOT NULL, attributeIdentifier TEXT NOT NULL, attributePayload TEXT NOT NULL);"
    poster "$original" celosia.timeOfDay PRPosterRoleLockScreen
    poster 33333333-0000-0000-0000-000000000000 fluidity.three PRPosterRoleAmbient
    select_poster "$original"
}

cat > "$state/fake-xcodebuild" <<'FAKE'
#!/bin/sh
set -eu
. "$FAKE_SIM_STATE/posters.sh"
echo "SET=$TEST_RUNNER_SET_THE_WALLPAPER UUID=$TEST_RUNNER_WALLPAPER_UUID $*" >> "$FAKE_SIM_STATE/xcodebuild-calls"
case "$(cat "$FAKE_SIM_STATE/test-does")" in
    fail) exit 65 ;;
    nothing) exit 0 ;;
esac
if [ -z "$TEST_RUNNER_WALLPAPER_UUID" ]; then
    poster "$FAKE_ADDED" fluidity.three PRPosterRoleLockScreen
    select_poster "$FAKE_ADDED"
else
    select_poster "$TEST_RUNNER_WALLPAPER_UUID"
fi
FAKE
chmod +x "$state/fake-xcodebuild"

calls() {
    if [ -f "$state/xcodebuild-calls" ]; then wc -l < "$state/xcodebuild-calls" | tr -d ' '; else echo 0; fi
}

set_it() {
    "$scripts/wallpaper.sh" set "$state/result.xcresult" "$state/fake-xcodebuild" -scheme TROMEDocsScreenshots > "$state/out" 2> "$state/err"
}

expect "the id comes from Wallpaper.swift" "$("$scripts/wallpaper.sh" id)" "com.apple.MercuryPoster:fluidity.three"

new_simulator
expect "it lists the wallpapers of the lock screen only, with the one in use" "$("$scripts/wallpaper.sh" list "$udid")" "$original com.apple.MercuryPoster:celosia.timeOfDay 1"
status=0
"$scripts/wallpaper.sh" check "$udid" 2> "$state/err" || status=$?
expect "the check fails on another wallpaper" "$status" "1"
expect "with one line that names the command that sets it" "$(cat "$state/err")" "The Simulator does not show the wallpaper of the pictures (com.apple.MercuryPoster:fluidity.three): run make simulator-wallpaper"

rm -rf "$state/devices"
status=0
"$scripts/wallpaper.sh" check "$udid" 2> "$state/err" || status=$?
expect "the check fails on a Simulator with no wallpaper data (new or erased)" "$status:$(wc -l < "$state/err" | tr -d ' ')" "1:1"

new_simulator
echo add > "$state/test-does"
set_it
expect "set adds the wallpaper when the switcher does not hold it" "$(cat "$state/xcodebuild-calls")" \
    "SET=1 UUID= -scheme TROMEDocsScreenshots -resultBundlePath $state/result.xcresult -only-testing:TROMEDocsScreenshots/SetTheWallpaperTests test-without-building"
expect "it says so" "$(head -n 1 "$state/out")" "Wallpaper com.apple.MercuryPoster:fluidity.three: set (added)"
expect "then the check passes" "$("$scripts/wallpaper.sh" check "$udid" && echo passed)" "passed"
expect "the original and the added wallpaper remain" "$("$scripts/wallpaper.sh" list "$udid" | tr '\n' ';')" \
    "$original com.apple.MercuryPoster:celosia.timeOfDay 0;$added com.apple.MercuryPoster:fluidity.three 1;"

set_it
expect "a second set runs no test" "$(calls)" "1"
expect "and says that it is already set" "$(cat "$state/out")" "Wallpaper com.apple.MercuryPoster:fluidity.three: already set, nothing to do"
expect "and leaves the same wallpapers" "$("$scripts/wallpaper.sh" list "$udid" | tr '\n' ';')" \
    "$original com.apple.MercuryPoster:celosia.timeOfDay 0;$added com.apple.MercuryPoster:fluidity.three 1;"

select_poster "$original"
echo choose > "$state/test-does"
set_it
expect "set chooses the wallpaper that the switcher holds, so there is no second copy" "$(tail -n 1 "$state/xcodebuild-calls" | cut -d ' ' -f 1-2)" "SET=1 UUID=$added"
expect "it says so" "$(head -n 1 "$state/out")" "Wallpaper com.apple.MercuryPoster:fluidity.three: set (chosen in the switcher)"
expect "and the Simulator holds one copy" "$("$scripts/wallpaper.sh" list "$udid" | grep -c fluidity.three)" "1"

new_simulator
echo nothing > "$state/test-does"
status=0
set_it || status=$?
expect "set fails when the test passes but iOS does not show the wallpaper" "$status" "1"
expect "and lists the wallpapers" "$(tail -n 1 "$state/err")" "$original com.apple.MercuryPoster:celosia.timeOfDay 1"

new_simulator
echo fail > "$state/test-does"
status=0
set_it || status=$?
expect "set fails when the test fails" "$([ "$status" -ne 0 ] && echo failed)" "failed"

makefile="$scripts/../Makefile"
expect "make docs-screenshots checks the wallpaper before its build and its wait for the lock" \
    "$(sed -n '/^docs-screenshots:/{n;p;}' "$makefile")" "	@./scripts/wallpaper.sh check"
expect "the docs script checks it again under the lock, before any picture" \
    "$(grep -c '^"$scripts/wallpaper.sh" check "$udid"$' "$scripts/docs-screenshots.sh")" "1"
expect "make store-screenshots checks the wallpaper before its build and its wait for the lock" \
    "$(sed -n '/^store-screenshots:/{n;p;}' "$makefile")" "	@./scripts/wallpaper.sh check"
expect "the store script checks it again under the lock, before any capture" \
    "$(grep -c '^    "$scripts/wallpaper.sh" check "$udid"$' "$scripts/store-screenshots.sh")" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "All wallpaper script tests passed"
