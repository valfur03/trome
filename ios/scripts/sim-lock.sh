#!/bin/sh
set -eu

base_lock=${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}
watcher="$base_lock.slots-watcher"
merge_queue=${RATP_MERGE_QUEUE:-$base_lock.merge-queue}
# One Simulator job at a time: a second Simulator next to the first one takes the whole CPU of the Mac,
# and each job then runs several times slower. The code of a second slot stays, but off.
slots=${RATP_SIM_SLOTS:-1}
min_idle_percent=${RATP_SIM_MIN_IDLE_PERCENT:-25}
idle_minutes=${RATP_SIM_IDLE_MINUTES:-5}
poll_seconds=${RATP_SIM_POLL_SECONDS:-10}
scripts=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$scripts/../.." && pwd)
simulator="$scripts/simulator.sh"
watch_seconds=${RATP_SIM_WATCH_SECONDS:-10}
watcher_version=4
held_slots=
# Each Simulator job adds one line here when it frees the Simulator: when it asked, how long it waited, how long it held it.
# It is outside /tmp, so a restart of the Mac keeps it; 'make simulator-times' sums it up.
logs=${TROME_LOGS:-$HOME/Library/Logs/TROME}
jobs_log="$logs/simulator-jobs.tsv"
tab=$(printf '\t')
if [ -n "${RATP_SIM_MERGE:-}" ]; then
    # A merge looks at the lock every second, so it wins the free lock even against the scripts of an older branch.
    poll_seconds=1
fi

case "$slots" in
    "" | *[!0-9]* | 0)
        echo "Unknown RATP_SIM_SLOTS: $slots (use 1 or more)" >&2
        exit 1
        ;;
esac

usage() {
    echo "Usage: $0 job <command...>   Run a Simulator job with the lock of a free Simulator slot (at once inside a job that holds it)" >&2
    echo "       $0 open <command...>  Open the Simulator with the lock of a free slot, and keep the lock" >&2
    echo "       $0 free               Remove the app from the Simulator and free the lock that this folder keeps after 'open'" >&2
    echo "       $0 all <command...>   Run a command with the locks of every slot (waits until no other job runs)" >&2
    echo "       $0 reopen <command...> Run a command on the Simulator that this folder keeps after 'open' (same slot, same size), and keep the lock, also when the command fails" >&2
    echo "       $0 udid               Print the ID of the Simulator that this folder keeps after 'open', or of the Simulator of slot 1" >&2
    echo "       $0 watch              Shut down the shared Simulators of each slot after $idle_minutes minutes with no job, and, during a job, the other shared Simulator of its slot" >&2
    echo "At most $slots Simulator jobs run at once (RATP_SIM_SLOTS). A job runs next to another one only when the CPU is at least $min_idle_percent% idle (RATP_SIM_MIN_IDLE_PERCENT)." >&2
    exit 1
}

all_slots() {
    seq 1 "$slots"
}

use_slot() {
    RATP_SIM_SLOT=$1
    export RATP_SIM_SLOT
    if [ "$1" -eq 1 ]; then
        lock=$base_lock
    else
        lock="$base_lock.$1"
    fi
    last_job="$lock.last"
}

holder() {
    cat "$lock/$1" 2> /dev/null || true
}

is_booted() {
    booted=$(xcrun simctl list devices booted) || return 0
    printf '%s\n' "$booted" | grep -qF "($1)"
}

is_stale() {
    pid=$(holder pid)
    udid=$(holder udid)
    if [ -n "$pid" ]; then
        ! kill -0 "$pid" 2> /dev/null && [ "$(holder pid)" = "$pid" ]
    elif [ -n "$udid" ]; then
        [ ! -d "$(holder worktree)" ] || ! is_booted "$udid"
    else
        return 1
    fi
}

describe_holder() {
    worktree=$(holder worktree)
    pid=$(holder pid)
    if [ -n "$pid" ]; then
        echo "a job in $worktree (PID $pid)"
    elif [ -n "$(holder udid)" ]; then
        echo "the open Simulator of $worktree (run 'make simulator-shutdown' there to free it)"
    else
        echo "someone who took it by hand${worktree:+ ($worktree)}"
    fi
}

owns_session() {
    [ -z "$(holder pid)" ] && [ -n "$(holder udid)" ] && [ "$(holder worktree)" = "$root" ]
}

