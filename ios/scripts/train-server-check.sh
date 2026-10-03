#!/bin/sh
set -eu

[ "${RATP_REQUIRE_TRAIN_SERVER:-}" = YES ] || exit 0

host=${RATP_APP_TRAIN_SERVER_HOST:-}
failed=0

fail() {
    echo "error: $1" >&2
    failed=1
}

if [ -z "$host" ]; then
    fail "No train server host: a ${CONFIGURATION:-Release} build asks the server for the trains, so TRAIN_SERVER_HOST must be set. Copy ios/Config/Server.example.xcconfig to ios/Config/Server.xcconfig and fill it in."
else
    case $host in
        *[!A-Za-z0-9.-]* | .* | -*)
            fail "TRAIN_SERVER_HOST in ios/Config/Server.xcconfig is not a host name ($host): write only the host, with no https:// and no path, as ios/Config/Server.example.xcconfig says." ;;
    esac
fi

if [ -z "${RATP_APP_TRAIN_SERVER_APP_TOKEN:-}" ]; then
    fail "No app token for the train server: a ${CONFIGURATION:-Release} build sends it to the server, so TRAIN_SERVER_APP_TOKEN must be set. Copy ios/Config/Server.example.xcconfig to ios/Config/Server.xcconfig and fill it in."
fi

exit "$failed"
