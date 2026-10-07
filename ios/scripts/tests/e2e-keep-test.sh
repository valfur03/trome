#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

mkdir -p "$state/bin" "$state/home/Library/Logs/DiagnosticReports" "$state/app/TROME.app" "$state/build/e2e.xcresult"
cat > "$state/bin/xcrun" << 'EOF'
#!/bin/sh
case "$1 $2" in
    "xcresulttool get")
        [ -e "$FAKE_STATE/$4.json" ] || exit 1
        cat "$FAKE_STATE/$4.json"
        ;;
    "simctl list")
        echo "    RATP-Shared (11111111-2222-3333-4444-555555555555) (Booted) "
        ;;
    "simctl spawn")
        echo "$*" > "$FAKE_STATE/log-show-args"
        echo "runningboardd: Launch request for com.example.trome.dev"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$state/bin/xcrun"
export FAKE_STATE="$state" PATH="$state/bin:$PATH" HOME="$state/home" TROME_E2E_EVIDENCE="$state/kept"
unset ONLY RATP_SIM_SLOT RATP_SIM_SIZE TROME_E2E_EVIDENCE_NOTE || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

plutil -create xml1 "$state/app/TROME.app/Info.plist"
plutil -insert CFBundleIdentifier -string com.example.trome.dev "$state/app/TROME.app/Info.plist"
plutil -insert CFBundleExecutable -string TROME "$state/app/TROME.app/Info.plist"
echo "result" > "$state/build/e2e.xcresult/Info.plist"
echo "the whole output of xcodebuild" > "$state/build/e2e.log"
git init -q -b fix/launch "$state/repo"
git -C "$state/repo" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m start

start=$(($(date +%s) - 120))
printf '{"result": "Failed", "startTime": %s.5, "finishTime": %s.5}\n' "$start" "$((start + 100))" > "$state/summary.json"
cat > "$state/tests.json" << 'EOF'
{"testNodes": [{"nodeType": "Test Plan", "children": [
  {"nodeType": "Test Case", "nodeIdentifier": "AutoLiveActivityTests/testAuto()", "result": "Passed", "durationInSeconds": 41.2},
  {"nodeType": "Test Case", "nodeIdentifier": "LiveActivityTests/testLaunch()", "result": "Failed", "durationInSeconds": 3.7}
]}]}
EOF
touch "$state/home/Library/Logs/DiagnosticReports/TROME-today.ips" "$state/home/Library/Logs/DiagnosticReports/Other-today.ips"
touch -t 202001010000 "$state/home/Library/Logs/DiagnosticReports/TROME-old.ips"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

keep() {
    (cd "$state/repo" && "$scripts/e2e-keep.py" "$state/build/e2e.xcresult" "$state/build/e2e.log" "$state/app/TROME.app") > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

has() {
    [ -e "$1" ] && echo yes || echo no
}

expect "keeping the evidence of a failed run succeeds" "$(keep)" "exit 0"
kept=$(ls -d "$state/kept"/*)
expect "the run gets its own folder, named by the time and the branch" "$(basename "$kept" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-//')" "fix-launch"
expect "it says where the evidence is" "$(cat "$state/out")" "E2E evidence: the log, the result bundle, the Simulator log and the context of this failed run are kept in $kept"
expect "it keeps the result bundle" "$(cat "$kept/e2e.xcresult/Info.plist")" "result"
expect "it keeps the log" "$(cat "$kept/e2e.log")" "the whole output of xcodebuild"
expect "it keeps the Simulator log" "$(cat "$kept/simulator.log")" "runningboardd: Launch request for com.example.trome.dev"
expect "the Simulator log is the one of the shared Simulator" "$(cut -d' ' -f3 "$state/log-show-args")" "11111111-2222-3333-4444-555555555555"
window_start=$(date -r "$((start - 5))" "+%Y-%m-%d %H:%M:%S")
window_end=$(date -r "$((start + 105))" "+%Y-%m-%d %H:%M:%S")
expect "the Simulator log covers the run, with 5 s on each side" "$(grep -c -- "--start $window_start --end $window_end" "$state/log-show-args")" "1"
expect "the Simulator log has the lines of the app, and every line of iOS that names it" "$(grep -c 'process == "TROME" OR eventMessage CONTAINS "com.example.trome.dev"$' "$state/log-show-args")" "1"
expect "it keeps the crash report of the app written during the run" "$(has "$kept/TROME-today.ips")" "yes"
expect "it does not keep an older crash report" "$(has "$kept/TROME-old.ips")" "no"
expect "it does not keep the crash report of another process" "$(has "$kept/Other-today.ips")" "no"
expect "the context names the crash report" "$(grep '^Crash reports' "$kept/context.txt")" "Crash reports of the app: TROME-today.ips"
expect "the context gives the load of the Mac" "$(grep -c '^Load of the Mac at the end of the run: .* (1, 5 and 15 min averages) on [0-9]* cores$' "$kept/context.txt")" "1"
expect "the context lists the tests in the order they ran, with their result" "$(sed -n '/^Tests, in the order they ran:$/,$p' "$kept/context.txt" | tr '\n' '|')" "Tests, in the order they ran:|  AutoLiveActivityTests/testAuto(): Passed, 41 s|  LiveActivityTests/testLaunch(): Failed, 4 s|"
expect "the context says that the full suite ran" "$(grep '^Only' "$kept/context.txt")" "Only these tests: no (the full suite)"

rm "$state/home/Library/Logs/DiagnosticReports/TROME-today.ips"
TROME_E2E_EVIDENCE_NOTE="$state/note"
export TROME_E2E_EVIDENCE_NOTE
keep > /dev/null
unset TROME_E2E_EVIDENCE_NOTE
second=$(cat "$state/note")
expect "a second run in the same second gets a folder of its own" "$(ls "$state/kept" | wc -l | tr -d ' ') $([ "$second" != "$kept" ] && echo distinct)" "2 distinct"
expect "it writes the folder of the run in the file of TROME_E2E_EVIDENCE_NOTE" "$(has "$second/context.txt")" "yes"
expect "with no crash report, the context says so" "$(grep -c '^Crash reports of the app: none: no TROME-\*.ips' "$second/context.txt")" "1"

rm -r "$state/build/e2e.xcresult" "$state/summary.json" "$state/tests.json"
TROME_E2E_EVIDENCE_NOTE="$state/note"
export TROME_E2E_EVIDENCE_NOTE
expect "a run that ended before its result bundle still keeps its log" "$(keep)" "exit 0"
unset TROME_E2E_EVIDENCE_NOTE
third=$(cat "$state/note")
expect "it then keeps the log" "$(has "$third/e2e.log") $(has "$third/e2e.xcresult")" "yes no"
expect "it then reads the last 15 min of the Simulator log" "$(grep -c -- "--last 900s" "$state/log-show-args")" "1"
expect "the context says that there is no result bundle" "$(grep '^Result bundle' "$third/context.txt")" "Result bundle: none (the run ended before it wrote one)"

for old in $(seq 1 25); do
    mkdir "$state/kept/2020-01-01-0000$old-old"
    touch -t "2020010100$(printf '%02d' "$old")" "$state/kept/2020-01-01-0000$old-old"
done
keep > /dev/null
expect "it keeps only the 20 newest runs" "$(ls "$state/kept" | wc -l | tr -d ' ')" "20"
expect "it removes the oldest runs first" "$(has "$state/kept/2020-01-01-00001-old") $(has "$state/kept/2020-01-01-000025-old") $(has "$third")" "no yes yes"

[ "$failures" -eq 0 ]
