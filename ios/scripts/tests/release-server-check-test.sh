#!/bin/sh
# Tests release-server-check.sh against a fake server that answers with the examples of contracts/api/.
# It proves the line of each case, one request per run, and that the token is never in the output,
# on the command line of a process, or in a file, even when a .curlrc asks curl to log everything.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-server-check.sh"
contracts="$tests/../../../contracts"
work=$(mktemp -d)
good="goodtoken$$abcdef"
wrong="wrongtoken$$abcdef"
out="outtoken$$abcdef"
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

# The fake server: the good token gets trains, the out token the answer of a spent hour, any other token a refusal.
# It writes one line per request (the Host header, the path, and which token it got), never the token.
cat > "$work/server.py" <<'PY'
import http.server, json, sys
contracts, port_file, log_file, good, out = sys.argv[1:6]
def example(name):
    with open(f"{contracts}/api/{name}") as f:
        response = json.load(f)["response"]
    if "bodyIsPrimAnswer" in response:
        with open(f"{contracts}/prim/{response['bodyIsPrimAnswer']}", "rb") as f:
            return response["status"], f.read()
    return response["status"], json.dumps(response["body"]).encode()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        which = {f"Bearer {good}": "good", f"Bearer {out}": "out"}.get(auth, "other")
        # Answers that do not come from the train server: a Worker that throws, Cloudflare busy, another site.
        for word, status, text in (("crash", 500, "error code: 1101"), ("busy", 503, "<html>Service Unavailable</html>"), ("elsewhere", 404, "<html>Not Found</html>")):
            if word in auth:
                which, answer = word, (status, text.encode())
        if which in ("good", "out", "other"):
            answer = example({"good": "departures-times.json", "out": "departures-out-budget.json"}.get(which, "departures-unauthorized.json"))
        status, body = answer
        with open(log_file, "a") as f:
            f.write(f"{self.headers.get('Host')} {self.path} {which}\n")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
