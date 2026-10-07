#!/usr/bin/env python3
import json
import struct
import sys
from pathlib import Path

USAGE = "Usage: app-icon-check.py <AppIcon.appiconset folder>"

STORE_SIZE = 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
COLOR_TYPES_WITH_ALPHA = {4, 6}


def store_icon_name(icon_set):
    try:
        contents = json.loads((icon_set / "Contents.json").read_text())
    except OSError:
        return None, f"{icon_set}: the app has no icon (this icon set does not exist)"
    except ValueError as error:
        return None, f"{icon_set}/Contents.json: it is not valid JSON ({error})"
    for image in contents.get("images", []):
        if image.get("size") == f"{STORE_SIZE}x{STORE_SIZE}" and image.get("filename") and "appearances" not in image:
            return image["filename"], None
    return None, (
        f"{icon_set}: the app has no icon. "
        f"Add a {STORE_SIZE} x {STORE_SIZE} PNG image to this icon set, for any appearance"
    )


def png_problems(path):
    try:
        data = path.read_bytes()
    except OSError as error:
        return [f"{path}: the icon file is missing ({error})"]
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return [f"{path}: the icon is not a PNG image"]
    width, height, _, color_type = struct.unpack(">IIBB", data[16:26])
    problems = []
    if (width, height) != (STORE_SIZE, STORE_SIZE):
        problems.append(
            f"{path}: the icon is {width} x {height} pixels; "
            f"the App Store needs a square of {STORE_SIZE} x {STORE_SIZE} pixels"
        )
    if color_type in COLOR_TYPES_WITH_ALPHA or has_chunk(data, b"tRNS"):
        problems.append(
            f"{path}: the icon has an alpha channel (transparency); "
            "the App Store refuses it. Save it as a PNG with no alpha, on a plain background"
        )
    return problems


def has_chunk(data, name):
    position = len(PNG_SIGNATURE)
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        if kind == name:
            return True
        if kind == b"IEND":
            return False
        position += 12 + length
    return False


def main(arguments):
    if len(arguments) != 1:
        sys.exit(USAGE)
    icon_set = Path(arguments[0])
    filename, problem = store_icon_name(icon_set)
    problems = [problem] if problem else png_problems(icon_set / filename)
    if problems:
        print("app-icon-check: FAILED:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)
    print(f"app-icon-check: OK ({filename} is {STORE_SIZE} x {STORE_SIZE}, with no alpha channel)")


if __name__ == "__main__":
    main(sys.argv[1:])
