#!/bin/sh
# The build number of the release workflow (release-build-number.py), against a fake App Store Connect on this Mac and
# throwaway repos: the next number is one more than the highest that Apple holds (all versions, expired builds and
# refused uploads included) or the highest builds/ tag; a run started again after a refused upload takes the next
# number; a number of another form, an error of Apple or a next page on another host gives no number; the token that
# the script sends is a valid ES256 token of the key, and it is never printed.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
answers="$state/answers"
failures=0
server_pid=
cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2> /dev/null || true
        wait "$server_pid" 2> /dev/null || true
    fi
    rm -rf "$state"
}
trap cleanup EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GITHUB_OUTPUT || true

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# A fake App Store Connect: it answers each path with the file of answers/ named after the path and its cursor, puts
# its own address in place of {base} (and under another name in place of {other host}), and keeps the Authorization header of each request in requests.log.
cat > "$state/fake-asc.py" << 'EOF'
import http.server, os, sys, urllib.parse
answers, log, ready = sys.argv[1:4]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        cursor = urllib.parse.parse_qs(url.query).get("cursor", ["1"])[0]
        name = url.path.strip("/").replace("/", "_") + f"-{cursor}.json"
        with open(log, "a") as file:
            file.write(f"{self.path} {self.headers.get('Authorization', '')}\n")
        path = os.path.join(answers, name)
        status = 200
        if os.path.exists(path + ".status"):
            status = int(open(path + ".status").read())
        if not os.path.exists(path):
            status, body = 404, '{"errors":[{"title":"Not found","detail":"no such page"}]}'
        else:
            body = open(path).read().replace("{base}", f"http://127.0.0.1:{self.server.server_port}")
            body = body.replace("{other host}", f"http://localhost:{self.server.server_port}")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(ready, "w") as file:
    file.write(f"{server.server_port}\n")
server.serve_forever()
EOF
mkdir -p "$answers"
mkfifo "$state/ready"
python3 "$state/fake-asc.py" "$answers" "$state/requests.log" "$state/ready" &
server_pid=$!
# Reading the fifo waits until the server has its port: no wait on the clock.
read -r port < "$state/ready"
base="http://127.0.0.1:$port"

# The API key: a new P-256 key in the form of Apple's .p8 file, and its public half to check the tokens.
openssl ecparam -name prime256v1 -genkey -noout 2> /dev/null | openssl pkcs8 -topk8 -nocrypt -out "$state/AuthKey.p8"
openssl pkey -in "$state/AuthKey.p8" -pubout -out "$state/public.pem"
export APP_STORE_CONNECT_KEY_ID=TESTKEY123 APP_STORE_CONNECT_ISSUER_ID=00000000-test-issuer

# A repo as the app has it: its version, its App Store ID in the Release configuration, and the given build tags.
reset_repo() {
    rm -rf "$repo" "$answers"
    mkdir -p "$answers" "$repo/ios/Config"
    git init -q -b main "$repo"
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    printf 'MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = 5\n' > "$repo/ios/Config/Base.xcconfig"
    printf 'configs:\n  Debug:\n      APP_BUNDLE_ID: $(TROME_WANTED_APP_ID)\n  Release:\n      APP_BUNDLE_ID: io.example.trome\n      WIDGET_BUNDLE_ID: io.example.trome.widget\n' > "$repo/ios/project.yml"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m first
    for tag in "$@"; do git -C "$repo" tag -a "$tag" -m "$tag"; done
    answer v1_apps 1 '{"data":[{"type":"apps","id":"42","attributes":{"bundleId":"io.example.trome"}}],"links":{}}'
}

# answer <path as a name> <cursor> <json>: the page that the fake App Store Connect gives.
answer() {
    printf '%s\n' "$3" > "$answers/$1-$2.json"
}

