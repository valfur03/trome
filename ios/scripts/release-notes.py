#!/usr/bin/env python3
"""Prints the notes that the next release of the app would have, from the notes of ios/changes/, or says "no release".

  make release-notes   The store What's New and the TestFlight What to Test, in French and in English, and the entry of
                       CHANGELOG.md. Or "no release: nothing a rider notices since <build>", with the lines that wait.

The notes of a version are the notes that the build on the App Store does not hold: the files of ios/changes/ that are
not in the commit of its tag. The build on the App Store is the newest row of the table "The builds that riders may
hold" of the release guide whose Where cell says App Store; before the first one, it is the first build of the table.
Why the tag and not a date: a line is true only if the build that a rider holds lacks the change, and a date (of a note,
of an issue) cannot say which build shipped a change; the tag of the build can.

A release exists for one headline (or a requirement of Apple that stops the updates), with up to three smaller items.
So the command ends green with "no release" when no headline and no apple note waits, and ends red with "two headlines"
when two wait: the second waits a week, for its own release. A builder note alone never makes a release.

Exit status: 0 for a release or "no release", 1 when the notes cannot make the texts.
"""
from __future__ import annotations

import datetime
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List

from builds_table import GUIDE, table_rows, tag_of
from change_notes import NOTES, README, read_note, note_problems
from repo_files import repo_files

VERSION_FILE = "ios/Config/Base.xcconfig"
STORE_LIMIT = 4000  # characters per language: Apple's limit of the What's New field.
# Bytes per language. Apple's pages give no limit for What to Test, and a forum report saw a text well above 2 KB stop
# showing, so every TestFlight text of the repo stays under 1,000 bytes.
TESTFLIGHT_LIMIT = 1000
ITEMS = 3  # The items that ride with the headline: the store cuts its text after about 3 lines, then "more".
NEW_IN_THIS_BUILD = {"fr": "Nouveau dans ce build :", "en": "New in this build:"}
# What a tester of a later build needs: where the app works, and how to report a problem. Not the "three things to try"
# of the first text, which is for a first install.
FOR_TESTERS = {
    "fr": "Pour Paris et l’Île-de-France seulement. Un problème ? Prenez une capture d’écran : TestFlight propose de me l’envoyer.",
    "en": "For Paris and Île-de-France only. A problem? Take a screenshot: TestFlight offers to send it to me.",
}
NAMES = {"fr": "French", "en": "English"}
MONTHS = {
    "fr": ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
}
USAGE = "Usage: release-notes.py (no argument): run it as make release-notes"


class Refused(Exception):
    """The notes cannot make the texts of a release: the message says why and what to do."""


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True, check=True).stdout


def store_build(root: Path):
    """(the build, its tag, whether it is on the App Store) that the notes of the next version are counted from."""
    rows = table_rows(str(root / GUIDE))
    if rows is None:
        raise Refused(f'the table "The builds that riders may hold" of {GUIDE} cannot be read, so no build is known')
    where = next((heading for heading in rows[0] if heading.startswith("Where")), None)
    on_store = [row for row in rows if where and "App Store" in row[where]]
    build = (on_store or rows)[-1 if on_store else 0]["build"]
    tag = tag_of(build)
    if tag is None:
        raise Refused(f"the build '{build}' of the table of builds is not written as 1.0.0 (3)")
    try:
        git(root, "rev-parse", "-q", "--verify", f"{tag}^{{commit}}")
    except subprocess.CalledProcessError:
        raise Refused(f"the build {build} has no tag {tag}: add it on the commit of the build, as step 4 of the release guide says")
    try:
        git(root, "merge-base", "--is-ancestor", tag, "HEAD")
    except subprocess.CalledProcessError:
        raise Refused(f"this commit does not hold the build {build} ({tag}): run the command from main")
    return build, tag, bool(on_store)


def pending_notes(root: Path, tag: str) -> List[Dict[str, str]]:
    """The notes that the build of the tag does not hold, each with its file, its fields and when it was added."""
    _, paths = repo_files("release-notes", [NOTES])
    paths = [path for path in paths if path != README]
    problems = []
    for path in paths:
        problems += [f"{path}: {problem}" for problem in note_problems(path, (root / path).read_text(encoding="utf-8"))]
    if problems:
        raise Refused("a note breaks its format (make change-notes-check says the same):\n" + "\n".join(problems))
    shipped = set(git(root, "ls-tree", "-r", "--name-only", tag, "--", NOTES).split("\n"))
    notes = []
    for path in paths:
        if path in shipped:
            continue
        fields, _ = read_note((root / path).read_text(encoding="utf-8"))
        added = git(root, "log", "-1", "--diff-filter=A", "--format=%ct", "--", path).strip()
        # A note that no commit holds yet is the newest.
        notes.append({**fields, "file": path, "added": added or str(int(time.time()))})
    # Newest first; the file name orders the notes of one commit.
    notes.sort(key=lambda note: note["file"])
    notes.sort(key=lambda note: int(note["added"]), reverse=True)
    return notes


