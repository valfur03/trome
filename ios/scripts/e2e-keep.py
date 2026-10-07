#!/usr/bin/env python3
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

KEPT_RUNS = 20
SIMULATOR_LOG_MARGIN_SECONDS = 5
NO_SUMMARY_LOG_SECONDS = 900
LAUNCH_PROCESSES = ["runningboardd", "SpringBoard", "locationd", "tccd", "testmanagerd"]


def usage():
    print(f"Usage: {sys.argv[0]} <result bundle> <log file> <app path>", file=sys.stderr)
    print("       Keeps the evidence of a failed E2E run in a folder outside the worktree, which the next run does not overwrite:", file=sys.stderr)
    print("       the log, the result bundle, the Simulator log of the run, the crash reports of the app, and the context (load, tests).", file=sys.stderr)
    print(f"       The folder is TROME_E2E_EVIDENCE (default: ~/Library/Logs/TROME/e2e-failures); it keeps the {KEPT_RUNS} newest runs.", file=sys.stderr)
    print("       When TROME_E2E_EVIDENCE_NOTE names a file, the path of the kept run is written in it.", file=sys.stderr)
    print("       Run it inside the Simulator job, so that the Simulator log still holds the run.", file=sys.stderr)
    sys.exit(2)


def output_of(command, cwd=None):
    try:
        result = subprocess.run(command, capture_output=True, text=True, errors="replace", cwd=cwd)
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def json_of(command):
    text = output_of(command)
    if text is None:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def evidence_root():
    configured = os.environ.get("TROME_E2E_EVIDENCE")
    if configured:
        return Path(configured)
    return Path.home() / "Library" / "Logs" / "TROME" / "e2e-failures"


def run_name(now):
    branch = output_of(["git", "symbolic-ref", "--short", "-q", "HEAD"])
    label = branch.strip() if branch else Path(output_of(["git", "rev-parse", "--show-toplevel"]) or os.getcwd()).name.strip()
    label = re.sub(r"[^A-Za-z0-9._-]+", "-", label) or "detached"
    return f"{now.strftime('%Y-%m-%d-%H%M%S')}-{label}"


def new_folder(root, now):
    root.mkdir(parents=True, exist_ok=True)
    name = run_name(now)
    folder = root / name
    suffix = 1
    while folder.exists():
        suffix += 1
        folder = root / f"{name}-{suffix}"
    folder.mkdir()
    return folder


def app_info(app):
    try:
        with open(Path(app) / "Info.plist", "rb") as plist:
            info = plistlib.load(plist)
    except (OSError, plistlib.InvalidFileException):
        return None, None
    return info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")


def tests_in_order(tests):
    lines = []

    def walk(node):
        if node.get("nodeType") == "Test Case":
            name = node.get("nodeIdentifier") or node.get("name")
            seconds = node.get("durationInSeconds")
            took = f", {round(seconds)} s" if isinstance(seconds, (int, float)) else ""
            lines.append(f"  {name}: {node.get('result', 'unknown')}{took}")
            return
        for child in node.get("children", []):
            walk(child)

    for root in tests.get("testNodes", []):
        walk(root)
    return lines


def load_of_the_mac():
    load = output_of(["sysctl", "-n", "vm.loadavg"])
    cores = output_of(["sysctl", "-n", "hw.logicalcpu"])
    if load is None:
        return "unknown (sysctl vm.loadavg failed)"
    averages = load.strip().strip("{}").split()
    text = f"{' '.join(averages)} (1, 5 and 15 min averages)"
    if cores:
        text += f" on {cores.strip()} cores"
    return text


def keep_crash_reports(folder, executable, since):
    reports = Path.home() / "Library" / "Logs" / "DiagnosticReports"
    if not executable or not reports.is_dir():
        return "none (no app name, or no DiagnosticReports folder)"
    kept = []
    for report in sorted(reports.glob(f"{executable}-*.ips")):
        if report.stat().st_mtime >= since:
            shutil.copy2(report, folder / report.name)
            kept.append(report.name)
    if not kept:
        return f"none: no {executable}-*.ips in ~/Library/Logs/DiagnosticReports since the run started"
    return ", ".join(kept)


