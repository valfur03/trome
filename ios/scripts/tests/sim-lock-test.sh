#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
default=11111111-1111-1111-1111-111111111111
old=22222222-2222-2222-2222-222222222222
failures=0
export FAKE_SIM_STATE="$state" PATH="$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock"
unset RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID || true

version=$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")

fake_watcher() {
    name=$1
    shift
    mkdir "$state/$name"
    printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/$name/sim-lock.sh"
    (/bin/sh "$state/$name/sim-lock.sh" watch "$@" > /dev/null 2>&1 & echo $! > "$state/$name/pid")
    cat "$state/$name/pid"
}

idle_watcher=$(fake_watcher idle-watcher "$version")

cleanup() {
    kill ${watcher:-} ${started:-} 2> /dev/null || true
    for fake in "$state"/*/pid; do
        kill "$(cat "$fake")" 2> /dev/null || true
    done
    kill "$(cat "$RATP_SIM_LOCK.slots-watcher" 2> /dev/null)" 2> /dev/null || true
    rm -rf "$state"
}
trap cleanup EXIT

pretend_a_watcher_runs() {
    echo "$idle_watcher" > "$RATP_SIM_LOCK.slots-watcher"
}
pretend_a_watcher_runs

booted() {
    xcrun simctl list devices booted | sed -n -E 's/^    ([^ ]+) .*/\1/p' | sort | tr '\n' ' '
}

hold() {
    mkdir "$1"
    echo "$idle_watcher" > "$1/pid"
    echo /another/worktree > "$1/worktree"
}

wait_for() {
    tries=0
    until "$@" || [ "$tries" -ge 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
}

wait_for_two_watcher_passes() {
    for pass in 1 2; do
        rm -f "$RATP_SIM_LOCK.last"
        wait_for test -e "$RATP_SIM_LOCK.last"
    done
}

logged() {
    grep -qF "$1" "$state/background.log" 2> /dev/null
}

in_background() {
    RATP_SIM_POLL_SECONDS=1 "$@" > "$state/background.log" 2>&1 &
    background=$!
    wait_for logged "Waiting for the Simulator lock"
}

finish_background() {
    tries=0
    while kill -0 "$background" 2> /dev/null && [ "$tries" -lt 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
    kill "$background" 2> /dev/null || true
    wait "$background" 2> /dev/null || true
}

ran() {
    cat "$state/$1" 2> /dev/null || echo waiting
}

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

watch_in_background() {
    RATP_SIM_WATCH_SECONDS=1 "$scripts/sim-lock.sh" watch > /dev/null 2>&1 &
    watcher=$!
}

stop_watcher() {
    kill "$watcher" 2> /dev/null || true
    wait "$watcher" 2> /dev/null || true
    watcher=
    pretend_a_watcher_runs
}

is_running() {
    if kill -0 "$1" 2> /dev/null; then echo running; else echo stopped; fi
}

wait_until_stopped() {
    tries=0
    while kill -0 "$1" 2> /dev/null && [ "$tries" -lt 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
}

is_the_watcher_itself() {
    case $1 in
        *setsid*) return 1 ;;
        *"sim-lock.sh watch"*) return 0 ;;
        *) return 1 ;;
    esac
}

command_of_started_watcher() {
    started=$(cat "$RATP_SIM_LOCK.slots-watcher")
    tries=0
    command=$(ps -p "$started" -o command= 2> /dev/null)
    until is_the_watcher_itself "$command" || [ "$tries" -ge 20 ]; do
        sleep 1
        tries=$((tries + 1))
        command=$(ps -p "$started" -o command= 2> /dev/null)
    done
    echo "$command" | sed 's/^[^ ]* //'
}

stop_started_watcher() {
    started=$(cat "$RATP_SIM_LOCK.slots-watcher")
    kill "$started" 2> /dev/null || true
    wait_until_stopped "$started"
    started=
    pretend_a_watcher_runs
}

