#!/usr/bin/env python3
"""Proves, from the file alone, the guards of the release workflow (.github/workflows/release.yml), which signs the app
and uploads it with secrets, in a public repo whose logs anyone can read:
- no job opens a secret before the maintainer's approval: each job that names one waits at the environment app-store,
  runs only on main (an if: on github.ref), and needs the release checks, whose E2E proof job stops a commit with no
  record of a full E2E pass on the Mac;
- a secret reaches only the env: or with: of the step that uses it, never a job, the workflow, a called workflow or
  the text of a run:;
- the workflow has no pull request trigger, and shares the concurrency group release, never cancelled while it runs;
- nothing can print a value: no step prints Info.plist, the build settings, the environment or the shell's commands;
  a step that holds a secret writes it only to a file; the host and the app token of the server are masked; the
  keychain is a new one, with a random password that is masked, and is deleted at the end;
- no artifact and no cache, and every action pinned to a full commit hash, in this workflow and in the workflows of
  the repo that it calls;
- the summary says "E2E: proven at merge", never "E2E passed"; the run never sets the version.
It reads YAML with the YAML library of Ruby, which macOS and GitHub's Mac both have.
"""
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterator, List, Set, Tuple

USAGE = "Usage: release-workflow-check.py <.github/workflows/release.yml>"
ENVIRONMENT = "app-store"
GROUP = "release"
MAIN = "github.ref == 'refs/heads/main'"
CHECKS = "./.github/workflows/release-checks.yml"
PROOF = "./.github/workflows/e2e-proof.yml"
PROOF_READ = "ios/scripts/e2e-proof.sh read"
SECRET = re.compile(r"secrets\.(?!GITHUB_TOKEN\b)([A-Za-z_][A-Za-z0-9_]*)")
# Any read of the secrets in an expression: by name, in brackets (secrets['NAME']), or the whole context (toJSON).
ANY_SECRET = re.compile(r"\bsecrets\b(?!\.GITHUB_TOKEN\b)")
WHOLE_SECRETS = re.compile(r"\bsecrets\b(?!\s*[.\[])")
EXPRESSION = re.compile(r"\$\{\{(.*?)\}\}", re.DOTALL)
PINNED = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
MASKED = ("TRAIN_SERVER_HOST", "TRAIN_SERVER_APP_TOKEN")
# What a run: must never hold, each with its reason.
NEVER = (
    (r"\bset\s+-[A-Za-z]*x|\bset\s+-o\s+xtrace|\b(ba)?sh\s+-[A-Za-z]*x\b", "prints each command with its values"),
    (r"showBuildSettings", "prints the build settings, which hold the server and its token"),
    (r"Info\.plist", "reads an Info.plist, which holds the server and its token"),
    (r"\bplutil\s+-p\b|PlistBuddy|\bdefaults\s+read\b", "prints a property list"),
    (r"\bprintenv\b|^\s*(export|env|set)\s*($|[|>])", "prints the environment"),
    (r"\bsecurity\s+(find-identity|find-certificate|find-generic-password|dump-keychain|export)\b",
     "prints or exports what the keychain holds"),
    (r"-allowProvisioningUpdates", "lets Xcode make certificates and profiles with the key, with no approval"),
    (r"\bgh\s+release\b", "can upload a file to a public release"),
    (r"MARKETING_VERSION\s*=", "sets the version, which is the one of the repo"),
    (r"E2E passed", "says that the E2E suite passed here: it says 'E2E: proven at merge'"),
)
OUTPUTS = re.compile(r"GITHUB_STEP_SUMMARY|GITHUB_OUTPUT|GITHUB_ENV|GITHUB_PATH|/dev/std(out|err)|/dev/tty|\btee\b")
PRINTS = re.compile(r"^\s*(echo|printf|cat)\b")
# A redirection to a file; >&2 and 2>&1 go to the log.
TO_FILE = re.compile(r">>?\s*(?!&)\S")


# YAML to JSON, for each file: one Ruby for all of them, as it takes seconds to start on a busy Mac. A syntax error
# gives one line, with no path of this computer.
RUBY = ("out = {}; ARGV.each { |path| begin; out[path] = YAML.safe_load(File.read(path)); "
        "rescue Psych::SyntaxError => error; warn File.basename(path) + ': ' + error.message; exit 1; end }; "
        "puts JSON.generate(out)")
