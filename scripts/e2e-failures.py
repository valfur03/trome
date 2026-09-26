#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


def failures(node, test=None):
    if node.get("nodeType") == "Test Case":
        test = node.get("nodeIdentifier") or node.get("name")
    if node.get("nodeType") == "Failure Message":
        yield test, node.get("name", ""), node.get("sourceLocation")
    for child in node.get("children", []):
        yield from failures(child, test)


def main():
    bundle = Path(sys.argv[1])
    if not bundle.exists():
        return
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return
    for root in json.loads(result.stdout).get("testNodes", []):
        for test, message, location in failures(root):
            where = ""
            if location:
                where = f"{Path(location['filePath']).name}:{location['lineNumber']}: "
            print(f"{where}{test}: {message}")


if __name__ == "__main__":
    main()
