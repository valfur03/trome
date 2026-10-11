#!/bin/sh
# A Simulator job stopped by TERM (sent to its make, to quiet.sh, to the script, to sim-lock.sh, or to all of them):
# no process of the job goes on after the stop, the lock is freed only after the last one has ended,
# and the shared Simulator is left as it was (its wallpaper, its language, its status bar, its location).
# It runs the real chain of make docs-screenshots and make live-activity-render, with a fake xcrun and a fake xcodebuild.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
udid=11111111-1111-1111-1111-111111111111
failures=0
export FAKE_SIM_STATE="$state" PATH="$state/bin:$tests/bin:$PATH" RATP_SIM_LOCK="$state/lock" TROME_LOGS="$state/logs" \
    RATP_BUILD_GATE="$state/gate" RATP_MERGE_QUEUE="$state/merge-queue" TROME_SIM_DEVICES="$state/devices" \
    TROME_WIDGET_HOST_WAIT_SECONDS=1 RATP_SIM_STOP_SECONDS=20
unset RATP_SIM_SIZE RATP_SIM_SLOTS RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID RATP_SIM_MERGE RATP_BUILD_GATE_HELD VERBOSE || true

# A watcher of the lock that does nothing, so that the real one does not start.
mkdir "$state/watcher"
printf 'trap "kill \\$!; exit" TERM\nsleep 600 &\nwait\n' > "$state/watcher/sim-lock.sh"
/bin/sh "$state/watcher/sim-lock.sh" watch "$(sed -n 's/^watcher_version=//p' "$scripts/sim-lock.sh")" > /dev/null 2>&1 &
watcher=$!
echo "$watcher" > "$RATP_SIM_LOCK.slots-watcher"

# The processes of the run: every one has a path of $state in its command line.
run_processes() {
    pgrep -f "$state" | grep -vx "$watcher" | tr '\n' ' ' || true
}

# The processes of the job, which has its own process group: make, sim-lock.sh and what sim-lock.sh runs after the
# lock is freed stay in the group of make ($run), and end just after the lock is freed.
job_processes() {
    for pid in $(run_processes); do
        group=$(ps -o pgid= -p "$pid" 2> /dev/null) || continue
        [ "$group" -eq "$run" ] || printf '%s ' "$pid"
    done
}

cleanup() {
    kill "$watcher" 2> /dev/null || true
    for pid in $(run_processes); do
        kill -KILL "$pid" 2> /dev/null || true
    done
    rm -rf "$state"
}
trap cleanup EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# Waits for a condition, up to 30 s, every 0.2 s.
wait_for() {
    tries=0
    until "$@" || [ "$tries" -ge 150 ]; do
        sleep 0.2
        tries=$((tries + 1))
    done
}

# The repo as the scripts see it: they find the other scripts and the wallpaper id from their own folder.
mkdir -p "$state/ios" "$state/bin"
ln -s "$scripts" "$state/ios/scripts"
ln -s "$scripts/../DocsScreenshots" "$state/ios/DocsScreenshots"
printf '#!/bin/sh\nexit 0\n' > "$state/bin/pngquant"
cat > "$state/bin/xcrun" <<XCRUN
#!/bin/sh
# The pictures of a test run: none, with the manifest that xcresulttool writes.
if [ "\$1" = xcresulttool ]; then
    mkdir -p "\$7"
    echo '[]' > "\$7/manifest.json"
    exit 0
fi
exec "$tests/bin/xcrun" "\$@"
XCRUN
# The test run: the English pass of the pictures ends at once; the French pass, and a render, run until stopped.
# Stopped, it takes a moment to end, as xcodebuild does, then says whether the lock was still held.
cat > "$state/xcodebuild" <<'XCODEBUILD'
#!/bin/sh
[ "${TEST_RUNNER_DOCS_LANGUAGE:-}" = en ] && exit 0
stop() {
    sleep 1
    if [ -d "$RATP_SIM_LOCK" ]; then echo held; else echo freed; fi > "$FAKE_SIM_STATE/lock-at-test-end"
    exit 143
}
if [ -n "${FAKE_TEST_IGNORES_TERM:-}" ]; then trap '' TERM; else trap stop TERM; fi
echo $$ > "$FAKE_SIM_STATE/test-run.pid"
tries=0
while [ "$tries" -lt 60 ]; do
    sleep 1
    tries=$((tries + 1))
done
XCODEBUILD
chmod +x "$state/bin/pngquant" "$state/bin/xcrun" "$state/xcodebuild"

