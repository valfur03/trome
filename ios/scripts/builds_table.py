"""The table "The builds that riders may hold" of the release guide: one row per build uploaded to Apple, kept forever.

server/scripts/builds-table.ts reads the same table for the server; this module reads it for the scripts of the app.
"""
from __future__ import annotations

import re
from typing import Dict, List, Optional

GUIDE = "docs/src/content/docs/en/maintain/release-on-the-app-store.mdx"
TABLE_HEADING = "## The builds that riders may hold"
BUILD_NAME = re.compile(r"^(\d+\.\d+\.\d+) \((\d+)\)$")


def cells(line: str) -> List[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def table_rows(guide_path: str) -> Optional[List[Dict[str, str]]]:
    """Each row of the table, oldest first, as a cell per heading of its column, and its first cell, the build, also
    under "build"; None when the guide has no such table."""
    try:
        with open(guide_path, encoding="utf-8") as file:
            lines = file.read().split("\n")
    except OSError:
        return None
    if TABLE_HEADING not in lines:
        return None
    section = lines[lines.index(TABLE_HEADING) + 1 :]
    section = section[: next((i for i, line in enumerate(section) if line.startswith("## ")), len(section))]
    header = next((i for i, line in enumerate(section) if line.strip().startswith("|")), None)
    if header is None:
        return None
    headings = cells(section[header])
    body = section[header + 2 :]
    body = body[: next((i for i, line in enumerate(body) if not line.strip().startswith("|")), len(body))]
    rows = []
    for line in body:
        row = cells(line)
        values = {heading: re.sub(r"[*`]", "", row[i] if i < len(row) else "").strip() for i, heading in enumerate(headings)}
        rows.append({**values, "build": row[0]})
    return rows or None


def tag_of(build: str) -> Optional[str]:
    """builds/1.0.0/3 for the build 1.0.0 (3): the git tag that step 4 of the release guide puts on its commit."""
    match = BUILD_NAME.match(build)
    return f"builds/{match.group(1)}/{match.group(2)}" if match else None
