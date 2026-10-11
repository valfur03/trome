#!/bin/sh
# Splits the time of a call to the production server of ios/Config/Server.xcconfig into its parts:
# the connection to Cloudflare, the Worker, the hop to the server object, and the wait for PRIM.
# It asks for the trains of one stop as a rider who opens it and waits 30 seconds: 5 calls, of which at most
# 2 make the server ask PRIM (the first one, and the one 30 seconds later if the server forgot its answer).
# It never prints the host or the token, never stores them, and never passes the token on a command line.
# Usage: release-server-timing.sh <path of Server.xcconfig>
set -u
export LC_ALL=C

# Abbesses (metro 12), the stop of the examples of contracts/api/ and of release-server-check.sh.
trains=/v1/stops/STIF:StopArea:SP:42155:/departures
health=/health
# The app asks again every 30 seconds while it shows a station.
wait=${RELEASE_SERVER_TIMING_TEST_WAIT:-30}

say() {
    echo "$1"
    exit "${2:-1}"
}

config=${1:?usage: release-server-timing.sh <path of Server.xcconfig>}
. "$(dirname "$0")/release-server-config.sh"

# The tests of this script set RELEASE_SERVER_CHECK_TEST_SERVER to a fake server (address:port), reached over plain HTTP.
if [ -n "${RELEASE_SERVER_CHECK_TEST_SERVER:-}" ]; then
    base="http://$host"
    reach="--connect-to $host:80:$RELEASE_SERVER_CHECK_TEST_SERVER"
else
    base="https://$host"
    reach="--proto =https"
fi

times='timing: %{time_appconnect} %{time_connect} %{time_starttransfer} %{time_pretransfer} %{time_total} %{http_code}\n'

# One call on a new connection, as the first call of the app after a quiet time. Prints the headers, then the times.
# -q first: no .curlrc. printf is a shell builtin: no process gets the token.
call() {
    # shellcheck disable=SC2086 # $reach is two words on purpose.
    if [ "$1" = "$trains" ]; then
        printf 'Authorization: Bearer %s\n' "$token" |
            curl -q --silent --max-time 20 --header @- --output /dev/null --dump-header - --write-out "$times" $reach "$base$1" 2>/dev/null
    else
        curl -q --silent --max-time 20 --output /dev/null --dump-header - --write-out "$times" $reach "$base$1" < /dev/null 2>/dev/null
    fi
}

header() { printf '%s\n' "$answer" | tr -d '\r' | grep -i "^$1:" | head -n 1 | sed 's/^[^:]*:[[:space:]]*//'; }
epoch() { [ -n "$1" ] && date -j -u -f '%a, %d %b %Y %T GMT' "$1" +%s 2>/dev/null; }

# The values of the last call: connect, server and total in ms, the edge, the HTTP status, and whether PRIM was asked.
last_lm=
prim_calls=0
measure() {
    answer=$(call "$1")
    set -- $(printf '%s\n' "$answer" | sed -n 's/^timing: //p')
    [ $# -eq 6 ] || say "The server at TRAIN_SERVER_HOST of $file cannot be reached: check your connection, then run this again."
    status=$6
    # Plain HTTP has no TLS step: the connection is then the TCP connect.
    connect=$(awk -v a="$1" -v c="$2" 'BEGIN { printf "%d", ((a > 0 ? a : c) * 1000) + 0.5 }')
    server=$(awk -v s="$3" -v p="$4" 'BEGIN { printf "%d", ((s - p) * 1000) + 0.5 }')
    total=$(awk -v t="$5" 'BEGIN { printf "%d", (t * 1000) + 0.5 }')
    edge=$(header cf-ray | sed -n 's/.*-\([A-Z][A-Z][A-Z]\)$/\1/p')
    asked=-
    lm=$(header last-modified)
    if [ -n "$lm" ]; then
        asked=no
        answered=$(epoch "$lm")
        served=$(epoch "$(header date)")
        # The server sets Last-Modified when PRIM answers: a new one, a second or two before the answer, is a new PRIM call.
        if [ "$lm" != "$last_lm" ] && [ -n "$answered" ] && [ -n "$served" ] && [ $((served - answered)) -le 2 ]; then
            asked=yes
            prim_calls=$((prim_calls + 1))
        fi
        last_lm=$lm
    fi
}

row() {
    printf '%-22s %-5s %8s %8s %8s  %s\n' "$1" "${edge:-?}" "$connect ms" "$server ms" "$total ms" "$asked"
}

median3() { printf '%s\n%s\n%s\n' "$1" "$2" "$3" | sort -n | sed -n 2p; }

trains_ok() {
    [ "$status" = 200 ] || say "The server answered HTTP $status for the trains, so nothing is measured: run make release-server-check to know why."
}

echo "Call                   Edge   Connect   Server    Total  PRIM asked"
measure $health
row "health, first"
measure $trains
trains_ok
row "trains, first"
first_trains=$server
first_asked=$asked
set --
for i in 1 2 3; do
    measure $trains
    trains_ok
    row "trains, again"
    set -- "$@" "$server"
done
held=$(median3 "$@")
set --
connects=
for i in 1 2 3; do
    measure $health
    row "health, again"
    set -- "$@" "$server"
    connects="$connects $connect"
done
worker=$(median3 "$@")
# shellcheck disable=SC2086 # three numbers.
handshake=$(median3 $connects)
sleep "$wait"
measure $trains
trains_ok
row "trains, ${wait} s later"
later_asked=$asked

echo
echo "Connection to Cloudflare (DNS, TCP, TLS): $handshake ms, only on a new connection."
echo "Worker alone (health): $worker ms."
echo "Hop to the server object (held answer minus health): $((held - worker)) ms."
if [ "$first_asked" = yes ]; then
    echo "Wait for PRIM (first trains minus held answer): $((first_trains - held)) ms."
else
    echo "Wait for PRIM: not measured, the server already held an answer; run this again in 2 minutes."
fi
if [ "$later_asked" = yes ]; then
    echo "After ${wait} s: the server had forgotten its answer, so it asked PRIM again."
else
    echo "After ${wait} s: the server still held its answer."
fi
echo "PRIM calls of this run: $prim_calls, as many as a rider who opens this stop for ${wait} s."