find_session() {
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if owns_session; then
            return 0
        fi
    done
    return 1
}

remove_if_stale() {
    find "$lock.reap" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2> /dev/null || true
    mkdir "$lock.reap" 2> /dev/null || return 1
    removed=1
    if is_stale; then
        echo "Removing a stale Simulator lock of $(holder worktree)" >&2
        record_job stale
        touch "$last_job"
        rm -rf "$lock"
        removed=0
    fi
    rmdir "$lock.reap"
    return "$removed"
}

write_size() {
    echo "${RATP_SIM_SIZE:-}" > "$lock/size.new"
    mv "$lock/size.new" "$lock/size"
}

one_line() {
    printf '%s' "$1" | tr '\t\n' '  '
}

# Called right after a job takes a free lock, with $asked (when it started to wait) and $waited_for (why it waited).
stamp() {
    taken=$(date +%s)
    kind=${RATP_SIM_KIND:-$1}
    if [ -n "${RATP_SIM_MERGE:-}" ]; then
        kind=merge
    fi
    branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2> /dev/null || echo "?")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$taken" "$asked_at" "$(one_line "$kind")" "$((taken - asked))" \
        "$(one_line "$(basename "$root")")" "$(one_line "$branch")" "$waited_for" > "$lock/job"
    one_line "${RATP_SIM_DETAIL:-}" > "$lock/detail"
}

start_waiting() {
    asked=$(date +%s)
    asked_at=$(date +%Y-%m-%dT%H:%M:%S%z)
    waited_for=
}

waited_for() {
    case ",$waited_for," in
        *",$1,"*) ;;
        *) waited_for="$waited_for${waited_for:+,}$1" ;;
    esac
}

# Adds the line of the job that holds $lock to the records; a job that the scripts of an older branch took has no line.
# Its variables start with rec_: a job that waits removes a stale lock here, and must keep its own asked_at and waited_for.
record_job() {
    [ -f "$lock/job" ] || return 0
    IFS=$tab read -r rec_taken rec_asked_at rec_kind rec_wait rec_worktree rec_branch rec_waited_for < "$lock/job" || return 0
    rec_hold=$(($(date +%s) - rec_taken))
    rec_gate_wait=$(cat "$lock/gate-wait" 2> /dev/null || true)
    rec_detail=$(cat "$lock/detail" 2> /dev/null || true)
    {
        mkdir -p "$logs" &&
            if [ ! -s "$jobs_log" ]; then
                printf 'asked\tkind\twait_s\thold_s\tgate_wait_s\tend\tworktree\tbranch\tdetail\twaited_for\n' >> "$jobs_log"
            fi &&
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rec_asked_at" "$rec_kind" "$rec_wait" "$rec_hold" "${rec_gate_wait:-0}" "$1" \
                "$rec_worktree" "$rec_branch" "$rec_detail" "$rec_waited_for" >> "$jobs_log"
    } 2> /dev/null || true
}

mark_held() {
    held_slots="$held_slots $RATP_SIM_SLOT"
    RATP_SIM_HELD_LOCK=$lock
    RATP_SIM_HELD_PID=$$
    export RATP_SIM_HELD_LOCK RATP_SIM_HELD_PID
}

take() {
    echo "$$" > "$lock/pid"
    echo "$root" > "$lock/worktree"
    write_size
    mark_held
}

join_session() {
    echo "$$" > "$lock/pid"
    write_size
    mark_held
}

in_held_job() {
    [ -n "${RATP_SIM_HELD_LOCK:-}" ] && [ -n "${RATP_SIM_HELD_PID:-}" ] || return 1
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if [ "$lock" = "$RATP_SIM_HELD_LOCK" ] && [ "$(holder pid)" = "$RATP_SIM_HELD_PID" ]; then
            return 0
        fi
    done
    return 1
}

keeps_running_watcher() {
    running_pid=$(cat "$1" 2> /dev/null || true)
    [ -n "$running_pid" ] || return 1
    running_command=$(ps -p "$running_pid" -o command= 2> /dev/null | grep -F "sim-lock.sh watch") || return 1
    running_version=$(printf '%s\n' "$running_command" | sed -n -E 's/.*sim-lock\.sh watch ([0-9]+).*/\1/p')
    if [ "${running_version:-0}" -ge "$watcher_version" ]; then
        return 0
    fi
    kill "$running_pid" 2> /dev/null || true
    return 1
}

