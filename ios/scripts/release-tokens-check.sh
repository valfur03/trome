#!/bin/sh
# Says, one line per build that riders may hold, whether the production server accepts its app token.
# The builds are the rows of the table "The builds that riders may hold" of the release guide that are not retired;
# their tokens are in ios/Config/BuildTokens.txt, which git ignores; the host is the one of ios/Config/Server.xcconfig.
# It asks the server once per build, as a Release build does, so at most one PRIM call per token,
# and stops when the server says that it has no PRIM calls left.
# It never prints the host or a token, never stores them, and never passes a token on a command line.
# Usage: release-tokens-check.sh <path of BuildTokens.txt> <path of Server.xcconfig> <path of the release guide>
set -u
usage='usage: release-tokens-check.sh <path of BuildTokens.txt> <path of Server.xcconfig> <path of the release guide>'

say() {
    echo "$1"
    exit "${2:-1}"
}

tokens=${1:?$usage}
config=${2:?$usage}
guide=${3:?$usage}
tokens_file=ios/Config/BuildTokens.txt
section='The builds that riders may hold'

# The builds of the table, one line each: the version and build as the table writes it, the build number, and
# "field" or "retired". A row whose status does not start with Retired is in the field.
builds=$(awk -v section="## $section" '
    $0 == section { found = 1; inside = 1; next }
    inside && /^#/ { inside = 0 }
    inside && /^\|[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+\([0-9]+\)[[:space:]]*\|/ {
        n = split($0, cell, "|")
        name = cell[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        number = name; sub(/.*\(/, "", number); sub(/\).*/, "", number)
        state = cell[n - 1]; gsub(/^[[:space:]]+/, "", state)
        print name "|" number "|" (state ~ /^Retired/ ? "retired" : "field")
    }
    END { if (!found) print "no-section" }
' "$guide" 2>/dev/null)
[ -f "$guide" ] && [ "$builds" != no-section ] ||
    say "The release guide has no table \"$section\": this check reads its builds there, so restore the table, then run this again."
field=$(printf '%s\n' "$builds" | grep '|field$')
[ -n "$field" ] || say "OK: the release guide lists no build in the field, so no token to check." 0
numbers=$(printf '%s\n' "$field" | cut -d '|' -f 2 | tr '\n' ' ' | sed 's/ $//; s/ /, /g')

# The file: one line per build, "<build number> = <its app token>"; // starts a comment, as in Server.xcconfig.
[ -f "$tokens" ] || say "No $tokens_file: make it with cp -n ios/Config/BuildTokens.example.txt $tokens_file, add the app token of each build in the field ($numbers) as \"$section\" in the release guide says, then run this again."
lines() { sed -e 's/\r$//' -e 's|//.*||' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$tokens"; }
lines | grep -q . ||
    say "$tokens_file has no token: add one line \"<build> = <its app token>\" for each build in the field ($numbers), from your password manager, then run this again."
# The number of a line that is not "<build> = <token>": cut keeps the rest of the line, and so any token, out of the variable.
bad=$(lines | grep -nv '^$' | grep -Ev '^[0-9]+:[0-9]+[[:space:]]*=[[:space:]]*[^[:space:]]+$' | cut -d : -f 1 | head -n 1)
[ -z "$bad" ] || say "Line $bad of $tokens_file is not \"<build> = <its app token>\": write the build number, =, and its token, then run this again."

# The token of a build number, read by sed from the file: it reaches this script through a pipe, never a command line.
token_of() { lines | sed -n "s/^$1[[:space:]]*=[[:space:]]*//p"; }
missing=0
while IFS='|' read -r name number state; do
    case $(token_of "$number" | wc -l | tr -d ' ') in
        0) echo "No token for build $name in $tokens_file: add the line \"$number = <its app token>\", from your password manager."
           missing=$((missing + 1)) ;;
        1) ;;
        *) echo "Build $number has more than one line in $tokens_file: keep only the one with its app token."
           missing=$((missing + 1)) ;;
    esac
done <<EOF
$field
EOF
[ "$missing" -eq 0 ] || say "Then run this again: no build was checked."

server_config_host_only=1
. "$(dirname "$0")/release-server-config.sh"
unset token
. "$(dirname "$0")/release-server-ask.sh"

refused=0
left=
total=$(printf '%s\n' "$field" | wc -l | tr -d ' ')
# The loop runs in this shell, so say_server_problem stops the whole check.
while IFS='|' read -r name number state; do
    if [ -n "$left" ]; then
        echo "$name: not asked"
        continue
    fi
    token=$(token_of "$number")
    ask_server
    unset token
    [ "$asked" -eq 0 ] || say_server_problem
    case $status in
        200)
            case $answer in
                *'"Siri"'*) echo "$name: accepted" ;;
                *) say_server_problem ;;
            esac ;;
        # Only 401 is the server's refusal of a token; a 403 comes from Cloudflare, before the server, and says nothing of it.
        401)
            echo "$name: refused"
            refused=$((refused + 1)) ;;
        503)
            [ -n "$reason" ] || say_server_problem
            echo "$name: accepted"
            # The server has no PRIM call left: stop, so that this check never asks a server whose budget is spent.
            case $reason in budget | prim-limit) left=$reason ;; esac ;;
        *) say_server_problem ;;
    esac
done <<EOF
$field
EOF

[ "$refused" -eq 0 ] || echo "Refused: the production server refuses the token of $refused of the $total builds in the field. If its line in $tokens_file matches your password manager, the production list lost that token: set the whole list again at once, with the token of every build in the field and the newest one, as Add a token in server/guide/deploy.md says."
[ -z "$left" ] || say "Not finished: the production server has no PRIM calls left this hour ($left), so the builds marked not asked wait: run this again in an hour."
[ "$refused" -ne 0 ] || say "OK: the production server accepts the app token of each build in the field ($numbers)." 0
exit 1
