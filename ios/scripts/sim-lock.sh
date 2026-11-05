#!/bin/sh
set -eu

base_lock=${RATP_SIM_LOCK:-/tmp/ratp-sim.lock}
watcher="$base_lock.slots-watcher"
# The jobs that wait for the Simulator stand in a line: one file each, named by when it asked (in microseconds) and its PID.
# Jobs that are not merges get the lock in the order in which they asked, not the first to look after a release.
# A merge goes before them, but a job that one merge has passed goes before the next merge: no job waits behind two merges.
line="$base_lock.line"
# The key of the last merge that took the lock: the jobs in line that asked before it were passed once.
passed="$line/passed"
my_entry=
nl='
'
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
# How long a stopped job has to end (a test run cancels, a script puts the Simulator back) before it is killed.
stop_seconds=${RATP_SIM_STOP_SECONDS:-60}
watcher_version=4
held_slots=
# Each Simulator job adds one line here when it frees the Simulator: when it asked, how long it waited, how long it held it.
# It is outside /tmp, so a restart of the Mac keeps it; 'make simulator-times' sums it up.
logs=${TROME_LOGS:-$HOME/Library/Logs/TROME}
jobs_log="$logs/simulator-jobs.tsv"
# Each check that runs as a Simulator job also adds one JSON line to the check ledger of the repo (see record_check).
# A script test sets TROME_CHECK_LEDGER to a file of its own, so it never writes the ledger of the repo.
check_ledger=${TROME_CHECK_LEDGER:-}
# The kinds of job that check nothing: they hold the Simulator, but they have no place in the check ledger.
not_checks=" simulator-delete-old simulator-wallpaper "
check_started=
joined_session=
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
    echo "       $0 lane               Print one line: the Simulator jobs that run and those that wait, with their kind and folder (takes no lock)" >&2
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
        # Its kind (e2e, run...), from its record; a job of no kind is "job".
        held_kind=$(cut -f 3 "$lock/job" 2> /dev/null || true)
        [ "$held_kind" != job ] || held_kind=
        echo "a job${held_kind:+ ($held_kind)} in $worktree (PID $pid)"
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

iso_time() {
    date -r "$1" +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9][0-9])$/:\1/'
}

json_string() {
    printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# Adds one line to the check ledger: a JSON object with the check (the kind of the job), its result, when it started,
# how long it ran and waited for the lane, where it ran (FACTORY_CHECK_WHERE: merge, main; branch when unset), its commit
# and its task (from the folder name task-<n>). A job reports a pass on a retry by writing "flaky" in $TROME_CHECK_RESULT.
# $1: the exit status of the job, $2: when it started, $3: its wait, $4: its kind, $5: its result file.
# The ledger is a record, not a check: a write that fails never changes the end or the exit status of the job.
record_check() {
    case "$not_checks" in *" $4 "*) return 0 ;; esac
    {
        result=red
        if [ "$1" -eq 0 ]; then
            result=green
            [ "$(cat "$5" 2> /dev/null)" != flaky ] || result=flaky
        fi
        ledger=$check_ledger
        if [ -z "$ledger" ]; then
            common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir) || return 0
            ledger="$common/factory-checks.jsonl"
        fi
        commit=$(git -C "$root" rev-parse HEAD 2> /dev/null || true)
        folder=$(basename "$root")
        task=null
        case "$folder" in
            task- | task-*[!0-9]*) ;;
            task-*) task=$(json_string "TASK-${folder#task-}") ;;
        esac
        printf '{"at": %s, "check": %s, "result": "%s", "seconds": %s, "waited": %s, "where": %s, "commit": %s, "task": %s}\n' \
            "$(json_string "$(iso_time "$2")")" "$(json_string "$4")" "$result" "$(($(date +%s) - $2))" "${3:-0}" \
            "$(json_string "${FACTORY_CHECK_WHERE:-branch}")" "$(json_string "$commit")" "$task" >> "$ledger"
    } 2> /dev/null || true
}

