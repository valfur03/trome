#!/bin/sh
# Tests ios/scripts/lock-screen-clock-check.sh with a fake text recognition: a fake swift prints the texts that
# the file read-<picture> holds, as the text recognition of the Mac prints them (<picture><tab><text>).
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

mkdir -p "$state/bin" "$state/pictures"
cat > "$state/bin/swift" << 'EOF'
#!/bin/sh
shift
for picture in "$@"; do
    [ -e "$picture" ] || { echo "no picture $picture in $(pwd)" >&2; exit 1; }
    while IFS= read -r text; do
        printf '%s\t%s\n' "$picture" "$text"
    done < "read-$picture"
done
EOF
chmod +x "$state/bin/swift"
export PATH="$state/bin:$PATH"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# picture <name> <text>...: a picture whose text recognition reads these texts.
picture() {
    name=$1
    shift
    : > "$state/pictures/$name.png"
    printf '%s\n' "$@" > "$state/pictures/read-$name.png"
}

check() {
    "$scripts/lock-screen-clock-check.sh" "$state/pictures" "$@" > "$state/out" 2>&1 && echo "exit 0" || echo "exit $?"
}

has() {
    grep -c -F -- "$1" "$state/out" || true
}

picture metro-en "Sat Jan 1" "9:41" "Saint-Paul (Le Marais)" "3" "7"
picture metro-fr "Sam. 1 janv." "9:41" "30 min"
expect "the pictures that show 9:41 pass" "$(check metro-en metro-fr)" "exit 0"
expect "a pass prints nothing" "$(wc -c < "$state/out" | tr -d ' ')" "0"

picture real-en "Sat Oct 10" "7:29" "Saint-Paul (Le Marais)"
expect "a picture that shows the real time fails" "$(check metro-en real-en)" "exit 1"
expect "the failure names the picture and the time that it shows" \
    "$(has "real-en.png: the lock screen clock shows the time 7:29, not 9:41")" "1"
expect "the failure does not name a right picture" "$(has "metro-en.png")" "0"

picture evening-fr "Sam. 10 oct." "21:10"
expect "a 24-hour real time fails" "$(check evening-fr)" "exit 1"
expect "the failure gives the 24-hour time" "$(has "evening-fr.png: the lock screen clock shows the time 21:10, not 9:41")" "1"

picture zero-en "Sat Jan 1" "09:41"
expect "09:41 is not the clock of the pictures" "$(check zero-en)" "exit 1"

picture blank-en "Saint-Paul (Le Marais)" "La Défense"
expect "a picture with no time fails" "$(check blank-en)" "exit 1"
expect "the failure says that it read no time" "$(has "blank-en.png: the lock screen clock shows no time, not 9:41")" "1"

picture inside-en "Sat Oct 10" "Next at 9:41 PM"
expect "9:41 inside a longer text is not the clock" "$(check inside-en)" "exit 1"

expect "with no picture name, it shows its usage" "$(check)" "exit 1"
expect "the usage names its arguments" "$(has "Usage:")" "1"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "lock-screen-clock-check: all tests passed"
