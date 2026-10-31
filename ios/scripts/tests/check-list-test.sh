#!/bin/sh
# The checks of make check: each one is a file of ios/checks/, so two changes that each add a check rebase onto each
# other with no conflict, and make check and make help list every check, in the order of the file names.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
root=$(cd "$ios/.." && pwd)
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE MAKEFLAGS MAKELEVEL || true

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

# The checks of make check, as make sees them, one per line.
checks_of() {
    make --no-print-directory -C "$1" -p -n -q check 2> /dev/null | sed -n 's/^check: //p' | tr ' ' '\n'
}

# The wiring of the real files: every file of ios/checks/ names one check, with its step, its help line and its rule.
in_order=$(for file in "$ios"/checks/*.mk; do sed -n 's/^CHECKS += //p' "$file"; done)
expect "make check runs the checks of ios/checks/, in the order of the file names" "$(checks_of "$ios")" "$in_order"
expect "make check runs at least the checks of the gate" "$(echo "$in_order" | grep -cxE 'lint|build|test|test-scripts')" "4"
ios_help=$(make --no-print-directory -C "$ios" help)
root_help=$(make --no-print-directory -C "$root" help)
unwired=""
for file in "$ios"/checks/*.mk; do
    name=$(sed -n 's/^CHECKS += //p' "$file")
    step=$(sed -n "s/^CHECK_STEP_$name := //p" "$file")
    [ "$(sed -n 's/^CHECKS += //p' "$file" | wc -l | tr -d ' ')" = 1 ] || unwired="$unwired ${file##*/}:not-one-check"
    [ -n "$step" ] || unwired="$unwired $name:no-step"
    grep -q "^$name:" "$file" || unwired="$unwired $name:no-rule"
    grep -q "^\.PHONY: $name\$" "$file" || unwired="$unwired $name:not-phony"
    printf '%s\n' "$ios_help" | grep -q "^make $name " || unwired="$unwired $name:no-help"
    printf '%s\n' "$root_help" | grep -q "^make $name " || unwired="$unwired $name:no-root-help"
    printf '%s\n' "$ios_help" | grep "^make check " | grep -qF "$step" || unwired="$unwired $name:not-in-check-help"
    printf '%s\n' "$root_help" | grep "^make check " | grep -qF "$step" || unwired="$unwired $name:not-in-root-check-help"
    make --no-print-directory -C "$root" -n "$name" 2> /dev/null | grep -q -- "-C ios $name\$" || unwired="$unwired $name:not-at-root"
done
expect "each check has one name, a step, a rule, a help line, and runs from the root" "$unwired" ""

# Two branches made from the same main each add a check: the second rebases onto the first with no conflict.
repo="$state/repo"
mkdir -p "$repo/ios/Config"
cp "$root/Makefile" "$repo/"
cp "$ios/Makefile" "$repo/ios/"
cp -R "$ios/checks" "$repo/ios/"
cp "$ios/Config/Base.xcconfig" "$repo/ios/Config/"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=t -c user.email=t@example.com add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m main

# A new check, as a task adds it: a new file, between the same two checks in both branches.
add_check() {
    git -C "$repo" checkout -q -b "$1" main
    printf 'CHECKS += %s\nCHECK_STEP_%s := %s step\n.PHONY: %s\n\nhelp::\n\t@echo "make %s  Fail on %s"\n\n%s:\n\t@echo %s\n' \
        "$1" "$1" "$1" "$1" "$1" "$1" "$1" "$1" > "$repo/ios/checks/045-$1.mk"
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m "$1"
}
add_check alpha-check
add_check beta-check
status=0
git -C "$repo" -c user.name=t -c user.email=t@example.com rebase -q alpha-check > "$state/rebase.log" 2>&1 || status=$?
expect "the second check rebases onto the first with no conflict" "$status" "0"
expect "make check runs both, in the order of their file names, between their neighbours" \
    "$(checks_of "$repo/ios" | grep -A3 -x page-date-check | tr '\n' ' ')" "page-date-check alpha-check beta-check change-notes-check "
expect "make help lists both, and the steps of make check name both" \
    "$(make --no-print-directory -C "$repo" help 2> /dev/null | grep -cE '^make (alpha|beta)-check |alpha-check step \+ beta-check step')" "3"
expect "the root runs both" "$(make --no-print-directory -C "$repo" -n alpha-check beta-check 2> /dev/null | grep -c -- '-C ios ')" "2"

# The control: the same two checks added to one shared line of the Makefile conflict, so the scratch repo can see one.
git -C "$repo" rebase --abort > /dev/null 2>&1 || true
for branch in alpha-line beta-line; do
    git -C "$repo" checkout -q -b "$branch" main
    sed -i.bak "s/^check: \$(CHECKS)\$/check: \$(CHECKS) $branch/" "$repo/ios/Makefile"
    rm "$repo/ios/Makefile.bak"
    git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -am "$branch"
done
status=0
git -C "$repo" -c user.name=t -c user.email=t@example.com rebase -q alpha-line > "$state/rebase.log" 2>&1 || status=$?
expect "the control: two edits of one shared line conflict" "$([ "$status" -ne 0 ] && echo conflict)" "conflict"

[ "$failures" -eq 0 ] || exit 1
