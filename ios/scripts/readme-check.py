#!/usr/bin/env python3
import re
import sys

MAX_LENGTH = 400
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")

USAGE = "Usage: readme-check.py <Markdown file...>"


def long_lines(path):
    try:
        with open(path, encoding="utf-8") as file:
            lines = file.read().split("\n")
    except OSError as error:
        sys.exit(f"readme-check: could not read {path}: {error}")
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


def main(paths):
    if not paths:
        sys.exit(USAGE)
    failures = [(path, number, length) for path in paths for number, length in long_lines(path)]
    for path, number, length in failures:
        print(f"readme-check: {path}:{number}: {length} characters, more than {MAX_LENGTH}", file=sys.stderr)
    if failures:
        print(
            "readme-check: FAILED. Write the prose of the README with one sentence per line.\n"
            "When one sentence is still too long, break the line after a comma, a colon or a semicolon.\n"
            "Edit only the sentences that your change makes false, and never reflow a paragraph. Tables and code blocks may have long lines.\n"
            "Why: git merges by line. Two tasks that change two sentences of one long line conflict "
            "(CLAUDE.md, section \"The README\").",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"readme-check: OK (no line of prose longer than {MAX_LENGTH} characters)")


main(sys.argv[1:])