# One page of builds with these numbers (version:number:expired), and a next page when a cursor is given.
builds_page() {
    cursor=$1 next=$2
    shift 2
    data=""
    for build in "$@"; do
        number=${build#*:}
        number=${number%%:*}
        data="$data${data:+,}{\"type\":\"builds\",\"id\":\"b$number\",\"attributes\":{\"version\":\"$number\",\"expired\":${build##*:}}}"
    done
    links="{}"
    [ -z "$next" ] || links="{\"next\":\"{base}/v1/builds?filter%5Bapp%5D=42&cursor=$next\"}"
    answer v1_builds "$cursor" "{\"data\":[$data],\"links\":$links}"
}

uploads_page() {
    data=""
    for upload in "$@"; do
        data="$data${data:+,}{\"type\":\"buildUploads\",\"id\":\"u${upload%%:*}\",\"attributes\":{\"cfBundleVersion\":\"${upload%%:*}\",\"state\":\"${upload#*:}\"}}"
    done
    answer v1_apps_42_buildUploads 1 "{\"data\":[$data],\"links\":{}}"
}

# The number that the script gives, as the workflow reads it from GITHUB_OUTPUT, or its error.
number() {
    : > "$state/output"
    : > "$state/requests.log"
    status=0
    GITHUB_OUTPUT="$state/output" "$ios/scripts/release-build-number.py" next --key-file "$state/AuthKey.p8" \
        --repo "$repo" --api "$base" > "$state/out" 2> "$state/err" || status=$?
    if [ "$status" -eq 0 ]; then
        sed -n 's/^build=//p' "$state/output"
    else
        echo "none ($status)"
    fi
}

# Build 5 of 1.0.0 is on TestFlight with its tag; older builds of 0.9.0 expired.
reset_repo builds/0.9.0/3 builds/1.0.0/5
builds_page 1 "" 0.9.0:2:true 0.9.0:3:true 1.0.0:4:false 1.0.0:5:false
uploads_page 2:COMPLETE 3:COMPLETE 4:COMPLETE 5:COMPLETE
expect "the next number is one more than the highest that Apple holds and the highest tag" "$(number)" 6
expect "the version is the one of the repo" "$(sed -n 's/^version=//p' "$state/output")" 1.0.0
expect "the run says where the number comes from" "$(cat "$state/out")" \
    "Build number 6 of io.example.trome 1.0.0: Apple's highest is 5 (4 builds and 4 uploads of all versions), the highest builds/ tag is 5"
expect "the script never changes the version of the repo" "$(git -C "$repo" status --short)" ""

# The upload of 6 is refused: it is in the build uploads with a failed state, and in no build. The run again takes 7.
uploads_page 2:COMPLETE 3:COMPLETE 4:COMPLETE 5:COMPLETE 6:FAILED
expect "a run started again after a refused upload takes the next number" "$(number)" 7

# Then 7 is processed but invalid: it is a build of Apple. The next run takes 8.
builds_page 1 "" 0.9.0:2:true 0.9.0:3:true 1.0.0:4:false 1.0.0:5:false 1.0.0:7:false
uploads_page 2:COMPLETE 3:COMPLETE 4:COMPLETE 5:COMPLETE 6:FAILED 7:COMPLETE
expect "after a build that Apple holds, the next number is one more" "$(number)" 8

# An expired build of an older version holds the highest number.
reset_repo builds/1.0.0/5
builds_page 1 "" 0.9.0:9:true 1.0.0:5:false
uploads_page 5:COMPLETE
expect "an expired build of an older version counts" "$(number)" 10

# The highest build is on the second page of Apple's answer.
reset_repo builds/1.0.0/5
builds_page 1 2 1.0.0:4:false 1.0.0:5:false
builds_page 2 "" 1.0.0:11:false
uploads_page 4:COMPLETE 5:COMPLETE
expect "every page of Apple's builds counts" "$(number)" 12

# A tag is higher than all that Apple shows (a build that Apple no longer lists).
reset_repo builds/1.0.0/5 builds/1.0.1/14
builds_page 1 "" 1.0.0:5:false
uploads_page 5:COMPLETE
expect "a builds/ tag higher than Apple's builds counts" "$(number)" 15
expect "the version stays the one of the repo, not the one of a tag" "$(sed -n 's/^version=//p' "$state/output")" 1.0.0

# The first upload of the app: no build, no tag.
reset_repo
builds_page 1 ""
uploads_page
expect "with no build and no tag, the first number is 1" "$(number)" 1

# The cases that give no number: a person looks first.
reset_repo builds/1.0.0/5
builds_page 1 "" 1.0.0:5:false
uploads_page 5:COMPLETE 6.1:COMPLETE
expect "a build number of another form gives no number" "$(number)" "none (1)"
expect "and says which one" "$(cat "$state/err")" \
    "release-build-number: no number: an upload of App Store Connect has the build number '6.1', which is not one integer: a person looks before the next number is taken"

reset_repo builds/1.0.0/5 builds/1.0.0/x
builds_page 1 "" 1.0.0:5:false
uploads_page 5:COMPLETE
expect "a builds/ tag of another form gives no number" "$(number)" "none (1)"

reset_repo builds/1.0.0/5
builds_page 1 "" 1.0.0:5:false
uploads_page 5:COMPLETE
echo 401 > "$answers/v1_apps_42_buildUploads-1.json.status"
answer v1_apps_42_buildUploads 1 '{"errors":[{"title":"Authentication credentials are missing or invalid.","detail":"Provide a properly configured and signed bearer token."}]}'
expect "an error of Apple on the uploads gives no number" "$(number)" "none (1)"
expect "and gives Apple's words" "$(cat "$state/err")" \
    "release-build-number: no number: App Store Connect answered 401 to /v1/apps/42/buildUploads: Authentication credentials are missing or invalid. Provide a properly configured and signed bearer token."

reset_repo builds/1.0.0/5
answer v1_apps 1 '{"data":[],"links":{}}'
expect "an App Store ID that Apple does not know gives no number" "$(number)" "none (1)"

reset_repo builds/1.0.0/5
answer v1_builds 1 '{"data":[{"type":"builds","id":"b5","attributes":{"version":"5"}}],"links":{"next":"{other host}/v1/builds?cursor=2"}}'
answer v1_builds 2 '{"data":[],"links":{}}'
uploads_page 5:COMPLETE
expect "a next page on another host gives no number" "$(number)" "none (1)"
expect "and the token never went to the other host" "$(grep -c . "$state/requests.log")" 2

# The token: what the fake App Store Connect got is an ES256 token of the key, for Apple's audience, of 15 minutes at most.
reset_repo builds/1.0.0/5
builds_page 1 "" 1.0.0:5:false
uploads_page 5:COMPLETE
number > /dev/null
bearer=$(sed -n '1s/^.* Bearer //p' "$state/requests.log")
expect "every request carries the token" "$(grep -c " Bearer $bearer\$" "$state/requests.log")" 3
check=$(python3 - "$bearer" "$state/public.pem" "$state" << 'EOF'
import base64, json, subprocess, sys
bearer, public, folder = sys.argv[1:4]
def part(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
header, claims, signature = bearer.split(".")
raw = part(signature)
def integer(value):
    value = value.lstrip(b"\0") or b"\0"
    if value[0] & 0x80:
        value = b"\0" + value
    return b"\x02" + bytes([len(value)]) + value
body = integer(raw[:32]) + integer(raw[32:])
open(f"{folder}/signature.der", "wb").write(b"\x30" + bytes([len(body)]) + body)
verified = subprocess.run(["openssl", "dgst", "-sha256", "-verify", public, "-signature", f"{folder}/signature.der"],
                          input=f"{header}.{claims}".encode(), capture_output=True).returncode == 0
h, c = json.loads(part(header)), json.loads(part(claims))
print(verified, h["alg"], h["kid"], h["typ"], c["iss"], c["aud"], 0 < c["exp"] - c["iat"] <= 1200)
EOF
)
expect "the token is signed by the key, with the key ID, the issuer and Apple's audience" "$check" \
    "True ES256 TESTKEY123 JWT 00000000-test-issuer appstoreconnect-v1 True"
expect "the token is never printed" "$(cat "$state/out" "$state/err" "$state/output" | grep -c -F "$bearer" || true)" 0

if [ "$failures" -ne 0 ]; then
    echo "release-build-number-test: $failures FAILED"
    exit 1
fi
echo "release-build-number-test: OK"
