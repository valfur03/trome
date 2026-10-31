#!/usr/bin/env python3
"""Runs the unit tests of the changed test files in the two paces of a busy Mac, to catch a test that passes only on a
quiet one.

A test that waits for one thing and then checks another passes only while the code under test catches up during the
pause of the wait: a quiet Mac gives it that time, and a busy Mac does not, so it fails later, on another machine.
The waits of the unit tests (waitUntil, in the tests of TROMECore) read their pace from TROME_TEST_WAITS:
"eager" looks again after a bare yield, as when the code under test runs late, and "late" looks again after 50 ms,
as when the test itself runs late. A race shows in some runs only, so each pace runs a few times.

  filter [<base>]  Print the --filter of swift test for the tests of the test files changed since <base> (main by
                   default), with the changes not committed yet; "all" when a changed test file holds no test (a fake
                   or a helper, which any test may use); nothing when no test file changed.
  run [<base>]     Run them, REPEATS times in each pace (3 by default); ALL=1 runs every unit test. Each run keeps its
                   whole output in .build/logs/test-waits-<pace>-<n>.log, and a failure prints its issues.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

TESTS = "ios/Packages/TROMECore/Tests/"
PACKAGE = "Packages/TROMECore"
SCRATCH = ".build/TROMECore"
LOGS = Path(".build/logs")
PACES = ("eager", "late")
USAGE = "Usage: test-waits.py filter|run [<base branch, main by default>]"

TYPE = re.compile(
    r"^(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|final)\s+)*(?:struct|class|enum|actor|extension)"
    r"\s+(\w+)",
    re.MULTILINE,
)
TEST = re.compile(r"@Test\b")
FUNC = re.compile(r"\bfunc\s+(\w+)")
RAN = re.compile(r"Test run with (\d+) tests? ")


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, text=True, check=True).stdout


def changed_test_files(root: Path, base: str) -> Optional[List[str]]:
    """The test files changed since base, committed or not, that still exist; None with no base to compare with."""
    start = None
    for ref in (base, f"origin/{base}"):
        try:
            start = git(root, "merge-base", "HEAD", ref).strip()
            break
        except subprocess.CalledProcessError:
            continue
    if start is None:
        return None
    paths = git(root, "diff", "--name-only", "--no-renames", start).split("\n")
    paths += git(root, "ls-files", "--others", "--exclude-standard", "--", TESTS).split("\n")
    return sorted({path for path in paths if path.startswith(TESTS) and path.endswith(".swift") and (root / path).is_file()})


def tests_in(text: str) -> List[str]:
    """The ids of the tests of a file, as "<type>/<function>", each under the last type declared above it."""
    types = [(match.start(), match.group(1)) for match in TYPE.finditer(text)]
    found = []
    for test in TEST.finditer(text):
        function = FUNC.search(text, test.end())
        owner = [name for start, name in types if start < test.start()]
        if function and owner:
            found.append(f"{owner[-1]}/{function.group(1)}")
    return found


def test_filter(root: Path, base: str) -> str:
    files = changed_test_files(root, base)
    if files is None:
        return "all"
    if not files:
        return ""
    ids: List[str] = []
    for path in files:
        tests = tests_in((root / path).read_text(encoding="utf-8"))
        if not tests:
            return "all"
        ids += tests
    return "|".join(rf"\.{test}\(" for test in sorted(set(ids)))


def issues(log: Path) -> List[str]:
    lines = log.read_text(encoding="utf-8", errors="replace").split("\n")
    shown = []
    for index, line in enumerate(lines):
        if "recorded an issue" in line or "error:" in line:
            shown.append(line)
            shown += [detail for detail in lines[index + 1:index + 4] if detail.startswith("↳")]
    return shown or lines[-20:]


def run(root: Path, base: str) -> int:
    chosen = "all" if os.environ.get("ALL") == "1" else test_filter(root, base)
    if not chosen:
        print(f"test-waits: OK, no unit test file changed since {base}")
        return 0
    repeats = int(os.environ.get("REPEATS", "3"))
    command = ["swift", "test", "--package-path", PACKAGE, "--scratch-path", SCRATCH, "-Xswiftc", "-warnings-as-errors"]
    if chosen != "all":
        command += ["--filter", chosen]
    expected = 0 if chosen == "all" else chosen.count("|") + 1
    what = "every unit test" if chosen == "all" else f"{expected} tests of the changed test files"
    LOGS.mkdir(parents=True, exist_ok=True)
    for pace in PACES:
        for number in range(1, repeats + 1):
            log = LOGS / f"test-waits-{pace}-{number}.log"
            with log.open("w") as output:
                status = subprocess.run(
                    command, stdout=output, stderr=subprocess.STDOUT, env={**os.environ, "TROME_TEST_WAITS": pace}
                ).returncode
            if status != 0:
                print("\n".join(issues(log)))
                print(
                    f"test-waits: FAILED in the {pace} pace (run {number} of {repeats}). If the test passes in make "
                    "test, it waits for one thing and checks another, so it passes only on a quiet Mac: wait for the "
                    f"state that the check reads (ios/guide/tests.md). Whole output: ios/{log}; replay it with "
                    f"TROME_TEST_WAITS={pace} swift test --filter <test>."
                )
                return 1
            ran = sum(int(count) for count in RAN.findall(log.read_text(encoding="utf-8", errors="replace")))
            if ran < expected:
                print(
                    f"test-waits: FAILED, the filter ran {ran} of the {expected} tests of the changed test files: "
                    f"test-waits.py did not read the name of a test or of its type. Whole output: ios/{log}."
                )
                return 1
    print(f"test-waits: OK, {what}, {repeats} runs in each pace ({', '.join(PACES)})")
    return 0


def main(arguments: List[str]) -> int:
    if not arguments or arguments[0] not in ("filter", "run") or len(arguments) > 2:
        print(USAGE, file=sys.stderr)
        return 2
    base = arguments[1] if len(arguments) == 2 else "main"
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    if arguments[0] == "filter":
        chosen = test_filter(root, base)
        if chosen:
            print(chosen)
        return 0
    return run(root, base)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
