#!/usr/bin/env python3
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

USAGE = "Usage: upload-check.py <built .app>"

MANIFEST = "PrivacyInfo.xcprivacy"
MANIFEST_KEYS = {
    "NSPrivacyTracking",
    "NSPrivacyTrackingDomains",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyAccessedAPITypes",
}
COLLECTED_DATA_KEYS = {
    "NSPrivacyCollectedDataType",
    "NSPrivacyCollectedDataTypeLinked",
    "NSPrivacyCollectedDataTypeTracking",
    "NSPrivacyCollectedDataTypePurposes",
}

REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "reasons": {"DDA9.1", "C617.1", "3B52.1"},
        "symbols": {
            "_stat", "_fstat", "_fstatat", "_lstat",
            "_getattrlist", "_getattrlistbulk", "_fgetattrlist", "_getattrlistat",
            "_NSFileCreationDate", "_NSFileModificationDate",
            "_NSURLContentModificationDateKey", "_NSURLCreationDateKey",
        },
        "selectors": {"fileModificationDate"},
    },
    "NSPrivacyAccessedAPICategorySystemBootTime": {
        "reasons": {"35F9.1", "8FFB.1", "3D61.1"},
        "symbols": {"_mach_absolute_time"},
        "selectors": {"systemUptime"},
    },
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "reasons": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
        "symbols": {
            "_statfs", "_statvfs", "_fstatfs", "_fstatvfs",
            "_getattrlist", "_fgetattrlist", "_getattrlistat",
            "_NSURLVolumeAvailableCapacityKey",
            "_NSURLVolumeAvailableCapacityForImportantUsageKey",
            "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey",
            "_NSURLVolumeTotalCapacityKey",
            "_NSFileSystemFreeSize", "_NSFileSystemSize",
        },
        "selectors": set(),
    },
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {
        "reasons": {"3EC4.1", "54BD.1"},
        "symbols": set(),
        "selectors": {"activeInputModes"},
    },
    "NSPrivacyAccessedAPICategoryUserDefaults": {
        "reasons": {"CA92.1", "1C8F.1", "AC6B.1"},
        "symbols": {"_OBJC_CLASS_$_NSUserDefaults"},
        "selectors": set(),
    },
}

PLACEHOLDER_HOST = b"example.com"

VERSION = re.compile(r"^\d+\.\d+\.\d+$")
BUILD_NUMBER = re.compile(r"^\d+(\.\d+){0,2}$")


def read_plist(path):
    try:
        with open(path, "rb") as file:
            return plistlib.load(file)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        return error


def check_info(bundle, info, app_version):
    problems = []
    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not VERSION.match(version):
        problems.append(
            f"{bundle.name}: the version (CFBundleShortVersionString) is {version!r}; "
            "it must be three numbers with dots, such as 1.0.0 (MARKETING_VERSION in ios/Config/Base.xcconfig)"
        )
    elif app_version is not None and version != app_version:
        problems.append(
            f"{bundle.name}: the version is {version}, but the app's version is {app_version}; "
            "the app and its extensions must have the same version"
        )
    build_number = info.get("CFBundleVersion")
    if not isinstance(build_number, str) or not BUILD_NUMBER.match(build_number):
        problems.append(
            f"{bundle.name}: the build number (CFBundleVersion) is {build_number!r}; "
            "it must be a number, such as 1 (CURRENT_PROJECT_VERSION in ios/Config/Base.xcconfig)"
        )
    return problems


def check_encryption(bundle, info):
    answer = info.get("ITSAppUsesNonExemptEncryption")
    if not isinstance(answer, bool):
        return [
            f"{bundle.name}: the Info.plist has no answer on encryption (ITSAppUsesNonExemptEncryption, "
            "a true or false value); add it to the app's info properties in ios/project.yml"
        ]
    if answer and not info.get("ITSEncryptionExportComplianceCode"):
        return [
            f"{bundle.name}: the Info.plist says that the app uses encryption that is not exempt, "
            "but it has no ITSEncryptionExportComplianceCode from Apple"
        ]
    return []


def check_icon(bundle, info):
    icons = info.get("CFBundleIcons")
    icon = icons.get("CFBundlePrimaryIcon") if isinstance(icons, dict) else None
    name = icon.get("CFBundleIconName") if isinstance(icon, dict) else None
    if not name:
        return [
            f"{bundle.name}: the app has no icon (no CFBundleIconName in its Info.plist); "
            "set ASSETCATALOG_COMPILER_APPICON_NAME of the app in ios/project.yml"
        ]
    catalog = bundle / "Assets.car"
    try:
        renditions = json.loads(
            subprocess.run(
                ["xcrun", "assetutil", "--info", str(catalog)], capture_output=True, text=True, check=True
            ).stdout
        )
    except (OSError, ValueError, subprocess.CalledProcessError):
        return [f"{bundle.name}: the app has no icon (its asset catalog Assets.car is missing or cannot be read)"]
    for rendition in renditions:
        if (
            rendition.get("AssetType") == "Icon Image"
            and rendition.get("Name") == name
            and rendition.get("PixelWidth") == 1024
            and rendition.get("PixelHeight") == 1024
        ):
            if rendition.get("Opaque") is True:
                return []
            return [f"{bundle.name}: the icon {name} has transparent pixels; the App Store refuses it"]
    return [f"{bundle.name}: the app has no icon {name} of 1024 x 1024 pixels in Assets.car"]


