#!/bin/sh
set -eu

usage() {
    echo "Usage: strings-sync.sh sync|check <command that makes Xcode update the String Catalogs...>" >&2
    exit 2
}

[ $# -ge 2 ] || usage
mode=$1
shift
case $mode in
    sync | check) ;;
    *) usage ;;
esac

catalogs() {
    find . -path ./.build -prune -o -name '*.xcstrings' -type f -print | sort
}

snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT

mkdir -p "$snapshot/files"
catalogs > "$snapshot/before.list"
while IFS= read -r catalog; do
    mkdir -p "$snapshot/files/$(dirname "$catalog")"
    cp "$catalog" "$snapshot/files/$catalog"
done < "$snapshot/before.list"

if ! "$@" > "$snapshot/command.log" 2>&1; then
    cat "$snapshot/command.log" >&2
    echo "strings-sync: the Xcode command failed" >&2
    [ "$mode" = sync ] || cp -R "$snapshot/files/." .
    exit 1
fi

catalogs > "$snapshot/after.list"
changed=""
while IFS= read -r catalog; do
    if [ ! -f "$snapshot/files/$catalog" ]; then
        changed="$changed ${catalog#./}"
        [ "$mode" = sync ] || { cat "$catalog"; rm "$catalog"; }
    elif ! cmp -s "$snapshot/files/$catalog" "$catalog"; then
        changed="$changed ${catalog#./}"
        [ "$mode" = sync ] || { diff -u "$snapshot/files/$catalog" "$catalog" || true; }
    fi
done < "$snapshot/after.list"
while IFS= read -r catalog; do
    grep -qxF "$catalog" "$snapshot/after.list" || changed="$changed ${catalog#./}"
done < "$snapshot/before.list"

if [ "$mode" = sync ]; then
    if [ -n "$changed" ]; then
        echo "strings-sync: Xcode updated:$changed. Check the change and commit it."
    else
        echo "strings-sync: OK (Xcode changed no String Catalog)"
    fi
    exit 0
fi

cp -R "$snapshot/files/." .
if [ -n "$changed" ]; then
    echo "strings-check: FAILED: a build in Xcode would change:$changed (see the diff above)." >&2
    echo "Run make strings-sync: Xcode then updates the String Catalogs. Check the change and commit it." >&2
    exit 1
fi
echo "strings-check: OK (a build in Xcode changes no String Catalog)"
