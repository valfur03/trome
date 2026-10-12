#!/bin/sh
# Tests release-tokens-check.sh against a fake server that answers with the examples of contracts/api/,
# and a fake release guide and token file. It proves the line of each build, one request per build in the field,
# the stop on a spent budget, the lines of a missing, empty or incomplete file or of a placeholder, that it reads the table of the
# real release guide, and that no token is in the output, on the command line of a process, or in a file.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../release-tokens-check.sh"
contracts="$tests/../../../contracts"
real_guide="$tests/../../../docs/src/content/docs/en/maintain/release-on-the-app-store.mdx"
work=$(mktemp -d)
one="onetoken$$abcdef"
two="twotoken$$abcdef"
old="retiredtoken$$abcdef"
wrong="wrongtoken$$abcdef"
budget="budgettoken$$abcdef"
primlimit="primlimittoken$$abcdef"
primfail="primfailtoken$$abcdef"
crash="crashtoken$$abcdef"
blocked="blockedtoken$$abcdef"
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

# The fake server: each token gets the example of its name; any other token a refusal.
# It writes one line per request (the Host header, the path, and which token it got), never the token.
cat > "$work/server.py" <<'PY'
import http.server, json, sys
contracts, port_file, log_file = sys.argv[1:4]
tokens = dict(arg.split("=", 1) for arg in sys.argv[4:])
examples = {"budget": "departures-out-budget.json", "primlimit": "departures-out-prim-limit.json",
            "primfail": "departures-out-prim-failure.json", "other": "departures-unauthorized.json"}
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
        which = tokens.get(auth.removeprefix("Bearer "), "other")
        if which == "crash":
            status, body = 500, b"error code: 1101"
        elif which == "blocked":
            status, body = 403, b"error code: 1020"
        else:
            status, body = example(examples.get(which, "departures-times.json"))
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
python3 -I "$work/server.py" "$contracts" "$work/port" "$work/requests" \
    "$one=one" "$two=two" "$old=old" "$budget=budget" "$primlimit=primlimit" "$primfail=primfail" "$crash=crash" "$blocked=blocked" &
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

tokens="$work/config/BuildTokens.txt"
config="$work/config/Server.xcconfig"
guide="$work/guide.mdx"
# The server file of the next build: its host, and no token, which this check does not need.
printf 'TRAIN_SERVER_HOST = trome-server.example.workers.dev\nTRAIN_SERVER_APP_TOKEN =\n' > "$config"

# A guide with the table of the release guide: build 1 retired, builds 2 and 3 in the field.
write_guide() {
    cat > "$guide" <<'MD'
## 9. Watch the first days

| Version (build) | Uploaded | Commit | Where, and until when | Status |
|---|---|---|---|---|
| 9.9.9 (9) | not a build of the field table | | | In the field |

## The builds that riders may hold

Every build uploaded to Apple is a row of this table.

| Version (build) | Uploaded | Commit | Where, and until when | Status |
|---|---|---|---|---|
| 1.0.0 (1) | 11 October 2026 | `ca169af` | TestFlight, until 9 January 2027 | Retired on 10 January 2027: its TestFlight date has passed |
| 1.0.0 (2) | 11 October 2026 | `9d83a8d` | TestFlight, until 9 January 2027 | In the field |
| 1.0.1 (3) | 12 October 2026 | `0123abc` | App Store | In the field |

### Retire a build

| 8.8.8 (8) | a table of another heading is not read | | | In the field |

## Fix this page
MD
}
write_guide

