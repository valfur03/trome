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
        if [ -e "$FAKE_STATE/simulator.log" ]; then
            cat "$FAKE_STATE/simulator.log"
        else
            echo "runningboardd: Launch request for com.example.trome.dev"
        fi
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
expect "the Simulator log has the lines of the app, and every line of iOS that names it" "$(grep -c 'process == "TROME" OR eventMessage CONTAINS "com.example.trome.dev" OR ' "$state/log-show-args")" "1"
expect "it also has the path of a tap on a Live Activity button: the taps of chronod, and the intent runner with its launch" "$(grep -c 'OR (process == "chronod" AND category == "interactions") OR (process == "chronod" AND category == "taskservice") OR eventMessage CONTAINS "LiveActivity will be empty" OR process == "BackgroundShortcutRunner" OR (process == "launchd_sim" AND eventMessage CONTAINS "Successfully spawned BackgroundShortcutRunner\[")$' "$state/log-show-args")" "1"
expect "with no tap in the Simulator log, the context says so" "$(grep '^Taps' "$kept/context.txt")" "Taps on a Live Activity button: none in the Simulator log"
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

# The lines of a real run (2026-10-08) where a tap took too long, after a tap that ran, shortened.
cat > "$state/simulator.log" << 'EOF'
2026-10-08 09:07:40.192 Df TROME[50654:21e4b] [TROME:LiveActivity] the app ends 0 Live Activities []
2026-10-08 09:07:50.100 Df chronod[35014:20bc6] [com.apple.chrono:interactions] Starting to run action: <LNAction: 0x108932c40, identifier: ShowNextLinesIntent, mangledTypeName: 9TROMECore19ShowNextLinesIntentV, openAppWhenRun: NO>
2026-10-08 09:07:50.200 Df launchd_sim[34811:22799] [pid/35014/com.apple.WorkflowKit.BackgroundShortcutRunner.A [51900]:] Successfully spawned BackgroundShortcutRunner[51900] because ipc (mach)
2026-10-08 09:07:52.700 Df BackgroundShortcutRunner[51900:0] [com.apple.libsystem.libdispatch:] BUG in libdispatch: 25G83 24A434 - 612 - 0x4
2026-10-08 09:07:56.600 Df chronod[35014:3d77e] [com.apple.chrono:interactions] Successfully ran action: <LNAction: 0x108932c40, identifier: ShowNextLinesIntent, mangledTypeName: 9TROMECore19ShowNextLinesIntentV>
2026-10-08 09:08:00.224 Df chronod[35014:20bc6] [com.apple.chrono:interactions] Starting to run action: <LNAction: 0x108877ae0, identifier: ShowNextLinesIntent, mangledTypeName: 9TROMECore19ShowNextLinesIntentV, openAppWhenRun: NO>
2026-10-08 09:08:00.349 Df launchd_sim[34811:22799] [pid/35014/com.apple.WorkflowKit.BackgroundShortcutRunner.B [51915]:] Successfully spawned BackgroundShortcutRunner[51915] because ipc (mach)
2026-10-08 09:08:30.241 E  chronod[35014:1da3d] [com.apple.chrono:interactions] Watchdog fired on interaction runner for extension: com.example.trome.dev::com.example.trome.dev.widget
2026-10-08 09:08:33.316 Df BackgroundShortcutRunner[51915:0] [com.apple.libsystem.libdispatch:] BUG in libdispatch: 25G83 24A434 - 612 - 0x4
2026-10-08 09:09:04.550 E  chronod[35014:2392e] [com.apple.chrono:interactions] Failed to execute LNAction with error: ChronoCore.InteractiveWidgetActionRunner.Errors.runnerClientError(Error Domain=LNConnectionErrorDomain Code=1014)
EOF
slow="the tap on ShowNextLinesIntent at 09:08:00 had not ended after 30 s (the watchdog of iOS fired), its intent runner (BackgroundShortcutRunner) took 33 s to start, and it failed at 09:09:04"
TROME_E2E_EVIDENCE_NOTE="$state/note"
export TROME_E2E_EVIDENCE_NOTE
keep > /dev/null
unset TROME_E2E_EVIDENCE_NOTE
expect "the context says how long the taps took, and names the tap that took too long, with its runner and its end" "$(grep '^Taps' "$(cat "$state/note")/context.txt")" "Taps on a Live Activity button: 1 ran, the longest in 6.5 s; $slow"
expect "it also prints that tap, before the folder" "$(head -1 "$state/out")" "Taps on a Live Activity button: 1 ran, the longest in 6.5 s; $slow."
grep -v "Watchdog\|51915:0\|Failed to execute" "$state/simulator.log" > "$state/cut.log" && mv "$state/cut.log" "$state/simulator.log"
TROME_E2E_EVIDENCE_NOTE="$state/note"
export TROME_E2E_EVIDENCE_NOTE
keep > /dev/null
unset TROME_E2E_EVIDENCE_NOTE
expect "a tap still running at the end of the log is named" "$(grep '^Taps' "$(cat "$state/note")/context.txt")" "Taps on a Live Activity button: 1 ran, the longest in 6.5 s; the tap on ShowNextLinesIntent at 09:08:00, and it had not ended at the end of the log"
grep -v "spawned BackgroundShortcutRunner\[51915\]" "$state/simulator.log" > "$state/cut.log" && mv "$state/cut.log" "$state/simulator.log"
cat >> "$state/simulator.log" << 'EOF'
2026-10-08 09:09:10.000 Df chronod[35014:20bc6] [com.apple.chrono:interactions] Starting to run action: <LNAction: 0x108877f00, identifier: SnoozeLiveActivityIntent, mangledTypeName: 9TROMECore24SnoozeLiveActivityIntentV, openAppWhenRun: NO>
2026-10-08 09:09:10.100 Df launchd_sim[34811:22799] [pid/35014/com.apple.WorkflowKit.BackgroundShortcutRunner.C [51930]:] Successfully spawned BackgroundShortcutRunner[51930] because ipc (mach)
2026-10-08 09:09:12.100 Df BackgroundShortcutRunner[51930:0] [com.apple.libsystem.libdispatch:] BUG in libdispatch: 25G83 24A434 - 612 - 0x4
2026-10-08 09:09:15.000 Df chronod[35014:3d77e] [com.apple.chrono:interactions] Successfully ran action: <LNAction: 0x108877f00, identifier: SnoozeLiveActivityIntent, mangledTypeName: 9TROMECore24SnoozeLiveActivityIntentV>
EOF
TROME_E2E_EVIDENCE_NOTE="$state/note"
export TROME_E2E_EVIDENCE_NOTE
keep > /dev/null
unset TROME_E2E_EVIDENCE_NOTE
expect "a slow tap is not given the intent runner of a later tap" "$(grep '^Taps' "$(cat "$state/note")/context.txt")" "Taps on a Live Activity button: 2 ran, the longest in 6.5 s; the tap on ShowNextLinesIntent at 09:08:00, and it had not ended at the end of the log"
rm "$state/simulator.log"

for old in $(seq 1 25); do
    mkdir "$state/kept/2020-01-01-0000$old-old"
    touch -t "2020010100$(printf '%02d' "$old")" "$state/kept/2020-01-01-0000$old-old"
done
keep > /dev/null
expect "it keeps only the 20 newest runs" "$(ls "$state/kept" | wc -l | tr -d ' ')" "20"
expect "it removes the oldest runs first" "$(has "$state/kept/2020-01-01-00001-old") $(has "$state/kept/2020-01-01-000025-old") $(has "$third")" "no yes yes"

[ "$failures" -eq 0 ]