LOADED: Dict[str, dict] = {}


class Unreadable(Exception):
    pass


def preload(paths: List[Path]) -> None:
    wanted = [str(path) for path in paths if path.is_file() and str(path) not in LOADED]
    if not wanted:
        return
    try:
        converted = subprocess.run(["ruby", "-ryaml", "-rjson", "-e", RUBY, *wanted], capture_output=True, text=True)
    except FileNotFoundError:
        raise Unreadable("ruby is missing, and it reads the YAML of the workflow") from None
    if converted.returncode != 0:
        name, _, error = (converted.stderr.strip().splitlines() or ["?: no error"])[0].partition(": ")
        raise Unreadable(f"{name} is not YAML that Ruby reads: {error}")
    LOADED.update(json.loads(converted.stdout))


def load(path: Path) -> dict:
    preload([path])
    document = LOADED.get(str(path))
    if not isinstance(document, dict):
        raise Unreadable(f"{path.name} is missing, or is not a workflow")
    return document


def triggers(workflow: dict) -> List[str]:
    # YAML 1.1 reads the key on as true.
    on = workflow.get("on", workflow.get("true"))
    if isinstance(on, str):
        return [on]
    if isinstance(on, list):
        return [str(item) for item in on]
    return list(on or {})


def strings(node: object, path: Tuple = ()) -> Iterator[Tuple[Tuple, str]]:
    if isinstance(node, dict):
        for key, value in node.items():
            yield from strings(value, path + (key,))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from strings(value, path + (index,))
    elif isinstance(node, str):
        yield path, node


def where(path: Tuple) -> str:
    return ".".join(str(part) for part in path)


def jobs(workflow: dict) -> Dict[str, dict]:
    return {name: job for name, job in (workflow.get("jobs") or {}).items() if isinstance(job, dict)}


def steps(job: dict) -> List[dict]:
    return [step for step in job.get("steps") or [] if isinstance(step, dict)]


def environment(job: dict) -> str:
    value = job.get("environment")
    return value.get("name", "") if isinstance(value, dict) else str(value or "")


def needs(job: dict) -> List[str]:
    value = job.get("needs") or []
    return [value] if isinstance(value, str) else list(value)


def expressions(path: Tuple, text: str) -> List[str]:
    """The expressions of a value: each ${{ }}, or the whole value of an if:, which is one with no ${{ }}."""
    return [text] if path and path[-1] == "if" else EXPRESSION.findall(text)


def reads_secret(path: Tuple, text: str) -> bool:
    return any(ANY_SECRET.search(expression) for expression in expressions(path, text))


def secret_env(step: dict) -> Set[str]:
    return {name for name, value in (step.get("env") or {}).items()
            if isinstance(value, str) and reads_secret(("env", name), value)}


def uses_of(workflow: dict) -> List[Tuple[str, str]]:
    found = []
    for name, job in jobs(workflow).items():
        if "uses" in job:
            found.append((f"jobs.{name}", str(job["uses"])))
        for index, step in enumerate(steps(job)):
            if "uses" in step:
                found.append((f"jobs.{name}.steps.{index}", str(step["uses"])))
    return found


def secret_findings(workflow: dict) -> Tuple[List[str], Set[str]]:
    """A secret only in the env: or with: of a step; the jobs that hold one."""
    found, holders = [], set()
    for path, text in strings(workflow):
        if not reads_secret(path, text):
            continue
        if any(WHOLE_SECRETS.search(expression) for expression in expressions(path, text)):
            found.append(f"{where(path)} reads every secret at once: each secret goes by its name to the step that "
                         "uses it")
        in_step = len(path) == 6 and path[0] == "jobs" and path[2] == "steps" and path[4] in ("env", "with")
        if not in_step:
            found.append(f"{where(path)} names a secret outside the env: or with: of a step")
        if len(path) > 1 and path[0] == "jobs":
            holders.add(path[1])
    for name, job in jobs(workflow).items():
        if "secrets" in job:
            found.append(f"jobs.{name} passes secrets to a called workflow")
    return found, holders


