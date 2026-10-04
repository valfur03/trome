#!/usr/bin/env python3
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

POWER_EVENT = re.compile(r"^(?P<moment>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (?P<zone>[+-]\d{4}) (?P<kind>\S+) *\t(?P<message>.*)")


def failures(node, test=None):
    if node.get("nodeType") == "Test Case":
        test = node.get("nodeIdentifier") or node.get("name")
    if node.get("nodeType") == "Failure Message":
        yield test, node.get("name", ""), node.get("sourceLocation")
    for child in node.get("children", []):
        yield from failures(child, test)


def output_of(command):
    result = subprocess.run(command, capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        return None
    return result.stdout


def sleeps(power_log, start, end):
    asleep = None
    for line in power_log.splitlines():
        event = POWER_EVENT.match(line)
        if not event:
            continue
        moment = event["moment"]
        when = datetime.strptime(f"{moment} {event['zone']}", "%Y-%m-%d %H:%M:%S %z").timestamp()
        if asleep is None and event["kind"] == "Sleep" and event["message"].startswith("Entering Sleep") and start <= when <= end:
            asleep = (moment, when)
        elif asleep is not None and event["kind"] == "Wake":
            yield asleep[0], moment, round(when - asleep[1])
            asleep = None
    if asleep is not None:
        yield asleep[0], None, None


def print_sleeps(summary):
    start = summary.get("startTime")
    if start is None:
        return
    end = summary.get("finishTime") or time.time()
    power_log = output_of(["pmset", "-g", "log"])
    if power_log is None:
        return
    spans = []
    for asleep, awake, seconds in sleeps(power_log, int(start), end):
        if awake is None:
            spans.append(f"from {asleep} (no wake in the log yet)")
        else:
            spans.append(f"from {asleep} to {awake} ({seconds} s)")
    if spans:
        print(f"The Mac slept during the E2E tests, {', then '.join(spans)}, says 'pmset -g log'.")
        print("The Simulator stops while the Mac sleeps, but the waits of the tests count on the clock. So the failures above may come from the sleep, not from the code.")
        print("Run the same command again (make e2e, make merge or make docs-screenshots) before you look for a bug.")


def print_counts(summary):
    if "totalTestCount" not in summary:
        return
    counts = f"{summary.get('passedTests', 0)} passed, {summary.get('failedTests', 0)} failed, {summary.get('skippedTests', 0)} skipped"
    start, end = summary.get("startTime"), summary.get("finishTime")
    time_taken = f" in {round(end - start)} s" if start is not None and end is not None else ""
    print(f"E2E tests: {counts} (of {summary['totalTestCount']}){time_taken}")


def main():
    bundle = Path(sys.argv[1])
    if not bundle.exists():
        return
    summary = output_of(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)])
    summary = json.loads(summary) if summary is not None else None
    if summary is not None:
        print_counts(summary)
    tests = output_of(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)])
    if tests is not None:
        for root in json.loads(tests).get("testNodes", []):
            for test, message, location in failures(root):
                where = ""
                if location:
                    where = f"{Path(location['filePath']).name}:{location['lineNumber']}: "
                print(f"{where}{test}: {message}")
    if summary is not None and summary.get("result") != "Passed":
        print_sleeps(summary)


if __name__ == "__main__":
    main()
