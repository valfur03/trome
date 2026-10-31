#!/usr/bin/env python3
"""Fail when a docs page that carries a date line ("Last updated: ..." or "Dernière mise à jour : ...") says a day older
than the last change of its text, or a day other than the one of the same page in the other language.

Why: such a page promises its reader that the date at the top changes each time the page changes, and a reviewer who
reads a diff misses a date line that the diff does not touch.

The day of a change is the author date of its commit, in the author's own time zone: a rebase or an amend keeps it, so
a rebase never makes the check fail by itself. A change not yet committed (staged, unstaged or a new file) was written
today. A change that touches only the date line is not a change of the text.

PAGE_DATE_CHECK_TODAY=YYYY-MM-DD sets "today", for the script test only.
"""
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

from repo_files import repo_files

DOCS = "docs/src/content/docs/"
PATTERNS = [f"{DOCS}*.md", f"{DOCS}*.mdx"]
DATE_LINE = re.compile(r"^(?:Last updated|Dernière mise à jour)\s*:\s*(?P<date>.+?)\s*\.?\s*$", re.IGNORECASE)
DAY = re.compile(r"^(?P<day>\d{1,2})(?:er)?\s+(?P<month>[^\W\d_]+)\s+(?P<year>\d{4})$", re.IGNORECASE)
ENGLISH_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                  "November", "December"]
MONTHS = {
    name.lower(): number
    for names in (
        ENGLISH_MONTHS,
        ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre",
         "décembre"],
    )
    for number, name in enumerate(names, start=1)
}
COMMIT = "\x00commit "
USAGE = "Usage: page-date-check.py (no argument: every docs page of the repo that carries a date line)"


class Failure(Exception):
    pass


def git(root, arguments):
    try:
        return subprocess.run(["git", *arguments], cwd=root, capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise Failure(f"git {' '.join(arguments)} failed: {getattr(error, 'stderr', '') or error}") from error


def is_date_line(line):
    return DATE_LINE.match(line) is not None


def page_date(path):
    """The first date line of the page: (its text, its day), or None when the page has none."""
    with open(path, encoding="utf-8") as file:
        for line in file:
            match = DATE_LINE.match(line.rstrip("\n"))
            if match:
                return line.strip(), parse_day(match.group("date"), path)
    return None


def parse_day(text, path):
    match = DAY.match(text.replace(" ", " ").replace(" ", " "))
    month = MONTHS.get(match.group("month").lower()) if match else None
    if not month:
        raise Failure(f"{path}: the date line says '{text}', which is not a day such as '14 October 2026' or "
                      "'14 octobre 2026'")
    try:
        return datetime.date(int(match.group("year")), month, int(match.group("day")))
    except ValueError as error:
        raise Failure(f"{path}: the date line says '{text}', which is not a real day ({error})") from error


def changes_text(diff):
    """True when a diff with no context lines (--unified=0) adds or removes a line other than a date line."""
    in_hunk = False
    for line in diff.splitlines():
        if line.startswith("diff --git ") or line.startswith(COMMIT):
            in_hunk = False
        elif line.startswith("@@"):
            in_hunk = True
        elif in_hunk and line[:1] in "+-" and not is_date_line(line[1:]):
            return True
    return False


def today():
    forced = os.environ.get("PAGE_DATE_CHECK_TODAY")
    return datetime.date.fromisoformat(forced) if forced else datetime.date.today()


def shallow_commits(root):
    shallow = Path(git(root, ["rev-parse", "--path-format=absolute", "--git-path", "shallow"]).strip())
    return set(shallow.read_text().split()) if shallow.is_file() else set()


def last_change(root, page):
    """The last change of the text of the page: (its day, where it is), or None when the history cannot tell."""
    has_head = subprocess.run(["git", "rev-parse", "--verify", "--quiet", "HEAD"], cwd=root,
                              capture_output=True).returncode == 0
    tracked = has_head and git(root, ["ls-tree", "--name-only", "HEAD", "--", page]).strip() != ""
    if not tracked or changes_text(git(root, ["diff", "HEAD", "--unified=0", "--no-color", "--", page])):
        return today(), "not yet committed"
    log = git(root, ["log", "--follow", "-p", "--unified=0", "--no-color", "--no-ext-diff",
                     "--format=%x00commit %H %ad", "--date=short", "--", page])
    boundary = shallow_commits(root)
    for entry in log.split(COMMIT)[1:]:
        header, _, diff = entry.partition("\n")
        commit, day = header.split()
        if commit in boundary:
            return None
        if changes_text(diff):
            return datetime.date.fromisoformat(day), f"commit {commit[:7]}"
    return None


def twin_key(page):
    """docs/src/content/docs/<language>/<path> gives <path>: the pages of one key are one page in each language."""
    language, _, rest = page[len(DOCS):].partition("/")
    return rest if rest else None


def spoken(day):
    return f"{day.day} {ENGLISH_MONTHS[day.month - 1]} {day.year}" if day else "no date line"


def check(root, pages):
    failures = []
    dated = {}
    for page in pages:
        found = page_date(root / page)
        if found:
            dated[page] = found
    for page, (line, day) in dated.items():
        change = last_change(root, page)
        if change and day < change[0]:
            failures.append(
                f"{page}: the date line says '{line}', but the text of the page changed on {spoken(change[0])} "
                f"({change[1]}): set the date line to that day or later")
    groups = {}
    for page in pages:
        key = twin_key(page)
        if key:
            groups.setdefault(key, []).append(page)
    for key, twins in groups.items():
        if len(twins) > 1 and any(page in dated for page in twins):
            days = {page: dated[page][1] if page in dated else None for page in twins}
            if len(set(days.values())) > 1:
                said = ", ".join(f"{page} says {spoken(day)}" for page, day in days.items())
                failures.append(f"the pages of {key} in each language must carry the same date: {said}")
    return failures, dated


def main(arguments):
    if arguments:
        sys.exit(USAGE)
    root, pages = repo_files("page-date-check", PATTERNS)
    try:
        failures, dated = check(root, pages)
    except Failure as error:
        sys.exit(f"page-date-check: {error}")
    for failure in failures:
        print(f"page-date-check: {failure}", file=sys.stderr)
    if failures:
        sys.exit("page-date-check: FAILED. A page with a date line promises that the date changes each time the "
                 "page changes: set the date line to the day of the change, the same in each language.")
    print(f"page-date-check: OK ({len(dated)} dated pages, each date as recent as its text, the same in each language)")


if __name__ == "__main__":
    main(sys.argv[1:])