# The check of a job that holds the lock: its line, unless the checks inside it wrote theirs (the checks of 'make merge').
# A job stopped by a signal says nothing about its check: it has no line.
record_held_check() {
    [ -n "$check_started" ] && [ -z "${job_signal:-}" ] && [ -n "${RATP_SIM_HELD_LOCK:-}" ] || return 0
    if [ ! -e "$RATP_SIM_HELD_LOCK/checks-inside" ]; then
        check_wait=0
        if [ -z "$joined_session" ]; then
            check_wait=$(cut -f 4 "$RATP_SIM_HELD_LOCK/job" 2> /dev/null || true)
        fi
        check_kind=${RATP_SIM_KIND:-job}
        [ -z "${RATP_SIM_MERGE:-}" ] || check_kind=merge
        record_check "$1" "$check_started" "${check_wait:-0}" "$check_kind" "$TROME_CHECK_RESULT"
    fi
    rm -rf "$RATP_SIM_HELD_LOCK/checks-inside" "$TROME_CHECK_RESULT" 2> /dev/null || true
}

# A job that starts inside a job that holds the lock runs at once, in its slot, and adds its own line to the ledger.
# The first one also takes the wait of the job that holds the lock, so a merge counts its wait once.
run_inside_held_job() {
    inside_started=$(date +%s)
    inside_result="$RATP_SIM_HELD_LOCK/check-result.$$"
    inside_status=0
    TROME_CHECK_RESULT=$inside_result "$@" || inside_status=$?
    inside_wait=0
    if mkdir "$RATP_SIM_HELD_LOCK/checks-inside" 2> /dev/null; then
        inside_wait=$(cut -f 4 "$RATP_SIM_HELD_LOCK/job" 2> /dev/null || true)
    fi
    record_check "$inside_status" "$inside_started" "${inside_wait:-0}" "${RATP_SIM_KIND:-job}" "$inside_result"
    rm -f "$inside_result"
    exit "$inside_status"
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

ordinal() {
    case $(($1 % 100)) in
        11 | 12 | 13)
            echo "${1}th"
            return
            ;;
    esac
    case $(($1 % 10)) in
        1) echo "${1}st" ;;
        2) echo "${1}nd" ;;
        3) echo "${1}rd" ;;
        *) echo "${1}th" ;;
    esac
}

# A process is told apart from a later process with the same PID by the time when it started.
started_at() {
    LC_ALL=C ps -p "$1" -o lstart= 2> /dev/null | sed -E 's/ +/ /g; s/^ //; s/ $//'
}

# A job joins the line when it starts to wait, and leaves it when it takes the lock or ends (on_exit).
join_line() {
    [ -z "$my_entry" ] || return 0
    my_key=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000000')
    my_entry="$my_key.$$"
    my_kind=job
    [ -z "${RATP_SIM_MERGE:-}" ] || my_kind=merge
    my_start=$(started_at "$$")
    trap on_exit EXIT
    write_entry
}

# The kind of the job (e2e, run...) is in a file of its own, for 'lane': the scripts of an older branch read the entry.
write_entry() {
    mkdir -p "$line"
    if [ "$my_kind" = merge ]; then
        echo merge > "$line/.kind.$my_entry"
    else
        echo "${RATP_SIM_KIND:-job}" > "$line/.kind.$my_entry"
    fi
    printf '%s\n%s\n%s\n' "$my_kind" "$my_start" "$root" > "$line/.new.$$"
    mv "$line/.new.$$" "$line/$my_entry"
}

leave_line() {
    [ -n "$my_entry" ] || return 0
    rm -f "$line/$my_entry" "$line/.new.$$" "$line/.kind.$my_entry"
    my_entry=
}

# A merge that takes the lock passes the jobs in line that asked before it: they go before the next merge.
mark_passed() {
    [ "$my_kind" = merge ] || return 0
    read_passed
    [ "$my_key" -gt "$passed_key" ] || return 0
    echo "$my_key" > "$line/.passed.$$"
    mv "$line/.passed.$$" "$passed"
}