# The shared Simulator, in English, with the wallpaper of the pictures in use.
echo "RATP-Shared Booted" > "$state/device.$udid"
store="$state/devices/$udid/data/Library/Application Support/PRBPosterExtensionDataStore/61"
database="$store/PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3"
mkdir -p "$store"
sqlite3 "$database" "CREATE TABLE poster (posterId INTEGER PRIMARY KEY AUTOINCREMENT, UUID TEXT UNIQUE, providerId TEXT NOT NULL);
    CREATE TABLE posterRoleMembership (posterUUID TEXT NOT NULL, roleId TEXT NOT NULL, roleSortKey INTEGER NOT NULL);
    CREATE TABLE posterAttributes (posterUUID TEXT NOT NULL, roleId TEXT NOT NULL, attributeIdentifier TEXT NOT NULL, attributePayload TEXT NOT NULL);"
for poster in 67F8CF9C:celosia.timeOfDay 3ADCB97E:fluidity.three; do
    sqlite3 "$database" "INSERT INTO poster (UUID, providerId) VALUES ('${poster%%:*}', 'com.apple.MercuryPoster');
        INSERT INTO posterRoleMembership VALUES ('${poster%%:*}', 'PRPosterRoleLockScreen', (SELECT count(*) FROM posterRoleMembership));"
    mkdir -p "$store/Extensions/com.apple.MercuryPoster/configurations/${poster%%:*}"
    printf '%s' "${poster#*:}" > "$store/Extensions/com.apple.MercuryPoster/configurations/${poster%%:*}/com.apple.posterkit.provider.descriptor.identifier"
done
sqlite3 "$database" "INSERT INTO posterAttributes VALUES ('3ADCB97E', 'PRPosterRoleLockScreen', 'SELECTED', '1');"
"$scripts/simulator.sh" language > /dev/null
wallpapers=$("$scripts/wallpaper.sh" list "$udid")
language=$(cat "$state/global.$udid.AppleLanguages")
expect "before the runs, the wallpaper of the pictures is in use" "$("$scripts/wallpaper.sh" check "$udid" && echo yes)" "yes"

# The recipes of make docs-screenshots and make live-activity-render, behind a root make that runs make again, as the root Makefile does.
cat > "$state/Makefile" <<'MAKEFILE'
LOG := $(FAKE_SIM_STATE)/logs/job.log
FAKE_XCODEBUILD := $(FAKE_SIM_STATE)/xcodebuild

root-docs-screenshots root-live-activity-render:
	@$(MAKE) --no-print-directory -f $(FAKE_SIM_STATE)/Makefile $(subst root-,,$@)

docs-screenshots:
	@RATP_SIM_KIND=docs-screenshots ./scripts/sim-lock.sh job ./scripts/build-gate.py tests ./scripts/simulator.sh with-destination \
		./scripts/quiet.sh $(LOG) '^Saved ' ./scripts/docs-screenshots.sh $(FAKE_SIM_STATE)/docs.xcresult $(LOG) "$(FAKE_SIM_STATE)/App.app" \
		$(FAKE_XCODEBUILD) -scheme TROMEDocsScreenshots

live-activity-render:
	@RATP_SIM_KIND=live-activity-render ./scripts/sim-lock.sh job ./scripts/build-gate.py tests ./scripts/simulator.sh with-destination \
		./scripts/quiet.sh $(LOG) '^Simulator time' ./scripts/live-activity-render.sh render $(FAKE_SIM_STATE)/render \
		$(FAKE_XCODEBUILD) -scheme TROMERenderCheck test-without-building
MAKEFILE

lock_is_freed() {
    [ ! -d "$RATP_SIM_LOCK" ]
}

run_has_ended() {
    ! kill -0 "$run" 2> /dev/null
}

no_run_process() {
    [ -z "$(run_processes)" ]
}

last_call() {
    grep -E "^simctl $1 $udid" "$state/calls" | tail -n 1 | cut -d ' ' -f 4
}