def gate_findings(workflow: dict, holders: Set[str], root: Path) -> List[str]:
    found = []
    all_jobs = jobs(workflow)
    checks = {name for name, job in all_jobs.items() if job.get("uses") == CHECKS}
    for name in sorted(holders | {n for n, job in all_jobs.items() if job.get("environment")}):
        job = all_jobs.get(name, {})
        if environment(job) != ENVIRONMENT:
            found.append(f"jobs.{name} holds a secret or an environment, but does not wait at the environment "
                         f"{ENVIRONMENT}, whose reviewer approves each run")
        condition = re.sub(r"\s+", " ", str(job.get("if", "")))
        if MAIN not in condition or "||" in condition or re.search(r"\b(always|failure|cancelled)\(", condition):
            found.append(f"jobs.{name} has not only the if: {MAIN}: a run from another branch would reach it, "
                         "or it would run when the checks failed")
        seen, todo = set(), needs(job)
        while todo:
            need = todo.pop()
            if need not in seen:
                seen.add(need)
                todo.extend(needs(all_jobs.get(need, {})))
        if not seen & checks:
            found.append(f"jobs.{name} holds a secret but does not need the release checks ({CHECKS}), "
                         "which read the E2E proof first")
    if holders and checks:
        called = load(root / CHECKS)
        proof_jobs = [job for job in jobs(called).values() if job.get("uses") == PROOF]
        proof = load(root / PROOF)
        reads = any(PROOF_READ in str(step.get("run", "")) for job in jobs(proof).values() for step in steps(job))
        if not proof_jobs or not reads:
            found.append(f"{CHECKS} does not run the E2E proof ({PROOF}, which runs {PROOF_READ})")
    return found


def run_findings(workflow: dict) -> List[str]:
    found = []
    for name, job in jobs(workflow).items():
        for index, step in enumerate(steps(job)):
            run = str(step.get("run", ""))
            at = f"jobs.{name}.steps.{index}"
            if "${{" in run:
                found.append(f"{at} puts an expression in its run: (pass it through env:)")
            for pattern, reason in NEVER:
                if re.search(pattern, run, re.MULTILINE):
                    found.append(f"{at} {reason}")
            for line in run.splitlines():
                if "set-key-partition-list" in line and "> /dev/null" not in line:
                    found.append(f"{at} prints the keys of the keychain (security set-key-partition-list with no "
                                 "> /dev/null)")
            found.extend(f"{at} {problem}" for problem in printed_secrets(run, secret_env(step)))
            if "security create-keychain" in run:
                found.extend(f"{at} {problem}" for problem in keychain_problems(run))
    return found


def printed_secrets(run: str, names: Set[str]) -> List[str]:
    """A line that names a secret prints it only into a file, or masks it."""
    if not names:
        return []
    found = []
    lines = run.splitlines()
    names_of = lambda line: [n for n in names if re.search(rf"\$\{{?{n}\b", line)]
    index = 0
    while index < len(lines):
        line = lines[index]
        heredoc = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
        if heredoc:
            end = next((i for i in range(index + 1, len(lines)) if lines[i].strip() == heredoc.group(1)), len(lines))
            body = [n for body_line in lines[index + 1:end] for n in names_of(body_line)]
            if (body or names_of(line)) and (OUTPUTS.search(line) or not TO_FILE.search(line.split("<<")[0])):
                found.append(f"writes the secret {sorted(set(body))[0] if body else names_of(line)[0]} "
                             "with a here-document that does not go to a file")
            index = end + 1
            continue
        if line.strip() == "{":
            end = next((i for i in range(index + 1, len(lines)) if lines[i].strip().startswith("}")), len(lines) - 1)
            group = [n for group_line in lines[index + 1:end] for n in names_of(group_line)]
            closing = lines[end]
            if group and (OUTPUTS.search(closing) or not TO_FILE.search(closing)):
                found.append(f"prints the secret {group[0]} in a group that does not go to a file")
            index = end + 1
            continue
        named = names_of(line)
        if named:
            masked = "::add-mask::" in line
            if not masked and OUTPUTS.search(line):
                found.append(f"writes the secret {named[0]} where the log or a later step can read it")
            elif not masked and PRINTS.match(line) and not TO_FILE.search(line):
                found.append(f"prints the secret {named[0]}")
        index += 1
    for name in sorted(names & set(MASKED)):
        uses = [line for line in lines if re.search(rf"\$\{{?{name}\b", line)]
        if not uses or "::add-mask::" not in uses[0]:
            found.append(f"does not mask {name} before its first use")
    return found