wait_until_booted() {
    tries=0
    while [ "$(booted)" != "$1" ] && [ "$tries" -lt 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
}

small_open() {
    RATP_SIM_SIZE=small "$scripts/sim-lock.sh" open "$scripts/simulator.sh" boot > /dev/null
}

echo "RATP-Shared Booted" > "$state/device.$default"

small_open
small=$("$scripts/simulator.sh" booted | grep -vxF "$default")
expect "make run SMALL=1 shuts down RATP-Shared and boots only the small Simulator" "$(booted)" "RATP-Shared-Small "
expect "the small Simulator is an iPhone SE" "$(cat "$state/type.$small")" "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
expect "the lock keeps the small Simulator" "$(cat "$RATP_SIM_LOCK/udid")" "$small"
mkdir -p "$state/TROME.app"
/usr/libexec/PlistBuddy -c 'Add CFBundleIdentifier string com.example.trome.dev' "$state/TROME.app/Info.plist" > /dev/null
echo com.example.trome.dev > "$state/apps.$small"
RATP_SIM_LANGUAGE=en "$scripts/sim-lock.sh" reopen "$scripts/simulator.sh" switch-language "$state/TROME.app" > /dev/null
expect "switch-language after make run SMALL=1 keeps only the small Simulator booted" "$(booted)" "RATP-Shared-Small "
expect "switch-language after make run SMALL=1 opens the app again on the small Simulator" "$(cat "$state/launched.$small" 2> /dev/null || true)" "com.example.trome.dev"
expect "switch-language after make run SMALL=1 does not open the app on RATP-Shared" "$(cat "$state/launched.$default" 2> /dev/null || true)" ""
expect "the lock keeps the small Simulator after switch-language" "$(cat "$RATP_SIM_LOCK/udid") $(cat "$RATP_SIM_LOCK/size")" "$small small"

"$scripts/sim-lock.sh" open sh -c '"$1" boot && kill -0 "$(cat "$RATP_SIM_LOCK/pid")" && echo held > "$FAKE_SIM_STATE/switch"' \
    sh "$scripts/simulator.sh" > /dev/null
expect "make run after make run SMALL=1 in the same folder shuts down the small Simulator and boots RATP-Shared again" "$(booted)" "RATP-Shared "
expect "a live job holds the lock while the session switches Simulator" "$(cat "$state/switch" 2> /dev/null || true)" "held"
expect "the session keeps the lock with no job after the switch" "$(test -e "$RATP_SIM_LOCK/pid" && echo job || true)" ""
expect "the lock follows the Simulator of the session" "$(cat "$RATP_SIM_LOCK/udid")" "$default"

small_open
echo com.example.trome.dev > "$state/apps.$small"
"$scripts/sim-lock.sh" free
expect "make simulator-shutdown after make run SMALL=1 keeps only the small Simulator booted" "$(booted)" "RATP-Shared-Small "
expect "make simulator-shutdown after make run SMALL=1 removes the app from the small Simulator" "$(cat "$state/apps.$small")" ""
expect "make simulator-shutdown frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

echo com.example.trome.dev > "$state/apps.$small"
echo com.example.trome.dev > "$state/apps.$default"
RATP_SIM_SIZE=small "$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job on the small Simulator removes the app that an earlier job left on it" "$(cat "$state/apps.$small")" ""
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job on RATP-Shared removes the app that an earlier job left on it" "$(cat "$state/apps.$default")" ""
printf '%s\n' com.example.trome.dev.render-check-host com.example.trome.dev.uitests.xctrunner com.other.App > "$state/apps.$default"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job removes the host app of the render check, and keeps the test runners and the other apps" \
    "$(tr '\n' ' ' < "$state/apps.$default")" "com.example.trome.dev.uitests.xctrunner com.other.App "
printf '%s\n' com.example.RATPActivity com.example.RATPActivityRenderCheckHost com.example.RATPActivityUITests.xctrunner \
    com.example.RATPActivityDocsScreenshots.xctrunner com.example.RATPActivityOtherHost com.example.trome.dev.docs-screenshots.xctrunner \
    > "$state/apps.$default"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job removes every app and test runner of a build with the old bundle IDs" \
    "$(tr '\n' ' ' < "$state/apps.$default")" "com.example.trome.dev.docs-screenshots.xctrunner "

echo "RATP-Shared Booted" > "$state/device.$default"
echo "RATP-Shared-Small Booted" > "$state/device.$small"
RATP_SIM_SIZE=small "$scripts/sim-lock.sh" open true
watch_in_background
wait_until_booted "RATP-Shared-Small "
expect "while make run SMALL=1 keeps the lock, the watcher shuts down RATP-Shared even when it was booted before the job" "$(booted)" "RATP-Shared-Small "
"$scripts/sim-lock.sh" free
small_open
echo "RATP-Shared Booted" > "$state/device.$default"
wait_until_booted "RATP-Shared-Small "
expect "while make run SMALL=1 keeps the lock, the watcher shuts down RATP-Shared that another tool boots" "$(booted)" "RATP-Shared-Small "
cat > "$state/e2e-after-small.sh" << 'EOF'
"$1" boot > /dev/null
for pass in 1 2; do
    rm -f "$RATP_SIM_LOCK.last"
    tries=0
    until [ -e "$RATP_SIM_LOCK.last" ] || [ "$tries" -ge 20 ]; do
        sleep 1
        tries=$((tries + 1))
    done
done
"$1" booted | tr '\n' ' ' > "$FAKE_SIM_STATE/joined"
EOF
"$scripts/sim-lock.sh" job sh "$state/e2e-after-small.sh" "$scripts/simulator.sh" > /dev/null
expect "make e2e after make run SMALL=1 in the same folder shuts down the small Simulator and keeps RATP-Shared booted" "$(ran joined)" "$default "
echo "RATP-Shared-Small Shutdown" > "$state/device.$small"
cat > "$state/boot-small-during-job.sh" << 'EOF'
"$1" boot > /dev/null
echo "RATP-Shared-Small Booted" > "$FAKE_SIM_STATE/device.$2"
tries=0
while [ "$("$1" booted)" != "$3" ] && [ "$tries" -lt 20 ]; do
    sleep 1
    tries=$((tries + 1))
done
"$1" booted > "$FAKE_SIM_STATE/job-others"
EOF
"$scripts/sim-lock.sh" job sh "$state/boot-small-during-job.sh" "$scripts/simulator.sh" "$small" "$default" > /dev/null
stop_watcher
expect "while a job uses RATP-Shared, the watcher shuts down the small Simulator that another tool boots" "$(ran job-others)" "$default"

"$scripts/sim-lock.sh" job true
expect "a job keeps a watcher of its own version" "$(is_running "$idle_watcher") $(cat "$RATP_SIM_LOCK.slots-watcher")" "running $idle_watcher"

newer_watcher=$(fake_watcher newer-watcher $((version + 1)))
echo "$newer_watcher" > "$RATP_SIM_LOCK.slots-watcher"
"$scripts/sim-lock.sh" job true
expect "a job keeps a watcher of newer scripts" "$(is_running "$newer_watcher") $(cat "$RATP_SIM_LOCK.slots-watcher")" "running $newer_watcher"
kill "$newer_watcher"
pretend_a_watcher_runs

old_watcher=$(fake_watcher old-watcher)
older_watcher=$(fake_watcher older-watcher)
echo "$old_watcher" > "$RATP_SIM_LOCK.slots-watcher"
echo "$older_watcher" > "$RATP_SIM_LOCK.watcher"
echo "RATP-Shared Shutdown" > "$state/device.$default"
RATP_SIM_WATCH_SECONDS=1 RATP_SIM_SIZE=small "$scripts/sim-lock.sh" open "$scripts/simulator.sh" boot > /dev/null
wait_until_stopped "$old_watcher"
wait_until_stopped "$older_watcher"
expect "make run stops the watchers of old scripts" "$(is_running "$old_watcher") $(is_running "$older_watcher")" "stopped stopped"
expect "make run starts a watcher of its own scripts in their place" "$(command_of_started_watcher)" "$scripts/sim-lock.sh watch $version"
echo "RATP-Shared Booted" > "$state/device.$default"
wait_until_booted "RATP-Shared-Small "
expect "after an old watcher ran, the watcher shuts down RATP-Shared that another tool boots while make run SMALL=1 keeps the lock" "$(booted)" "RATP-Shared-Small "
"$scripts/sim-lock.sh" free
stop_started_watcher
echo "RATP-Shared-Small Shutdown" > "$state/device.$small"

mkdir -p "$state/removed/ios"
cp -R "$scripts" "$state/removed/ios/scripts"
hold "$RATP_SIM_LOCK"
RATP_SIM_WATCH_SECONDS=1 "$state/removed/ios/scripts/sim-lock.sh" watch > /dev/null 2>&1 &
watcher=$!
wait_for grep -qx "$watcher" "$RATP_SIM_LOCK.slots-watcher"
rm -rf "$state/removed"
wait_until_stopped "$watcher"
expect "a watcher stops when its worktree is removed" "$(is_running "$watcher")" "stopped"
stop_watcher
rm -rf "$RATP_SIM_LOCK"

"$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null
expect "a job keeps RATP-Shared booted after it ends" "$(booted)" "RATP-Shared "

echo "RATP-Shared-Small Booted" > "$state/device.$small"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null
expect "a job shuts down a small Simulator left booted" "$(booted)" "RATP-Shared "

echo "RATP-Shared Shutdown" > "$state/device.$default"
echo "RATP-Shared-Small Booted" > "$state/device.$small"
no_shutdown=$(FAKE_SHUTDOWN_FAILS=1 "$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset sh -c 'echo ran > "$FAKE_SIM_STATE/no-shutdown"' > /dev/null 2>&1 && echo passes || echo fails)
expect "a job does not boot RATP-Shared when it cannot shut down the small Simulator" "$(booted)" "RATP-Shared-Small "
expect "a job fails and does not run its command when it cannot shut down the small Simulator" "$no_shutdown $(cat "$state/no-shutdown" 2> /dev/null || true)" "fails "
expect "a job that cannot shut down the small Simulator frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

"$scripts/sim-lock.sh" job false > /dev/null 2>&1 || true
expect "a failed job frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

touch -t 202001010000 "$RATP_SIM_LOCK.last"
RATP_SIM_IDLE_MINUTES=1 "$scripts/sim-lock.sh" watch
pretend_a_watcher_runs
expect "the idle watcher shuts down every shared Simulator" "$(booted)" ""

"$scripts/sim-lock.sh" job "$scripts/simulator.sh" boot > /dev/null
printf '%s\n' com.apple.Maps com.example.trome.dev com.example.trome.dev.uitests.xctrunner com.other.App > "$state/prefs.$default"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job deletes the saved settings that the app of an earlier job left on the Simulator" "$(tr '\n' ' ' < "$state/prefs.$default")" "com.apple.Maps com.other.App "
echo com.example.trome.dev >> "$state/prefs.$default"
expect "a job goes on when the Simulator lists settings of the app that it cannot delete" "$(FAKE_DEFAULTS_DELETE_FAILS=1 "$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null 2>&1 && echo reset || true)" "reset"

echo com.example.trome.dev > "$state/apps.$default"
echo "Allow TROME to also use your location even when you are not using the app?" > "$state/popup.$default"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job closes a system popup that an earlier job left on the Simulator" "$(test -e "$state/popup.$default" && echo shown || true)" ""
expect "a job restarts SpringBoard only after it removed the app of the earlier job" "$(cat "$state/apps-at-springboard-restart.$default" 2> /dev/null || echo "no restart")" ""
expect "a job goes on when SpringBoard does not say it is ready" "$(FAKE_SPRINGBOARD_NOT_READY=1 RATP_SPRINGBOARD_WAIT_SECONDS=1 "$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null 2>&1 && echo reset || true)" "reset"

