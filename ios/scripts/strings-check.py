#!/usr/bin/env python3
import json
import sys
from pathlib import Path

LANGUAGES = ["fr"]

USAGE = "Usage: strings-check.py <String Catalog...>"


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


def check_catalog(catalog_path):
    catalog = Path(catalog_path)
    name = f"{catalog.parent.name}/{catalog.name}"
    problems = []
    for key, entry in sorted(load_json(catalog)["strings"].items()):
        if entry.get("extractionState") == "stale":
            problems.append(f"{name}: \"{key}\" is no longer in the code; remove it")
            continue
        for language in untranslated_languages(entry):
            problems.append(f"{name}: no {language} text marked \"translated\" for \"{key}\"")
    return problems


def main():
    if len(sys.argv) < 2:
        sys.exit(USAGE)
    problems = [problem for path in sys.argv[1:] for problem in check_catalog(path)]
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