def version(root: Path) -> str:
    try:
        text = (root / VERSION_FILE).read_text(encoding="utf-8")
    except OSError:
        return "?"
    match = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", text, re.MULTILINE)
    return match.group(1) if match else "?"


def day(language: str, today: datetime.date) -> str:
    return f"{today.day} {MONTHS[language][today.month - 1]} {today.year}"


def lines_of(notes: List[Dict[str, str]], language: str) -> List[str]:
    """The first note as a line of its own, then each other note as a bullet."""
    return [note[language] for note in notes[:1]] + [f"• {note[language]}" for note in notes[1:]]


def block(title: str, text: str) -> str:
    return f"\n{title}\n{text}"


def texts(notes: List[Dict[str, str]]) -> Dict[str, Dict[str, str]]:
    """The texts of each place in each language, checked against the limit of its field."""
    store = {language: "\n".join(lines_of(notes, language)) for language in NAMES}
    testflight = {
        language: "\n".join(([NEW_IN_THIS_BUILD[language], store[language], ""] if notes else []) + [FOR_TESTERS[language]])
        for language in NAMES
    }
    for language, name in NAMES.items():
        if len(store[language]) > STORE_LIMIT:
            raise Refused(f"the {name} What's New has {len(store[language])} characters, more than Apple's {STORE_LIMIT}: shorten its notes")
        size = len(testflight[language].encode("utf-8"))
        if size > TESTFLIGHT_LIMIT:
            raise Refused(f"the {name} What to Test has {size} bytes, more than {TESTFLIGHT_LIMIT}: shorten its notes")
    return {"store": store, "testflight": testflight}


def report(root: Path, today: datetime.date) -> str:
    build, tag, on_store = store_build(root)
    notes = pending_notes(root, tag)
    by_kind = {kind: [note for note in notes if note["kind"] == kind] for kind in ("headline", "apple", "item", "builder")}
    if len(by_kind["headline"]) > 1:
        files = ", ".join(note["file"] for note in by_kind["headline"])
        raise Refused(
            f"two headlines wait ({files}): a release tells one, and the second waits a week for its own release.\n"
            "Keep the change of one of them out of this build, or make it an item if a rider would not tell a friend about it.")
    since = f"the notes since {build}, " + ("the build on the App Store" if on_store else "the first build, as no build is on the App Store yet")
    out = []
    rider = by_kind["headline"] + by_kind["apple"] + by_kind["item"]
    if not by_kind["headline"] and not by_kind["apple"]:
        out.append(f"no release: nothing a rider notices since {build}.")
        if not on_store:
            out.append(f"No build is on the App Store yet: {build} is the first build of the table of builds.")
        waiting = [f"- item: {note['en']} ({note['file']})" for note in by_kind["item"]]
        waiting += [f"- builder: {note['en']} ({note['file']})" for note in by_kind["builder"]]
        out.append("The lines that wait for a headline:\n" + "\n".join(waiting) if waiting else "No line waits.")
        shown = by_kind["item"]
    else:
        shown, left_out = rider[: 1 + ITEMS], rider[1 + ITEMS :]
        lead = "the headline" if by_kind["headline"] else "the requirement of Apple"
        count = f"{len(shown) - 1} item{'' if len(shown) == 2 else 's'}"
        out.append(f"release-notes: {since} (tag {tag}): {lead} and {count}, newest first.")
        if not on_store:
            out.append("The first version has no What's New field: these texts are for the versions after it.")
        if left_out:
            out.append(
                f"Left out, as the store shows at most {ITEMS} items (merge one into another note to keep it):\n"
                + "\n".join(f"- {note['en']} ({note['file']})" for note in left_out))
        current = version(root)
        if on_store and current == build.split(" ")[0]:
            out.append(f"Raise MARKETING_VERSION in {VERSION_FILE}: {current} is the version on the App Store.")
    made = texts(shown)
    if by_kind["headline"] or by_kind["apple"]:
        for language, name in NAMES.items():
            text = made["store"][language]
            out.append(block(f"== App Store, What's New, {name} ({len(text)} characters of {STORE_LIMIT}) ==", text))
    for language, name in NAMES.items():
        text = made["testflight"][language]
        out.append(block(f"== TestFlight, What to Test, {name} ({len(text.encode('utf-8'))} bytes of {TESTFLIGHT_LIMIT}) ==", text))
    if by_kind["headline"] or by_kind["apple"]:
        entry = [f"## {version(root)} – {day('en', today)}", "", "### For riders", ""] + [f"- {note['en']}" for note in shown]
        if by_kind["builder"]:
            entry += ["", "### For builders", ""] + [f"- {note['en']}" for note in by_kind["builder"]]
        out.append(block("== CHANGELOG.md; the What's new pages take the same rider lines, French on the French page ==", "\n".join(entry)))
    return "\n".join(out)


def main(arguments: List[str]) -> int:
    if arguments:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
        print(report(root, datetime.date.today()))
    except Refused as refused:
        print(f"release-notes: {refused}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