chronod_line() {
    echo "2026-10-01 15:31:19.389 Df chronod[28175:eb6459] [com.apple.chrono:taskservice] $1"
}
chronod_busy() {
    chronod_line "Add pending task: descriptor<com.example.trome.dev::com.example.trome.dev.widget>.84AB4E5B"
    chronod_line "No available queue to process pending tasks"
}
chronod_idle() {
    chronod_line "[84AB4E5B]: task session completed in 0.070800s. time since creation: 0.070854s"
    chronod_line "No tasks pending"
}
wait_for_widget_host() {
    "$scripts/sim-lock.sh" job "$scripts/simulator.sh" wait-for-widget-host sh -c 'echo ran > "$FAKE_SIM_STATE/after-widget-host"' 2> "$state/widget-host.err" > /dev/null
    cat "$state/after-widget-host" 2> /dev/null || echo "did not run"
    rm -f "$state/after-widget-host" "$state/chronod-log.$default" "$state/chronod-log.$default.next"
}
widget_host_message() {
    sed -n -E 's/.*(Waiting for the widget host|still had work queued).*/\1/p' "$state/widget-host.err" | paste -s -d ' ' -
}
expect "a job runs at once when the widget host of the Simulator logs no work" "$(wait_for_widget_host) $(widget_host_message)" "ran "
{ chronod_busy; chronod_idle; } > "$state/chronod-log.$default"
expect "a job runs at once when the widget host has emptied its queue" "$(wait_for_widget_host) $(widget_host_message)" "ran "
{ chronod_idle; chronod_line "[84AB4E5B]: starting pended task descriptor<com.example.trome.dev::com.example.trome.dev.widget>.84AB4E5B; pendingTasks.count = 12"; } > "$state/chronod-log.$default"
chronod_line "[84AB4E5B]: starting pended task descriptor<com.example.trome.dev::com.example.trome.dev.widget>.84AB4E5B; pendingTasks.count = 0" > "$state/chronod-log.$default.next"
expect "a job waits while the widget host has tasks queued, then runs" "$(wait_for_widget_host) $(widget_host_message)" "ran Waiting for the widget host"
chronod_line "Would pop task, but all extensions are busy, namely [com.example.trome.dev::com.example.trome.dev.widget]" > "$state/chronod-log.$default"
expect "a job says that it waits for the widget host before it goes on at the limit, also when the limit is reached at the first check" "$(RATP_WIDGET_HOST_WAIT_SECONDS=0 wait_for_widget_host) $(widget_host_message)" "ran Waiting for the widget host still had work queued"

