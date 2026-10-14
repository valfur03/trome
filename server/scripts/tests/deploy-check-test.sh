#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
failures=0
server_pid=
trap '[ -z "$server_pid" ] || { kill "$server_pid"; wait "$server_pid"; } 2> /dev/null || true; rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

contains() {
    grep -qF -- "$2" "$1" && echo yes || echo no
}

# A fake Worker on a free port of this computer. The file "mode" says how it answers; "requests" lists each request.
cat > "$state/fake-worker.mjs" << 'FAKE'
import { createServer } from "node:http";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const state = process.argv[2];
const server = createServer((request, response) => {
  const mode = readFileSync(`${state}/mode`, "utf8").trim();
  appendFileSync(`${state}/requests`, `${request.url} ${request.headers.authorization ?? "-"}\n`);
  const json = (status, body) => { response.writeHead(status, { "content-type": "application/json" }); response.end(JSON.stringify(body)); };
  if (request.url === "/health") {
    if (mode === "health-down") return json(500, { error: "internal" });
    if (mode === "health-late" && readFileSync(`${state}/requests`, "utf8").split("\n").filter((line) => line.startsWith("/health")).length < 3) return json(503, {});
    return json(200, { status: "ok" });
  }
  if (request.url === "/v1/stops/STIF:StopArea:SP:42155:/departures") {
    if (request.headers.authorization !== "Bearer right-token") return json(401, { error: "unauthorized" });
    if (mode === "prim-failure") return json(503, { status: "out", reason: "prim-failure", retryAt: "2026-10-14T10:00:00.000Z" });
    return json(200, { Siri: { ServiceDelivery: {} } });
  }
  return json(404, { error: "not found" });
});
server.listen(0, "127.0.0.1", () => writeFileSync(`${state}/port`, String(server.address().port)));
FAKE
echo ok > "$state/mode"
node "$state/fake-worker.mjs" "$state" &
server_pid=$!
tries=0
while [ ! -s "$state/port" ] && [ "$tries" -lt 100 ]; do
    sleep 0.1
    tries=$((tries + 1))
done
port=$(cat "$state/port")

# The output file of wrangler deploy (WRANGLER_OUTPUT_FILE_PATH): one JSON entry per line, as wrangler 4 writes it.
# The script reads the workers.dev address there; DEPLOY_CHECK_ADDRESS_FOR_TEST sends its requests to the fake Worker.
address="http://127.0.0.1:$port"
output() {
    printf '%s\n' '{"type":"wrangler-session","version":1}' > "$state/output.json"
    printf '{"type":"deploy","version":1,"worker_name":"trome-server-staging","targets":["%s"],"version_id":"v1"}\n' "$1" >> "$state/output.json"
}

check() {
    : > "$state/requests"
    APP_TOKEN_FOR_CHECK=$1 DEPLOY_CHECK_WAIT_MS=10 DEPLOY_CHECK_ADDRESS_FOR_TEST="$address" \
        node "$scripts/deploy-check.ts" "$state/output.json" > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

output "https://trome-server-staging.example.workers.dev"
echo ok > "$state/mode"
expect "a Worker that answers passes both checks" "$(check right-token)" "passes"
expect "it asks /health, then the trains of one stop, once (one PRIM call at most)" "$(cut -d' ' -f1 "$state/requests" | tr '\n' ' ')" "/health /v1/stops/STIF:StopArea:SP:42155:/departures "
expect "it sends the app token only to the departures request" "$(cut -d' ' -f2- "$state/requests" | tr '\n' ' ')" "- Bearer right-token "
expect "it names the address that it checked" "$(contains "$state/out" "https://trome-server-staging.example.workers.dev/health answers")" "yes"
expect "it never prints the token" "$(contains "$state/out" "right-token")" "no"

expect "a refused app token fails" "$(check wrong-token)" "fails"
expect "it says which check failed, and the answer" "$(contains "$state/out" "Check 2 of 2 failed: the trains of one stop, with the app token, gave HTTP 401 unauthorized")" "yes"
expect "it never prints the token it sent" "$(contains "$state/out" "wrong-token")" "no"
expect "it is an error line of GitHub" "$(contains "$state/out" "::error::")" "yes"

echo prim-failure > "$state/mode"
expect "a Worker that cannot reach PRIM fails" "$(check right-token)" "fails"
expect "it gives the status and the reason of the answer" "$(contains "$state/out" "gave HTTP 503 out prim-failure")" "yes"

echo health-down > "$state/mode"
expect "a Worker whose /health fails, fails" "$(check right-token)" "fails"
expect "it says that check 1 failed" "$(contains "$state/out" "Check 1 of 2 failed")" "yes"
expect "it tries /health 6 times, then stops" "$(grep -c '^/health' "$state/requests")" "6"
expect "it never asks for trains then (no PRIM call)" "$(grep -c '/departures' "$state/requests" || true)" "0"

echo health-late > "$state/mode"
expect "a Worker that answers /health on the third try passes" "$(check right-token)" "passes"

echo ok > "$state/mode"
expect "no app token fails at once" "$(check '')" "fails"
expect "it names the missing secret" "$(contains "$state/out" "no app token (APP_TOKEN_FOR_CHECK)")" "yes"
expect "it makes no request then" "$(wc -l < "$state/requests" | tr -d ' ')" "0"

printf '%s\n' '{"type":"wrangler-session","version":1}' > "$state/output.json"
expect "an output with no deploy entry fails" "$(check right-token)" "fails"
expect "it says that it has no address" "$(contains "$state/out" "names no workers.dev address")" "yes"

rm "$state/output.json"
expect "no output file fails" "$(check right-token)" "fails"
expect "it says that the file is missing" "$(contains "$state/out" "found no output of wrangler deploy")" "yes"

[ "$failures" -eq 0 ]
