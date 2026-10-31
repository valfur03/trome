#!/usr/bin/env python3
"""Keeps the recorded phone sets of contracts/phone/ as each build wrote them.

Each build in the field has one recorded phone set, contracts/phone/<version>-<build>/: the values that it keeps on the
phone, which the unit tests read with the code of today. The tests protect a rider only while each set stays as its build
wrote it, so:

  check    (make check) fails when a file of a recorded set changed, moved, went, or was added after the set,
           while its build is in the field. A new set is a new folder, never an edit of one.
  release  (the release checks) says whether the newest build in the field has its set, and fails when it has none.

A build leaves the field only by the status "Retired on <date>: <reason>" in the table "The builds that riders may hold"
of the release guide, read here as server/scripts/builds-table.ts reads it for the sets of promises.
Why: a build never changes once riders hold it, so a set that a change could edit to match the new code would protect nobody.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from typing import Dict, List, Optional

SETS = "contracts/phone"
GUIDE = "docs/src/content/docs/en/maintain/release-on-the-app-store.mdx"
TABLE_HEADING = "## The builds that riders may hold"
RETIRED_WITH_A_REASON = re.compile(r"^Retired on [^:]+:\s*\S")
BUILD_NAME = re.compile(r"^(\d+\.\d+\.\d+) \((\d+)\)$")

USAGE = (
    "Usage: phone-set-check.py check|release [<root of the repo> <release guide>]\n"
    "  check    fail when a recorded phone set changed while its build is in the field\n"
    "  release  say whether the newest build in the field has its phone set, and fail when it has none"
)


def git(root: str, *args: str, stdin: Optional[str] = None) -> str:
    return subprocess.run(
        ["git", "-C", root, *args], input=stdin, capture_output=True, text=True, check=True
    ).stdout


def cells(line: str) -> List[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def build_rows(guide_path: str) -> Optional[List[Dict[str, object]]]:
    """The rows of the table of builds, or None when the guide has no table that can be read."""
    try:
        with open(guide_path, encoding="utf-8") as file:
            lines = file.read().split("\n")
    except OSError:
        return None
    if TABLE_HEADING not in lines:
        return None
    section = lines[lines.index(TABLE_HEADING) + 1 :]
    section = section[: next((i for i, line in enumerate(section) if line.startswith("## ")), len(section))]
    header = next((i for i, line in enumerate(section) if line.strip().startswith("|")), None)
    if header is None or "Status" not in cells(section[header]):
        return None
    status = cells(section[header]).index("Status")
    body = section[header + 2 :]
    body = body[: next((i for i, line in enumerate(body) if not line.strip().startswith("|")), len(body))]
    rows = []
    for line in body:
        row = cells(line)
        text = re.sub(r"[*`]", "", row[status] if status < len(row) else "").strip()
        rows.append(
            {
                "build": row[0],
                "retired": text.startswith("Retired on "),
                "retired_with_a_reason": bool(RETIRED_WITH_A_REASON.match(text)),
            }
        )
    return rows or None


def folder_of(build: str) -> Optional[str]:
    """contracts/phone/1.0.0-3 for the build 1.0.0 (3)."""
    match = BUILD_NAME.match(build)
    return f"{SETS}/{match.group(1)}-{match.group(2)}" if match else None


def check(root: str, guide_path: str) -> int:
    if git(root, "rev-parse", "--is-shallow-repository").strip() == "true":
        print(
            f"phone-set-check: {root} has only part of its git history, so this check cannot see what each set was"
            " when it was recorded: fetch the whole history (git fetch --unshallow).",
            file=sys.stderr,
        )
        return 1
    rows = build_rows(guide_path)
    if rows is None:
        print(
            f'phone-set-check: the table "The builds that riders may hold" of {guide_path} cannot be read,'
            " so no build can be shown retired.",
            file=sys.stderr,
        )
        return 1

    # The commit that first added each file of a set, and the commit that recorded each set: its first file.
    added_in: Dict[str, str] = {}
    set_recorded_in: Dict[str, str] = {}
    has_history = subprocess.run(["git", "-C", root, "rev-parse", "--verify", "--quiet", "HEAD"], capture_output=True).returncode == 0
    log = git(root, "log", "--reverse", "--no-renames", "--diff-filter=A", "--format=@%H", "--name-only", "--", SETS) if has_history else ""
    commit = ""
    for line in log.split("\n"):
        if line.startswith("@"):
            commit = line[1:]
        elif len(line.split("/")) > 3 and line not in added_in:
            added_in[line] = commit
            set_recorded_in.setdefault(line.split("/")[2], commit)

    # The blob of each file as it was recorded, and as it is in the working tree now.
    recorded_blob: Dict[str, str] = {}
    for commit in set(added_in.values()):
        for entry in git(root, "ls-tree", "-r", commit, "--", f"{SETS}/").splitlines():
            meta, path = entry.split("\t", 1)
            if added_in.get(path) == commit:
                recorded_blob[path] = meta.split()[2]
    present = [path for path in git(root, "ls-files", "--cached", "--others", "--exclude-standard", "--", f"{SETS}/").splitlines()]
    present = [path for path in present if os.path.isfile(os.path.join(root, path))]
    blobs = git(root, "hash-object", "--stdin-paths", stdin="".join(f"{path}\n" for path in present)).split()
    now = dict(zip(present, blobs))

    changes: Dict[str, List[str]] = {}
    for path, commit in added_in.items():
        name = path.split("/")[2]
        recorded = set_recorded_in[name][:7]
        if commit != set_recorded_in[name]:
            if path in now:
                changes.setdefault(name, []).append(f"{path} was added in {commit[:7]}, after the set was recorded in {recorded}")
        elif path not in now:
            changes.setdefault(name, []).append(f"{path} is gone (recorded in {recorded})")
        elif now[path] != recorded_blob.get(path):
            changes.setdefault(name, []).append(f"{path} changed (recorded in {recorded})")
    for path in present:
        name = path.split("/")[2] if len(path.split("/")) > 3 else ""
        if path not in added_in and name in set_recorded_in:
            changes.setdefault(name, []).append(
                f"{path} is new, and not committed, in the set recorded in {set_recorded_in[name][:7]}"
            )

    retired = {folder_of(str(row["build"])) for row in rows if row["retired_with_a_reason"]}
    problems = []
    for name, lines in sorted(changes.items()):
        if f"{SETS}/{name}" in retired:
            continue
        problems.append(
            f"phone-set-check: the recorded phone set {SETS}/{name}/ changed, but its build is not retired in the release guide:\n"
            + "".join(f"  {line}\n" for line in lines)
            + "  A recorded set is never edited: riders still hold this build, and the code of today must read what it wrote.\n"
            f"  Put the set back as {set_recorded_in[name][:7]} recorded it (git checkout {set_recorded_in[name][:7]} -- {SETS}/{name},"
            " and remove the files that it did not hold), and make the code read it.\n"
            "  A new build gets a new folder (make phone-set-record), recorded in one commit.\n"
            "  A set may change only when its build has the status 'Retired on <date>: <reason>' in the table of the release guide."
        )
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"phone-set-check: OK ({len(set_recorded_in)} recorded sets, each as its build wrote it or retired)")
    return 0


def release(root: str, guide_path: str) -> int:
    rows = build_rows(guide_path)
    field = [row for row in rows or [] if not row["retired"]]
    if rows is None:
        line, code = f'Phone set: missing (the table "The builds that riders may hold" of {guide_path} cannot be read)', 1
    elif not field:
        line, code = "Phone set: no build in the field", 0
    else:
        build = str(field[-1]["build"])
        folder = folder_of(build)
        files = git(root, "ls-files", "--", f"{folder}/") if folder else ""
        if not folder:
            line, code = f"Phone set of {build}: missing (its row does not name it as <version> (<build>))", 1
        elif files.strip():
            line, code = f"Phone set of {build}: found", 0
        else:
            version_build = folder[len(SETS) + 1 :]
            line, code = f"Phone set of {build}: missing (no {folder}/: record it with make phone-set-record BUILD={version_build})", 1
    print(line)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as file:
            file.write(f"- {line}\n")
    return code


def main(args: List[str]) -> int:
    if len(args) not in (1, 3) or args[0] not in ("check", "release"):
        print(USAGE, file=sys.stderr)
        return 2
    if len(args) == 3:
        root, guide_path = args[1], args[2]
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        root = git(here, "rev-parse", "--show-toplevel").strip()
        guide_path = os.path.join(root, GUIDE)
    return check(root, guide_path) if args[0] == "check" else release(root, guide_path)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