language_at_restart() {
    cat "$state/language-at-springboard-restart.$default" 2> /dev/null || echo "no restart"
}
RATP_SIM_LANGUAGE=fr "$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "RATP_SIM_LANGUAGE=fr sets the Simulator to French before SpringBoard restarts" "$(language_at_restart)" "fr fr_FR"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job sets the Simulator back to English by default" "$(language_at_restart)" "en en_US"
expect "an unknown language fails" "$(RATP_SIM_LANGUAGE=de "$scripts/simulator.sh" reset > /dev/null 2>&1 && echo reset || echo fails)" "fails"
: > "$state/apps.$default"
expect "sim-lock.sh reopen fails when this folder keeps no Simulator" "$("$scripts/sim-lock.sh" reopen true > /dev/null 2>&1 && echo reopened || echo fails)" "fails"
expect "switch-language fails when the app is not in the Simulator" "$(RATP_SIM_LANGUAGE=en "$scripts/simulator.sh" switch-language "$state/TROME.app" > /dev/null 2>&1 && echo switched || echo fails)" "fails"
echo com.example.trome.dev > "$state/apps.$default"
RATP_SIM_LANGUAGE=fr "$scripts/simulator.sh" switch-language "$state/TROME.app" > /dev/null
expect "switch-language keeps the app, sets the language and opens the app again" "$(cat "$state/apps.$default") $(language_at_restart) $(cat "$state/launched.$default")" "com.example.trome.dev fr fr_FR com.example.trome.dev"
rm -f "$state/launched.$default"
RATP_SIM_LANGUAGE=en "$scripts/simulator.sh" language > /dev/null
expect "language keeps the app and restarts SpringBoard in the language, with no app opened" "$(cat "$state/apps.$default") $(language_at_restart) $(cat "$state/launched.$default" 2> /dev/null || echo "not opened")" "com.example.trome.dev en en_US not opened"
echo 1 > "$state/global.$default.AppleICUForce24HourTime"
echo 1 > "$state/global.$default.AppleICUForce12HourTime"
echo false > "$state/global.$default.AppleMetricUnits"
echo Inches > "$state/global.$default.AppleMeasurementUnits"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job sets metres and the clock of its language, whatever an earlier job left" "$(cat "$state/global.$default.AppleMetricUnits" "$state/global.$default.AppleMeasurementUnits" | paste -s -d ' ' -) $(ls "$state" | grep -c "^global\.$default\.AppleICUForce" || true)" "true Centimeters 0"
RATP_SIM_CLOCK=12 RATP_SIM_LANGUAGE=fr "$scripts/simulator.sh" language > /dev/null
expect "language with RATP_SIM_CLOCK=12 forces a 12-hour clock, so that the lock screen shows the override time" "$(language_at_restart) $(cat "$state/global.$default.AppleICUForce12HourTime" 2> /dev/null || echo none)" "fr fr_FR true"
RATP_SIM_LANGUAGE=en "$scripts/simulator.sh" language > /dev/null
expect "language with no RATP_SIM_CLOCK removes the forced clock" "$(ls "$state" | grep -c "^global\.$default\.AppleICUForce" || true)" "0"
echo accessibility-extra-extra-extra-large > "$state/ui.$default.content_size"
echo dark > "$state/ui.$default.appearance"
"$scripts/sim-lock.sh" job "$scripts/simulator.sh" reset > /dev/null
expect "a job sets back the default text size and the light appearance that an earlier job changed" "$(cat "$state/ui.$default.content_size" "$state/ui.$default.appearance" | paste -s -d ' ' -)" "large light"

