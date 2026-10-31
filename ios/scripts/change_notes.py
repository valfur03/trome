"""The notes of the changes of the app, in ios/changes/: their format, read by change-notes-check.py and release-notes.py.

ios/changes/README.md tells a person how to write a note; this module is the one place that reads one.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

NOTES = "ios/changes/"
README = NOTES + "README.md"
LANGUAGES = {"fr": "French", "en": "English"}
# Each kind with the languages that it needs. Builders read the repo in English, so a builder note has English only.
KINDS: Dict[str, Tuple[str, ...]] = {"headline": ("fr", "en"), "item": ("fr", "en"), "apple": ("fr", "en"), "builder": ("en",)}
# A headline fits in 2 lines on the card of an iPhone's width, so that the French one leaves room for an item before
# the store cuts the text with "more" (about 3 lines).
HEADLINE_LIMIT = 100
FIELD = re.compile(r"^(kind|fr|en):(.*)$")


def read_note(text: str) -> Tuple[Dict[str, str], List[str]]:
    """The fields of a note ('kind', 'fr', 'en'), and the problems of its lines."""
    fields: Dict[str, str] = {}
    problems: List[str] = []
    last: Optional[str] = None
    for line in text.split("\n"):
        line = line.rstrip("\r")
        if not line.strip():
            continue
        match = FIELD.match(line)
        if match is None:
            if last in LANGUAGES:
                problem = f"the {LANGUAGES[last]} line goes on over more than one line: write one line per language"
            else:
                problem = f"a line that is not 'kind:', 'fr:' or 'en:': \"{line.strip()[:40]}\""
            if problem not in problems:
                problems.append(problem)
            continue
        key, value = match.group(1), match.group(2).strip()
        if key in fields:
            problems.append(f"two '{key}:' lines: write one line per language")
        fields[key] = value
        last = key
    return fields, problems


def note_problems(path: str, text: str) -> List[str]:
    """The reasons why the note at path is refused, or an empty list."""
    if not path.endswith(".txt"):
        return ["a note is a .txt file (ios/changes/README.md shows one)"]
    fields, problems = read_note(text)
    kind = fields.get("kind", "")
    if not kind:
        return problems + ["no kind: start with 'kind: headline', 'kind: item', 'kind: apple' or 'kind: builder'"]
    if kind not in KINDS:
        return problems + [f"unknown kind '{kind}': write headline, item, apple or builder"]
    for language, name in LANGUAGES.items():
        if language in KINDS[kind] and not fields.get(language):
            problems.append(f"no {name} line: add '{language}: <one line in {name}>'")
        if language not in KINDS[kind] and language in fields:
            problems.append(f"a {kind} note is in English only: remove its '{language}:' line")
    if kind == "headline":
        for language, name in LANGUAGES.items():
            length = len(fields.get(language, ""))
            if length > HEADLINE_LIMIT:
                problems.append(
                    f"the {name} headline has {length} characters, more than {HEADLINE_LIMIT}: "
                    "a headline fits in 2 lines on the card of an iPhone's width")
    return problems
