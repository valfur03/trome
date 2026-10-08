#!/usr/bin/env python3
"""Keep the Mac quiet while a Simulator test run runs.

A heavy build of any worktree (a compile, the unit tests) takes all the cores. When one runs next to the tests,
iOS in the Simulator gets so little CPU that it starts its own processes many times slower: the process that runs
the intent of a Live Activity button took 33 s to start instead of 2 s, so iOS gave up on the tap at 30 s and the test
failed. So the builds and the test runs share a machine-wide lock: many builds run at once, a test run runs alone.

- `build <command...>`: waits while a test run waits or runs, then runs the command next to other builds.
- `tests <command...>`: waits for the builds that run, then runs the command; new builds wait for it.

A test run that waits has priority over new builds (a second lock file, the "turn", that a test run holds from the
start of its wait to its end), so a stream of builds never keeps it waiting. The kernel frees the locks of a process
that dies, so a killed build or test run never blocks the others. A command inside a held gate (the unit tests that
`make check` starts, the build inside a test run) runs at once: it is already counted.
"""
import fcntl
import os
import signal
import subprocess
import sys

PREFIX = os.environ.get("RATP_BUILD_GATE") or "/tmp/ratp-build-gate"
HELD = "RATP_BUILD_GATE_HELD"


def usage():
    print(f"Usage: {sys.argv[0]} build <command...>  Run a heavy build; it waits while a Simulator test run runs", file=sys.stderr)
    print(f"       {sys.argv[0]} tests <command...>  Run a Simulator test run alone; it waits for the builds that run, and new builds wait", file=sys.stderr)
    sys.exit(2)


def open_lock(name):
    return os.open(f"{PREFIX}.{name}", os.O_RDWR | os.O_CREAT, 0o666)


def try_lock(fd, mode):
    try:
        fcntl.flock(fd, mode | fcntl.LOCK_NB)
        return True
    except BlockingIOError:
        return False


def is_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as file:
            return file.read().strip()
    except OSError:
        return ""


def test_run_folder():
    text = read_text(f"{PREFIX}.turn")
    pid, _, folder = text.partition(" ")
    return folder if pid.isdigit() and is_alive(int(pid)) else ""


def running_builds():
    folder = f"{PREFIX}.builds"
    try:
        names = os.listdir(folder)
    except OSError:
        return []
    builds = []
    for name in sorted(names):
        path = os.path.join(folder, name)
        if name.isdigit() and is_alive(int(name)):
            builds.append(f"{read_text(path) or '?'} (process {name})")
        else:
            try:
                os.remove(path)
            except OSError:
                pass
    return builds


def run(command, role):
    env = dict(os.environ, **{HELD: role})
    try:
        child = subprocess.Popen(command, env=env)
    except OSError as error:
        print(f"{sys.argv[0]}: cannot run {command[0]}: {error}", file=sys.stderr)
        return 127

    def forward(signum, _frame):
        child.send_signal(signum)

    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, forward)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    status = child.wait()
    return 128 - status if status < 0 else status


def build(command):
    turn = open_lock("turn")
    if not try_lock(turn, fcntl.LOCK_EX):
        folder = test_run_folder()
        where = f" ({folder})" if folder else ""
        print(f"Waiting: a Simulator test run{where} needs a quiet Mac. This build starts when the test run ends.", file=sys.stderr)
        fcntl.flock(turn, fcntl.LOCK_EX)
    shared = open_lock("lock")
    fcntl.flock(shared, fcntl.LOCK_SH)
    os.close(turn)
    mark = f"{PREFIX}.builds/{os.getpid()}"
    try:
        os.makedirs(f"{PREFIX}.builds", exist_ok=True)
        with open(mark, "w", encoding="utf-8") as file:
            file.write(os.getcwd())
    except OSError:
        mark = None
    try:
        return run(command, "build")
    finally:
        if mark:
            try:
                os.remove(mark)
            except OSError:
                pass


def tests(command):
    turn = open_lock("turn")
    if not try_lock(turn, fcntl.LOCK_EX):
        folder = test_run_folder()
        where = f" ({folder})" if folder else ""
        print(f"Waiting: another Simulator test run{where} is running.", file=sys.stderr)
        fcntl.flock(turn, fcntl.LOCK_EX)
    os.ftruncate(turn, 0)
    os.pwrite(turn, f"{os.getpid()} {os.getcwd()}\n".encode(), 0)
    alone = open_lock("lock")
    if not try_lock(alone, fcntl.LOCK_EX):
        builds = running_builds()
        names = ": " + ", ".join(builds) if builds else ""
        print(f"Waiting for the builds that run to end, so that the tests run on a quiet Mac (new builds wait){names}", file=sys.stderr)
        fcntl.flock(alone, fcntl.LOCK_EX)
    try:
        return run(command, "tests")
    finally:
        os.ftruncate(turn, 0)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("build", "tests"):
        usage()
    command = sys.argv[2:]
    if os.environ.get(HELD):
        os.execvp(command[0], command)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))
    return build(command) if sys.argv[1] == "build" else tests(command)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
