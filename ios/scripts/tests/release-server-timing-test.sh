#!/bin/sh
# Tests release-server-timing.sh against a fake server that holds an answer for a stop, as the real one does,
# and waits 300 ms when it "asks PRIM". It proves the calls that the script makes, the PRIM calls that it counts,
# the parts that it splits, and that the token is never in the output, on a command line, or in a file.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-server-timing.sh"
contracts="$tests/../../../contracts"
work=$(mktemp -d)
keeps="keepstoken$$abcdef"
forgets="forgetstoken$$abcdef"
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

# The fake server. Each token is a server of its own: "keeps" holds its answer, "forgets" loses it after a quiet
# time of 0.9 s or more (the wait of a rider, 1 s here), "held" already holds one from 30 s ago, and any other token is refused.
# It writes one line per request (the path, and which token it got), never the token.
cat > "$work/server.py" <<'PY'
import email.utils, http.server, sys, time
contracts, port_file, log_file, keeps, forgets, held = sys.argv[1:7]
with open(f"{contracts}/prim/stop-monitoring-abbesses-stop-area.json", "rb") as f:
    times = f.read()
answers = {}
last_call = {}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization")
        which = {None: "none", f"Bearer {keeps}": "keeps", f"Bearer {forgets}": "forgets", f"Bearer {held}": "held"}.get(auth, "other")
        with open(log_file, "a") as f:
            f.write(f"{self.path} {which}\n")
        status, body, headers = 401, b'{"error":"unauthorized"}', {}
        if self.path == "/health":
            status, body = 200, b'{"status":"ok"}'
        elif which in ("keeps", "forgets", "held"):
            now = int(time.time())
            quiet = time.monotonic() - last_call.get(which, time.monotonic())
            last_call[which] = time.monotonic()
            kept = answers.get(which, now - 30 if which == "held" else None)
            if kept is None or (which == "forgets" and quiet >= 0.9):
                time.sleep(0.3)
                kept = int(time.time())
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
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
PY
python3 -I "$work/server.py" "$contracts" "$work/port" "$work/requests" "$keeps" "$forgets" "$held" &
server_pid=$!
tries=0
until [ -s "$work/port" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || { echo "FAIL the fake server did not start"; exit 1; }
    sleep 0.1
done
fake="127.0.0.1:$(cat "$work/port")"

# A curl that writes its command line to a log, then runs the real one.
mkdir -p "$work/bin" "$work/home" "$work/tmp" "$work/cwd" "$work/config"
real_curl=$(command -v curl)
cat > "$work/bin/curl" <<SH
#!/bin/sh
printf '%s\n' "\$*" >> "$work/curl-args"
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
    rm -f "$work/requests"
    (cd "$work/cwd" && env -i PATH="$work/bin:$PATH" HOME="$work/home" TMPDIR="$work/tmp" \
        RELEASE_SERVER_CHECK_TEST_SERVER="$fake" RELEASE_SERVER_TIMING_TEST_WAIT=1 "$script" "$config" > "$work/output" 2>&1) \
        && echo "status 0" >> "$work/output" || echo "status $?" >> "$work/output"
}

line() { grep "^$1" "$work/output" || true; }
column() { line "$1" | awk -v n="$2" '{ print $n }' | tr '\n' ' ' | sed 's/ $//'; }
outcome() { tail -n 1 "$work/output"; }

leaks() {
    found=no
    for token in "$keeps" "$forgets" "$held" "$wrong"; do
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
expect "the wait for PRIM is the 300 ms of the fake server" "$([ "${wait_ms:-0}" -ge 250 ] && [ "$wait_ms" -le 600 ] && echo yes || echo "no ($wait_ms)")" "yes"
for part in 'Connection to Cloudflare (DNS, TCP, TLS): ' 'Worker alone (health): ' 'Hop to the server object (held answer minus health): '; do
    expect "the summary gives: $part" "$(line "$part" | sed -n 's/.*: -*[0-9][0-9]* ms.*/ms/p')" "ms"
done
expect "a server that keeps its answer: the token is nowhere" "$(leaks)" "no"

run "$forgets"
expect "a server that forgets: the call a rider makes later asked PRIM again" "$(column 'trains, 1 s later' 12)" "yes"
expect "a server that forgets: the summary says so" "$(line 'After 1 s')" "After 1 s: the server had forgotten its answer, so it asked PRIM again."
expect "a server that forgets: two PRIM calls" "$(line 'PRIM calls of this run' | cut -d, -f1)" "PRIM calls of this run: 2"

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
