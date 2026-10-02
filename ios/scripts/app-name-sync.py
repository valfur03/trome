#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

USAGE = "Usage: app-name-sync.py [--check] <xcconfig with APP_NAME> <InfoPlist String Catalog>"
VALUE_LINE = re.compile(r'^(\s*"value" : )(".*")(,?)$')


def app_name(xcconfig_path):
    with open(xcconfig_path, encoding="utf-8") as file:
        for line in file:
            match = re.match(r"^APP_NAME\s*=\s*(.+?)\s*$", line)
            if match:
                return match.group(1)
    sys.exit(f"app-name-sync: {xcconfig_path} has no APP_NAME")


def catalog_name(catalog):
    try:
        return catalog["strings"]["CFBundleDisplayName"]["localizations"]["en"]["stringUnit"]["value"]
    except KeyError:
        return None


def committed_catalog(catalog_path):
    path = Path(catalog_path).resolve()
    try:
        text = subprocess.run(["git", "show", f"HEAD:./{path.name}"], cwd=path.parent,
                              capture_output=True, text=True, check=True).stdout
        return json.loads(text)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return {}


def renamed_line(line, old_names, new_name):
    match = VALUE_LINE.match(line)
    if not match:
        return line
    value = json.loads(match.group(2))
    for old_name in old_names:
        value = re.sub(rf"(?<!\w){re.escape(old_name)}(?!\w)", new_name, value)
    return f"{match.group(1)}{json.dumps(value, ensure_ascii=False)}{match.group(3)}"


def says_name(value, name):
    return re.search(rf"(?<!\w){re.escape(name)}(?!\w)", value) is not None


def missing_names(catalog, name):
    for key, entry in sorted(catalog["strings"].items()):
        localizations = entry.get("localizations", {})
        english = localizations.get("en", {}).get("stringUnit", {}).get("value", "")
        if not says_name(english, name):
            continue
        for language, localization in sorted(localizations.items()):
            value = localization.get("stringUnit", {}).get("value", "")
            if language != "en" and not says_name(value, name):
                yield f"{key} ({language}): \"{value}\""


def check(catalog_path, name):
    with open(catalog_path, encoding="utf-8") as file:
        problems = list(missing_names(json.load(file), name))
    for problem in problems:
        print(f"app-name-sync: {catalog_path}: {problem} does not say {name}", file=sys.stderr)
    if problems:
        sys.exit(f"app-name-sync: FAILED. The English text says {name} (APP_NAME), and this translation does not: "
                 f"put {name} in place of the old name by hand.")


def main():
    arguments = sys.argv[1:]
    checking = arguments[:1] == ["--check"]
    if checking:
        arguments = arguments[1:]
    if len(arguments) != 2:
        sys.exit(USAGE)
    xcconfig_path, catalog_path = arguments
    new_name = app_name(xcconfig_path)
    if checking:
        check(catalog_path, new_name)
        return
    with open(catalog_path, encoding="utf-8") as file:
        text = file.read()
    names = [catalog_name(json.loads(text)), catalog_name(committed_catalog(catalog_path))]
    old_names = sorted({name for name in names if name and name != new_name}, key=len, reverse=True)
    if not old_names:
        return
    renamed = "\n".join(renamed_line(line, old_names, new_name) for line in text.split("\n"))
    if renamed == text:
        return
    with open(catalog_path, "w", encoding="utf-8") as file:
        file.write(renamed)
    print(f"app-name-sync: {catalog_path}: {', '.join(old_names)} -> {new_name}")


if __name__ == "__main__":
    main()