def check_manifest(bundle, manifest):
    name = f"{bundle.name}/{MANIFEST}"
    if isinstance(manifest, Exception):
        return [f"{name}: it is not a valid property list ({manifest})"], {}
    if not isinstance(manifest, dict):
        return [f"{name}: it must be a dictionary"], {}
    problems = [f"{name}: Apple refuses the unknown key {key}" for key in sorted(set(manifest) - MANIFEST_KEYS)]
    problems += [f"{name}: the key {key} is missing" for key in sorted(MANIFEST_KEYS - set(manifest))]
    tracking = manifest.get("NSPrivacyTracking")
    domains = manifest.get("NSPrivacyTrackingDomains", [])
    if "NSPrivacyTracking" in manifest and not isinstance(tracking, bool):
        problems.append(f"{name}: NSPrivacyTracking must be true or false")
    if not isinstance(domains, list) or not all(isinstance(domain, str) for domain in domains):
        problems.append(f"{name}: NSPrivacyTrackingDomains must be a list of domains")
    elif tracking is True and not domains:
        problems.append(f"{name}: NSPrivacyTracking is true, so NSPrivacyTrackingDomains must list the domains")
    collected = manifest.get("NSPrivacyCollectedDataTypes", [])
    if not isinstance(collected, list):
        problems.append(f"{name}: NSPrivacyCollectedDataTypes must be a list")
    else:
        for entry in collected:
            if not isinstance(entry, dict) or set(entry) != COLLECTED_DATA_KEYS:
                problems.append(
                    f"{name}: each collected data type must have exactly the keys {', '.join(sorted(COLLECTED_DATA_KEYS))}"
                )
    declared = {}
    accessed = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(accessed, list):
        return problems + [f"{name}: NSPrivacyAccessedAPITypes must be a list"], declared
    for entry in accessed:
        category = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
        if category not in REQUIRED_REASON_APIS:
            problems.append(f"{name}: {category!r} is not a category of Apple's list of required reason APIs")
            continue
        if not isinstance(reasons, list) or not reasons:
            problems.append(f"{name}: {category} gives no reason")
            continue
        for reason in reasons:
            if reason not in REQUIRED_REASON_APIS[category]["reasons"]:
                problems.append(f"{name}: {reason!r} is not a reason that an app may give for {category}")
        declared[category] = reasons
    return problems, declared


def used_categories(executable):
    try:
        symbols = set(
            subprocess.run(
                ["xcrun", "nm", "-u", "-j", str(executable)], capture_output=True, text=True, check=True
            ).stdout.split()
        )
        binary = executable.read_bytes()
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"upload-check: could not read the symbols of {executable}: {error}")
    used = {}
    for category, apis in REQUIRED_REASON_APIS.items():
        found = sorted(symbols & apis["symbols"])
        found += sorted(selector for selector in apis["selectors"] if b"\0" + selector.encode() + b"\0" in binary)
        if found:
            used[category] = found
    return used


def check_required_reasons(bundle, info, declared, has_manifest):
    executable_name = info.get("CFBundleExecutable", "")
    executable = bundle / executable_name
    if not executable_name or not executable.is_file():
        return [f"{bundle.name}: the executable {executable_name!r} is missing"]
    where = f"{bundle.name}/{MANIFEST}" if has_manifest else f"a {MANIFEST} at the top of {bundle.name}"
    problems = []
    for category, apis in sorted(used_categories(executable).items()):
        undeclared = [
            api
            for api in apis
            if not any(
                api in REQUIRED_REASON_APIS[other]["symbols"] | REQUIRED_REASON_APIS[other]["selectors"]
                for other in declared
            )
        ]
        if undeclared:
            problems.append(
                f"{bundle.name}: its code uses {', '.join(undeclared)}, an API of {category}, "
                f"so {where} must declare that category with an approved reason "
                "(Apple refuses the upload, ITMS-91053)"
            )
    return problems


def check_placeholder_address(bundle, info):
    executable = bundle / info.get("CFBundleExecutable", "")
    if not executable.is_file() or PLACEHOLDER_HOST not in executable.read_bytes():
        return []
    return [
        f"{bundle.name}: its code holds a placeholder address ({PLACEHOLDER_HOST.decode()}); "
        "a link of the app would open no real page, and App Review refuses a broken privacy policy link"
    ]


def check_bundle(bundle, app_version, is_app):
    info = read_plist(bundle / "Info.plist")
    if isinstance(info, Exception) or not isinstance(info, dict):
        return [f"{bundle.name}: could not read its Info.plist ({info})"]
    problems = check_info(bundle, info, app_version)
    if is_app:
        problems += check_encryption(bundle, info)
        problems += check_icon(bundle, info)
    manifest_path = bundle / MANIFEST
    declared = {}
    if manifest_path.is_file():
        manifest_problems, declared = check_manifest(bundle, read_plist(manifest_path))
        problems += manifest_problems
    elif is_app:
        problems.append(
            f"{bundle.name}: the app has no privacy manifest ({MANIFEST} at the top of the app); "
            "Apple refuses an upload without it"
        )
    problems += check_required_reasons(bundle, info, declared, manifest_path.is_file())
    problems += check_placeholder_address(bundle, info)
    return problems


def main(arguments):
    if len(arguments) != 1:
        sys.exit(USAGE)
    app = Path(arguments[0])
    info = read_plist(app / "Info.plist")
    if isinstance(info, Exception) or not isinstance(info, dict):
        sys.exit(f"upload-check: FAILED: {app} is not a built app ({info})")
    problems = check_bundle(app, None, is_app=True)
    app_version = info.get("CFBundleShortVersionString")
    for extension in sorted((app / "PlugIns").glob("*.appex")):
        problems += check_bundle(extension, app_version, is_app=False)
    if problems:
        print("upload-check: FAILED: App Store Connect would refuse this build:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)
    print(
        f"upload-check: OK ({app.name} {app_version} has its icon, its privacy manifest, its answer on encryption, "
        "a reason for each required reason API that its code and its extensions use, and no placeholder address)"
    )


if __name__ == "__main__":
    main(sys.argv[1:])
