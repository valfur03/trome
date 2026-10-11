#!/bin/sh
# Says in one line whether the server of ios/Config/Server.xcconfig accepts its host and its app token.
# It asks the server once for the trains of one stop, as a Release build does, and gets a train answer or a refusal.
# It never prints the host or the token, never stores them, and never passes the token on a command line,
# where another process could read it: the header goes to curl on its standard input.
# Usage: release-server-check.sh <path of Server.xcconfig>
set -u

say() {
    echo "$1"
    exit "${2:-1}"
}

config=${1:?usage: release-server-check.sh <path of Server.xcconfig>}
. "$(dirname "$0")/release-server-config.sh"
. "$(dirname "$0")/release-server-ask.sh"

ask_server
unset token
[ "$asked" -eq 0 ] || say_server_problem

case $status in
    200)
        case $answer in
            *'"Siri"'*) say "OK: the production server accepts the host and the app token of $file, and gave trains." 0 ;;
        esac ;;
    401)
        say "Refused: the server does not accept TRAIN_SERVER_APP_TOKEN of $file: put the APP_TOKEN that you set for the production server, then run this again." ;;
    503)
        [ -z "$reason" ] || say "OK: the production server accepts the host and the app token of $file, but has no trains right now ($reason); if it lasts, read Find a problem in server/guide/deploy.md." 0 ;;
esac
say_server_problem