def moment(seconds):
    return datetime.fromtimestamp(seconds).strftime("%Y-%m-%d %H:%M:%S")


def simulator_udid():
    udid = output_of([str(Path(__file__).resolve().parent / "simulator.sh"), "find"])
    return udid.strip() if udid else None


def keep_simulator_log(folder, bundle_id, executable, start, end):
    udid = simulator_udid()
    if not udid:
        return "not kept: no shared Simulator found"
    processes = LAUNCH_PROCESSES + ([executable] if executable else [])
    predicate = " OR ".join(f'process == "{process}"' for process in processes)
    if bundle_id:
        predicate += f' OR eventMessage CONTAINS "{bundle_id}"'
    window = ["--last", f"{NO_SUMMARY_LOG_SECONDS}s"]
    if start is not None:
        window = ["--start", moment(start - SIMULATOR_LOG_MARGIN_SECONDS), "--end", moment(end + SIMULATOR_LOG_MARGIN_SECONDS)]
    command = ["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "compact", "--info", *window, "--predicate", predicate]
    with open(folder / "simulator.log", "w") as log:
        status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
    if status != 0:
        return f"simulator.log (log show ended with exit {status}: see its end)"
    return f"simulator.log (processes {', '.join(processes)}, and every line that names {bundle_id})"


def prune(root, folder):
    runs = sorted((run for run in root.iterdir() if run.is_dir()), key=lambda run: run.stat().st_mtime, reverse=True)
    for old in runs[KEPT_RUNS:]:
        if old != folder:
            shutil.rmtree(old, ignore_errors=True)


def main():
    if len(sys.argv) != 4:
        usage()
    bundle, log, app = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    now = datetime.now()
    root = evidence_root()
    folder = new_folder(root, now)

    summary = None
    tests = None
    if bundle.exists():
        shutil.copytree(bundle, folder / bundle.name, symlinks=True)
        summary = json_of(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)])
        tests = json_of(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)])
    if log.exists():
        shutil.copy2(log, folder / log.name)

    start = summary.get("startTime") if summary else None
    end = (summary.get("finishTime") if summary else None) or time.time()
    bundle_id, executable = app_info(app)
    crash_reports = keep_crash_reports(folder, executable, start if start is not None else time.time() - NO_SUMMARY_LOG_SECONDS)
    simulator_log = keep_simulator_log(folder, bundle_id, executable, start, end)

    context = [
        f"Failed E2E run, kept at {now.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Commit: {(output_of(['git', 'rev-parse', 'HEAD']) or 'unknown').strip()}",
        f"Folder: {(output_of(['git', 'rev-parse', '--show-toplevel']) or os.getcwd()).strip()}",
        f"Only these tests: {os.environ.get('ONLY') or 'no (the full suite)'}",
        f"Load of the Mac at the end of the run: {load_of_the_mac()}",
        f"Crash reports of the app: {crash_reports}",
        f"Simulator log: {simulator_log}",
        f"Result bundle: {bundle.name if bundle.exists() else 'none (the run ended before it wrote one)'}",
        f"Log: {log.name if log.exists() else 'none'}",
        "Tests, in the order they ran:",
    ]
    context += tests_in_order(tests) if tests else ["  unknown (no test results)"]
    (folder / "context.txt").write_text("\n".join(context) + "\n")

    prune(root, folder)
    note = os.environ.get("TROME_E2E_EVIDENCE_NOTE")
    if note:
        Path(note).write_text(f"{folder}\n")
    print(f"E2E evidence: the log, the result bundle, the Simulator log and the context of this failed run are kept in {folder}")


if __name__ == "__main__":
    main()
