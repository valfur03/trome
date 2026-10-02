#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

USAGE = "Usage: app-name-sync.py <xcconfig with APP_NAME> <InfoPlist String Catalog>"
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


def main():
    if len(sys.argv) != 3:
        sys.exit(USAGE)
    xcconfig_path, catalog_path = sys.argv[1:]
    new_name = app_name(xcconfig_path)
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
