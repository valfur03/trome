import subprocess
import sys
from pathlib import Path


def repo_files(check, patterns=()):
    try:
        root = Path(git(["rev-parse", "--show-toplevel"]).strip())
        listed = git(["ls-files", "-z", "--", *patterns], cwd=root)
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"{check}: could not list the files of the repo: {error}")
    return root, [path for path in listed.split("\0") if path and (root / path).is_file()]


def git(arguments, cwd=None):
    return subprocess.run(["git", *arguments], cwd=cwd, capture_output=True, text=True, check=True).stdout