hold "$RATP_SIM_LOCK"
in_background "$scripts/sim-lock.sh" job sh -c 'echo "$RATP_SIM_SLOT" > "$FAKE_SIM_STATE/one-slot"'
expect "by default (one slot), a job waits for the other job even when the CPU is idle" "$(ran one-slot)" "waiting"
rm -rf "$RATP_SIM_LOCK"
finish_background
expect "by default, the job runs on slot 1 once the other job ends" "$(ran one-slot)" "1"

cat > "$state/nested-job.sh" << 'EOF'
"$1" job sh -c 'echo "$RATP_SIM_SLOT" > "$FAKE_SIM_STATE/nested"' &
inner=$!
tries=0
while [ ! -e "$FAKE_SIM_STATE/nested" ] && [ "$tries" -lt 20 ]; do
    sleep 1
    tries=$((tries + 1))
done
kill "$inner" 2> /dev/null || true
wait "$inner" 2> /dev/null || true
test -e "$RATP_SIM_LOCK/pid" && echo held > "$FAKE_SIM_STATE/after-nested"
EOF
"$scripts/sim-lock.sh" job sh "$state/nested-job.sh" "$scripts/sim-lock.sh" > /dev/null 2>&1 || true
expect "a job inside a job that holds the lock (make e2e inside make merge) runs at once" "$(ran nested)" "1"
expect "a job inside a job leaves the lock to the outer job" "$(ran after-nested)" "held"
expect "the outer job frees the lock when it ends" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

