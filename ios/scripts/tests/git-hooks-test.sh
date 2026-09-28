#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
state=$(cd "$(mktemp -d)" && pwd -P)
repo="$state/repo"
clone="$state/clone"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE MAKEFLAGS MFLAGS MAKELEVEL SMALL LIVE || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export FAKE_XCODEGEN_LOG="$state/xcodegen.log" PATH="$state/bin:$PATH"

mkdir "$state/bin"
cat > "$state/bin/xcodegen" << 'EOF'
#!/bin/sh
echo "$(pwd) $*" >> "$FAKE_XCODEGEN_LOG"
[ -z "${FAKE_XCODEGEN_FAIL:-}" ] || { echo "fake xcodegen failed" >&2; exit 1; }
mkdir -p RATPActivity.xcodeproj
ls App > RATPActivity.xcodeproj/project.pbxproj
EOF
chmod +x "$state/bin/xcodegen"

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

commit() {
    echo "$3" > "$1/ios/App/$2"
    git -C "$1" add "ios/App/$2"
    git -C "$1" commit -q -m "add $2"
}

runs() {
    wc -l < "$FAKE_XCODEGEN_LOG" | tr -d ' '
}

lists() {
    grep -qx "$2" "$1/ios/RATPActivity.xcodeproj/project.pbxproj" 2> /dev/null && echo yes || echo no
}

clean() {
    [ -z "$(git -C "$1" status --porcelain --untracked-files=all)" ] && echo yes || echo no
}

git init -q -b main "$repo"
mkdir -p "$repo/ios/scripts/git-hooks" "$repo/ios/App"
cp "$ios/Makefile" "$repo/ios/"
cp "$ios/scripts/xcode-project-hook.sh" "$ios/scripts/git-hooks.sh" "$repo/ios/scripts/"
cp "$ios/scripts/git-hooks/"* "$repo/ios/scripts/git-hooks/"
cp "$ios/../.gitignore" "$repo/"
echo "name: RATPActivity" > "$repo/ios/project.yml"
echo one > "$repo/ios/App/One.swift"
git -C "$repo" add -A
git -C "$repo" commit -q -m first
: > "$FAKE_XCODEGEN_LOG"

make -C "$repo/ios" --no-print-directory git-hooks > "$state/on.out"
expect "make git-hooks turns the hooks on" "$(git -C "$repo" config core.hooksPath)" "ios/scripts/git-hooks"

git -C "$repo" checkout -q -b feature
commit "$repo" Two.swift two
git -C "$repo" checkout -q main
git -C "$repo" checkout -q feature
expect "a checkout creates the project again" "$(lists "$repo" Two.swift)" "yes"
expect "the hook uses the cache of make project" "$(tail -1 "$FAKE_XCODEGEN_LOG")" "$repo/ios generate --use-cache --quiet --cache-path .build/xcodegen-cache"
expect "the main folder stays clean" "$(clean "$repo")" "yes"

git -C "$repo" checkout -q main
expect "a checkout of an older commit removes the new file from the project" "$(lists "$repo" Two.swift)" "no"

before=$(runs)
git -C "$repo" checkout -q -b same-commit
git -C "$repo" checkout -q -- ios/App/One.swift
expect "a checkout that keeps the commit, or of files only, does not run xcodegen" "$(runs)" "$before"

git -C "$repo" merge -q --ff-only feature
expect "a fast-forward merge creates the project again" "$(lists "$repo" Two.swift)" "yes"

git -C "$repo" branch -q -f main HEAD~1
git -C "$repo" checkout -q main
git -C "$repo/ios" merge -q --ff-only feature
expect "a merge run from a subfolder (like make merge) creates the project again" "$(lists "$repo" Two.swift)" "yes"

git clone -q "$repo" "$clone"
git -C "$clone" config core.hooksPath ios/scripts/git-hooks
commit "$repo" Three.swift three
git -C "$clone" pull -q --ff-only
expect "a git pull creates the project again" "$(lists "$clone" Three.swift)" "yes"
expect "the clone stays clean" "$(clean "$clone")" "yes"

commit "$repo" Four.swift four
commit "$clone" Local.swift local
git -C "$clone" pull -q --rebase
expect "a git pull --rebase creates the project again" "$(lists "$clone" Four.swift)" "yes"

before=$(runs)
git -C "$repo" worktree add -q -b other "$state/worktree" feature
git -C "$state/worktree" checkout -q main 2> /dev/null || git -C "$state/worktree" checkout -q --detach main
expect "a linked worktree does not run xcodegen" "$(runs)" "$before"

git -C "$repo" checkout -q feature
git -C "$repo" branch -q -f main HEAD~1
status=0
FAKE_XCODEGEN_FAIL=1 git -C "$repo" checkout -q main 2> "$state/fail.err" || status=$?
expect "a failing xcodegen does not fail the checkout" "$status" "0"
expect "a failing xcodegen prints what to do" "$(grep -c "Run 'make generate' before you build in Xcode" "$state/fail.err")" "1"

git -C "$repo" checkout -q feature
LIVE=1 SMALL=1 git -C "$repo" checkout -q main 2> "$state/live.err"
expect "LIVE=1 or SMALL=1 in the shell does not stop the hook" "$(cat "$state/live.err")" ""

before=$(runs)
make -C "$repo/ios" --no-print-directory git-hooks-off > "$state/off.out"
expect "make git-hooks-off turns the hooks off" "$(git -C "$repo" config core.hooksPath || echo none)" "none"
git -C "$repo" checkout -q feature
expect "with the hooks off, a checkout does not run xcodegen" "$(runs)" "$before"

git -C "$repo" config core.hooksPath .husky
status=0
make -C "$repo/ios" --no-print-directory git-hooks > /dev/null 2>&1 || status=$?
expect "make git-hooks keeps another hooks folder" "$status $(git -C "$repo" config core.hooksPath)" "2 .husky"
git -C "$repo" config --unset core.hooksPath

echo hook > "$repo/.git/hooks/pre-commit"
status=0
make -C "$repo/ios" --no-print-directory git-hooks > /dev/null 2>&1 || status=$?
expect "make git-hooks keeps the hooks of .git/hooks" "$status $(git -C "$repo" config core.hooksPath || echo none)" "2 none"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
