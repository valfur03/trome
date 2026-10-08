#!/usr/bin/env python3
import os
import re
import sys
from typing import NamedTuple

from markdown_prose import MARKDOWN_SUFFIXES, lines_outside_code_blocks
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
    ("an old name of a build setting or of a variable of the tools", re.compile(
        r"RATP_(?:BUNDLE_ID_PREFIX|DEBUG_APP_BUNDLE_ID|DEBUG_WIDGET_BUNDLE_ID|WANTED_|REFUSED_ID|SHARED_CACHE"
        r"|WIDGET_HOST_WAIT_SECONDS|SPRINGBOARD_WAIT_SECONDS|MERGE_CHECK|MERGE_E2E)", re.IGNORECASE)),
    ("the old folder of the shared build cache", re.compile(r"Caches/RATPActivity", re.IGNORECASE)),
    ("an old key of the docs site", re.compile(r"ratp-docs-checklist", re.IGNORECASE)),
]
INTERNAL_RULES = [
    ("a backlog id", re.compile(r"\b(?:task|decision|doc)-\d+\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"\bprompters?\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"(?<![\w-])factory(?![\w-])", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"\bthe manager\b", re.IGNORECASE)),
    ("a word of the team's own process", re.compile(r"(?<![\w-])(?<!user )agents?(?![\w-])", re.IGNORECASE)),
]
# The voice of one person: one person makes TROME, so a page says "I" ("je" in French), never a team's "we" or "nous",
# which pretend a company that does not exist. It applies to the prose of the Markdown and MDX files only: a code word
# such as a variable or a path is not a voice. Lowercase or capitalised only, so "US" (the country) is not a hit.
# A word followed by a hyphen is part of a name ("Notre-Dame", a station), except "nous-même(s)"; a word after a hyphen
# is a hit, for "contactez-nous".
VOICE_REASON = "a word of a team's voice (one person speaks: say I, or je in French)"
VOICE_RULE = re.compile(
    r"(?<!\w)(?:[Ww]e|[Uu]s|[Oo]urs?|[Oo]urselves|[Ll]et['’]s|[Nn]ous|[Nn]otre|[Nn]os|[Nn]ôtres?)(?![\w-])"
    r"|(?<!\w)[Nn]ous-mêmes?(?![\w-])")
# What a page shows but does not say in its own voice: inline code, the import line of an MDX file, the target of a
# link (a Markdown link, an href or a src) or a bare address, and a quotation in double or curly quotes ("we", “we”,
# ‘Our Title’, « nous »). A straight single quote is also an apostrophe, so it does not mark a quotation. The value of
# another attribute (alt="...") is the page's own text, so its quotes are taken off before the quotations; the double
# quotes of the front matter are YAML syntax, not a quotation.
INLINE_CODE = re.compile(r"(`+).+?\1")
MDX_IMPORT = re.compile(r"^import\s.*\sfrom\s")
ADDRESS = re.compile(r"\]\([^)]*\)|<?https?://[^\s>)]+>?|\b(?:href|src)=(?:\"[^\"]*\"|'[^']*'|\{[^}]*\})")
ATTRIBUTE_VALUE = re.compile(r"=\"([^\"]*)\"")
QUOTATION = re.compile(r"\"[^\"]*\"|“[^”]*”|‘[^’]*’|«[^»]*»")
EXAMPLE_EMAIL = re.compile(r"@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|[\w-]+\.(?:example|test|invalid))$",
                           re.IGNORECASE)
# The public contact address of the project, on its own domain: the Help page, the privacy policy and the store text give it to every reader.
# No other real email address passes.
PUBLIC_CONTACT_EMAIL = "contact@trome.valfur.fr"
NOT_AN_EMAIL = re.compile(r"^git@|@\d+x\.", re.IGNORECASE)

INTERNAL_FILES = {
    "CLAUDE.md": "the manual of Claude Code may cite the private task list",
    ".claude/": "the manual of Claude Code may cite the private task list",
}
SKIPPED_FILES = {
    "ios/scripts/public-text-check.py": "it holds the word list of this check",
    "ios/scripts/tests/public-text-check-test.sh": "it holds the examples that this check must find",
    "server/worker-configuration.d.ts": "wrangler types generates it from the runtime types of Cloudflare, so its words are Cloudflare's",
}
OLD_PROJECT_NAME_REASON = ("a build or a project of the old name can still be on a Mac or on the shared Simulator, "
                           "so this file must name it to remove it")
