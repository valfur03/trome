#!/bin/sh
# Tests release-server-timing.sh against a fake server that holds an answer for a stop, as the real one does,
# and waits 300 ms when it "asks PRIM". It proves the calls that the script makes, the PRIM calls that it counts,
# the parts that it splits, and that the token is never in the output, on a command line, or in a file.
# No result may depend on the speed of the machine: the fake server forgets by the order of the calls, not by a time
# alone, and a run with a forced slow call proves it.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-server-timing.sh"
contracts="$tests/../../../contracts"
work=$(mktemp -d)
keeps="keepstoken$$abcdef"
forgets="forgetstoken$$abcdef"
slow="slowtoken$$abcdef"
held="heldtoken$$abcdef"
wrong="wrongtoken$$abcdef"
failures=0
server_pid=

cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
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

# The fake server. Each token is a server of its own: "keeps" holds its answer, "held" already holds one from 30 s ago,
# and any other token is refused.
# "forgets" (and "slow", the same server for the run with a slow call) holds its answer for the 3 calls that follow
# a PRIM call, and loses it for the next one, the call of the rider after the wait (1 s here), if it comes 0.9 s or more
# after the call before: a script that does not wait still gets the held answer.
# Why not a quiet time alone: on a busy machine, the calls of one rider can come more than 0.9 s apart, and the fake
# server then forgot too early and counted 3 PRIM calls.
# It writes one line per request (the path, and which token it got), never the token.
cat > "$work/server.py" <<'PY'
import email.utils, http.server, socketserver, sys, time
contracts, port_file, log_file, keeps, forgets, held, slow = sys.argv[1:8]
with open(f"{contracts}/prim/stop-monitoring-abbesses-stop-area.json", "rb") as f:
    times = f.read()
answers = {}
last_call = {}
held_calls = {}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization")
        which = {None: "none", f"Bearer {keeps}": "keeps", f"Bearer {forgets}": "forgets", f"Bearer {held}": "held", f"Bearer {slow}": "slow"}.get(auth, "other")
        with open(log_file, "a") as f:
            f.write(f"{self.path} {which}\n")
        status, body, headers = 401, b'{"error":"unauthorized"}', {}
        if self.path == "/health":
            status, body = 200, b'{"status":"ok"}'
        elif which in ("keeps", "forgets", "held", "slow"):
            now = int(time.time())
            quiet = time.monotonic() - last_call.get(which, time.monotonic())
            last_call[which] = time.monotonic()
            kept = answers.get(which, now - 30 if which == "held" else None)
            forgot = which in ("forgets", "slow") and held_calls.get(which, 0) >= 3 and quiet >= 0.9
            if kept is None or forgot:
                time.sleep(0.3)
                kept = int(time.time())
                held_calls[which] = 0
            else:
                held_calls[which] = held_calls.get(which, 0) + 1
            answers[which] = kept
            status, body = 200, times
            headers = {"Last-Modified": email.utils.formatdate(kept, usegmt=True)}
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("cf-ray", "8c0ffee000000000-CDG")
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
class Server(http.server.ThreadingHTTPServer):
    # HTTPServer looks up a name for its address when it binds. On a Mac whose network has no answer for it
    # (GitHub's Mac), that lookup takes more than 30 s, and the fake server never needs the name.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]
