#!/bin/sh
# Says in one line whether the server of ios/Config/Server.xcconfig accepts its host and its app token.
# It asks the server once for the trains of one stop, as a Release build does, and gets a train answer or a refusal.
# It never prints the host or the token, never stores them, and never passes the token on a command line,
# where another process could read it: the header goes to curl on its standard input.
# Usage: release-server-check.sh <path of Server.xcconfig>
set -u

config=${1:?usage: release-server-check.sh <path of Server.xcconfig>}
file=ios/Config/Server.xcconfig
# Abbesses (metro 12), the stop of the examples of contracts/api/.
path=/v1/stops/STIF:StopArea:SP:42155:/departures

say() {
    echo "$1"
    exit "${2:-1}"
}

# The value of a setting as Xcode reads it: // starts a comment, the spaces around the value go, the last line wins.
setting() {
    sed -n -e 's/\r$//' -e 's|//.*||' -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$config" | tail -n 1 | sed 's/[[:space:]]*$//'
}

[ -f "$config" ] || say "No $file: make it as step 4.2 of the release guide says (cp -n ios/Config/Server.example.xcconfig $file), put the host and the app token in it, then run this again."

host=$(setting TRAIN_SERVER_HOST)
token=$(setting TRAIN_SERVER_APP_TOKEN)

[ -n "$host" ] || say "No host in $file: put the host of the production server after TRAIN_SERVER_HOST =, then run this again."
case $host in
    *[!A-Za-z0-9.-]* | .* | -*)
        say "TRAIN_SERVER_HOST in $file is not a host: write only the host, with no https:// and no path, then run this again." ;;
    *staging*)
        say "TRAIN_SERVER_HOST in $file is the staging server: put the host of the production server, then run this again." ;;
esac
[ -n "$token" ] || say "No app token in $file: put the APP_TOKEN of the production server after TRAIN_SERVER_APP_TOKEN =, then run this again."

# The tests of this script set RELEASE_SERVER_CHECK_TEST_SERVER to a fake server (address:port), reached over plain HTTP.
if [ -n "${RELEASE_SERVER_CHECK_TEST_SERVER:-}" ]; then
    set -- --connect-to "$host:80:$RELEASE_SERVER_CHECK_TEST_SERVER" "http://$host$path"
else
    set -- --proto =https "https://$host$path"
fi

# -q first: no .curlrc, so no setting of this Mac can make curl log the header. printf is a shell builtin: no process gets the token.
answer=$(printf 'Authorization: Bearer %s\n' "$token" | curl -q --silent --max-time 20 --header @- --write-out '\n%{http_code}' "$@" 2>/dev/null)
code=$?
unset token

case $code in
    0) ;;
    6) say "No server found at TRAIN_SERVER_HOST of $file: check the host against the one that make server-deploy printed, and your connection." ;;
    *) say "The server at TRAIN_SERVER_HOST of $file cannot be reached (curl error $code): check your connection and the host, then run this again." ;;
esac

status=$(printf '%s\n' "$answer" | tail -n 1)
case $status in
    200)
        case $answer in
            *'"Siri"'*) say "OK: the production server accepts the host and the app token of $file, and gave trains." 0 ;;
        esac ;;
    401)
        say "Refused: the server does not accept TRAIN_SERVER_APP_TOKEN of $file: put the APP_TOKEN that you set for the production server, then run this again." ;;
    503)
        reason=$(printf '%s\n' "$answer" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([a-z-]*\)".*/\1/p' | head -n 1)
        say "OK: the production server accepts the host and the app token of $file, but has no trains right now (${reason:-out}); if it lasts, read Find a problem in server/guide/deploy.md." 0 ;;
esac
say "The host in TRAIN_SERVER_HOST of $file answers, but not as the train server (HTTP $status): check the host against the one that make server-deploy printed."