hold "$RATP_SIM_LOCK"
in_background env RATP_SIM_HELD_LOCK="$RATP_SIM_LOCK" RATP_SIM_HELD_PID=1 "$scripts/sim-lock.sh" job sh -c 'echo ran > "$FAKE_SIM_STATE/not-nested"'
expect "a job whose parent does not hold the lock waits for it" "$(ran not-nested)" "waiting"
rm -rf "$RATP_SIM_LOCK"
finish_background
expect "that job runs once the lock is free" "$(ran not-nested)" "ran"

mkdir -p "$state/other/ios" "$state/slow-bin"
cp -R "$scripts" "$state/other/ios/scripts"
other_scripts="$state/other/ios/scripts"
cat > "$state/slow-bin/cat" << 'EOF'
#!/bin/sh
case "${1:-}" in
    */udid)
        if mkdir "$FAKE_SIM_STATE/slow-read" 2> /dev/null; then
            tries=0
            until [ -e "$FAKE_SIM_STATE/session-kept" ] || [ "$tries" -ge 20 ]; do
                sleep 1
                tries=$((tries + 1))
            done
        fi
        ;;
esac
exec /bin/cat "$@"
EOF
chmod +x "$state/slow-bin/cat"
echo com.example.trome.dev > "$state/apps.$default"
cat > "$state/open-until-told.sh" << 'EOF'
"$1" boot > /dev/null
tries=0
until [ -e "$FAKE_SIM_STATE/session-may-end" ] || [ "$tries" -ge 20 ]; do
    sleep 1
    tries=$((tries + 1))
done
EOF
"$other_scripts/sim-lock.sh" open sh "$state/open-until-told.sh" "$other_scripts/simulator.sh" &
other_open=$!
wait_for test -e "$RATP_SIM_LOCK/pid"
RATP_SIM_POLL_SECONDS=1 PATH="$state/slow-bin:$PATH" "$scripts/sim-lock.sh" job sh -c '"$1" reset > /dev/null && echo ran > "$FAKE_SIM_STATE/after-session"' sh "$scripts/simulator.sh" > "$state/background.log" 2>&1 &
background=$!
wait_for test -e "$state/slow-read"
touch "$state/session-may-end"
wait "$other_open"
touch "$state/session-kept"
tries=0
until grep -q "Waiting for the Simulator lock" "$state/background.log" || [ -e "$state/after-session" ] || [ "$tries" -ge 20 ]; do
    sleep 1
    tries=$((tries + 1))