read_passed() {
    passed_key=$(cat "$passed" 2> /dev/null || true)
    case $passed_key in "" | *[!0-9]*) passed_key=0 ;; esac
}

# Reads the line in its order: the jobs that a merge has passed, then the merges, then the other jobs, each in the order
# in which they asked. A waiter that has ended leaves the line here, also when the system gave its PID to another process
# (its start time differs); a suspended waiter keeps its place, but the others go before it while it is suspended.
# Sets place (where this job stands, from 1) and merge_ahead (the folder of the first merge before it, if any).
read_line() {
    [ -f "$line/$my_entry" ] || write_entry
    read_passed
    in_line=
    for entry in "$line"/[0-9]*.[0-9]*; do
        [ -f "$entry" ] || continue
        name=${entry##*/}
        key=${name%%.*}
        pid=${name#*.}
        case "$key.$pid" in *[!0-9.]* | *.*.*) continue ;; esac
        if [ "$name" = "$my_entry" ]; then
            entry_kind=$my_kind
            entry_root=$root
        else
            content=$(cat "$entry" 2> /dev/null || true)
            entry_kind=${content%%"$nl"*}
            content=${content#*"$nl"}
            entry_start=${content%%"$nl"*}
            entry_root=${content#*"$nl"}
            process=$(LC_ALL=C ps -p "$pid" -o stat= -o lstart= 2> /dev/null | sed -E 's/ +/ /g; s/^ //; s/ $//')
            if [ -z "$process" ] || [ "${process#* }" != "$entry_start" ]; then
                rm -f "$entry" "$line/.kind.$name"
                continue
            fi
            case $process in T*) continue ;; esac
        fi
        rank=3
        if [ "$entry_kind" = merge ]; then
            rank=2
        elif [ "$key" -lt "$passed_key" ]; then
            rank=1
        fi
        in_line="$in_line$rank $key $name $entry_kind $entry_root$nl"
    done
    place=0
    merge_ahead=
    while read -r rank key name entry_kind entry_root; do
        [ -n "$name" ] || continue
        place=$((place + 1))
        [ "$name" != "$my_entry" ] || break
        [ "$entry_kind" != merge ] || [ -n "$merge_ahead" ] || merge_ahead=$entry_root
    done << LINE
$(printf '%s' "$in_line" | sort -k1,1n -k2,2n)
LINE
}

# Sets the line that a job that waits prints (its place, and who holds the lock), and records why it waited.
wait_in_line() {
    wait_kind=$1
    [ -z "$merge_ahead" ] || waited_for merge
    waited_for "$wait_kind"
    wait_reason="$(ordinal "$place") in line${merge_ahead:+, a merge goes first ($merge_ahead)}, $2"
}

# The first in line looks at the lock every second, so that a free lock does not stay idle while the others wait.
wait_a_little() {
    if [ "$place" -eq 1 ]; then
        sleep 1
    else
        sleep "$poll_seconds"
    fi
}

# Returns 0 with the lock of a free slot; 1 when the job waits ($wait_kind, $wait_reason), or another job took the slot first (race).
try_to_take_a_slot() {
    free_slots=
    busy=
    read_line
    for candidate in $(all_slots); do
        use_slot "$candidate"
        if [ ! -e "$lock" ] || remove_if_stale; then
            free_slots="$free_slots $candidate"
        elif [ "$slots" -eq 1 ]; then
            busy=$(describe_holder)
        else
            busy="$busy${busy:+; }slot $candidate: $(describe_holder)"
        fi
    done
    if [ -z "$free_slots" ]; then
        if [ "$slots" -eq 1 ]; then
            wait_in_line busy "held by $busy"
        else
            wait_in_line busy "every Simulator slot is busy ($busy)"
        fi
        return 1
    fi
    if [ "$place" -gt 1 ]; then
        wait_in_line line "free for the $(ordinal 1)"
        return 1
    fi
    if [ -n "$busy" ]; then
        idle=$(cpu_idle_percent)
        if [ "$idle" -lt "$min_idle_percent" ]; then
            wait_in_line cpu "a Simulator slot is free, but the CPU is only $idle% idle, and a job next to another one needs $min_idle_percent% ($busy)"
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
    join_line
    until try_to_take_a_slot; do
        if [ "$wait_kind" = race ]; then
            sleep 1
            continue
        fi
        if [ "$wait_kind $place $merge_ahead $busy" != "$said" ]; then
            echo "Waiting for the Simulator lock: $wait_reason" >&2
            said="$wait_kind $place $merge_ahead $busy"
        fi
        wait_a_little
    done
    take
    stamp "$1"
    mark_passed
    leave_line
    start_watcher
    if [ -n "$said" ]; then
        echo "Got the Simulator lock$(slot_name)" >&2
    fi
}

# With one slot (the default), the messages say nothing about slots.
slot_name() {
    [ "$slots" -eq 1 ] || echo " (slot $RATP_SIM_SLOT)"
}

acquire_slot() {
    said=
    start_waiting
    join_line
    while :; do
        read_line
        if [ "$place" -eq 1 ] && mkdir "$lock" 2> /dev/null; then
            break
        fi
        if [ -e "$lock" ] && remove_if_stale; then
            continue
        fi
        if [ -e "$lock" ]; then
            wait_in_line busy "held by $(describe_holder)"
        elif [ "$place" -gt 1 ]; then
            wait_in_line line "free for the $(ordinal 1)"
        else
            sleep 1
            continue
        fi
        if [ "$wait_reason" != "$said" ]; then
            echo "Waiting for the Simulator lock$(slot_name): $wait_reason" >&2
            said=$wait_reason
        fi
        wait_a_little
    done
    take
    stamp all
}

enter() {
    if find_session; then
        joined_session=1
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

# One line on the Simulator lane: the jobs that hold it and the jobs that wait, in the order of the line, each with its kind
# and its folder. It only reads: it takes no lock, removes nothing, and boots no Simulator.
lane() {
    now=$(date +%s)
    runs=0
    running=
    for candidate in $(all_slots); do
        use_slot "$candidate"
        [ -d "$lock" ] || continue
        runs=$((runs + 1))
        lane_kind=$(cut -f 3 "$lock/job" 2> /dev/null || true)
        lane_taken=$(cut -f 1 "$lock/job" 2> /dev/null || true)
        lane_folder=$(holder worktree)
        lane_folder=${lane_folder##*/}
        about="${lane_kind:-job}, ${lane_folder:-by hand}"
        case $lane_taken in
            "" | *[!0-9]*) ;;
            *) about="$about, $(((now - lane_taken) / 60)) min" ;;
        esac
        pid=$(holder pid)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2> /dev/null; then
            about="$about, stale"
        fi
        running="$running${running:+; }$about"
    done
    read_passed
    in_line=
    for entry in "$line"/[0-9]*.[0-9]*; do
        [ -f "$entry" ] || continue
        name=${entry##*/}
        key=${name%%.*}
        pid=${name#*.}
        case "$key.$pid" in *[!0-9.]* | *.*.*) continue ;; esac
        content=$(cat "$entry" 2> /dev/null || true)
        entry_kind=${content%%"$nl"*}
        content=${content#*"$nl"}
        entry_start=${content%%"$nl"*}
        entry_root=${content#*"$nl"}
        [ "$(started_at "$pid")" = "$entry_start" ] || continue
        rank=3
        if [ "$entry_kind" = merge ]; then
            rank=2
        elif [ "$key" -lt "$passed_key" ]; then
            rank=1
        fi
        shown_kind=$(cat "$line/.kind.$name" 2> /dev/null || true)
        in_line="$in_line$rank $key ${shown_kind:-$entry_kind}, ${entry_root##*/}$nl"
    done
    waits=0
    waiting=
    while read -r rank key about; do
        [ -n "$about" ] || continue
        waits=$((waits + 1))
        waiting="$waiting${waiting:+; }$about"
    done << LINE
$(printf '%s' "$in_line" | sort -k1,1n -k2,2n)
LINE
    if [ "$runs" -eq 0 ] && [ "$waits" -eq 0 ]; then
        echo "Simulator lane: free, no job waits."
        return 0
    fi
    echo "Simulator lane: $runs running${running:+ ($running)}, $waits waiting${waiting:+ ($waiting)}."
}

on_exit() {
    status=$?
    trap - EXIT
    leave_line
    record_held_check "$status"
    release "$status"
    exit "$status"
}

on_exit_if_failed() {
    status=$?
    trap - EXIT
    leave_line
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
    leave_line
    rm -f "$lock/pid"
    exit "$status"
}

# The Simulator was this folder's before the command, so a failed command keeps it: the folder can run it again.
reopen_simulator() {
    enter open
    trap on_reopen_exit EXIT
    "$@"
    "$simulator" udid > "$lock/udid"
}

# A stopped job must leave nothing running with the Simulator once the lock is free: a script stopped by a signal
# leaves its children running, and a signal to make or to this script does not reach the job by itself.
# So the job runs in its own session (one process group, whose processes stay in it when their parent is gone),
# a signal to this script goes to the whole group, and the lock is freed only when no process of the group is left.
# A command that this script starts in the background ignores INT and QUIT (the shell does so with no job control),
# so the job puts them back to their default, or an INT (Ctrl-C) would not reach it.
run_job() {
    job=
    job_ended=
    job_signal=
    trap 'stop_job HUP 129' HUP
    trap 'stop_job INT 130' INT
    trap 'stop_job TERM 143' TERM
    perl -MPOSIX -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; setsid(); exec { $ARGV[0] } @ARGV; print STDERR "$ARGV[0]: $!\n"; exit 127' \
        -- "$@" 0<&0 &
    job=$!
    # A signal that came before the job had its PID: pass it on now.
    if [ -n "$job_signal" ]; then
        signal_job "$job_signal_name"
    fi
    while :; do
        job_status=0
        wait "$job" || job_status=$?
        # A signal ends the wait while the job still runs: wait again.
        kill -0 "$job" 2> /dev/null || break
    done
    job_ended=1
    end_job_group
    return "${job_signal:-$job_status}"
}

stop_job() {
    if [ -z "$job_signal" ] && [ -n "$job" ]; then
        signal_job "$1"
    fi
    job_signal=$2
    job_signal_name=$1
}

# With no group yet, the job has not started its command, and it may still ignore INT: TERM stops it for sure.
# Once its first process has ended, its PID may be another process's: only the group gets the signal.
signal_job() {
    kill -"$1" -- "-$job" 2> /dev/null && return
    [ -n "$job_ended" ] || kill -TERM "$job" 2> /dev/null || true
}

# The processes that the job left when its first process ended. A stopped job has had its signal once:
# a second one would cut short the script that puts the Simulator back.
end_job_group() {
    if [ -z "$job_signal" ]; then
        kill -TERM -- "-$job" 2> /dev/null || return 0
        echo "Stopping what the Simulator job left running; the lock is freed when it has ended." >&2
    fi
    waited=0
    while kill -0 -- "-$job" 2> /dev/null; do
        if [ "$waited" -eq "$stop_seconds" ]; then
            echo "The Simulator job still runs $stop_seconds s after it was stopped: killing it." >&2
            kill -KILL -- "-$job" 2> /dev/null || true
        fi
        sleep 1
        waited=$((waited + 1))
    done
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
            run_inside_held_job "$@"
        fi
        enter job
        trap on_exit EXIT
        TROME_CHECK_RESULT="$RATP_SIM_HELD_LOCK/check-result"
        export TROME_CHECK_RESULT
        check_started=$(date +%s)
        run_job "$@"
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
        leave_line
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
    lane)
        lane
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
