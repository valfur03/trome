# Asks the production server once for the trains of one stop, as a Release build does, with the app token in $token.
# Source it after release-server-config.sh, which sets host. ask_server sets asked (the exit status of curl),
# answer (the body, then the HTTP status on its last line), status (the HTTP status) and reason (the reason of an out answer).
# It never prints the host or the token, never stores them, and never passes the token on a command line,
# where another process could read it: the header goes to curl on its standard input.

# Abbesses (metro 12), the stop of the examples of contracts/api/.
path=/v1/stops/STIF:StopArea:SP:42155:/departures

ask_server() {
    # The tests of these scripts set RELEASE_SERVER_CHECK_TEST_SERVER to a fake server (address:port), reached over plain HTTP.
    if [ -n "${RELEASE_SERVER_CHECK_TEST_SERVER:-}" ]; then
        set -- --connect-to "$host:80:$RELEASE_SERVER_CHECK_TEST_SERVER" "http://$host$path"
    else
        set -- --proto =https "https://$host$path"
    fi
    # -q first: no .curlrc, so no setting of this Mac can make curl log the header. printf is a shell builtin: no process gets the token.
    answer=$(printf 'Authorization: Bearer %s\n' "$token" | curl -q --silent --max-time 20 --header @- --write-out '\n%{http_code}' "$@" 2>/dev/null)
    asked=$?
    status=$(printf '%s\n' "$answer" | tail -n 1)
    # Only the server's own "out" answer, which comes after the token check, proves the token; a 503 of Cloudflare has no reason.
    reason=
    [ "$status" != 503 ] || reason=$(printf '%s\n' "$answer" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([a-z-]*\)".*/\1/p' | head -n 1)
}

# Says the line of an answer that tells nothing of the token (the server cannot be reached, fails, or is another site), and exits.
say_server_problem() {
    case $asked in
        0) ;;
        6) say "No server found at TRAIN_SERVER_HOST of $file: check the host against the one that make server-deploy printed, and your connection." ;;
        *) say "The server at TRAIN_SERVER_HOST of $file cannot be reached (curl error $asked): check your connection and the host, then run this again." ;;
    esac
    case $status in
        5??) say "The server at TRAIN_SERVER_HOST of $file fails (HTTP $status), so this cannot tell if it accepts the token: run this again later; if it lasts, read Find a problem in server/guide/deploy.md." ;;
    esac
    say "The host in TRAIN_SERVER_HOST of $file answers, but not as the train server (HTTP $status): check the host against the one that make server-deploy printed."
}
