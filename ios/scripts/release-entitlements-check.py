#!/usr/bin/env python3
"""Proves that a Release build carries the silent start: the push capability and the app group that the app shares
with its widget.

With no push capability, the store build cannot get a start token, so the Live Activity never starts by itself.
With no app group on both, the widget shows the first page after each push of the server, not the page that the
rider tapped to.
It reads what Xcode signs a Release build with (the entitlements file of each target, with its build settings), so it
needs no team and no Apple account.
With an archive (make release-archive-check), it also checks the archive: the group that the app and its widget read
in their Info.plist, and the push code compiled into the app.
It prints no build setting but the name of the app group, which ios/project.yml shows: the release checks run on
GitHub, where the logs are public.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

USAGE = "Usage: release-entitlements-check.py <TROME.xcodeproj> [<TROME.xcarchive>]"

APP = "TROME"
WIDGET = "TROMEWidget"
PUSH = "aps-environment"
GROUPS = "com.apple.security.application-groups"
GROUP_KEY = "TROMEAppGroup"
# A type that exists only in a build with the silent start (ios/App/AutoLiveActivity/, inside #if SILENT_START).
SILENT_START_TYPE = b"ActivityKitPushToStartTokenSource"


def release_settings(project, target):
    xcodebuild = os.environ.get("XCODEBUILD", "xcodebuild")
    result = subprocess.run(
        [xcodebuild, "-project", project, "-target", target, "-configuration", "Release", "-sdk", "iphoneos",
         "-showBuildSettings", "-json"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"xcodebuild could not read the Release settings of {target} (exit {result.returncode})")
    for entry in json.loads(result.stdout):
        if entry.get("target") == target:
            return entry["buildSettings"]
    raise ValueError(f"xcodebuild gave no Release settings for {target}")


def expanded(value, settings):
    return re.sub(r"\$[({](\w+)[)}]", lambda match: settings.get(match.group(1), ""), value)


def entitlements(settings, target):
    name = settings.get("CODE_SIGN_ENTITLEMENTS", "")
    if not name:
        raise ValueError(f"the Release build of {target} has no entitlements file (CODE_SIGN_ENTITLEMENTS)")
    path = Path(settings.get("SRCROOT", ".")) / name
    try:
        with path.open("rb") as file:
            values = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f"the entitlements file of {target} ({name}) cannot be read: {error}") from error
    groups = [expanded(group, settings) for group in values.get(GROUPS, [])]
    return values, groups


def problems_of_the_project(project):
    app = release_settings(project, APP)
    group = f"group.{app.get('APP_BUNDLE_ID', '')}"
    app_values, app_groups = entitlements(app, APP)
    problems = []
    if PUSH not in app_values:
        problems.append(f"the Release entitlements of {APP} have no push capability ({PUSH})")
    if group not in app_groups:
        problems.append(f"the Release entitlements of {APP} do not name the app group {group}")
    _, widget_groups = entitlements(release_settings(project, WIDGET), WIDGET)
    if group not in widget_groups:
        problems.append(f"the Release entitlements of {WIDGET} do not name the app group {group}")
    return group, problems


def problems_of_the_archive(archive, group):
    app = Path(archive) / "Products" / "Applications" / f"{APP}.app"
    problems = []
    for name, bundle in ((APP, app), (WIDGET, app / "PlugIns" / f"{WIDGET}.appex")):
        try:
            with (bundle / "Info.plist").open("rb") as file:
                read = plistlib.load(file).get(GROUP_KEY)
        except (OSError, plistlib.InvalidFileException):
            read = None
        if read != group:
            problems.append(f"in the archive, {name} does not read the app group {group} ({GROUP_KEY} of its Info.plist)")
    try:
        binary = (app / APP).read_bytes()
    except OSError:
        binary = b""
    if SILENT_START_TYPE not in binary:
        problems.append(f"in the archive, {APP} has no silent start (no {SILENT_START_TYPE.decode()}): "
                        "the Release build must compile SILENT_START")
    return problems


def main(arguments):
    if len(arguments) not in (1, 2):
        print(USAGE, file=sys.stderr)
        return 2
    try:
        group, problems = problems_of_the_project(arguments[0])
    except ValueError as error:
        print(f"release-entitlements-check: FAILED: {error}", file=sys.stderr)
        return 1
    if len(arguments) == 2:
        problems += problems_of_the_archive(arguments[1], group)
    for problem in problems:
        print(f"release-entitlements-check: FAILED: {problem}", file=sys.stderr)
    if problems:
        return 1
    scope = "the archive and the project" if len(arguments) == 2 else "the project"
    print(f"release-entitlements-check: OK (in {scope}, the Release app has the push capability, "
          "and the app and its widget share their app group)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
