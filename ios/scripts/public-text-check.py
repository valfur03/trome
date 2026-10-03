#!/usr/bin/env python3
import re
import sys
from typing import NamedTuple

from repo_files import repo_files


class Allowed(NamedTuple):
    path: str
    text: str
    reason: str


PERSONAL_RULES = [
    ("an email address", re.compile(r"[\w.%+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}\b")),
    ("a local path", re.compile(r"/Users/")),
    ("the old name of the app", re.compile(r"RATP(?:\s|&nbsp;)+Activit", re.IGNORECASE)),
    ("an old name of the project or of its module", re.compile(r"(?<!Caches/)RATP(?:Activity|Core)", re.IGNORECASE)),
]
INTERNAL_RULES = [
    ("a backlog id", re.compile(r"\b(?:task|decision|doc)-\d+\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"\bprompters?\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"(?<![\w-])factory(?![\w-])", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"\bthe manager\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"(?<![\w-])(?<!user )agents?(?![\w-])", re.IGNORECASE)),
]
EXAMPLE_EMAIL = re.compile(r"@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|[\w-]+\.(?:example|test|invalid))$",
                           re.IGNORECASE)
NOT_AN_EMAIL = re.compile(r"^git@|@\d+x\.", re.IGNORECASE)

INTERNAL_FILES = {
    "CLAUDE.md": "the manual of Claude Code may cite the private task list",
    ".claude/": "the manual of Claude Code may cite the private task list",
    # The feature sections of the developer text that moved out of the front page still cite the backlog.
    # The rewrite that moves the last of them to ios/guide/ removes this line.
    "ios/README.md": "until its rewrite for developers: its feature sections still cite the backlog",
}
SKIPPED_FILES = {
    "ios/scripts/public-text-check.py": "it holds the word list of this check",
    "ios/scripts/tests/public-text-check-test.sh": "it holds the examples that this check must find",
    "server/worker-configuration.d.ts": "wrangler types generates it from the runtime types of Cloudflare, so its words are Cloudflare's",
}
OLD_PROJECT_NAME_REASON = ("a build or a project of the old name can still be on a Mac or on the shared Simulator, "
                           "so this file must name it to remove it")
ALLOWED_TEXTS: list[Allowed] = [
    Allowed("ios/Makefile", "RATPActivity", OLD_PROJECT_NAME_REASON),
    Allowed("ios/scripts/simulator.sh", "RATPActivity", OLD_PROJECT_NAME_REASON),
    Allowed("ios/scripts/tests/sim-lock-test.sh", "RATPActivity", "it checks that the Simulator script removes the apps of the old name"),
]

USAGE = "Usage: public-text-check.py (it checks every file of the repo)"


def matching(path, prefixes):
    return next((prefix for prefix in prefixes if path == prefix or prefix.endswith("/") and path.startswith(prefix)),
                None)


def is_allowed(path, text):
    return any(path == allowed.path and text == allowed.text for allowed in ALLOWED_TEXTS)


def hits(root, path):
    try:
        data = (root / path).read_bytes()
    except OSError as error:
        sys.exit(f"public-text-check: could not read {path}: {error}")
    if b"\0" in data:
        return
    rules = PERSONAL_RULES if matching(path, INTERNAL_FILES) else PERSONAL_RULES + INTERNAL_RULES
    for number, line in enumerate(data.decode("utf-8", errors="replace").split("\n"), start=1):
        for reason, pattern in rules:
            for found in pattern.finditer(line):
                text = found.group(0)
                if reason == "an email address" and (EXAMPLE_EMAIL.search(text) or NOT_AN_EMAIL.search(text)):
                    continue
                if not is_allowed(path, text):
                    yield number, reason, text


def describe_exceptions(paths):
    for listing, what in ((INTERNAL_FILES, "checks only personal data, local paths and the old app name in"), (SKIPPED_FILES, "skips")):
        for prefix, reason in listing.items():
            if any(matching(path, [prefix]) for path in paths):
                print(f"public-text-check: {what} {prefix}: {reason}")


def main(arguments):
    if arguments:
        sys.exit(USAGE)
    root, paths = repo_files("public-text-check")
    describe_exceptions(paths)
    checked = [path for path in paths if not matching(path, SKIPPED_FILES)]
    failures = [(path, number, reason, text) for path in checked for number, reason, text in hits(root, path)]
    sys.stdout.flush()
    for path, number, reason, text in failures:
        print(f"public-text-check: {path}:{number}: {reason}: \"{text}\"", file=sys.stderr)
    if failures:
        print(
            "public-text-check: FAILED. The files of this repo are public: write the rule and its reason instead.\n"
            "No backlog id and no word of the team's own process (the backlog is private, and a stranger cannot read it),\n"
            "no email address other than an example one, no local path, and not the old names of the app, of the Xcode project or of its module (it is TROME).\n"
            "CLAUDE.md and .claude/ may cite the backlog.\n"
            "When a hit is a normal word in its place, add it to ALLOWED_TEXTS in ios/scripts/public-text-check.py,\n"
            "with its reason (CLAUDE.md, section \"The docs site\", rule \"Public text\").",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"public-text-check: OK ({len(checked)} files: no backlog id, no word of the team's own process, "
          "no personal email address, no local path, no old name of the app, of the project or of its module)")


main(sys.argv[1:])