OLD_SETTING_NAMES = ("RATP_BUNDLE_ID_PREFIX", "RATP_DEBUG_APP_BUNDLE_ID", "RATP_DEBUG_WIDGET_BUNDLE_ID")
OLD_SETTING_NAMES_TEST_REASON = "it checks that an old setting name in Local.xcconfig stops the build with its sentence"
OLD_SETTING_NAMES_REFUSAL = {
    "ios/scripts/old-setting-names.sh": "a Local.xcconfig made before the settings were called TROME_ can still set an old name: "
                                        "this script refuses it in make, the git hooks and Xcode, and says the new name",
    "ios/project.yml": "it reads the old setting names to refuse every Debug ID when one is set, also in a build from Xcode",
    "ios/scripts/tests/old-setting-names-test.sh": OLD_SETTING_NAMES_TEST_REASON,
    "ios/scripts/tests/bundle-id-check-test.sh": OLD_SETTING_NAMES_TEST_REASON,
    "ios/scripts/tests/git-hooks-test.sh": OLD_SETTING_NAMES_TEST_REASON,
}
ALLOWED_TEXTS: list[Allowed] = [
    Allowed("ios/Makefile", "RATPActivity", OLD_PROJECT_NAME_REASON),
    Allowed("ios/scripts/simulator.sh", "RATPActivity", OLD_PROJECT_NAME_REASON),
    Allowed("ios/scripts/tests/sim-lock-test.sh", "RATPActivity", "it checks that the Simulator script removes the apps of the old name"),
    Allowed("ios/scripts/tests/claude-rules-test.sh", "Agent", "the name of the tool of Claude Code that starts a subagent"),
    *(Allowed(path, name, reason) for path, reason in OLD_SETTING_NAMES_REFUSAL.items() for name in OLD_SETTING_NAMES),
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
    content = data.decode("utf-8", errors="replace")
    rules = PERSONAL_RULES if matching(path, INTERNAL_FILES) else PERSONAL_RULES + INTERNAL_RULES
    for number, line in enumerate(content.split("\n"), start=1):
        for reason, pattern in rules:
            for found in pattern.finditer(line):
                text = found.group(0)
                if reason == "an email address" and (
                        EXAMPLE_EMAIL.search(text) or NOT_AN_EMAIL.search(text) or text == PUBLIC_CONTACT_EMAIL):
                    continue
                if not is_allowed(path, text):
                    yield number, reason, text
    if path.endswith(MARKDOWN_SUFFIXES):
        yield from voice_hits(path, content)


def voice_hits(path, content):
    front_matter = content.startswith("---\n")
    for number, line in lines_outside_code_blocks(content):
        if front_matter and number > 1 and line.strip() == "---":
            front_matter = False
            continue
        if path.endswith(".mdx") and MDX_IMPORT.match(line):
            continue
        prose = ADDRESS.sub(" ", INLINE_CODE.sub(" ", line))
        if not front_matter:
            prose = QUOTATION.sub(" ", ATTRIBUTE_VALUE.sub(r"= \1 ", prose))
        for found in VOICE_RULE.finditer(prose):
            if not is_allowed(path, found.group(0)):
                yield number, VOICE_REASON, found.group(0)


def describe_exceptions(paths):
    for listing, what in ((INTERNAL_FILES, "checks only personal data, local paths and the old app name in"), (SKIPPED_FILES, "skips")):
        for prefix, reason in listing.items():
            if any(matching(path, [prefix]) for path in paths):
                print(f"public-text-check: {what} {prefix}: {reason}")


def main(arguments):
    if arguments:
        sys.exit(USAGE)
    root, paths = repo_files("public-text-check")
    checked = [path for path in paths if not matching(path, SKIPPED_FILES)]
    failures = [(path, number, reason, text) for path in checked for number, reason, text in hits(root, path)]
    if failures or os.environ.get("VERBOSE") == "1":
        describe_exceptions(paths)
    sys.stdout.flush()
    for path, number, reason, text in failures:
        print(f"public-text-check: {path}:{number}: {reason}: \"{text}\"", file=sys.stderr)
    if failures:
        print(
            "public-text-check: FAILED. The files of this repo are public: write the rule and its reason instead.\n"
            "No backlog id and no word of the team's own process (the backlog is private, and a stranger cannot read it),\n"
            "no email address other than an example one, no local path, and not the old names of the app, of the Xcode project or of its module (it is TROME),\n"
            "nor the old RATP_ names of the build settings and of the variables of the tools, the old build cache folder or the old key of the docs site (they use TROME now).\n"
            "One person makes TROME: the prose of a Markdown or MDX file says I (je in French), never we, us, our, nous, notre or nos;\n"
            "code, link addresses and text in double or curly quotes are not checked, so put a quoted word in double quotes.\n"
            "CLAUDE.md and .claude/ may cite the backlog.\n"
            "When a hit is a normal word in its place, add it to ALLOWED_TEXTS in ios/scripts/public-text-check.py,\n"
            "with its reason (CLAUDE.md, rule \"Public text\").",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"public-text-check: OK ({len(checked)} files: no backlog id, no word of the team's own process, "
          "no personal email address, no local path, no old name of the app, of the project, of its module, of a setting or of a tool, "
          "no team's voice in the prose)")


main(sys.argv[1:])
