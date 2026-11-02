#!/bin/sh
# The release archive check in make check (release-archive-gate.py, ios/checks/*-release-archive-gate.mk), in throwaway
# repos: a branch that deletes or renames a type that the archive check looks for fails make check when the archive
# check fails, and a branch that touches none of its inputs builds no archive (a stand-in takes the place of the archive).
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE MAKEFLAGS MAKELEVEL || true

# The type of the silent start, as the archive check names it: the test follows the check.
push_type=$(sed -n 's/^SILENT_START_TYPE = "\(.*\)"$/\1/p' "$ios/scripts/release-entitlements-check.py")
wake_type=$(sed -n 's/^WAKE_LOG_TYPE = "\(.*\)"$/\1/p' "$ios/scripts/release-entitlements-check.py")
gate_file=$(cd "$ios/checks" && ls ./*-release-archive-gate.mk)
gate_file=${gate_file#./}

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

write() {
    mkdir -p "$(dirname "$repo/$1")"
    printf '%s\n' "$2" > "$repo/$1"
}

commit() {
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "${1:-change}"
}

# A repo as the app has it on main: the type of the silent start, the place that uses it, the Wake log, other code.
reset_repo() {
    rm -rf "$repo"
    git init -q -b main "$repo"
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    mkdir -p "$repo/ios/scripts" "$repo/ios/checks"
    cp "$ios/scripts/release-archive-gate.py" "$ios/scripts/release-entitlements-check.py" "$repo/ios/scripts/"
    cp "$ios/checks/$gate_file" "$repo/ios/checks/"
    write ios/App/AutoLiveActivity/Push.swift "#if SILENT_START
final class $push_type: NSObject, UIApplicationDelegate {}
#endif"
    write ios/App/TROMEApp.swift "@UIApplicationDelegateAdaptor($push_type.self) private var delegate"
    write ios/App/TestingTools/WakeLog.swift "#if WAKE_LOG
struct $wake_type: View {}
#endif"
    write ios/App/Trains/NextTrains.swift "struct NextTrains: View {}"
    write ios/project.yml "name: TROME"
    write ios/Config/Base.xcconfig "APP_BUNDLE_ID = io.example.trome"
    write ios/Makefile "build:
	xcodebuild build
release-archive-check:
	xcodebuild archive"
    write docs/index.md "# Docs"
    commit first
    git -C "$repo" checkout -q -b task
}

# The decision of the gate alone: run (exit 0) or skip (exit 10).
decision() {
    status=0
    (cd "$repo/ios" && ./scripts/release-archive-gate.py) > "$state/out" 2>&1 || status=$?
    case $status in
        0) echo run ;;
        10) echo skip ;;
        *) echo "error $status: $(cat "$state/out")" ;;
    esac
}

# make release-archive-gate, as make check runs it, with a stand-in archive check that fails as the real one would on
# a missing type: prints whether make passes, and whether the stand-in ran.
gate() {
    rm -f "$state/archive-ran"
    status=0
    make --no-print-directory -C "$repo/ios" -f "checks/$gate_file" release-archive-gate \
        RELEASE_ARCHIVE_GATE_RUN="touch $state/archive-ran; echo 'release-entitlements-check: FAILED: no silent start' >&2; exit 1" \
        > "$state/out" 2>&1 || status=$?
    ran=no
    [ ! -f "$state/archive-ran" ] || ran=yes
    if [ "$status" -eq 0 ]; then echo "passes, archive ran: $ran"; else echo "fails, archive ran: $ran"; fi
}

said() {
    grep -c -- "$1" "$state/out" || true
}

reset_repo
expect "the type names come from the archive check" "$([ -n "$push_type" ] && [ -n "$wake_type" ] && echo found)" found

# The case of the incident: a branch deletes the type that the archive check looks for.
git -C "$repo" rm -q ios/App/AutoLiveActivity/Push.swift
write ios/App/TROMEApp.swift "struct TROMEApp: App {}"
commit "refactor: the start token has a new home"
expect "a branch that deletes a type of the archive check fails make check when the archive check fails" "$(gate)" "fails, archive ran: yes"
expect "the gate names the file that held the type" "$(said "ios/App/AutoLiveActivity/Push.swift")" 1

reset_repo
write ios/App/AutoLiveActivity/Push.swift "#if SILENT_START
final class StartTokenDelegate: NSObject, UIApplicationDelegate {}
#endif"
commit "refactor: rename"
expect "a branch that renames a type of the archive check runs it" "$(decision)" run

reset_repo
write ios/App/Trains/NextTrains.swift "struct NextTrains: View { let late = true }"
write docs/index.md "# Docs, again"
commit "feat: other code"
expect "a branch that touches none of the inputs builds no archive" "$(gate)" "passes, archive ran: no"
expect "the gate says why it skips" "$(said "skipped")" 1

reset_repo
write ios/Makefile "build:
	xcodebuild build -quiet
release-archive-check:
	xcodebuild archive"
commit "build: quiet"
expect "a change of ios/Makefile away from the archive check runs no archive" "$(decision)" skip
write ios/Makefile "build:
	xcodebuild build -quiet
release-archive-check:
	xcodebuild archive -quiet"
commit "build: quiet archive"
expect "a change of the archive check lines of ios/Makefile runs it" "$(decision)" run

for input in ios/project.yml ios/Config/Base.xcconfig ios/scripts/release-entitlements-check.py "ios/checks/$gate_file"; do
    reset_repo
    printf '\n# changed\n' >> "$repo/$input"
    commit "change $input"
    expect "a change of $input runs the archive check" "$(decision)" run
done

reset_repo
write ios/App/TestingTools/WakeLog.swift "struct $wake_type: View {}"
expect "a change not committed yet of a file of a type runs the archive check" "$(decision)" run

reset_repo
write ios/App/Trains/Hub.swift "let screen = $wake_type()"
expect "a new file that names a type runs the archive check" "$(decision)" run

reset_repo
git -C "$repo" branch -q -m main old-main
expect "with no main to compare with, the archive check runs" "$(decision)" run

if [ "$failures" -ne 0 ]; then
    echo "release-archive-gate-test: $failures FAILED"
    exit 1
fi
echo "release-archive-gate-test: OK"