server = Server(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
PY
python3 -I "$work/server.py" "$contracts" "$work/port" "$work/requests" "$keeps" "$forgets" "$held" "$slow" &
server_pid=$!
tries=0
until [ -s "$work/port" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || { echo "FAIL the fake server did not start"; exit 1; }
    sleep 0.1
done
fake="127.0.0.1:$(cat "$work/port")"

# A curl that writes its command line to a log, then runs the real one.
# When the file "slow" exists, it waits 1 s before the second trains call, as a busy machine can.
mkdir -p "$work/bin" "$work/home" "$work/tmp" "$work/cwd" "$work/config"
real_curl=$(command -v curl)
cat > "$work/bin/curl" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$work/curl-args"
case "\$*" in
*departures*)
    echo >> "$work/trains-calls"
    if [ -f "$work/slow" ] && [ "\$(wc -l < "$work/trains-calls")" -eq 2 ]; then sleep 1; fi ;;
esac
exec "$real_curl" "\$@"
SH
chmod +x "$work/bin/curl"
# A .curlrc that would print and store the headers, if the script let curl read it.
printf 'verbose\ntrace-ascii = "%s/home/curl-trace"\n' "$work" > "$work/home/.curlrc"
config="$work/config/Server.xcconfig"

# Runs the script with the fake server, in an empty folder, with an empty home and temporary folder.
# The wait of 30 s between the calls of a rider is 1 s here: the fake server that forgets then answers anew.
run() {
    printf 'TRAIN_SERVER_HOST = trome-server.example.workers.dev\nTRAIN_SERVER_APP_TOKEN = %s\n' "$1" > "$config"
    rm -f "$work/requests" "$work/trains-calls"
    (cd "$work/cwd" && env -i PATH="$work/bin:$PATH" HOME="$work/home" TMPDIR="$work/tmp" \
        RELEASE_SERVER_CHECK_TEST_SERVER="$fake" RELEASE_SERVER_TIMING_TEST_WAIT=1 "$script" "$config" > "$work/output" 2>&1) \
        && echo "status 0" >> "$work/output" || echo "status $?" >> "$work/output"
}

line() { grep "^$1" "$work/output" || true; }
column() { line "$1" | awk -v n="$2" '{ print $n }' | tr '\n' ' ' | sed 's/ $//'; }
outcome() { tail -n 1 "$work/output"; }

leaks() {
    found=no
    for token in "$keeps" "$forgets" "$held" "$slow" "$wrong"; do
        grep -qF "$token" "$work/output" && found="in the output"
        [ ! -f "$work/curl-args" ] || ! grep -qF "$token" "$work/curl-args" || found="on the command line of curl"
        [ -z "$(ls -A "$work/home" "$work/tmp" "$work/cwd" | grep -v '^\.curlrc$' | grep -v '^$' | grep -v ':$')" ] || found="in a file"
    done
    echo "$found"
}

run "$keeps"
expect "a server that keeps its answer: the run passes" "$(outcome)" "status 0"
expect "the calls of one rider: health, then the trains of one stop 5 times, the token only for the trains" \
    "$(sort "$work/requests" | uniq -c | awk '{ print $1, $2, $3 }' | tr '\n' ',')" \
    "4 /health none,5 /v1/stops/STIF:StopArea:SP:42155:/departures keeps,"
expect "the edge of each of the 9 calls, from cf-ray" "$(grep -c ' CDG ' "$work/output")" "9"
expect "the first trains call asked PRIM, the next ones got the held answer" \
    "$(column 'trains, first' 10) $(column 'trains, again' 10) $(column 'trains, 1 s later' 12)" "yes no no no no"
expect "the PRIM calls of the run: one" "$(line 'PRIM calls of this run')" "PRIM calls of this run: 1, as many as a rider who opens this stop for 1 s."
expect "the server kept its answer" "$(line 'After 1 s')" "After 1 s: the server still held its answer."
wait_ms=$(line 'Wait for PRIM' | sed -n 's/.*answer): \(-*[0-9]*\) ms\./\1/p')
# By the rows of the table, not by a time window: on a busy machine, a held answer can take longer than the 300 ms.
first_ms=$(column 'trains, first' 6)
# shellcheck disable=SC2046 # three numbers.
held_ms=$(printf '%s\n' $(column 'trains, again' 6) | sort -n | sed -n 2p)
expect "the wait for PRIM is the first trains call minus the median held answer" "${wait_ms:-none}" "$((first_ms - held_ms))"
expect "the first trains call holds the 300 ms of the fake server" "$([ "$first_ms" -ge 300 ] && echo yes || echo "no ($first_ms)")" "yes"
for part in 'Connection to Cloudflare (DNS, TCP, TLS): ' 'Worker alone (health): ' 'Hop to the server object (held answer minus health): '; do
    expect "the summary gives: $part" "$(line "$part" | sed -n 's/.*: -*[0-9][0-9]* ms.*/ms/p')" "ms"
done
expect "a server that keeps its answer: the token is nowhere" "$(leaks)" "no"

run "$forgets"
expect "a server that forgets: the call a rider makes later asked PRIM again" "$(column 'trains, 1 s later' 12)" "yes"
expect "a server that forgets: the summary says so" "$(line 'After 1 s')" "After 1 s: the server had forgotten its answer, so it asked PRIM again."
expect "a server that forgets: two PRIM calls" "$(line 'PRIM calls of this run' | cut -d, -f1)" "PRIM calls of this run: 2"

# A busy machine: the second trains call comes 1 s after the first one. The server still held its answer then.
touch "$work/slow"
run "$slow"
rm -f "$work/slow"
expect "a slow call on a busy machine: only the first call and the call after the wait asked PRIM" \
    "$(column 'trains, first' 10) $(column 'trains, again' 10) $(column 'trains, 1 s later' 12)" "yes no no no yes"
expect "a slow call on a busy machine: two PRIM calls" "$(line 'PRIM calls of this run' | cut -d, -f1)" "PRIM calls of this run: 2"
expect "a slow call on a busy machine: the token is nowhere" "$(leaks)" "no"

run "$held"
expect "a server that already held an answer: no PRIM call, and no wait for PRIM to measure" \
    "$(line 'PRIM calls of this run' | cut -d, -f1) / $(line 'Wait for PRIM')" \
    "PRIM calls of this run: 0 / Wait for PRIM: not measured, the server already held an answer; run this again in 2 minutes."

run "$wrong"
expect "a refused token: one line after the first rows, and the run fails" \
    "$(line 'The server answered') $(outcome)" \
    "The server answered HTTP 401 for the trains, so nothing is measured: run make release-server-check to know why. status 1"
expect "a refused token: one trains call, then nothing" "$(grep -c departures "$work/requests")" "1"
expect "a refused token: the token is nowhere" "$(leaks)" "no"

rm -f "$config"
(cd "$work/cwd" && env -i PATH="$work/bin:$PATH" HOME="$work/home" "$script" "$config" > "$work/output" 2>&1) || true
expect "a missing file: the line of release-server-check" "$(cut -c 1-31 "$work/output")" "No ios/Config/Server.xcconfig: "

[ "$failures" -eq 0 ] || { echo "$failures failures"; exit 1; }
echo "release-server-timing: all tests passed"