done
expect "a job of another folder that checks the lock while make run ends keeps waiting" "$(ran after-session)" "waiting"
expect "make run keeps its lock after it ends, while a job of another folder waits" "$(cat "$RATP_SIM_LOCK/worktree") $(cat "$RATP_SIM_LOCK/udid")" "$state/other $default"
expect "the waiting job says that make run of the other folder keeps the Simulator" "$(grep -c "the open Simulator of $state/other" "$state/background.log" || true)" "1"
watch_in_background
wait_for_two_watcher_passes
stop_watcher
expect "the watcher of another folder keeps the lock of make run" "$(cat "$RATP_SIM_LOCK/worktree" 2> /dev/null || true)" "$state/other"
expect "the waiting job does not remove the app of make run of the other folder" "$(cat "$state/apps.$default")" "com.example.trome.dev"
"$other_scripts/sim-lock.sh" free
finish_background
expect "the waiting job runs once the other folder runs make simulator-shutdown" "$(ran after-session)" "ran"

hold "$RATP_SIM_LOCK"
echo "$state/other" > "$RATP_SIM_LOCK/worktree"
in_background "$scripts/sim-lock.sh" job true
echo "$default" > "$RATP_SIM_LOCK/udid"
rm "$RATP_SIM_LOCK/pid"
wait_for logged "the open Simulator of $state/other"
expect "a waiting job says again who holds the lock when the job of make run in another folder ends and keeps the Simulator" \
    "$(grep -c "Waiting for the Simulator lock" "$state/background.log") $(grep -cF "a job in $state/other" "$state/background.log") $(grep -cF "the open Simulator of $state/other" "$state/background.log")" "2 1 1"
rm -rf "$RATP_SIM_LOCK"
finish_background

hold "$RATP_SIM_LOCK"
(cd "$scripts/../.." && pwd) > "$RATP_SIM_LOCK/worktree"
in_background "$other_scripts/sim-lock.sh" open sh -c 'echo ran > "$FAKE_SIM_STATE/open-after-job"'
expect "make run in another folder waits while a job holds the lock" "$(ran open-after-job)" "waiting"
rm -rf "$RATP_SIM_LOCK"
finish_background
expect "make run in the other folder runs once the job ends, and keeps the lock" "$(ran open-after-job) $(cat "$RATP_SIM_LOCK/worktree")" "ran $state/other"
"$other_scripts/sim-lock.sh" free
expect "make simulator-shutdown in the other folder frees the lock" "$(test -e "$RATP_SIM_LOCK" && echo held || true)" ""

export RATP_SIM_SLOTS=2
hold "$RATP_SIM_LOCK"
echo com.example.trome.dev > "$state/apps.$default"
"$scripts/sim-lock.sh" job sh -c 'echo "$RATP_SIM_SLOT" > "$FAKE_SIM_STATE/slot" && "$1" reset && "$1" with-destination echo > "$FAKE_SIM_STATE/destination"' \
    sh "$scripts/simulator.sh" > /dev/null
second=$(RATP_SIM_SLOT=2 "$scripts/simulator.sh" find)
expect "a job runs on slot 2 while another job holds slot 1" "$(ran slot)" "2"
expect "the job on slot 2 boots RATP-Shared-2 and keeps RATP-Shared booted" "$(booted)" "RATP-Shared RATP-Shared-2 "
expect "RATP-Shared-2 is an iPhone 17, like RATP-Shared" "$(cat "$state/type.$second")" "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
expect "the job on slot 2 runs its tests on RATP-Shared-2" "$(ran destination)" "-destination platform=iOS Simulator,id=$second"
expect "the job on slot 2 does not remove the app of the job on slot 1" "$(cat "$state/apps.$default")" "com.example.trome.dev"
expect "the job on slot 2 frees its lock and leaves the lock of slot 1 to its holder" "$(test -e "$RATP_SIM_LOCK.2" && echo held || true) $(cat "$RATP_SIM_LOCK/pid")" " $idle_watcher"

