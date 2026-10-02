#!/usr/bin/env python3
import re
import sys

from repo_files import repo_files

MAX_LENGTH = 400
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
PATTERNS = ["*.md", "*.mdx"]
SKIPPED = {
    "CLAUDE.md": "it is split into short files by topic next, and that move writes it one sentence per line;"
                 " a reflow now would conflict with every change that edits it in the meantime",
}

USAGE = "Usage: prose-check.py [Markdown file...] (no file: every Markdown and MDX file of the repo)"


def long_lines(path):
    try:
        with open(path, encoding="utf-8") as file:
            lines = file.read().split("\n")
    except OSError as error:
        sys.exit(f"prose-check: could not read {path}: {error}")
    fence = None
    for number, line in enumerate(lines, start=1):
        opening = FENCE.match(line)
        if fence:
            if opening and opening.group(1)[0] == fence[0] and len(opening.group(1)) >= len(fence) \
                    and not line[opening.end():].strip():
                fence = None
            continue
        if opening:
            fence = opening.group(1)
            continue
        if line.lstrip().startswith("|"):
            continue
        if len(line) > MAX_LENGTH:
            yield number, len(line)


def files_to_check(arguments):
    if arguments:
        return [(path, path) for path in arguments]
    root, paths = repo_files("prose-check", PATTERNS)
    for path, reason in SKIPPED.items():
        if path in paths:
            print(f"prose-check: skips {path}: {reason}", flush=True)
    return [(path, root / path) for path in paths if path not in SKIPPED]


def main(arguments):
    if any(argument.startswith("-") for argument in arguments):
        sys.exit(USAGE)
    files = files_to_check(arguments)
    failures = [(name, number, length) for name, path in files for number, length in long_lines(path)]
    for name, number, length in failures:
        print(f"prose-check: {name}:{number}: {length} characters, more than {MAX_LENGTH}", file=sys.stderr)
    if failures:
        print(
            "prose-check: FAILED. Write the prose of Markdown and MDX files with one sentence per line.\n"
            "When one sentence is still too long, break the line after a comma, a colon or a semicolon.\n"
            "Edit only the sentences that your change makes false, and never reflow a paragraph. Tables and code blocks may have long lines.\n"
            "Why: git merges by line. Two changes to two sentences of one long line conflict "
            "(CONTRIBUTING.md, section \"One sentence per line\").",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"prose-check: OK ({len(files)} files, no line of prose longer than {MAX_LENGTH} characters)")


main(sys.argv[1:])
