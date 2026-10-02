#!/bin/sh
set -eu

port=$1
cd "$(dirname "$0")/.."

if [ ! -f .dev.vars ]; then
    cp .dev.vars.example .dev.vars
    echo "Created server/.dev.vars with the fake secrets of .dev.vars.example (git ignores it)."
fi
while IFS= read -r line; do
    name=${line%%=*}
    if ! grep -q "^$name=" .dev.vars; then
        printf '%s\n' "$line" >> .dev.vars
        echo "Added the fake secret $name of .dev.vars.example to server/.dev.vars."
    fi
done < .dev.vars.example

mkdir -p .wrangler
echo $$ > .wrangler/dev.pid
echo "The server runs at http://127.0.0.1:$port (health: http://127.0.0.1:$port/health). Stop it with 'make server-stop'."
exec ./node_modules/.bin/wrangler dev --local --ip 127.0.0.1 --port "$port" --inspector-port $((port + 10000)) --show-interactive-dev-session=false
