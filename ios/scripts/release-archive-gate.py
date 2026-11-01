#!/usr/bin/env python3
"""Says whether make check must build the Release archive (make release-archive-check): only when the change since main
can alter what that check reads, so that the other changes build no archive.

The archive check reads the Release build settings and entitlements of the app and its widget, the app group in their
Info.plist, and the types that release-entitlements-check.py looks for in the binary of the app.
A change can make it fail when it touches one of these inputs:
- ios/project.yml and the files of ios/Config/: the targets, their settings, entitlements and Info.plist keys, and the
  compilation conditions (SILENT_START, WAKE_LOG) that put the types in the binary;
- a Swift file that names one of those types, on main or now: it declares the type or uses it, and a type that nothing
  uses may not reach an optimised binary;
- the check itself: release-entitlements-check.py, build-warnings.py (the archive fails on a warning), this file, its
  file of ios/checks/, and the rule of release-archive-check in ios/Makefile with its RELEASE_ARCHIVE variables (the
  rest of that file changes in about one commit out of ten, and the other builds of make check already run it).

Exit 0: the archive check must run (it prints the files that ask for it); exit 10: it need not run.
A doubt runs it: with no main to compare with, or when git fails.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Set

USAGE = "Usage: release-archive-gate.py [<base branch, main by default>]"
RUN = 0
SKIP = 10
SCRIPTS = Path(__file__).resolve().parent
INPUT_FILES = (
    "ios/project.yml",
    "ios/scripts/release-entitlements-check.py",
    "ios/scripts/build-warnings.py",
    "ios/scripts/release-archive-gate.py",
)
INPUT_FOLDERS = ("ios/Config/",)
INPUT_FILE_PATTERNS = ("ios/checks/*-release-archive-gate.mk",)
MAKEFILE = "ios/Makefile"
ARCHIVE_TARGET = "release-archive-check:"
ARCHIVE_VARIABLE = "RELEASE_ARCHIVE"


def archive_types() -> List[str]:
    """The names of the types that the archive check looks for in the binary, from the check itself."""
    spec = importlib.util.spec_from_file_location("release_entitlements_check", SCRIPTS / "release-entitlements-check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return [name.decode() for name in module.ARCHIVE_TYPES]


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True, check=True).stdout


def lines(text: str) -> Set[str]:
    return {line for line in text.split("\n") if line}


def start_of(root: Path, base: str) -> Optional[str]:
    for ref in (base, f"origin/{base}"):
        try:
            return git(root, "merge-base", "HEAD", ref).strip()
        except subprocess.CalledProcessError:
            continue
    return None


def files_naming(root: Path, names: List[str], commit: Optional[str]) -> Set[str]:
    """The Swift files that name one of the types, at a commit, or in the working tree (new files too) with none."""
    patterns = [argument for name in names for argument in ("-e", name)]
    where = [commit] if commit else ["--untracked"]
    result = subprocess.run(["git", "-C", str(root), "grep", "-l", "-w", *patterns, *where, "--", "*.swift"],
                            capture_output=True, text=True, check=False)
    if result.returncode not in (0, 1):
        raise subprocess.CalledProcessError(result.returncode, "git grep")
    prefix = f"{commit}:" if commit else ""
    return {line[len(prefix):] for line in lines(result.stdout)}


def archive_rule(makefile: str) -> List[str]:
    """The lines of a Makefile that make the archive: its RELEASE_ARCHIVE variables, and the rule of the target."""
    found = []
    in_rule = False
    for line in makefile.split("\n"):
        if line.startswith(ARCHIVE_TARGET):
            in_rule = True
        elif in_rule and not line.startswith("\t"):
            in_rule = False
        if in_rule or line.startswith(ARCHIVE_VARIABLE):
            found.append(line)
    return found


def makefile_rule_changed(root: Path, start: str) -> bool:
    try:
        before = git(root, "show", f"{start}:{MAKEFILE}")
    except subprocess.CalledProcessError:
        before = ""
    try:
        now = (root / MAKEFILE).read_text()
    except OSError:
        now = ""
    return archive_rule(before) != archive_rule(now)


def is_input(path: str, type_files: Set[str]) -> bool:
    return (path in INPUT_FILES or path in type_files or path.startswith(INPUT_FOLDERS)
            or any(Path(path).match(pattern) for pattern in INPUT_FILE_PATTERNS))


def inputs_changed(root: Path, base: str) -> Optional[List[str]]:
    """The inputs of the archive check that the change since base touches, committed or not; None with no base."""
    start = start_of(root, base)
    if start is None:
        return None
    changed = lines(git(root, "diff", "--name-only", "--no-renames", start))
    changed |= lines(git(root, "ls-files", "--others", "--exclude-standard"))
    names = archive_types()
    type_files = files_naming(root, names, start) | files_naming(root, names, None)
    found = {path for path in changed if is_input(path, type_files)}
    if MAKEFILE in changed and makefile_rule_changed(root, start):
        found.add(MAKEFILE)
    return sorted(found)


def main(arguments: List[str]) -> int:
    if len(arguments) > 1:
        print(USAGE, file=sys.stderr)
        return 2
    base = arguments[0] if arguments else "main"
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    try:
        found = inputs_changed(root, base)
    except (subprocess.CalledProcessError, OSError) as error:
        print(f"release archive check: runs, as git could not say what the change touches ({error})")
        return RUN
    if found is None:
        print(f"release archive check: runs, as there is no {base} to compare with")
        return RUN
    if not found:
        print(f"release archive check: skipped, the change since {base} touches none of its inputs "
              "(ios/project.yml, ios/Config/, the Swift files of the types that it looks for, the check itself)")
        return SKIP
    shown = ", ".join(found[:5]) + (f" and {len(found) - 5} more" if len(found) > 5 else "")
    print(f"release archive check: runs, as the change since {base} touches {shown}")
    return RUN


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