PY
python3 -I "$work/server.py" "$contracts" "$work/port" "$work/requests" "$good" "$out" &
server_pid=$!
tries=0
until [ -s "$work/port" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || { echo "FAIL the fake server did not start"; exit 1; }
    sleep 0.1
done
fake="127.0.0.1:$(cat "$work/port")"

# A curl that writes its command line to a log, then runs the real one.
mkdir -p "$work/bin" "$work/home" "$work/tmp" "$work/cwd"
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
mkdir -p "$work/config"

write_config() {
    printf '// The server of a Release build.\nTRAIN_SERVER_HOST = %s\nTRAIN_SERVER_APP_TOKEN = %s // a comment\n' "$1" "$2" > "$config"
}

# Runs the check with the fake server, in an empty folder, with an empty home and temporary folder.
run() {
    rm -f "$work/requests"
    (cd "$work/cwd" && env -i PATH="$work/bin:$PATH" HOME="$work/home" TMPDIR="$work/tmp" \
        RELEASE_SERVER_CHECK_TEST_SERVER="${1:-$fake}" "$script" "$config" > "$work/output" 2>&1) \
        && echo "status 0" >> "$work/output" || echo "status $?" >> "$work/output"
}

lines() { grep -vc '^status ' "$work/output" || true; }
starts() { head -n 1 "$work/output" | cut -c "1-${#1}"; }
outcome() { tail -n 1 "$work/output"; }
requests() { if [ -f "$work/requests" ]; then wc -l < "$work/requests" | tr -d ' '; else echo 0; fi; }

leaks() {
    found=no
    for token in "$good" "$wrong" "$out"; do
        grep -qF "$token" "$work/output" && found="in the output"
        [ ! -f "$work/curl-args" ] || ! grep -qF "$token" "$work/curl-args" || found="on the command line of curl"
        [ -z "$(ls -A "$work/home" "$work/tmp" "$work/cwd" | grep -v '^\.curlrc$' | grep -v '^$' | grep -v ':$')" ] || found="in a file"
    done
    echo "$found"
}

write_config trome-server.example.workers.dev "$good"
run
expect "a good token: one line that says OK" "$(starts 'OK: the production server accepts')$(lines)" "OK: the production server accepts1"
expect "a good token: the check passes" "$(outcome)" "status 0"
expect "a good token: one request, to the host of the file, for the trains of one stop" \
    "$(cat "$work/requests")" "trome-server.example.workers.dev /v1/stops/STIF:StopArea:SP:42155:/departures good"
expect "a good token: the token is nowhere" "$(leaks)" "no"

write_config trome-server.example.workers.dev "$wrong"
run
expect "a wrong token: one line that says refused and what to do" "$(starts 'Refused: ')$(lines)" "Refused: 1"
expect "a wrong token: the check fails" "$(outcome)" "status 1"
expect "a wrong token: one request" "$(requests)" "1"
expect "a wrong token: the token is nowhere" "$(leaks)" "no"

write_config trome-server.example.workers.dev "$out"
run
expect "a spent hour: the token is right, and the line says there are no trains now" \
    "$(grep -c 'accepts the host and the app token.*no trains right now (budget)' "$work/output")" "1"
expect "a spent hour: the check passes" "$(outcome)" "status 0"
expect "a spent hour: the token is nowhere" "$(leaks)" "no"

rm -f "$config"
run
expect "a missing file: one line that names it and the step of the guide" "$(starts 'No ios/Config/Server.xcconfig: make it as step 4.2')$(lines)" "No ios/Config/Server.xcconfig: make it as step 4.21"
expect "a missing file: the check fails, with no request" "$(outcome) $(requests)" "status 1 0"
expect "a missing file: nothing is written" "$(leaks)" "no"

write_config "https://trome-server.example.workers.dev/" "$good"
run
expect "a host with https://: one line that says it is not a host, with no request" \
    "$(starts 'TRAIN_SERVER_HOST in ios/Config/Server.xcconfig is not a host')$(lines) $(requests)" \
    "TRAIN_SERVER_HOST in ios/Config/Server.xcconfig is not a host1 0"
expect "a host with https://: the host is not printed" "$(grep -c 'example' "$work/output" || true)" "0"

write_config trome-server-staging.example.workers.dev "$good"
run
expect "the staging host: one line that says so, with no request" "$(starts 'TRAIN_SERVER_HOST in ios/Config/Server.xcconfig is the staging server')$(requests)" \
    "TRAIN_SERVER_HOST in ios/Config/Server.xcconfig is the staging server0"

write_config "" "$good"
run
expect "no host: one line that says so" "$(starts 'No host in ')$(lines) $(outcome)" "No host in 1 status 1"

write_config trome-server.example.workers.dev ""
run
expect "no token: one line that says so, with no request" "$(starts 'No app token in ')$(lines) $(requests)" "No app token in 1 0"

write_config trome-server.example.workers.dev "$good"
printf 'TRAIN_SERVER_APP_TOKEN = %s\n' "$wrong" >> "$config"
run
expect "the last line of a setting wins, as in Xcode" "$(starts 'Refused: ')" "Refused: "

for case in "crash 500" "busy 503"; do
    word=${case% *}
    write_config trome-server.example.workers.dev "${word}token$$abcdef"
    run
    expect "a server that fails (HTTP ${case#* }): one line that says it cannot tell, never OK" \
        "$(starts 'The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig fails (HTTP')$(lines) $(outcome)" \
        "The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig fails (HTTP1 status 1"
done

write_config trome-server.example.workers.dev "elsewhere$$abcdef"
run
expect "a host that is another site: one line that says to check the host" \
    "$(starts 'The host in TRAIN_SERVER_HOST of ios/Config/Server.xcconfig answers, but not as the train server')$(lines) $(outcome)" \
    "The host in TRAIN_SERVER_HOST of ios/Config/Server.xcconfig answers, but not as the train server1 status 1"

write_config trome-server.example.workers.dev "$good"
run 127.0.0.1:1
expect "a server that cannot be reached: one line that says so and what to do" "$(starts 'The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig cannot be reached')$(lines)" \
    "The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig cannot be reached1"
expect "a server that cannot be reached: the check fails, and the token is nowhere" "$(outcome) $(leaks)" "status 1 no"

[ "$failures" -eq 0 ] || { echo "$failures failures"; exit 1; }
echo "release-server-check: all tests passed"
