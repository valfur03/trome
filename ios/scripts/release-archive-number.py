#!/usr/bin/env python3
"""Proves that the signed archive of the release workflow is the version of the repo and the build number of the run,
in the app and in each of its extensions (the widget): Apple refuses an upload whose widget differs from its app.

It reads only CFBundleShortVersionString and CFBundleVersion of each Info.plist, and prints only those two values,
which every build shows to its riders: the Info.plist of the store build also holds the server and its token, and the
logs of the run are public.
"""
import plistlib
import sys
from pathlib import Path
from typing import List

USAGE = "Usage: release-archive-number.py <TROME.xcarchive> <version> <build number>"
KEYS = ("CFBundleShortVersionString", "CFBundleVersion")


def bundles(archive: Path) -> List[Path]:
    apps = sorted((archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError(f"the archive has {len(apps)} apps in Products/Applications, not one")
    return [apps[0]] + sorted((apps[0] / "PlugIns").glob("*.appex"))


def problems(archive: Path, version: str, build: str) -> List[str]:
    found = []
    for bundle in bundles(archive):
        with open(bundle / "Info.plist", "rb") as file:
            info = plistlib.load(file)
        for key, wanted in zip(KEYS, (version, build)):
            value = info.get(key)
            if value != wanted:
                found.append(f"{bundle.name} has {key} {value!r}, not {wanted!r}")
    return found


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    archive, version, build = Path(argv[0]), argv[1], argv[2]
    try:
        found = problems(archive, version, build)
        names = ", ".join(bundle.name for bundle in bundles(archive))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"release-archive-number: FAILED: {error}", file=sys.stderr)
        return 1
    if found:
        for problem in found:
            print(f"release-archive-number: FAILED: {problem}", file=sys.stderr)
        return 1
    print(f"release-archive-number: OK ({names}: version {version}, build {build})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