def keychain_problems(run: str) -> List[str]:
    found = []
    password = re.search(r"^\s*(\w+)=\$\(openssl rand ", run, re.MULTILINE)
    if not password:
        return ["makes a keychain with no random password (openssl rand)"]
    name = password.group(1)
    mask = run.find(f"::add-mask::${name}")
    if mask < 0 or mask > run.find("security create-keychain"):
        found.append("does not mask the password of the keychain before it makes the keychain")
    if not re.search(rf"security create-keychain -p \"\${name}\" \"\$(keychain|RUNNER_TEMP)", run) or \
            not re.search(r"^\s*keychain=\"\$RUNNER_TEMP/", run, re.MULTILINE):
        found.append("makes the keychain outside RUNNER_TEMP, or with another password")
    return found


def cleanup_findings(workflow: dict) -> List[str]:
    found = []
    for name, job in jobs(workflow).items():
        runs = [step for step in steps(job) if "security create-keychain" in str(step.get("run", ""))]
        deletes = [step for step in steps(job) if "security delete-keychain" in str(step.get("run", ""))
                   and "always()" in str(step.get("if", ""))]
        if runs and not deletes:
            found.append(f"jobs.{name} does not delete its keychain in a step with if: always()")
    return found


def called_workflows(workflow: dict, root: Path, seen: Set[str]) -> Iterator[Tuple[str, dict]]:
    for _, uses in uses_of(workflow):
        if uses.startswith("./.github/workflows/") and uses not in seen:
            seen.add(uses)
            called = load(root / uses)
            yield uses, called
            yield from called_workflows(called, root, seen)


def supply_findings(name: str, workflow: dict) -> List[str]:
    found = []
    for at, uses in uses_of(workflow):
        if re.match(r"^actions/(upload-artifact|cache)\b", uses):
            found.append(f"{name}: {at} uses {uses.split('@')[0]}: the archive and the .ipa are never an artifact "
                         "nor a cache")
        elif not uses.startswith("./") and not PINNED.match(uses):
            found.append(f"{name}: {at} uses {uses}, which is not pinned to a full commit hash")
    return found


def check(path: Path) -> Tuple[List[str], str]:
    root = path.resolve().parents[2]
    preload([path, root / CHECKS, root / PROOF])
    workflow = load(path)
    found = []
    for trigger in triggers(workflow):
        if trigger.startswith("pull_request") or trigger == "workflow_run":
            found.append(f"on: {trigger} runs the workflow for code that is not on main")
    concurrency = workflow.get("concurrency")
    if not isinstance(concurrency, dict) or concurrency.get("group") != GROUP \
            or concurrency.get("cancel-in-progress") is not False:
        found.append(f"the workflow does not share the concurrency group {GROUP} with cancel-in-progress: false")
    secrets, holders = secret_findings(workflow)
    found.extend(secrets)
    if not holders:
        found.append("no job holds a secret: this is not the release workflow")
    found.extend(gate_findings(workflow, holders, root))
    found.extend(run_findings(workflow))
    found.extend(cleanup_findings(workflow))
    if "E2E: proven at merge" not in path.read_text():
        found.append("the summary does not say 'E2E: proven at merge'")
    found = [f"{path.name}: {problem}" for problem in found]
    found.extend(supply_findings(path.name, workflow))
    called = list(called_workflows(workflow, root, set()))
    for name, other in called:
        found.extend(supply_findings(Path(name).name, other))
    pinned = sum(1 for _, w in [("", workflow)] + called for _, uses in uses_of(w) if not uses.startswith("./"))
    names = {m.group(1) for _, text in strings(workflow) for m in SECRET.finditer(text)}
    summary = (f"{len(names)} secrets, in {len(holders)} job behind the environment {ENVIRONMENT} on main, "
               f"after the E2E proof; {pinned} actions pinned in it and the {len(called)} workflows that it calls")
    return found, summary


def main(argv: List[str]) -> int:
    if len(argv) != 1:
        print(USAGE, file=sys.stderr)
        return 2
    path = Path(argv[0])
    try:
        found, summary = check(path)
    except (Unreadable, OSError) as error:
        print(f"release-workflow-check: FAILED: {error}", file=sys.stderr)
        return 1
    for problem in found:
        print(f"release-workflow-check: {problem}", file=sys.stderr)
    if found:
        print(f"release-workflow-check: FAILED ({len(found)} problems; the rules: .claude/rules/github.md)",
              file=sys.stderr)
        return 1
    print(f"release-workflow-check: OK ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
