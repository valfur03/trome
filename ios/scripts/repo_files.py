import subprocess
import sys
from pathlib import Path


# The files of the repo that a check reads: the files in git, plus the new files that git does not track yet and does not
# ignore. So a check run before the first commit reads the same files as the gate of the merge, which runs on a clean
# worktree, and a mistake in a new file shows before the commit.
def repo_files(check, patterns=()):
    try:
        root = Path(git(["rev-parse", "--show-toplevel"]).strip())
        listed = git(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *patterns], cwd=root)
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"{check}: could not list the files of the repo: {error}")
    return root, sorted({path for path in listed.split("\0") if path and (root / path).is_file()})


def git(arguments, cwd=None):
    return subprocess.run(["git", *arguments], cwd=cwd, capture_output=True, text=True, check=True).stdout
