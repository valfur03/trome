#!/usr/bin/env python3
"""Sum up where the time of the shared Simulator goes, from the records of sim-lock.sh and build-gate.py.

- simulator-jobs.tsv: one line per Simulator job, when it frees the Simulator: its kind, how long it waited for
  the Simulator, how long it held it, and how much of that hold its test run waited for the builds of other clones.
- build-waits.tsv: one line per wait of the build gate: a build that waited for a test run, or a test run that
  waited for the builds.

Both are in ~/Library/Logs/TROME/ (TROME_LOGS). They only grow: nothing resets them.
"""
import argparse
import os
import re
import statistics
import sys
from datetime import datetime

LOGS = os.environ.get("TROME_LOGS") or os.path.expanduser("~/Library/Logs/TROME")
TIME = "%Y-%m-%dT%H:%M:%S%z"


def read_records(name, since):
    path = os.path.join(LOGS, name)
    try:
        with open(path, encoding="utf-8", errors="replace") as file:
            lines = file.read().splitlines()
    except OSError:
        return path, []
    if not lines:
        return path, []
    header = lines[0].split("\t")
    records = []
    for line in lines[1:]:
        fields = line.split("\t")
        if fields == header or len(fields) < len(header):
            continue
        record = dict(zip(header, fields))
        try:
            record["when"] = datetime.strptime(record["asked"], TIME)
            record["wait_s"] = int(record["wait_s"])
            for key in ("hold_s", "gate_wait_s"):
                if key in record:
                    record[key] = int(record[key] or 0)
        except (KeyError, ValueError):
            continue
        if since and record["when"].strftime("%Y-%m-%d %H:%M") < since:
            continue
        records.append(record)
    return path, records


def duration(seconds):
    seconds = int(round(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, seconds = divmod(rest, 60)
    if hours:
        return f"{hours} h {minutes:02d} min"
    return f"{minutes} min {seconds:02d} s" if minutes else f"{seconds} s"


def table(rows):
    widths = [max(len(row[column]) for row in rows) for column in range(len(rows[0]))]
    for row in rows:
        cells = [row[0].ljust(widths[0])] + [cell.rjust(width) for cell, width in zip(row[1:], widths[1:])]
        print("  ".join(cells).rstrip())


def jobs_summary(jobs):
    first = min(job["when"] for job in jobs)
    last_end = max(job["when"].timestamp() + job["wait_s"] + job["hold_s"] for job in jobs)
    span = max(int(last_end - first.timestamp()), 1)
    held = sum(job["hold_s"] for job in jobs)
    print(f"Simulator jobs from {first.strftime('%Y-%m-%d %H:%M')}: {len(jobs)} job{"s" if len(jobs) > 1 else ""} held the Simulator "
          f"{duration(held)} of {duration(span)} ({held * 100 // span}%).")
    rows = [["kind", "jobs", "held", "share", "median hold", "waited", "median wait", "max wait", "held for builds"]]
    kinds = sorted({job["kind"] for job in jobs}, key=lambda kind: (-sum(j["hold_s"] for j in jobs if j["kind"] == kind), kind))
    for kind in kinds:
        group = [job for job in jobs if job["kind"] == kind]
        holds = [job["hold_s"] for job in group]
        waits = [job["wait_s"] for job in group]
        rows.append([
            kind,
            str(len(group)),
            duration(sum(holds)),
            f"{sum(holds) * 100 // max(held, 1)}%",
            duration(statistics.median(holds)),
            duration(sum(waits)),
            duration(statistics.median(waits)),
            duration(max(waits)),
            duration(sum(job.get("gate_wait_s", 0) for job in group)),
        ])
    table(rows)


def waits_summary(waits):
    rows = [["build gate", "waits", "waited", "median wait", "max wait"]]
    for gate, label in (("build", "a build waited for a test run"), ("tests", "a test run waited")):
        group = [wait["wait_s"] for wait in waits if wait["gate"] == gate]
        if group:
            rows.append([label, str(len(group)), duration(sum(group)), duration(statistics.median(group)), duration(max(group))])
    if len(rows) > 1:
        table(rows)


def main():
    parser = argparse.ArgumentParser(description="Sum up how long the Simulator jobs waited for the shared Simulator and held it.")
    parser.add_argument("--since", default="", help="only the records from this date and time on: 2026-10-08, or '2026-10-08 14:00'")
    since = parser.parse_args().since.strip().replace("T", " ")
    if since and not re.fullmatch(r"\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?", since):
        parser.error(f"--since {since}: write a date, 2026-10-08, or a date and a time, '2026-10-08 14:00'")
    jobs_path, jobs = read_records("simulator-jobs.tsv", since)
    waits_path, waits = read_records("build-waits.tsv", since)
    if not jobs:
        print(f"No Simulator job recorded{' since ' + since if since else ''} in {jobs_path}.")
    else:
        jobs_summary(jobs)
    if waits:
        print()
        waits_summary(waits)
    print(f"\nRecords: {jobs_path}, {waits_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