# The token file: a comment, then one line per argument "<build> <token>".
write_tokens() {
    printf '// The app token of each build.\n' > "$tokens"
    while [ $# -ge 2 ]; do
        printf '%s = %s // build %s\n' "$1" "$2" "$1" >> "$tokens"
        shift 2
    done
}

# Runs the check with the fake server, in an empty folder, with an empty home and temporary folder.
run() {
    rm -f "$work/requests"
    (cd "$work/cwd" && env -i PATH="$work/bin:$PATH" HOME="$work/home" TMPDIR="$work/tmp" \
        RELEASE_SERVER_CHECK_TEST_SERVER="${1:-$fake}" "$script" "$tokens" "$config" "${2:-$guide}" > "$work/output" 2>&1) \
        && echo "status 0" >> "$work/output" || echo "status $?" >> "$work/output"
}

output() { grep -v '^status ' "$work/output" || true; }
line() { output | sed -n "${1}p"; }
starts() { line "$1" | cut -c "1-${#2}"; }
outcome() { tail -n 1 "$work/output"; }
requests() { if [ -f "$work/requests" ]; then wc -l < "$work/requests" | tr -d ' '; else echo 0; fi; }
asked() { if [ -f "$work/requests" ]; then cut -d ' ' -f 3 "$work/requests" | tr '\n' ' ' | sed 's/ $//'; fi; }

leaks() {
    found=no
    for token in "$one" "$two" "$old" "$wrong" "$budget" "$primlimit" "$primfail" "$crash"; do
        grep -qF "$token" "$work/output" && found="in the output"
        [ ! -f "$work/curl-args" ] || ! grep -qF "$token" "$work/curl-args" || found="on the command line of curl"
        [ -z "$(ls -A "$work/home" "$work/tmp" "$work/cwd" | grep -v '^\.curlrc$' | grep -v '^$' | grep -v ':$')" ] || found="in a file"
    done
    echo "$found"
}

write_tokens 1 "$old" 2 "$one" 3 "$two"
run
expect "every token accepted: one line per build in the field, then OK" "$(output)" "1.0.0 (2): accepted
1.0.1 (3): accepted
OK: the production server accepts the app token of each build in the field (2, 3)."
expect "every token accepted: the check passes" "$(outcome)" "status 0"
expect "every token accepted: one request per build in the field, to the host of the server file, none for the retired build" \
    "$(cat "$work/requests")" "trome-server.example.workers.dev /v1/stops/STIF:StopArea:SP:42155:/departures one
trome-server.example.workers.dev /v1/stops/STIF:StopArea:SP:42155:/departures two"
expect "every token accepted: no token is anywhere" "$(leaks)" "no"

write_tokens 2 "$wrong" 3 "$two"
run
expect "a refused token: its build says refused, the next build is still asked" "$(line 1)|$(line 2)" "1.0.0 (2): refused|1.0.1 (3): accepted"
expect "a refused token: a last line that says refused and what to do" "$(starts 3 'Refused: the production server refuses the token of 1 of the 2 builds')" \
    "Refused: the production server refuses the token of 1 of the 2 builds"
expect "a refused token: the last line gives the remedy of Add a token, and its step 6 apart" "$(line 3 | sed 's/.*Add a token in server/Add a token in server/')" \
    "Add a token in server/guide/deploy.md says; at its step 6, paste the old list again instead, as that step says."
expect "a refused token: the check fails, after one request per build" "$(outcome) $(requests)" "status 1 2"
expect "a refused token: no token is anywhere" "$(leaks)" "no"

for case in "$budget budget budget" "$primlimit primlimit prim-limit"; do
    set -- $case
    write_tokens 2 "$1" 3 "$two"
    run
    expect "no PRIM call left ($3): the token is accepted, and the next build is not asked" "$(line 1)|$(line 2) $(asked)" \
        "1.0.0 (2): accepted|1.0.1 (3): not asked $2"
    expect "no PRIM call left ($3): a last line that says to run it again, and the check fails" \
        "$(starts 3 'Not finished: the production server has no PRIM calls left this hour ('"$3"')') $(outcome)" \
        "Not finished: the production server has no PRIM calls left this hour ($3) status 1"
done

write_tokens 2 "$primfail" 3 "$two"
run
expect "a PRIM failure: the token is accepted, and the next build is still asked" "$(line 1)|$(line 2) $(asked) $(outcome)" \
    "1.0.0 (2): accepted|1.0.1 (3): accepted primfail two status 0"

write_tokens 2 "$crash" 3 "$two"
run
expect "a server that fails: one line that says it cannot tell, and the check stops at once" \
    "$(starts 1 'The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig fails (HTTP 500)')$(output | wc -l | tr -d ' ') $(requests) $(outcome)" \
    "The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig fails (HTTP 500)1 1 status 1"

write_tokens 2 "$blocked" 3 "$two"
run
expect "a 403 of Cloudflare: not a refusal of the token, one line that says the host does not answer as the train server, and the check stops" \
    "$(starts 1 'The host in TRAIN_SERVER_HOST of ios/Config/Server.xcconfig answers, but not as the train server (HTTP 403)')$(output | wc -l | tr -d ' ') $(requests) $(outcome)" \
    "The host in TRAIN_SERVER_HOST of ios/Config/Server.xcconfig answers, but not as the train server (HTTP 403)1 1 status 1"

write_tokens 2 "$one" 3 "$two"
run 127.0.0.1:1
expect "a server that cannot be reached: one line that says so, and the check fails" \
    "$(starts 1 'The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig cannot be reached')$(output | wc -l | tr -d ' ') $(outcome)" \
    "The server at TRAIN_SERVER_HOST of ios/Config/Server.xcconfig cannot be reached1 status 1"
expect "a server that cannot be reached: no token is anywhere" "$(leaks)" "no"

rm -f "$tokens"
run
expect "a missing file: one line that names it, how to make it, and the builds to add" \
    "$(output | grep -c '^No ios/Config/BuildTokens.txt: make it with cp -n ios/Config/BuildTokens.example.txt ios/Config/BuildTokens.txt, add the app token of each build in the field (2, 3) as "The app token of each build" in the release guide says, then run this again.$')$(output | wc -l | tr -d ' ')" "11"
expect "a missing file: the check fails, with no request" "$(outcome) $(requests)" "status 1 0"
expect "a missing file: nothing is written" "$(leaks)" "no"

printf '// Only a comment.\n\n   \n' > "$tokens"
run
expect "an empty file: one line that says what to add, for which builds" \
    "$(output)" "ios/Config/BuildTokens.txt has no token: add one line \"<build> = <its app token>\" for each build in the field (2, 3), from your password manager, then run this again."
expect "an empty file: the check fails, with no request" "$(outcome) $(requests)" "status 1 0"

write_tokens 2 "$one" 1 "$old"
run
expect "a build of the table with no token: one line that names it and the line to add" \
    "$(line 1)" "No token for build 1.0.1 (3) in ios/Config/BuildTokens.txt: add the line \"3 = <its app token>\", from your password manager."
expect "a build of the table with no token: the check fails before any request" "$(output | wc -l | tr -d ' ') $(outcome) $(requests)" "2 status 1 0"

write_tokens 2 "$one" 3 "$two" 2 "$wrong"
run
expect "a build with two lines: one line that says to keep one, and no request" \
    "$(line 1) $(outcome) $(requests)" "Build 2 has more than one line in ios/Config/BuildTokens.txt: keep only the one with its app token. status 1 0"

write_tokens 2 "$one" 3 "$two"
printf 'build 4 %s\n' "$wrong" >> "$tokens"
run
expect "a line that is not <build> = <token>: its number, never its text, and no request" \
    "$(output) $(outcome) $(requests) $(leaks)" \
    "Line 4 of ios/Config/BuildTokens.txt is not \"<build> = <its app token>\": write the build number, =, and its token, then run this again. status 1 0 no"

for placeholder in '<token>' '<the app token of build 3>'; do
    write_tokens 2 "$one"
    printf '3 = %s\n' "$placeholder" >> "$tokens"
    run
    expect "a placeholder of the guide ($placeholder): its line number, and no request" "$(output) $(outcome) $(requests)" \
        "Line 3 of ios/Config/BuildTokens.txt still holds a placeholder in < >: put the app token of that build in its place, from your password manager, then run this again. status 1 0"
done

write_tokens 2 "$one" 3 "$two"
printf '\r\n' >> "$tokens"
sed -i '' 's/$/\r/' "$tokens"
run
expect "a file with Windows line ends: read as the same lines" "$(outcome) $(requests)" "status 0 2"

sed -i '' 's/1.0.1 (3) .*$/1.0.1 (3) | 12 October 2026 | `0123abc` | App Store | Retired on 1 May 2028: no rider left |/; s/1.0.0 (2) .*$/1.0.0 (2) | x | x | x | Retired on 1 May 2028: expired |/' "$guide"
rm -f "$tokens"
run
expect "a guide with every build retired: OK, with no file and no request" "$(starts 1 'OK: the release guide lists no build in the field') $(outcome) $(requests)" \
    "OK: the release guide lists no build in the field status 0 0"

printf '# Release\n\nNo table here.\n' > "$guide"
run
expect "a guide with no table of the builds: one line that says so, and the check fails" \
    "$(starts 1 'The release guide has no table "The builds that riders may hold"') $(outcome) $(requests)" \
    "The release guide has no table \"The builds that riders may hold\" status 1 0"
write_guide

# The real guide: the check finds its table and at least one build in the field, and the guide has the section that the check names.
rm -f "$tokens"
run "$fake" "$real_guide"
expect "the release guide of the repo: its table names builds in the field" \
    "$(output | grep -c '^No ios/Config/BuildTokens.txt: .*each build in the field ([0-9][0-9, ]*)')" "1"
expect "the release guide of the repo: it has the section that the missing-file line names" \
    "$(grep -c '^### The app token of each build$' "$real_guide")" "1"

[ "$failures" -eq 0 ] || { echo "$failures failures"; exit 1; }
echo "release-tokens-check: all tests passed"