# $1: the command (docs-screenshots or live-activity-render); $2: whom the signal goes to (make, sim-lock, quiet, script,
# all, or terminal: the process group of make, as Ctrl-C in a terminal does); $3: the case; $4: the signal (TERM by default).
# make runs in its own process group, with INT at its default, as in a terminal: a command that this script starts in the
# background would ignore INT.
stop_a_run() {
    command=$1
    target=$2
    case=$3
    signal=${4:-TERM}
    rm -f "$state/test-run.pid" "$state/lock-at-test-end" "$state/calls"
    (cd "$state/ios" && exec perl -MPOSIX -e 'setsid(); $SIG{INT} = "DEFAULT"; exec @ARGV' \
        make --no-print-directory -f "$state/Makefile" "root-$command") > "$state/run.log" 2>&1 &
    run=$!
    wait_for test -s "$state/test-run.pid"
    expect "$case: the test run started" "$(test -s "$state/test-run.pid" && echo yes)" "yes"
    case "$target" in
        make) pids=$run ;;
        terminal) pids=-$run ;;
        sim-lock) pids=$(pgrep -f "^/bin/sh [^ ]*scripts/sim-lock.sh job .*$state" || true) ;;
        quiet) pids=$(pgrep -f "^/bin/sh [^ ]*scripts/quiet.sh $state" || true) ;;
        script) pids=$(pgrep -f "^/bin/sh [^ ]*scripts/$command.sh .*$state" || true) ;;
        all) pids=$(run_processes) ;;
    esac
    expect "$case: $signal goes to $([ "$target" = all ] && echo "every process" || echo "one process or group")" \
        "$(echo $pids | wc -w | tr -d ' ')" "$([ "$target" = all ] && echo $pids | wc -w | tr -d ' ' || echo 1)"
    # shellcheck disable=SC2086
    kill -"$signal" -- $pids
    wait_for lock_is_freed
    left=$(job_processes)
    expect "$case: the lock is freed" "$(lock_is_freed && echo yes)" "yes"
    expect "$case: no process of the job is left when the lock is freed" "$left" ""
    expect "$case: the test run ended while the lock was still held" "$(cat "$state/lock-at-test-end" 2> /dev/null)" \
        "${expected_lock_at_test_end-held}"
    wait_for run_has_ended
    wait_for no_run_process
    expect "$case: the run has ended" "$(run_has_ended && echo yes)" "yes"
    expect "$case: no process of the run goes on" "$(run_processes)" ""
    status=0
    wait "$run" || status=$?
    expect "$case: the run failed" "$([ "$status" -ne 0 ] && echo yes)" "yes"
    expect "$case: the Simulator keeps its wallpapers" "$("$scripts/wallpaper.sh" list "$udid")" "$wallpapers"
    expect "$case: the wallpaper of the pictures is still in use (the check of the pictures)" \
        "$("$scripts/wallpaper.sh" check "$udid" && echo yes)" "yes"
    expect "$case: the Simulator is in English again" "$(cat "$state/global.$udid.AppleLanguages")" "$language"
    for target_pid in $(run_processes); do
        kill -KILL "$target_pid" 2> /dev/null || true
    done
    rm -rf "$RATP_SIM_LOCK"
}

for target in make quiet script sim-lock all; do
    stop_a_run docs-screenshots "$target" "docs-screenshots, TERM to $target"
    expect "docs-screenshots, TERM to $target: the status bar override is cleared" "$(last_call status_bar)" "clear"
    expect "docs-screenshots, TERM to $target: the fake location is cleared" "$(last_call location)" "clear"
done
for target in make quiet script; do
    stop_a_run live-activity-render "$target" "live-activity-render, TERM to $target"
done
# Ctrl-C in a terminal: INT to make, the make it runs and sim-lock.sh, but not to the job, which has its own session.
for target in terminal sim-lock; do
    stop_a_run docs-screenshots "$target" "docs-screenshots, INT to $target" INT
    expect "docs-screenshots, INT to $target: the status bar override is cleared" "$(last_call status_bar)" "clear"
done

# INT that comes while the job's perl still starts (before it puts INT back and opens its session) stops the job too.
# The perl of the job loads a module that waits 2 s first, so the signal comes in that moment.
mkdir -p "$state/perl"
echo 'package SlowStart; sleep 2; 1;' > "$state/perl/SlowStart.pm"
printf '#!/bin/sh\nsleep 60\n' > "$state/bin/long-job"
chmod +x "$state/bin/long-job"
perl -MPOSIX -e 'setsid(); $SIG{INT} = "DEFAULT"; exec @ARGV' env PERL5LIB="$state/perl" PERL5OPT=-MSlowStart \
    RATP_SIM_KIND=e2e "$scripts/sim-lock.sh" job "$state/bin/long-job" > "$state/run.log" 2>&1 &
run=$!
starting_job() {
    pgrep -f "^perl -MPOSIX -e .SIG.INT. = .SIG.QUIT. = .* -- $state/bin/long-job" > /dev/null
}
wait_for starting_job
expect "INT while the job starts: the job is starting" "$(starting_job && echo yes)" "yes"
kill -INT "$run"
wait_for lock_is_freed
expect "INT while the job starts: the lock is freed" "$(lock_is_freed && echo yes)" "yes"
wait_for no_run_process
expect "INT while the job starts: no process of the run goes on" "$(run_processes)" ""
status=0
wait "$run" || status=$?
expect "INT while the job starts: sim-lock.sh ends with the status of INT" "$status" "130"
rm -rf "$RATP_SIM_LOCK"

# A test run that does not stop on TERM is killed after RATP_SIM_STOP_SECONDS, and only then is the lock freed.
expected_lock_at_test_end=
export FAKE_TEST_IGNORES_TERM=1 RATP_SIM_STOP_SECONDS=2
stop_a_run live-activity-render make "a test run that ignores TERM"

if [ "$failures" -ne 0 ]; then
    echo "$failures failures"
    exit 1
fi
echo "All stop tests passed"
