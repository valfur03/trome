#!/usr/bin/env python3
import sys

from markdown_prose import lines_outside_code_blocks
from repo_files import repo_files

MAX_LENGTH = 400
PATTERNS = ["*.md", "*.mdx"]

USAGE = "Usage: prose-check.py [Markdown file...] (no file: every Markdown and MDX file of the repo)"


def long_lines(path):
    try:
        with open(path, encoding="utf-8") as file:
            text = file.read()
    except OSError as error:
        sys.exit(f"prose-check: could not read {path}: {error}")
    for number, line in lines_outside_code_blocks(text):
        if line.lstrip().startswith("|"):
            continue
        if len(line) > MAX_LENGTH:
            yield number, len(line)


def files_to_check(arguments):
    if arguments:
        return [(path, path) for path in arguments]
    root, paths = repo_files("prose-check", PATTERNS)
    return [(path, root / path) for path in paths]


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
            "(CLAUDE.md, rule \"One sentence per line\").",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"prose-check: OK ({len(files)} files, no line of prose longer than {MAX_LENGTH} characters)")


main(sys.argv[1:])