write_watcher_pid() {
    echo "$1" > "$watcher.new.$$"
    mv "$watcher.new.$$" "$watcher"
}

start_watcher() {
    if keeps_running_watcher "$watcher"; then
        return 0
    fi
    keeps_running_watcher "$base_lock.watcher" || true
    perl -MPOSIX -e 'setsid(); exec @ARGV' "$scripts/sim-lock.sh" watch "$watcher_version" < /dev/null > /dev/null 2>&1 &
    write_watcher_pid "$!"
}

cpu_idle_percent() {
    idle=$(top -l 2 -n 0 -s 1 2> /dev/null | sed -n -E 's/^CPU usage:.* ([0-9]+)(\.[0-9]*)?% idle.*/\1/p' | tail -n 1)
    echo "${idle:-0}"
}

# A merge goes first: a job that is not a merge waits while a 'make merge' waits in the queue.
merge_waits() {
    [ -z "${RATP_SIM_MERGE:-}" ] || return 1
    for merge_entry in "$merge_queue"/*.task; do
        [ -f "$merge_entry" ] && [ ! -e "${merge_entry%.task}.result" ] || continue
        merge_pid=$(sed -n 's/^pid=//p' "$merge_entry" 2> /dev/null || true)
        # A pid that the system gave again to another process is not a merge that waits.
        if [ -n "$merge_pid" ] && ps -p "$merge_pid" -o command= 2> /dev/null | grep -q 'merge\.sh'; then
            merge_root=$(sed -n 's/^root=//p' "$merge_entry" 2> /dev/null || true)
            return 0
        fi
    done
    return 1
}

try_to_take_a_slot() {
    free_slots=
    busy=
    if merge_waits; then
        wait_kind=merge
        busy=$merge_root
        wait_reason="a merge goes first ($merge_root)"
        return 1
    fi
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if [ ! -e "$lock" ] || remove_if_stale; then
            free_slots="$free_slots $candidate"
        else
            busy="$busy${busy:+; }slot $candidate: $(describe_holder)"
        fi
    done
    if [ -z "$free_slots" ]; then
        wait_kind=busy
        wait_reason="every Simulator slot is busy ($busy)"
        return 1
    fi
    if [ -n "$busy" ]; then
        idle=$(cpu_idle_percent)
        if [ "$idle" -lt "$min_idle_percent" ]; then
            wait_kind=cpu
            wait_reason="a Simulator slot is free, but the CPU is only $idle% idle, and a job next to another one needs $min_idle_percent% ($busy)"
            return 1
        fi
    fi
    set -- $free_slots
    use_slot "$1"
    if mkdir "$lock" 2> /dev/null; then
        return 0
    fi
    wait_kind=race
    return 1
}

acquire() {
    said=
    start_waiting
    until try_to_take_a_slot; do
        if [ "$wait_kind" = race ]; then
            sleep 1
            continue
        fi
        waited_for "$wait_kind"
        if [ "$wait_kind $busy" != "$said" ]; then
            echo "Waiting for the Simulator lock: $wait_reason" >&2
            said="$wait_kind $busy"
        fi
        sleep "$poll_seconds"
    done
    take
    stamp "$1"
    start_watcher
    if [ -n "$said" ]; then
        echo "Got the Simulator lock (slot $RATP_SIM_SLOT)" >&2
    fi
}

acquire_slot() {
    said=
    start_waiting
    until ! merge_waits && mkdir "$lock" 2> /dev/null; do
        if merge_waits; then
            waited_for merge
            if [ "merge $merge_root" != "$said" ]; then
                echo "Waiting for the Simulator lock of slot $RATP_SIM_SLOT: a merge goes first ($merge_root)" >&2
                said="merge $merge_root"
            fi
            sleep "$poll_seconds"
            continue
        fi
        if [ ! -e "$lock" ]; then
            sleep 1
            continue
        fi
        if remove_if_stale; then
            continue
        fi
        waited_for busy
        held_by=$(describe_holder)
        if [ "$held_by" != "$said" ]; then
            echo "Waiting for the Simulator lock of slot $RATP_SIM_SLOT, held by $held_by" >&2
            said=$held_by
        fi
        sleep "$poll_seconds"
    done
    take
    stamp all
}

enter() {
    if find_session; then
        join_session
        start_watcher
    else
        acquire "$1"
    fi
}

# $1: how the job ended, for its record (the exit status of its command, or "freed" after 'open').
release() {
    released=
    for held in $held_slots; do
        use_slot "$held"
        if [ "$(holder pid)" = "$$" ] || owns_session; then
            record_job "$1"
            touch "$last_job"
            rm -rf "$lock"
            released=1
        fi
    done
    held_slots=
    if [ -n "$released" ]; then
        start_watcher
    fi
}

is_idle() {
    if [ ! -e "$last_job" ]; then
        touch "$last_job"
    fi
    [ -n "$(find "$last_job" -mmin +"$idle_minutes" 2> /dev/null)" ]
}

shut_down_the_other_shared() {
    size=$(cat "$lock/size" 2> /dev/null) || return 0
    others=$(RATP_SIM_SIZE=$size "$simulator" booted-others 2> /dev/null) || return 0
    for other in $others; do
        size_now=$(cat "$lock/size" 2> /dev/null) || return 0
        [ "$size_now" = "$size" ] || return 0
        xcrun simctl shutdown "$other" 2> /dev/null || true
    done
}

shut_down_if_idle() {
    is_idle && mkdir "$lock" 2> /dev/null || return 1
    take
    for booted_udid in $1; do
        xcrun simctl shutdown "$booted_udid" 2> /dev/null || true
    done
    rm -rf "$lock"
}

watch() {
    write_watcher_pid "$$"
    trap 'if [ "$(cat "$watcher" 2> /dev/null)" = "$$" ]; then rm -f "$watcher"; fi' EXIT
    while [ -e "$simulator" ]; do
        active=
        for candidate in $(all_slots); do
            use_slot "$candidate"
            if [ -e "$lock" ]; then
                if ! remove_if_stale 2> /dev/null; then
                    touch "$last_job"
                    shut_down_the_other_shared
                fi
                active=1
            elif ! booted_shared=$("$simulator" booted 2> /dev/null); then
                active=1
            elif [ -n "$booted_shared" ] && ! shut_down_if_idle "$booted_shared"; then
                active=1
            fi
        done
        [ -n "$active" ] || break
        sleep "$watch_seconds"
    done
}

on_exit() {
    status=$?
    trap - EXIT
    release "$status"
    exit "$status"
}

on_exit_if_failed() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        release "$status"
    fi
    exit "$status"
}

open_simulator() {
    enter open
    trap on_exit_if_failed EXIT
    "$@"
    "$simulator" udid > "$lock/udid"
    rm "$lock/pid"
}

on_reopen_exit() {
    status=$?
    trap - EXIT
    rm -f "$lock/pid"
    exit "$status"
}

# The Simulator was this folder's before the command, so a failed command keeps it: the folder can run it again.
reopen_simulator() {
    enter
    trap on_reopen_exit EXIT
    "$@"
    "$simulator" udid > "$lock/udid"
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

command=${1:-}
[ $# -gt 0 ] && shift

case "$command" in
    job)
        [ $# -gt 0 ] || usage
        if in_held_job; then
            exec "$@"
        fi
        enter job
        trap on_exit EXIT
        "$@"
        ;;
    open)
        [ $# -gt 0 ] || usage
        open_simulator "$@"
        ;;
    reopen)
        [ $# -gt 0 ] || usage
        if ! find_session; then
            echo "This folder keeps no Simulator. Run 'make run' first." >&2
            exit 1
        fi
        RATP_SIM_SIZE=$(holder size)
        export RATP_SIM_SIZE
        reopen_simulator "$@"
        ;;
    free)
        if find_session; then
            held_slots=$RATP_SIM_SLOT
            "$simulator" uninstall "$(holder udid)" || true
            release freed
        fi
        ;;
    all)
        [ $# -gt 0 ] || usage
        trap on_exit EXIT
        for candidate in $(all_slots); do
            use_slot "$candidate"
            if owns_session; then
                join_session
            else
                acquire_slot
            fi
        done
        start_watcher
        "$@"
        ;;
    udid)
        if find_session; then
            holder udid
        else
            use_slot 1
            "$simulator" udid
        fi
        ;;
    watch)
        if [ "${1:-}" != "$watcher_version" ]; then
            exec "$scripts/sim-lock.sh" watch "$watcher_version"
        fi
        watch
        ;;
    *)
        usage
        ;;
esac
