#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

mkdir "$state/bin" "$state/e2e.xcresult"
cat > "$state/bin/xcrun" << 'EOF'
#!/bin/sh
[ "$1 $2 $3 $5" = "xcresulttool get test-results --path" ] || exit 1
cat "$FAKE_STATE/$4.json"
EOF
cat > "$state/bin/pmset" << 'EOF'
#!/bin/sh
[ "$*" = "-g log" ] || exit 1
[ -z "${FAKE_PMSET_FAILS:-}" ] || exit 1
cat "$FAKE_STATE/power.log"
EOF
chmod +x "$state/bin/xcrun" "$state/bin/pmset"
export FAKE_STATE="$state" PATH="$state/bin:$PATH"

cat > "$state/tests.json" << 'EOF'
{"testNodes": [{"nodeType": "Test Plan", "children": [{"nodeType": "Test Case", "nodeIdentifier": "SnoozeTests/testSnooze()", "children": [
  {"nodeType": "Failure Message", "name": "The next lines did not show.", "sourceLocation": {"filePath": "/x/UITests/SnoozeTests.swift", "lineNumber": 42}}
]}]}]}
EOF

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

epoch() {
    date -j -f "%Y-%m-%d %H:%M:%S %z" "$1" +%s
}

tests_ran() {
    if [ -n "${2:-}" ]; then
        printf '{"startTime": %s.807, "finishTime": %s.703}\n' "$(epoch "$1")" "$(epoch "$2")" > "$state/summary.json"
    else
        printf '{"startTime": %s.807}\n' "$(epoch "$1")" > "$state/summary.json"
    fi
}

explain() {
    "$scripts/e2e-failures.py" "$state/e2e.xcresult" > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

sleep_line() {
    grep "^The Mac slept" "$state/out" || echo "none"
}

real_night='2026-09-30 22:26:17 +0200 Notification        	Display is turned off
2026-09-30 22:26:22 +0200 Sleep               	Entering Sleep state due to '"'Clamshell Sleep'"':TCPKeepAlive=active Using Batt (Charge:100%) 96 secs
2026-09-30 22:26:23 +0200 Wake Requests       	[*process=dasd request=SleepService deltaSecs=971 wakeAt=2026-09-30 22:42:35 info="com.apple.dasd:501:com.apple.mediaanalysisd.background.scheduler"]
2026-09-30 22:26:23 +0200 PM Client Acks      	Delays to Sleep notifications: [com.apple.bluetooth.sleep is slow(1579 ms)]
2026-09-30 22:27:58 +0200 Notification        	Display is turned on
2026-09-30 22:27:58 +0200 Wake                	Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid MTP.DOCK.CHANNELS.AP0.IRQ RTP.multi-touch/HID Activity Using BATT (Charge:100%)
2026-09-30 22:27:58 +0200 WakeDetails         	DriverReason:smc.sysState.Wake(0x70070000) - DriverDetails:
2026-09-30 22:27:58 +0200 WakeTime            	WakeTime: 0.124 sec                                                        	          '

echo "$real_night" > "$state/power.log"
tests_ran "2026-09-30 22:24:40 +0200" "2026-09-30 22:28:30 +0200"
expect "the explanation of a failed run with a sleep succeeds" "$(explain)" "exit 0"
expect "it still prints the failing tests" "$(head -1 "$state/out")" "SnoozeTests.swift:42: SnoozeTests/testSnooze(): The next lines did not show."
expect "it says when the Mac slept during the tests, from the sleep to the wake, as the night of TASK-140" "$(sleep_line)" "The Mac slept during the E2E tests, from 2026-09-30 22:26:22 to 2026-09-30 22:27:58 (96 s), says 'pmset -g log'."
expect "it says that the failures may come from the sleep" "$(grep -c "may come from the sleep, not from the code" "$state/out")" "1"
expect "it says to run the command again" "$(grep -c "^Run the same command again (make e2e, or make merge)" "$state/out")" "1"
expect "the sleep comes after the failing tests" "$(sed -n 2p "$state/out" | cut -c1-14)" "The Mac slept "

TZ=America/New_York
export TZ
explain > /dev/null
unset TZ
expect "it reads the time zone of each line of the power log, not the one of the shell" "$(sleep_line)" "The Mac slept during the E2E tests, from 2026-09-30 22:26:22 to 2026-09-30 22:27:58 (96 s), says 'pmset -g log'."

tests_ran "2026-09-30 22:26:30 +0200" "2026-09-30 22:30:00 +0200"
explain > /dev/null
expect "a sleep that started before the tests is not named" "$(sleep_line)" "none"

tests_ran "2026-09-30 22:20:00 +0200" "2026-09-30 22:26:21 +0200"
explain > /dev/null
expect "a sleep that started after the tests is not named" "$(sleep_line)" "none"
expect "a run with no sleep prints only the failing tests" "$(wc -l < "$state/out" | tr -d ' ')" "1"

tests_ran "2026-09-30 22:26:22 +0200" "2026-09-30 22:26:22 +0200"
explain > /dev/null
expect "a sleep in the same second as the start of the tests is named" "$(sleep_line | cut -c1-14)" "The Mac slept "

cat > "$state/power.log" << 'EOF'
2026-10-01 06:44:31 +0200 Sleep               	Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:100%) 1018 secs
2026-10-01 06:44:34 +0200 Wake Requests       	[*process=dasd request=SleepService deltaSecs=1014 wakeAt=2026-10-01 07:01:28]
2026-10-01 07:01:29 +0200 DarkWake            	DarkWake from Deep Idle [CDNP] : due to NUB.SPMI0.SW3 nub-spmi0.0x02 rtc/SleepService Using BATT (Charge:100%) 2 secs
2026-10-01 07:01:31 +0200 Sleep               	Entering Sleep state due to 'Sleep Service Back to Sleep':TCPKeepAlive=active Using Batt (Charge:100%) 1001 secs
2026-10-01 07:18:49 +0200 Wake                	Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid Using BATT (Charge:100%)
2026-10-01 07:20:00 +0200 Sleep               	Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:100%) 30 secs
2026-10-01 07:20:30 +0200 Wake                	DarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion
EOF
tests_ran "2026-10-01 06:44:00 +0200" "2026-10-01 07:21:00 +0200"
explain > /dev/null
expect "a dark wake does not end the sleep, and two sleeps are both named" "$(sleep_line)" "The Mac slept during the E2E tests, from 2026-10-01 06:44:31 to 2026-10-01 07:18:49 (2058 s), then from 2026-10-01 07:20:00 to 2026-10-01 07:20:30 (30 s), says 'pmset -g log'."

cat > "$state/power.log" << 'EOF'
2026-10-01 08:00:10 +0200 Sleep               	Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:100%) 30 secs
EOF
tests_ran "2026-10-01 08:00:00 +0200"
explain > /dev/null
expect "a run with no end time looks up to now, and a sleep with no wake yet is named" "$(sleep_line)" "The Mac slept during the E2E tests, from 2026-10-01 08:00:10 (no wake in the log yet), says 'pmset -g log'."

FAKE_PMSET_FAILS=1
export FAKE_PMSET_FAILS
expect "the explanation succeeds when the power log cannot be read" "$(explain)" "exit 0"
unset FAKE_PMSET_FAILS
expect "it then prints only the failing tests" "$(cat "$state/out")" "SnoozeTests.swift:42: SnoozeTests/testSnooze(): The next lines did not show."

rm -r "$state/e2e.xcresult"
expect "the explanation prints nothing when the run left no results" "$(explain) $(wc -c < "$state/out" | tr -d ' ')" "exit 0 0"

[ "$failures" -eq 0 ]
