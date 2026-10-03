#!/bin/sh
set -eu
scripts=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

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

server="$state/server"
bin="$state/bin"
mkdir -p "$server/scripts" "$server/node_modules/.bin" "$bin"
cp "$scripts/login.sh" "$server/scripts/"

cat > "$server/node_modules/.bin/wrangler" << FAKE
#!/bin/sh
echo "\$*" > "$state/wrangler-args"
FAKE
chmod +x "$server/node_modules/.bin/wrangler"

for browser in open osascript xdg-open; do
    cat > "$bin/$browser" << FAKE
#!/bin/sh
echo "$browser \$*" >> "$state/browser-opened"
FAKE
    chmod +x "$bin/$browser"
done

login() {
    rm -f "$state/wrangler-args" "$state/browser-opened"
    (cd "$state" && PATH="$bin:$PATH" "$server/scripts/login.sh" "$@") > "$state/out" 2>&1 && echo "runs" || echo "refuses"
}

wrangler_args() {
    cat "$state/wrangler-args" 2> /dev/null || echo "not called"
}

browser_opened() {
    cat "$state/browser-opened" 2> /dev/null || echo "no browser"
}

expect "default: it runs" "$(login "" "")" "runs"
expect "default: it calls wrangler login as before, which opens the default browser" "$(wrangler_args)" "login"
expect "default: the script opens no browser itself" "$(browser_opened)" "no browser"

expect "no argument at all: it runs" "$(login)" "runs"
expect "no argument at all: it calls wrangler login as before" "$(wrangler_args)" "login"

expect "LINK=1: it runs" "$(login 1 "")" "runs"
expect "LINK=1: wrangler shows the link and opens no browser" "$(wrangler_args)" "login --browser=false"
expect "LINK=1: the script opens no browser itself" "$(browser_opened)" "no browser"
expect "LINK=1: it says to copy the link into the browser of your choice on this Mac" "$(contains "$state/out" "Copy the whole link into the browser of your choice on this Mac")" "yes"
expect "LINK=1: it says that the link works for 2 minutes" "$(contains "$state/out" "You have 2 minutes")" "yes"

expect "CODE=1: it runs" "$(login "" 1)" "runs"
expect "CODE=1: wrangler uses a code, and opens no browser for its page either" "$(wrangler_args)" "login --device --browser=false"
expect "CODE=1: the script opens no browser itself" "$(browser_opened)" "no browser"
expect "CODE=1: it says to type the code on the page" "$(contains "$state/out" "type the code")" "yes"

expect "LINK=1 and CODE=1: it refuses" "$(login 1 1)" "refuses"
expect "LINK=1 and CODE=1: it does not call wrangler" "$(wrangler_args)" "not called"
expect "LINK=1 and CODE=1: it says to choose one" "$(contains "$state/out" "Choose one way to log in")" "yes"

make_login() {
    make -s -n -C "$scripts/.." server-login "$@" 2> /dev/null | grep -F login.sh || echo "no login.sh"
}

root_make_login() {
    make -s -C "$scripts/../.." SUB_MAKE="make -s -n --no-print-directory" server-login "$@" 2> /dev/null | grep -F login.sh || echo "no login.sh"
}

expect "make server-login runs the script with no option" "$(make_login)" './scripts/login.sh "" ""'
expect "make server-login LINK=1 gives the link option to the script" "$(make_login LINK=1)" './scripts/login.sh "1" ""'
expect "make server-login CODE=1 gives the code option to the script" "$(make_login CODE=1)" './scripts/login.sh "" "1"'
expect "the root make server-login LINK=1 passes LINK to the server Makefile" "$(root_make_login LINK=1)" './scripts/login.sh "1" ""'
expect "the root make server-login CODE=1 passes CODE to the server Makefile" "$(root_make_login CODE=1)" './scripts/login.sh "" "1"'

[ "$failures" -eq 0 ]