in_background env FAKE_CPU_IDLE=10 "$scripts/sim-lock.sh" job sh -c 'echo "$RATP_SIM_SLOT" > "$FAKE_SIM_STATE/cpu-slot"'
expect "a job does not run next to another one when the CPU is less than 25% idle" "$(ran cpu-slot)" "waiting"
expect "a job says that it waits for the CPU" "$(grep -c "the CPU is only 10% idle" "$state/background.log" || true)" "1"
rm -rf "$RATP_SIM_LOCK"
finish_background
expect "the job runs on slot 1 once the other job ends" "$(ran cpu-slot)" "1"

hold "$RATP_SIM_LOCK"
hold "$RATP_SIM_LOCK.2"
in_background "$scripts/sim-lock.sh" job sh -c 'echo "$RATP_SIM_SLOT" > "$FAKE_SIM_STATE/busy-slot"'
expect "a third job waits while both slots are busy" "$(ran busy-slot)" "waiting"
expect "a third job says that both slots are busy" "$(grep -c "every Simulator slot is busy" "$state/background.log" || true)" "1"
rm -rf "$RATP_SIM_LOCK.2"
finish_background
expect "the third job runs on slot 2 once it is free" "$(ran busy-slot)" "2"
rm -rf "$RATP_SIM_LOCK"

hold "$RATP_SIM_LOCK"
small_open
second_small=$(RATP_SIM_SLOT=2 RATP_SIM_SIZE=small "$scripts/simulator.sh" find)
expect "make run SMALL=1 next to a job on slot 1 shuts down RATP-Shared-2 and keeps RATP-Shared booted" "$(booted)" "RATP-Shared RATP-Shared-Small-2 "
expect "make simulator prints the Simulator that make run of this folder uses" "$("$scripts/sim-lock.sh" udid)" "$second_small"
"$scripts/sim-lock.sh" free
expect "make simulator-shutdown on slot 2 keeps the small Simulator of slot 2 booted" "$(booted)" "RATP-Shared RATP-Shared-Small-2 "
expect "make simulator-shutdown on slot 2 frees slot 2 only" "$(test -e "$RATP_SIM_LOCK.2" && echo held || true) $(cat "$RATP_SIM_LOCK/pid")" " $idle_watcher"
rm -rf "$RATP_SIM_LOCK"
expect "make simulator prints the ID of RATP-Shared when this folder has no open Simulator" "$("$scripts/sim-lock.sh" udid)" "$default"

hold "$RATP_SIM_LOCK.2"
in_background "$scripts/sim-lock.sh" all sh -c 'test -d "$RATP_SIM_LOCK" && test -d "$RATP_SIM_LOCK.2" && echo both > "$FAKE_SIM_STATE/all"'
expect "make simulator-delete waits for the jobs of every slot" "$(ran all)" "waiting"
rm -rf "$RATP_SIM_LOCK.2"
finish_background
expect "make simulator-delete runs with the locks of every slot" "$(ran all)" "both"
expect "make simulator-delete frees the locks of every slot" "$(ls -d "$RATP_SIM_LOCK" "$RATP_SIM_LOCK.2" 2> /dev/null || true)" ""

RATP_SIM_SLOT=2 "$scripts/simulator.sh" boot > /dev/null
touch -t 202001010000 "$RATP_SIM_LOCK.last" "$RATP_SIM_LOCK.2.last"
RATP_SIM_IDLE_MINUTES=1 "$scripts/sim-lock.sh" watch
pretend_a_watcher_runs
expect "the idle watcher shuts down the shared Simulators of every slot" "$(booted)" ""

echo "RATP-old-folder-abc Shutdown" > "$state/device.$old"
"$scripts/simulator.sh" delete-old > /dev/null
expect "make simulator-delete-old keeps the small Simulator" "$(test -e "$state/device.$small" && echo kept || true)" "kept"
expect "make simulator-delete-old keeps the Simulators of slot 2" "$(test -e "$state/device.$second" && test -e "$state/device.$second_small" && echo kept || true)" "kept"
expect "make simulator-delete-old deletes an old Simulator" "$(test -e "$state/device.$old" && echo kept || true)" ""

"$scripts/simulator.sh" delete > /dev/null
expect "make simulator-delete deletes the shared Simulators of every slot" "$(xcrun simctl list devices | grep -c RATP-Shared || true)" "0"

[ "$failures" -eq 0 ]
