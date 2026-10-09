#!/bin/sh
# Checks ios/scripts/fake-trains.sh with a fake xcrun: the app writes its FakeTrains line, and the fake loses the
# arguments of the first launches, as iOS does when it has started the app again in the background.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
udid=33333333-3333-3333-3333-333333333333

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

mkdir -p "$state/bin" "$state/TROME.app"
/usr/libexec/PlistBuddy -c 'Add CFBundleIdentifier string com.example.trome.dev' "$state/TROME.app/Info.plist" > /dev/null
cat > "$state/bin/xcrun" << 'EOF'
#!/bin/sh
set -eu
state=$FAKE_STATE
[ "$1" = simctl ] || exit 1
shift
command=$1
shift
case "$command" in
    list) echo "    RATP-Shared ($FAKE_UDID) (Booted) " ;;
    get_app_container) [ -z "${FAKE_NOT_INSTALLED:-}" ] && echo "$state/container" ;;
    terminate) echo terminate >> "$state/calls" ;;
    launch)
        shift 2
        count=$(($(cat "$state/launches" 2> /dev/null || echo 0) + 1))
        echo "$count" > "$state/launches"
        echo "launch $*" >> "$state/calls"
        pid=$((500 + count))
        if [ "$count" -le "${FAKE_LOST_LAUNCHES:-0}" ]; then
            line="launch with no argument | saved: fake trains old from 10:00:00 | uses: fake trains old from 10:00:00"
        else
            name=${2:-default}
            case "$name" in
                nope) line="launch with arguments, --fake-trains nope (unknown state) | saved: no fake trains | uses: no fake trains, no key: no data" ;;
                *) line="launch with arguments, $* | saved: no fake trains | uses: fake trains $name from 10:01:00" ;;
            esac
        fi
        echo "2026-10-09 10:01:00.000000+0200  localhost TROME[$pid]: (TROMECore) [TROME:FakeTrains] $line" >> "$state/log"
        echo "com.example.trome.dev: $pid"
        ;;
    spawn)
        shift
        case "$1" in
            defaults) echo "$*" >> "$state/calls" ;;
            log) cat "$state/log" 2> /dev/null || true ;;
        esac
        ;;
esac
EOF
chmod +x "$state/bin/xcrun"
export FAKE_STATE="$state" FAKE_UDID="$udid" PATH="$state/bin:$PATH" TROME_FAKE_TRAINS_LOG_WAIT_SECONDS=0
unset RATP_SIM_SIZE RATP_SIM_SLOT FAKE_LOST_LAUNCHES FAKE_NOT_INSTALLED || true

run() {
    rm -f "$state/calls" "$state/launches" "$state/log"
    "$scripts/fake-trains.sh" "$state/TROME.app" "$@" > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

saved_choice() {
    grep '^defaults' "$state/calls" | head -n 1 | sed 's/.*-data //' | xxd -r -p | sed -E 's/[0-9]+}$/N}/'
}

expect "a state that the app gets is applied at the first launch" "$(run at-platform)" "exit 0"
expect "it says so in one sentence" "$(cat "$state/out")" "fake trains: at-platform applied"
expect "it launches the app with the state" "$(grep '^launch' "$state/calls")" "launch --fake-trains at-platform"
expect "it saves the state where a launch with no argument reads it" \
    "$(grep -c "^defaults write $state/container/Library/Preferences/com.example.trome.dev testingTools.fakeTrains -data " "$state/calls")" "1"
expect "the saved choice is the JSON of FakeTrainsStore" "$(saved_choice)" '{"scenario":"at-platform","start":N}'
expect "it closes the app after the save, so that the process that runs started after it" \
    "$(tr '\n' ' ' < "$state/calls" | sed -E 's/defaults write .* -data [0-9a-f]+/save/')" "terminate save terminate launch --fake-trains at-platform "

expect "no state gives the default times" "$(run)" "exit 0"
expect "it says the default times are applied" "$(cat "$state/out")" "fake trains: default applied"
expect "it launches the app with only --fake-trains" "$(grep '^launch' "$state/calls")" "launch --fake-trains"
expect "the saved choice has no scenario" "$(saved_choice)" '{"start":N}'

export FAKE_LOST_LAUNCHES=2
expect "a launch that iOS took over is tried again" "$(run fork-end-one-train)" "exit 0"
expect "it is applied at the third launch" "$(cat "$state/launches") $(cat "$state/out")" "3 fake trains: fork-end-one-train applied"

export FAKE_LOST_LAUNCHES=3
expect "three launches that iOS took over fail" "$(run ten-to-nine)" "exit 1"
expect "it says the state was not applied, and shows the line of the app" "$(cat "$state/out")" "fake trains: ten-to-nine not applied, launch again
The last line of the app: 2026-10-09 10:01:00.000000+0200  localhost TROME[503]: (TROMECore) [TROME:FakeTrains] launch with no argument | saved: fake trains old from 10:00:00 | uses: fake trains old from 10:00:00"
unset FAKE_LOST_LAUNCHES

expect "a state that the app does not know fails at once" "$(run nope)" "exit 1"
expect "it says the app knows no such state" "$(cat "$state/launches") $(cat "$state/out")" "1 fake trains: nope not applied: the app knows no such state (FakeTrainsScenario)"

export FAKE_NOT_INSTALLED=1
expect "it fails when the app is not in the Simulator" "$(run at-platform)" "exit 1"
expect "it says to run make run first, and launches nothing" "$(cat "$state/out") $(cat "$state/launches" 2> /dev/null || echo 0)" "The app is not in the Simulator. Run 'make run' first. 0"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
