#!/bin/sh
# The check of the date line of the docs pages: a page whose date is older than the last change of its text, or not the
# same as the date of the same page in the other language, fails; a rider would read a date that the page breaks.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
# "Today" is fixed, so a run near midnight gives the same result.
export PAGE_DATE_CHECK_TODAY=2026-11-05

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

said() {
    grep -cF "$1" "$state/out" || true
}

new_repo() {
    rm -rf "$repo"
    git init -q -b main "$repo"
    mkdir -p "$repo/docs/src/content/docs/en" "$repo/docs/src/content/docs/fr"
}

# page <language> <date line, or "none"> <text>
page() {
    file="$repo/docs/src/content/docs/$1/privacy.mdx"
    case "$1:$2" in
        *:none) date_line="" ;;
        en:*) date_line="Last updated: $2." ;;
        fr:*) date_line=$(printf 'Dernière mise à jour\302\240: %s.' "$2") ;;
    esac
    printf -- '---\ntitle: Privacy\n---\n\n%s\n\n%s\n' "$date_line" "$3" > "$file"
}

# commit_on <YYYY-MM-DD>: the author and the committer write the commit on that day.
commit_on() {
    git -C "$repo" add -A
    GIT_AUTHOR_DATE="$1T12:00:00+0200" GIT_COMMITTER_DATE="$1T12:00:00+0200" git -C "$repo" commit -q -m "change on $1"
}

check() {
    (cd "$repo/docs" && "$scripts/page-date-check.py") > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

en=docs/src/content/docs/en/privacy.mdx
fr=docs/src/content/docs/fr/privacy.mdx

new_repo
page en "20 October 2026" "The server keeps nothing."
commit_on 2026-10-20
expect "a page whose text did not change since its date passes" "$(check)" "passes"
expect "the OK line counts the dated pages" "$(said "OK (1 dated pages")" "1"

page en "20 October 2026" "The server keeps nothing, and forgets each answer."
commit_on 2026-10-31
expect "a committed change of the text with the date line left older fails" "$(check)" "fails"
expect "the message names the page, the date it says and the day of the change" \
    "$(said "$en: the date line says 'Last updated: 20 October 2026.', but the text of the page changed on 31 October 2026 (commit ")" "1"
expect "the message says to set the date line" "$(said "set the date line to that day or later")" "1"

page en "31 October 2026" "The server keeps nothing, and forgets each answer."
commit_on 2026-10-31
expect "a change that only moves the date line to the day of the change passes" "$(check)" "passes"

page en "2 November 2026" "The server keeps nothing, and forgets each answer."
commit_on 2026-11-02
expect "a date later than the last change (the merge day) passes, and a commit of the date alone is no change" \
    "$(check)" "passes"

page en "2 November 2026" "The server keeps nothing at all, and forgets each answer."
expect "a change of the text not yet committed, with the date line older than today, fails" "$(check)" "fails"
expect "the message says that the change is not yet committed, and gives today" \
    "$(said "changed on 5 November 2026 (not yet committed)")" "1"
git -C "$repo" add -A
expect "a staged change of the text, with the date line older than today, fails" "$(check)" "fails"

page en "5 November 2026" "The server keeps nothing at all, and forgets each answer."
expect "a change not yet committed that also sets the date to today passes" "$(check)" "passes"

git -C "$repo" checkout -q -- .
page en "4 November 2026" "The server keeps nothing, and forgets each answer."
expect "a date line moved forward and not yet committed, with no other change, passes" "$(check)" "passes"

git -C "$repo" checkout -q -- .
printf -- '---\ntitle: Help\n---\n\nLast updated: 1 October 2026.\n\nText.\n' > "$repo/docs/src/content/docs/en/help.mdx"
expect "a new page that git does not track yet, with a date older than today, fails" "$(check)" "fails"
expect "the message names the new page" "$(said "docs/src/content/docs/en/help.mdx: the date line says")" "1"
rm "$repo/docs/src/content/docs/en/help.mdx"

new_repo
page en "20 October 2026" "Text."
commit_on 2026-10-20
page en "20 October 2026" "Text, and more text."
commit_on 2026-10-25
page en "30 October 2026" "Text, and more text."
commit_on 2026-10-30
page en "21 October 2026" "Text, and more text."
commit_on 2026-10-31
expect "a commit of the date alone that sets a day older than the last change of the text fails" "$(check)" "fails"
expect "the day of the change is the one of the last commit that changed the text" \
    "$(said "changed on 25 October 2026")" "1"

new_repo
page en "30 October 2026" "Text."
page fr "30 octobre 2026" "Texte."
commit_on 2026-10-30
expect "the pages of each language with the same date pass" "$(check)" "passes"

page en "31 October 2026" "Text."
commit_on 2026-10-31
expect "a page with one date and its twin with another fails" "$(check)" "fails"
expect "the message names both pages and both dates" \
    "$(said "the pages of privacy.mdx in each language must carry the same date: $en says 31 October 2026, $fr says 30 October 2026")" "1"

page fr none "Texte."
commit_on 2026-10-31
expect "a dated page whose twin carries no date line fails" "$(check)" "fails"
expect "the message says that the twin has no date line" "$(said "$fr says no date line")" "1"

new_repo
page en "1 November 2026" "Text."
page fr "1er novembre 2026" "Texte."
commit_on 2026-11-01
expect "a French date written '1er novembre' is read as the first of the month" "$(check)" "passes"

page fr "31 novembre 2026" "Texte."
commit_on 2026-11-01
expect "a date line with a day that does not exist fails" "$(check)" "fails"
expect "the message names the page and the date it says" "$(said "$fr: the date line says '31 novembre 2026'")" "1"

page fr "next week" "Texte."
commit_on 2026-11-01
expect "a date line that is not a day fails" "$(check)" "fails"

new_repo
page en "20 October 2026" "Text."
commit_on 2026-10-20
git -C "$repo" checkout -q -b task
page en "30 October 2026" "Text, changed by the task."
commit_on 2026-10-30
git -C "$repo" checkout -q main
printf 'Other.\n' > "$repo/other.md"
commit_on 2026-10-31
git -C "$repo" checkout -q task
GIT_COMMITTER_DATE="2026-11-03T12:00:00+0100" git -C "$repo" rebase -q main
expect "the rebase gave the commit of the task a later committer date" \
    "$(git -C "$repo" log -1 --format=%cd --date=short -- "$en")" "2026-11-03"
expect "a rebase of a good task onto main never makes the check fail by itself" "$(check)" "passes"

new_repo
page en "20 October 2026" "Text."
commit_on 2026-10-20
git -C "$repo" mv "$en" docs/src/content/docs/en/policy.mdx
commit_on 2026-10-31
expect "a page renamed with no change of its text keeps the day of its last change" "$(check)" "passes"

new_repo
page en "20 October 2026" "Text."
commit_on 2026-10-20
printf 'Other.\n' > "$repo/other.md"
commit_on 2026-10-31
git clone -q --depth 1 "file://$repo" "$state/shallow"
(cd "$state/shallow" && "$scripts/page-date-check.py") > /dev/null 2>&1 && result="passes" || result="fails"
expect "a shallow clone, whose first commit shows each page as new, does not take that commit for a change" \
    "$result" "passes"

"$scripts/page-date-check.py" --all > /dev/null 2>&1 && result="passes" || result="fails"
expect "an argument fails" "$result" "fails"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "All page-date-check tests passed"
