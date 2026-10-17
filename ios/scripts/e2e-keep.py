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
# iOS runs the intent of a Live Activity button in a new process of its intent runner, then in the app. Its widget
# host (chronod) logs a watchdog when the intent has not ended after this time.
LIVE_ACTIVITY_TAP_LIMIT_SECONDS = 30
INTENT_RUNNER = "BackgroundShortcutRunner"
# make e2e writes the load of the Mac and its busiest processes in this file of its log folder (mac-load-log.sh).
MAC_LOAD_LOG = "mac-load.log"
MAC_LOAD_SAMPLE = re.compile(r"^\d\d:\d\d:\d\d load ([0-9.]+) \|")
# The daily update of the wallpapers of iOS: about 15 wallpaper extensions at once, for minutes (simulator.sh waits
# for it before a run, when it is due).
WALLPAPER_UPDATE = "com.apple.springboard.posterboardupdate.overnight"
BACKGROUND_TASK = re.compile(r'\] (STARTED|COMPLETED) <_DASActivity: "([^"]+?)(?::\w+)?"')
LOG_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) +\S+ +(\S+?)\[(\d+):")


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
    if not bundle_id or not executable:
        return "not kept: the app has no bundle ID or no executable name"
    predicate = simulator_log_predicate(bundle_id, executable)
    window = ["--last", f"{NO_SUMMARY_LOG_SECONDS}s"]
    if start is not None:
        window = ["--start", moment(start - SIMULATOR_LOG_MARGIN_SECONDS), "--end", moment(end + SIMULATOR_LOG_MARGIN_SECONDS)]
    command = ["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "compact", "--info", *window, "--predicate", predicate]
    with open(folder / "simulator.log", "w") as log:
        status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
    if status != 0:
        return f"simulator.log (log show ended with exit {status}: see its end)"
    return (
        f"simulator.log (the lines of {executable}, every line of iOS that names {bundle_id}, "
        "the path of the Live Activity buttons: the taps of chronod and iOS's intent runner, "
        "the queue of the widget host (chronod), which holds back a new Live Activity, "
        "and the heavy background tasks of iOS)"
    )


def simulator_log_predicate(bundle_id, executable):
    return " OR ".join([
        f'process == "{executable}"',
        f'eventMessage CONTAINS "{bundle_id}"',
        '(process == "chronod" AND category == "interactions")',
        # The queue of the widget host, and a card that iOS draws empty while it waits: a Live Activity that never shows.
        '(process == "chronod" AND category == "taskservice")',
        'eventMessage CONTAINS "LiveActivity will be empty"',
        f'process == "{INTENT_RUNNER}"',
        f'(process == "launchd_sim" AND eventMessage CONTAINS "Successfully spawned {INTENT_RUNNER}[")',
        # The heavy background tasks that the scheduler of iOS (dasd) runs, such as the daily update of the wallpapers.
        '(process == "dasd" AND category == "lifecycle" AND eventMessage CONTAINS "Intensive: "'
        ' AND (eventMessage BEGINSWITH "STARTED <" OR eventMessage BEGINSWITH "COMPLETED <"))',
    ])


def live_activity_taps(simulator_log):
    """Says how long iOS took to run each tap on a Live Activity button, and names each tap that took too long."""
    try:
        lines = simulator_log.read_text(errors="replace").splitlines()
    except OSError:
        return None
    taps, running, runner_spawns, runner_starts = [], {}, {}, {}
    for line in lines:
        match = LOG_LINE.match(line)
        if not match:
            continue
        at, process, pid = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S.%f"), match.group(2), match.group(3)
        spawned = re.search(rf"Successfully spawned {INTENT_RUNNER}\[(\d+)\]", line)
        if process == "launchd_sim" and spawned:
            runner_spawns[spawned.group(1)] = at
        elif process == INTENT_RUNNER:
            runner_starts.setdefault(pid, at)
        elif process == "chronod" and "[com.apple.chrono:interactions]" in line:
            action = re.search(r"action: <LNAction: (0x[0-9a-f]+), identifier: ([^,]+),", line)
            oldest = min(running, key=lambda address: running[address]["start"]) if running else None
            if "Starting to run action" in line and action:
                tap = {"name": action.group(2), "start": at}
                taps.append(tap)
                running[action.group(1)] = tap
            elif "Successfully ran action" in line and action and action.group(1) in running:
                running.pop(action.group(1))["ran"] = at
            elif "Watchdog fired on interaction runner" in line and oldest:
                running[oldest]["watchdog"] = at
            elif "Failed to execute LNAction" in line and oldest:
                running.pop(oldest)["failed"] = at
    if not taps:
        return "none in the Simulator log"
    ran = [(tap["ran"] - tap["start"]).total_seconds() for tap in taps if "ran" in tap]
    parts = [f"{len(ran)} ran, the longest in {max(ran):.1f} s"] if ran else []
    for index, tap in enumerate(taps):
        if "watchdog" not in tap and "ran" in tap:
            continue
        text = f"the tap on {tap['name']} at {tap['start']:%H:%M:%S}"
        if "watchdog" in tap:
            text += f" had not ended after {LIVE_ACTIVITY_TAP_LIMIT_SECONDS} s (the watchdog of iOS fired)"
        # The runner of this tap is the first one spawned after it, and before the next tap.
        next_tap = taps[index + 1]["start"] if index + 1 < len(taps) else datetime.max
        runner = next((pid for pid, at in runner_spawns.items() if tap["start"] <= at < next_tap), None)
        if runner in runner_starts:
            started = (runner_starts[runner] - runner_spawns[runner]).total_seconds()
            text += f", its intent runner ({INTENT_RUNNER}) took {started:.0f} s to start"
        if "ran" in tap:
            text += f", and it ran in {(tap['ran'] - tap['start']).total_seconds():.0f} s"
        elif "failed" in tap:
            text += f", and it failed at {tap['failed']:%H:%M:%S}"
        else:
            text += ", and it had not ended at the end of the log"
        parts.append(text)
    return "; ".join(parts)


def live_activity_renders(simulator_log, bundle_id):
    """Says how long iOS took to draw each content of the Live Activity in the widget process, how long that process
    took to start, and when iOS stopped it at its watchdog (chronod waits about 10 s): a content that iOS never draws
    never shows, and the Live Activity keeps the last one it drew."""
    try:
        lines = simulator_log.read_text(errors="replace").splitlines()
    except OSError:
        return None
    widget = f"[extension<{bundle_id}.widget["
    ours, renders, launched, starts, stopped = set(), [], {}, [], []
    for line in lines:
        match = LOG_LINE.match(line)
        if not match:
            continue
        at, process = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S.%f"), match.group(2)
        if process == "chronod":
            submitted = re.search(rf"\[(\w+)\]: task submitted activity<\[{re.escape(bundle_id)}::", line)
            completed = re.search(r"\[(\w+)\]: task session completed in ([0-9.]+)s", line)
            if submitted:
                ours.add(submitted.group(1))
            elif completed and completed.group(1) in ours:
                renders.append(float(completed.group(2)))
        elif process == "runningboardd" and widget in line:
            pid = re.search(r"\]:(\d+)\]", line)
            pid = pid.group(1) if pid else None
            if "Full encoding handle" in line:
                launched[pid] = at
            elif "as ready" in line and pid in launched:
                starts.append((at - launched.pop(pid)).total_seconds())
            elif "explanation:ChronodWidgetExtensionWatchdog" in line:
                stopped.append(at)
    if not renders:
        return "none in the Simulator log"
    parts = [f"{len(renders)} ran, the longest in {max(renders):.1f} s"]
    if starts:
        parts.append(f"the widget process took up to {max(starts):.1f} s to start")
    if stopped:
        times = ", ".join(f"{at:%H:%M:%S}" for at in stopped)
        parts.append(f"iOS stopped the widget process before it drew, at its watchdog, at {times}")
    return "; ".join(parts)


def background_tasks(simulator_log):
    """Names the heavy background tasks that iOS ran during the run, with their start and end: they keep the Simulator
    busy, and the daily update of the wallpapers starts about 15 processes at once."""
    try:
        lines = simulator_log.read_text(errors="replace").splitlines()
    except OSError:
        return None
    tasks = {}
    for line in lines:
        match, task = LOG_LINE.match(line), BACKGROUND_TASK.search(line)
        if not match or match.group(2) != "dasd" or not task:
            continue
        at = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S.%f")
        name = task.group(2)
        if task.group(1) == "STARTED":
            tasks.setdefault(name, []).append([at, None])
        elif name in tasks and tasks[name][-1][1] is None:
            tasks[name][-1][1] = at
    if not tasks:
        return "none in the Simulator log"
    parts = []
    for name, runs in sorted(tasks.items(), key=lambda item: item[1][0][0]):
        for start, end in runs:
            label = "the daily update of the wallpapers" if name == WALLPAPER_UPDATE else name
            parts.append(f"{label} from {start:%H:%M:%S} to {f'{end:%H:%M:%S}' if end else 'the end of the log'}")
    return "; ".join(parts)


def keep_mac_load(log, folder, since):
    """Keeps the load of the Mac that make e2e wrote during this run, and names its busiest moment."""
    path = log.parent / MAC_LOAD_LOG
    try:
        if path.stat().st_mtime < since:
            return f"not recorded during this run (no new {MAC_LOAD_LOG})"
        shutil.copy2(path, folder / path.name)
        samples = [line for line in path.read_text(errors="replace").splitlines() if MAC_LOAD_SAMPLE.match(line)]
    except OSError:
        return f"not recorded (no {MAC_LOAD_LOG} next to the log)"
    if not samples:
        return f"{MAC_LOAD_LOG} (no sample)"
    busiest = max(samples, key=lambda line: float(MAC_LOAD_SAMPLE.match(line).group(1)))
    return f"{MAC_LOAD_LOG} (every 10 s, with the busiest processes); the highest: {busiest}"


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
    taps = live_activity_taps(folder / "simulator.log")
    renders = live_activity_renders(folder / "simulator.log", bundle_id) if bundle_id else None
    background = background_tasks(folder / "simulator.log")
    mac_load = keep_mac_load(log, folder, start if start is not None else time.time() - NO_SUMMARY_LOG_SECONDS)

    context = [
        f"Failed E2E run, kept at {now.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Commit: {(output_of(['git', 'rev-parse', 'HEAD']) or 'unknown').strip()}",
        f"Folder: {(output_of(['git', 'rev-parse', '--show-toplevel']) or os.getcwd()).strip()}",
        f"Only these tests: {os.environ.get('ONLY') or 'no (the full suite)'}",
        f"Load of the Mac at the end of the run: {load_of_the_mac()}",
        f"Load of the Mac during the run: {mac_load}",
        f"Crash reports of the app: {crash_reports}",
        f"Simulator log: {simulator_log}",
        f"Taps on a Live Activity button: {taps or 'unknown (no Simulator log)'}",
        f"Draws of the Live Activity by iOS: {renders or 'unknown (no Simulator log)'}",
        f"Heavy background tasks of iOS: {background or 'unknown (no Simulator log)'}",
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
    if taps and "the tap on" in taps:
        print(f"Taps on a Live Activity button: {taps}.")
    if renders and "iOS stopped" in renders:
        print(f"Draws of the Live Activity by iOS: {renders}.")
    if background and "the daily update of the wallpapers" in background:
        print(f"Heavy background tasks of iOS: {background}.")
    print(f"E2E evidence: the log, the result bundle, the Simulator log and the context of this failed run are kept in {folder}")


if __name__ == "__main__":
    main()
