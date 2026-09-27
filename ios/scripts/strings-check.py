#!/usr/bin/env python3
import json
import plistlib
import sys
from pathlib import Path

LANGUAGES = ["fr"]

USAGE = """Usage: strings-check.py code <Localizable.xcstrings> <stringsdata file...>
       strings-check.py info-plist <InfoPlist.xcstrings> <Info.plist>"""


def load_json(path):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, json.JSONDecodeError) as error:
        sys.exit(f"strings-check: could not read {path}: {error}")


def string_units(localization):
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for cases in localization.get("variations", {}).values():
        for case in cases.values():
            yield from string_units(case)


def untranslated_languages(entry):
    if entry.get("shouldTranslate") is False:
        return []
    localizations = entry.get("localizations", {})
    missing = []
    for language in LANGUAGES:
        units = list(string_units(localizations.get(language, {})))
        if not units or any(unit.get("state") != "translated" or not unit.get("value") for unit in units):
            missing.append(language)
    return missing


def translation_problems(strings, name):
    problems = []
    for key, entry in sorted(strings.items()):
        for language in untranslated_languages(entry):
            problems.append(f"{name}: no {language} translation for \"{key}\"")
    return problems


def used_keys(table, stringsdata_paths):
    keys = {}
    for path in stringsdata_paths:
        data = load_json(path)
        source = Path(data.get("source", ""))
        if source.suffix != ".swift" or not source.is_file():
            continue
        for item in data.get("tables", {}).get(table, []):
            keys.setdefault(item["key"], source.name)
    return keys


def check_code(catalog_path, stringsdata_paths):
    catalog = Path(catalog_path)
    strings = load_json(catalog)["strings"]
    used = used_keys(catalog.stem, stringsdata_paths)
    name = f"{catalog.parent.name}/{catalog.name}"
    problems = []
    for key, source in sorted(used.items()):
        if key not in strings:
            problems.append(f"{name}: \"{key}\" ({source}) is not in the catalog")
    for key, entry in sorted(strings.items()):
        if key not in used and entry.get("extractionState") != "manual":
            problems.append(f"{name}: \"{key}\" is no longer in the code; remove it")
    return problems + translation_problems({key: strings[key] for key in strings if key in used}, name)


def check_info_plist(catalog_path, plist_path):
    catalog = Path(catalog_path)
    strings = load_json(catalog)["strings"]
    try:
        with open(plist_path, "rb") as file:
            info = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException) as error:
        sys.exit(f"strings-check: could not read {plist_path}: {error}")
    name = f"{catalog.parent.name}/{catalog.name}"
    problems = []
    for key in sorted(k for k in info if k.endswith("UsageDescription")):
        if key not in strings:
            problems.append(f"{name}: {key} is not in the catalog")
            continue
        english = next(string_units(strings[key].get("localizations", {}).get("en", {})), {}).get("value")
        if english != info[key]:
            problems.append(f"{name}: the English text of {key} is not the one of the Info.plist")
    for key in sorted(strings):
        if key not in info:
            problems.append(f"{name}: {key} is not in the Info.plist; remove it")
    return problems + translation_problems({key: strings[key] for key in strings if key in info}, name)


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("code", "info-plist"):
        sys.exit(USAGE)
    if sys.argv[1] == "code":
        problems = check_code(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) == 4:
        problems = check_info_plist(sys.argv[2], sys.argv[3])
    else:
        sys.exit(USAGE)
    for problem in problems:
        print(problem)
    if problems:
        print(
            "Each text that a user sees needs its French text in the String Catalog (README, section \"Languages\").",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
