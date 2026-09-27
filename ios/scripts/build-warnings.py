#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from urllib.parse import urlparse


def location(issue):
    url = urlparse(issue.get("sourceURL", ""))
    if not url.path:
        return ""
    line = dict(part.split("=", 1) for part in url.fragment.split("&") if "=" in part).get("StartingLineNumber")
    if line is None:
        return f"{Path(url.path).name}: "
    return f"{Path(url.path).name}:{int(line) + 1}: "


def main():
    try:
        results = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("build-warnings: could not read the build results", file=sys.stderr)
        sys.exit(1)
    issues = results.get("warnings", []) + results.get("analyzerWarnings", [])
    for issue in issues:
        target = issue.get("targetName")
        where = f"[{target}] " if target else ""
        print(f"warning: {where}{location(issue)}{issue['message']}")
    if issues:
        print(f"The build has {len(issues)} warning(s). Fix them: make check accepts no warning.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
