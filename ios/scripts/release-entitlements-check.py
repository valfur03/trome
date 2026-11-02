#!/usr/bin/env python3
"""Proves that a Release build carries the silent start: the push capability and the app group that the app shares
with its widget.

With no push capability, the store build cannot get a start token, so the Live Activity never starts by itself.
With no app group on both, the widget shows the first page after each push of the server, not the page that the
rider tapped to.
It reads what Xcode signs a Release build with (the entitlements file of each target, with its build settings), so it
needs no team and no Apple account.
With an archive (make release-archive-check), it also checks the archive: the group that the app and its widget read
in their Info.plist, and the push code compiled into the app, found by the whole name of its Swift type.
It also proves that the store build has no Wake log, the record of each wake for a walk: an archive has it only when
its Release settings compile it (TROME_WAKE_LOG_BUILD_<n> = YES for the build number n, a TestFlight build for a walk),
and then it must have it.
It prints no build setting but the name of the app group, which ios/project.yml shows: the release checks run on
GitHub, where the logs are public.
"""
import json
import os
import plistlib
import re
import struct
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
SILENT_START_TYPE = "PushRegistrationAppDelegate"
# A type that exists only in a build with the Wake log (ios/App/TestingTools/, inside #if WAKE_LOG).
WAKE_LOG_TYPE = "WakeLogScreen"
# The types that the archive check looks for: release-archive-gate.py builds the archive in make check when a change
# touches a Swift file that names one of them.
ARCHIVE_TYPES = (SILENT_START_TYPE, WAKE_LOG_TYPE)
WAKE_LOG_CONDITION = "WAKE_LOG"
WAKE_LOG_SETTING = "TROME_WAKE_LOG_BUILD_<n>"


# The Mach-O and Swift formats that swift_types reads: mach-o/loader.h and mach-o/fat.h of the SDK, and the type
# metadata records of the Swift ABI (docs/ABI/TypeMetadata.rst and include/swift/ABI/Metadata.h of the Swift repo).
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MACH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
# Each 4-byte record of these sections points to the descriptor of a type that the binary declares.
TYPE_SECTIONS = (b"__swift5_types", b"__swift5_types2")
# The kind of a record, in its 2 low bits: only a direct descriptor holds a Swift type of the app itself.
DIRECT_TYPE_DESCRIPTOR = 0
# The name of a type descriptor is its third field: after its flags and its parent, 4 bytes each.
NAME_FIELD = 8


def slices(binary):
    """The start of each Mach-O in the file: one for a thin binary, one per architecture for a universal one."""
    if len(binary) < 8:
        return []
    magic, count = struct.unpack_from(">II", binary)
    if magic == FAT_MAGIC:
        return [struct.unpack_from(">IIIII", binary, 8 + 20 * index)[2] for index in range(count)]
    if magic == FAT_MAGIC_64:
        return [struct.unpack_from(">IIQQII", binary, 8 + 32 * index)[2] for index in range(count)]
    return [0]


def names_in_slice(binary, start):
    magic, _, _, _, commands, _, _, _ = struct.unpack_from("<IiiIIIII", binary, start)
    if magic != MACH_MAGIC_64:
        return set()
    segments, sections = [], []
    offset = start + 32
    for _ in range(commands):
        command, size = struct.unpack_from("<II", binary, offset)
        if command == LC_SEGMENT_64:
            vmaddr, _, fileoff, filesize, _, _, count, _ = struct.unpack_from("<QQQQiiII", binary, offset + 24)
            segments.append((vmaddr, filesize, start + fileoff))
            for index in range(count):
                name, _, address, length, _ = struct.unpack_from("<16s16sQQI", binary, offset + 72 + 80 * index)
                sections.append((name.rstrip(b"\0"), address, length))
        offset += size

    def at(address):
        for vmaddr, filesize, fileoff in segments:
            if vmaddr <= address < vmaddr + filesize:
                return fileoff + address - vmaddr
        raise ValueError(f"address {address:#x} is outside the file")

    def relative(address):
        return address + struct.unpack_from("<i", binary, at(address))[0]

    names = set()
    for name, address, length in sections:
        if name not in TYPE_SECTIONS:
            continue
        for record in range(address, address + length, 4):
            target = relative(record)
            if target & 3 != DIRECT_TYPE_DESCRIPTOR:
                continue
            text = at(relative(target + NAME_FIELD))
            names.add(binary[text:binary.index(b"\0", text)].decode("utf-8", "replace"))
    return names


def swift_types(binary):
    """The names of the Swift types that a binary declares, read from its type metadata records.

    A name is matched whole, never as a part of a longer text: the binary also holds the source path of each file
    (TROME/PushRegistrationAppDelegate.swift, a #fileID), which stays when a change renames the type but not its file.
    A binary that is not a Mach-O, or that cannot be read, declares none.
    """
    names = set()
    for start in slices(binary):
        try:
            names |= names_in_slice(binary, start)
        except (struct.error, ValueError):
            continue
    return names


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
    has_wake_log = WAKE_LOG_CONDITION in app.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
    return group, has_wake_log, problems


def problems_of_the_archive(archive, group, has_wake_log):
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
    types = swift_types(binary)
    if SILENT_START_TYPE not in types:
        problems.append(f"in the archive, {APP} has no silent start (no type {SILENT_START_TYPE}): "
                        "the Release build must compile SILENT_START")
    if WAKE_LOG_TYPE in types and not has_wake_log:
        problems.append(f"in the archive, {APP} has the Wake log ({WAKE_LOG_TYPE}) while its Release settings "
                        f"do not compile it ({WAKE_LOG_SETTING}): the store build must never have it")
    if WAKE_LOG_TYPE not in types and has_wake_log:
        problems.append(f"in the archive, {APP} has no Wake log ({WAKE_LOG_TYPE}) while its Release settings "
                        f"compile it ({WAKE_LOG_SETTING} = YES): the Release build must compile WAKE_LOG")
    return problems


def main(arguments):
    if len(arguments) not in (1, 2):
        print(USAGE, file=sys.stderr)
        return 2
    try:
        group, has_wake_log, problems = problems_of_the_project(arguments[0])
    except ValueError as error:
        print(f"release-entitlements-check: FAILED: {error}", file=sys.stderr)
        return 1
    if len(arguments) == 2:
        problems += problems_of_the_archive(arguments[1], group, has_wake_log)
    for problem in problems:
        print(f"release-entitlements-check: FAILED: {problem}", file=sys.stderr)
    if problems:
        return 1
    scope = "the archive and the project" if len(arguments) == 2 else "the project"
    wake_log = (f"with the Wake log ({WAKE_LOG_SETTING} = YES): a TestFlight build for a walk, never for the store"
                if has_wake_log else "with no Wake log, as the store build")
    print(f"release-entitlements-check: OK (in {scope}, the Release app has the push capability, "
          f"and the app and its widget share their app group; {wake_log})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
