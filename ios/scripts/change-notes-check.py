#!/usr/bin/env python3
"""Checks the notes of the changes of the app, in ios/changes/: the lines that a version tells its riders and builders.

Each change that a rider or a builder notices adds one note file in the same change (ios/changes/README.md says how), and
the notes of a version are gathered from these files at release time.
Why: the person who makes a change knows, at that moment, what a rider will notice and in which words. A list made at
release time from the commit titles gives builder words, and one made from the closed issues gives lines that are false
for the build that riders hold.

  check [<base>]  Fail, with the file and the reason, on a note that breaks its format. Also fail when the commits since
                  <base> (main by default) change the code of the app with no note and no commit that says
                  "no rider change": a title that ends with "(no rider change)", or that is "chore: no rider change".
                  Only the commits are judged, as only they merge, and the marker is in a commit message.
"""
from __future__ import annotations

import re
import subprocess
import sys
from typing import List, Optional, Tuple

from change_notes import NOTES, README, note_problems
from repo_files import repo_files

NO_RIDER_CHANGE = "no rider change"
# The marker is a line of its own form, so that a title that only talks about the rule (as the change that made it)
# does not count: "<title> (no rider change)", or "no rider change" alone after the kind of the commit.
MARKER = re.compile(r"\(no rider change\)\s*$|^(?:[a-z]+(?:\([^)]*\))?!?:\s*)?no rider change\.?\s*$", re.IGNORECASE)
# The code that goes into the app: the app, the widget and the packages that they share, except the unit tests.
APP_CODE = re.compile(r"^ios/(?:App|Widget)/|^ios/Packages/(?![^/]+/Tests/)")

USAGE = "Usage: change-notes-check.py check [<base branch, main by default>]"


def git(root, *arguments: str) -> str:
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True, check=True).stdout


def merge_base(root, base: str) -> Optional[str]:
    for ref in (base, f"origin/{base}"):
        try:
            return git(root, "merge-base", "HEAD", ref).strip()
        except subprocess.CalledProcessError:
            continue
    return None


def judge_change(root, base: str) -> Tuple[bool, str]:
    """(passes, what the change is) for the commits since base."""
    start = merge_base(root, base)
    if start is None:
        return True, f"no branch '{base}' or 'origin/{base}' to compare with, so the change is not judged"
    changed = [path for path in git(root, "diff", "--name-only", "--no-renames", start, "HEAD").split("\n") if path]
    app_code = [path for path in changed if APP_CODE.match(path)]
    if not app_code:
        return True, f"the commits since {base} change no code of the app"
    if any(path.startswith(NOTES) and path != README for path in changed):
        return True, f"the commits since {base} change the app and add or edit its note"
    if any(MARKER.search(line) for line in git(root, "log", "--format=%B", f"{start}..HEAD").split("\n")):
        return True, f"the commits since {base} change the app and say \"{NO_RIDER_CHANGE}\""
    shown = ", ".join(app_code[:3]) + (f" and {len(app_code) - 3} more" if len(app_code) > 3 else "")
    return False, (
        f"the commits since {base} change the code of the app ({shown}), with no note in {NOTES} "
        f"and no commit that says \"{NO_RIDER_CHANGE}\".\n"
        f"When a rider or a builder will notice the change, add its note ({README} says how).\n"
        f"When nobody will, end the title of one of its commits with \"({NO_RIDER_CHANGE})\", "
        f"or add this commit: git commit --allow-empty -m \"chore: {NO_RIDER_CHANGE}\"\n"
        "Why: the notes of each version are gathered from these files, so a change with neither could reach riders with no line.")


def main(arguments: List[str]) -> None:
    if not arguments or arguments[0] != "check" or len(arguments) > 2:
        sys.exit(USAGE)
    base = arguments[1] if len(arguments) == 2 else "main"
    root, paths = repo_files("change-notes-check", [NOTES])
    notes = [path for path in paths if path != README]
    failures = []
    for path in notes:
        try:
            text = (root / path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            failures.append(f"{path}: could not read it as UTF-8 text: {error}")
            continue
        failures += [f"{path}: {problem}" for problem in note_problems(path, text)]
    passes, change = judge_change(root, base)
    if not passes:
        failures.append(change)
    for failure in failures:
        print(f"change-notes-check: {failure}", file=sys.stderr)
    if failures:
        sys.exit("change-notes-check: FAILED")
    print(f"change-notes-check: OK ({len(notes)} note{'' if len(notes) == 1 else 's'} in {NOTES}; {change})")


if __name__ == "__main__":
    main(sys.argv[1:])
