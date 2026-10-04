#!/usr/bin/env python3
import json
import os
import re
import shlex
import sys
import tempfile

EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
AGENT_TOOLS = {"Agent", "Task"}
COMMAND_PREFIXES = {"command", "exec", "nohup", "time", "env"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DIFF_PATH = re.compile(r"^(?:diff --git a/\S+ b/|\+\+\+ b/|--- a/)(\S+)", re.MULTILINE)


def glob_to_regex(pattern):
    out = ""
    i = 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile(out + r"\Z")


def expand_braces(pattern):
    match = re.search(r"\{([^{}]*)\}", pattern)
    if not match:
        return [pattern]
    head, tail = pattern[: match.start()], pattern[match.end():]
    return [p for option in match.group(1).split(",") for p in expand_braces(head + option + tail)]


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return json.loads(value)
    return value


def parse_rule(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    fields = {"paths": [], "commands": [], "agents": []}
    body = text
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            key = None
            for line in text[4:end].splitlines():
                item = re.match(r"^\s+-\s+(.*)$", line)
                if item and key in fields:
                    fields[key].append(unquote(item.group(1)))
                    continue
                pair = re.match(r"^([A-Za-z_]+):\s*$", line)
                key = pair.group(1) if pair else None
            body = text[end + 5:]
    return {
        "globs": [glob_to_regex(g) for p in fields["paths"] for g in expand_braces(p)],
        "commands": [re.compile(c) for c in fields["commands"]],
        "agents": [re.compile(a) for a in fields["agents"]],
        "body": body.strip(),
    }


def load_rules(project_dir):
    root = os.path.join(project_dir, ".claude", "rules")
    rules = {}
    for folder, _, files in os.walk(root):
        for name in sorted(files):
            if name.endswith(".md"):
                path = os.path.join(folder, name)
                rules[os.path.relpath(path, project_dir)] = parse_rule(path)
    return rules


def repo_root(path):
    folder = path if os.path.isdir(path) else os.path.dirname(path)
    while True:
        if os.path.exists(os.path.join(folder, ".git")):
            return folder
        parent = os.path.dirname(folder)
        if parent == folder:
            return None
        folder = parent


def rules_for_path(rules, relative):
    if not relative or relative.startswith(".."):
        return set()
    return {name for name, rule in rules.items() if any(g.match(relative) for g in rule["globs"])}


def rules_for_file(rules, path):
    root = repo_root(path)
    if root is None:
        return set()
    relative = os.path.relpath(path, root)
    if os.path.isdir(path):
        relative = "" if relative == "." else relative + "/x"
    return rules_for_path(rules, relative)


def simple_commands(command):
    for line in command.splitlines():
        try:
            lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
            lexer.whitespace_split = True
            tokens = list(lexer)
        except ValueError:
            tokens = line.split()
        words = []
        for token in tokens + [";"]:
            if token and set(token) <= set(";&|()<>"):
                if words:
                    yield words
                words = []
            else:
                words.append(token)


def command_words(words):
    while words and (ASSIGNMENT.match(words[0]) or words[0] in COMMAND_PREFIXES):
        words = words[1:]
    return words


def rules_for_command(rules, command):
    found = set()
    for words in simple_commands(command):
        line = " ".join(command_words(words))
        found |= {name for name, rule in rules.items() if any(c.search(line) for c in rule["commands"])}
    return found


def rules_for_command_files(rules, command, cwd):
    found = set()
    for words in simple_commands(command):
        for word in command_words(words)[1:]:
            if word.startswith("-") or "=" in word:
                continue
            path = os.path.normpath(os.path.join(cwd, os.path.expanduser(word)))
            if os.path.exists(path):
                found |= rules_for_file(rules, path)
    return found


def store(event):
    folder = os.path.join(tempfile.gettempdir(), "claude-rules-%d" % os.getuid(), event.get("session_id", "none"))
    return folder, os.path.join(folder, event.get("agent_id") or "main")


def delivered(event):
    try:
        with open(store(event)[1], encoding="utf-8") as handle:
            return set(handle.read().split())
    except FileNotFoundError:
        return set()


def mark(event, names):
    folder, path = store(event)
    os.makedirs(folder, exist_ok=True)
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("".join(name + "\n" for name in sorted(names)))


def text_of(rules, names):
    return "\n\n".join("# %s\n\n%s" % (name, rules[name]["body"]) for name in sorted(names))


def deliver(event, rules, names):
    names = set(names) - delivered(event)
    if names:
        mark(event, names)
    return names


def is_in_project(path, project_dir):
    root = repo_root(path)
    return root is not None and os.path.realpath(root) == os.path.realpath(project_dir)


def respond(event_name, context=None, deny=None):
    output = {"hookEventName": event_name}
    if deny:
        output["permissionDecision"] = "deny"
        output["permissionDecisionReason"] = deny
    if context:
        output["additionalContext"] = context
    print(json.dumps({"hookSpecificOutput": output}))


def handle(event, project_dir):
    name = event.get("hook_event_name")
    rules = load_rules(project_dir)
    if name == "SessionStart":
        folder = store(event)[0]
        if os.path.isdir(folder):
            for entry in os.listdir(folder):
                os.remove(os.path.join(folder, entry))
        return
    tool = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    if name == "PreToolUse" and tool == "Bash":
        names = deliver(event, rules, rules_for_command(rules, tool_input.get("command", "")))
        if names:
            respond(name, deny="This repo has rules for this command, and you have not read them yet in this session. "
                    "Read them now, then run the same command again: it will not be stopped twice.\n\n"
                    + text_of(rules, names))
        return
    if name == "PreToolUse" and tool in AGENT_TOOLS:
        kind = tool_input.get("subagent_type") or ""
        found = {n for n, rule in rules.items() if any(a.search(kind) for a in rule["agents"])}
        names = deliver(event, rules, found)
        if names:
            respond(name, deny="This repo has rules for the agent that you start, and you have not read them yet in this session. "
                    "Read them now, then start the agent again: it will not be stopped twice.\n\n" + text_of(rules, names))
        return
    if name == "PostToolUse" and tool == "Bash":
        response = event.get("tool_response")
        output = json.dumps(response) if not isinstance(response, str) else response
        if isinstance(response, dict):
            output = "%s\n%s" % (response.get("stdout", ""), response.get("stderr", ""))
        found = {n for match in DIFF_PATH.findall(output) for n in rules_for_path(rules, match)}
        found |= rules_for_command_files(rules, tool_input.get("command", ""), event.get("cwd") or project_dir)
        names = deliver(event, rules, found)
        if names:
            respond(name, context="The files of this command have rules in this repo. Follow them:\n\n" + text_of(rules, names))
        return
    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if name != "PreToolUse" or not path or is_in_project(path, project_dir):
        return
    names = deliver(event, rules, rules_for_file(rules, path))
    if not names:
        return
    if tool in EDIT_TOOLS:
        respond(name, deny="This file has rules in this repo, and you have not read them yet in this session. "
                "Read them now, then make the same change again: it will not be stopped twice.\n\n" + text_of(rules, names))
    else:
        respond(name, context="This file has rules in this repo. Follow them:\n\n" + text_of(rules, names))


def main():
    event = json.load(sys.stdin)
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or event.get("cwd") or os.getcwd()
    handle(event, project_dir)


if __name__ == "__main__":
    main()
