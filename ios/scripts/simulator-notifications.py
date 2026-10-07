#!/usr/bin/env python3
import plistlib
import re
import sys
from pathlib import Path

APP_SECTION = re.compile(r"\.trome\.dev(\.render-check-host)?$")


def usage():
    print(f"Usage: {sys.argv[0]} forget|remembered <Simulator data folder>", file=sys.stderr)
    print("       forget: removes the notification settings of the app (and of its test hosts) from the notification settings of the Simulator.", file=sys.stderr)
    print("               Restart SpringBoard after it: SpringBoard reads the file only when it starts.", file=sys.stderr)
    print("       remembered: prints the apps whose notification settings the Simulator still keeps, and fails when there is one.", file=sys.stderr)
    sys.exit(2)


def settings_file(data):
    return Path(data) / "Library" / "BulletinBoard" / "VersionedSectionInfo.plist"


def app_sections(settings):
    return sorted(section for section in settings.get("sectionInfo", {}) if APP_SECTION.search(section))


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("forget", "remembered"):
        usage()
    command, file = sys.argv[1], settings_file(sys.argv[2])
    if not file.exists():
        return
    content = file.read_bytes()
    settings = plistlib.loads(content)
    sections = app_sections(settings)
    if command == "remembered":
        if sections:
            print(" ".join(sections))
            sys.exit(1)
        return
    if not sections:
        return
    for section in sections:
        del settings["sectionInfo"][section]
    new_file = file.with_name(file.name + ".new")
    new_file.write_bytes(plistlib.dumps(settings, fmt=plistlib.FMT_BINARY if content.startswith(b"bplist") else plistlib.FMT_XML))
    new_file.replace(file)


if __name__ == "__main__":
    main()
