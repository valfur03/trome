#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$tests/../../.." && pwd)
hook="$root/.claude/hooks/rules.py"
state=$(mktemp -d)
failures=0
trap 'rm -rf "$state"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

project="$state/main"
worktree="$state/worktree-1"
mkdir -p "$project/.git" "$project/ios/App" "$worktree/.git" "$worktree/ios/App" "$worktree/docs/src/content" "$worktree/server/src"
cp -R "$root/.claude" "$project/.claude"
echo "let x = 1" > "$project/ios/App/X.swift"
echo "let x = 1" > "$worktree/ios/App/X.swift"
echo "A page." > "$worktree/docs/page.mdx"
echo "A Help page." > "$worktree/docs/src/content/support.mdx"

run() {
    printf '%s' "$1" | CLAUDE_PROJECT_DIR="$project" TMPDIR="$state" python3 "$hook" > "$state/out"
    cat "$state/out"
}

event() {
    python3 -c 'import json, sys; print(json.dumps(dict(json.loads(sys.argv[1]), session_id=sys.argv[2])))' "$1" "${2:-s1}"
}

delivered() {
    python3 -c '
import json, re, sys
text = sys.stdin.read()
if not text.strip():
    print("none"); sys.exit()
out = json.loads(text)["hookSpecificOutput"]
kind = "deny" if out.get("permissionDecision") == "deny" else "context"
body = out.get("permissionDecisionReason") or out.get("additionalContext")
print(kind, " ".join(re.findall(r"^# \.claude/rules/([a-z-]+)\.md$", body, re.M)))'
}

read_event() { event "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$1\"}${2:-}}" "${3:-s1}"; }
bash_event() { event "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}${2:-}}" "${3:-s1}"; }

expect "a read of an app file of another worktree brings the rules of its paths, next to the output" \
    "$(run "$(read_event "$worktree/ios/App/X.swift")" | delivered)" "context assets ios-code tests"
expect "the same rules do not come twice in one session" \
    "$(run "$(read_event "$worktree/ios/App/X.swift")" | delivered)" "none"
expect "another subagent of the same session gets them again" \
    "$(run "$(read_event "$worktree/ios/App/X.swift" ',"agent_id":"a2"')" | delivered)" "context assets ios-code tests"
expect "a read in the folder of the session is left to Claude Code, which loads its paths rules itself" \
    "$(run "$(read_event "$project/ios/App/X.swift" '' s2)" | delivered)" "none"

write_event=$(event "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$worktree/docs/new.mdx\",\"content\":\"x\"}}" s3)
expect "a first write in another worktree is stopped once, with the rules of its paths" \
    "$(run "$write_event" | delivered)" "deny docs-site writing"
expect "the same write again goes through" "$(run "$write_event" | delivered)" "none"

e2e=$(bash_event "cd $worktree && make e2e ONLY=\"SnoozeTests LiveActivityTests\"" '' s4)
expect "a Simulator job is stopped once, with the rules of its command" "$(run "$e2e" | delivered)" "deny simulator tests"
expect "the same command again goes through" "$(run "$e2e" | delivered)" "none"
expect "make -C and a variable bring the rules of each command" \
    "$(run "$(bash_event "make -C $worktree run LIVE=1 LANGUAGE=fr" '' s5)" | delivered)" "deny assets live-data qa simulator"
expect "make merge after cd brings the merge and Simulator rules" \
    "$(run "$(bash_event "cd $worktree && make merge" '' s6)" | delivered)" "deny merge simulator"
expect "a docs command through fnm exec brings the docs rules" \
    "$(run "$(bash_event 'fnm exec --using=.nvmrc -- make docs-check' '' s6b)" | delivered)" "deny docs-site"
expect "a server command through fnm exec, with a separate version, brings the server rules" \
    "$(run "$(bash_event 'fnm exec --using .nvmrc make server-check' '' s6c)" | delivered)" "deny server"
expect "git -C rebase brings the merge rules" \
    "$(run "$(bash_event "git -C $worktree rebase main" '' s7)" | delivered)" "deny merge"
expect "a command that only names make e2e or a rebase in a quoted text brings nothing" \
    "$(run "$(bash_event 'git commit -m "run make e2e before the rebase"' '' s8)" | delivered)" "none"
expect "a command through the Simulator lock brings the Simulator rules" \
    "$(run "$(bash_event 'ios/scripts/sim-lock.sh job ios/scripts/simulator.sh reset xcrun simctl list' '' s9)" | delivered)" "deny simulator"
expect "a server command brings the server rules" \
    "$(run "$(bash_event 'make server-dev' '' s10)" | delivered)" "deny server"
expect "a variable before make, that make reads from the environment, brings its rules" \
    "$(run "$(bash_event 'LIVE=1 make run' '' s15)" | delivered)" "deny assets live-data qa simulator"
expect "make merge behind caffeinate and its options brings its rules" \
    "$(run "$(bash_event 'caffeinate -i make merge' '' s16)" | delivered)" "deny merge simulator"
expect "make e2e behind timeout and its duration brings its rules" \
    "$(run "$(bash_event 'timeout 900 make e2e' '' s17)" | delivered)" "deny simulator tests"
expect "make e2e behind nice brings its rules" \
    "$(run "$(bash_event 'nice make e2e' '' s18)" | delivered)" "deny simulator tests"
expect "make e2e in the script of bash -c brings its rules" \
    "$(run "$(bash_event "bash -c 'make e2e'" '' s19)" | delivered)" "deny simulator tests"
expect "xcrun with an option before simctl brings the Simulator rules" \
    "$(run "$(bash_event 'xcrun --sdk iphonesimulator simctl list' '' s20)" | delivered)" "deny simulator"
expect "git pull --rebase brings the merge rules" \
    "$(run "$(bash_event 'git pull --rebase' '' s21)" | delivered)" "deny merge"
expect "a stop says first that it is not a refusal" \
    "$(run "$(bash_event 'make e2e' '' s22)" | python3 -c 'import json, sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"].startswith("This is not a refusal."))')" "True"

diff_output=$(python3 -c 'import json; print(json.dumps({"stdout": "diff --git a/server/src/core/x.ts b/server/src/core/x.ts\n+++ b/server/src/core/x.ts\n", "stderr": ""}))')
post="{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git diff main\"},\"tool_response\":$diff_output,\"cwd\":\"$worktree\"}"
expect "a diff in the output of a command brings the rules of its files" "$(run "$(event "$post" s11)" | delivered)" "context server"
post="{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -n 1,5p $worktree/docs/page.mdx\"},\"tool_response\":{\"stdout\":\"A page.\"},\"cwd\":\"$project\"}"
expect "a command that reads a file brings the rules of that file" "$(run "$(event "$post" s12)" | delivered)" "context docs-site writing"
expect "a page of the docs site, which an asset of the app is, brings the assets rules" \
    "$(run "$(read_event "$worktree/docs/src/content/support.mdx" '' s23)" | delivered)" "context assets docs-site writing"
expect "make run, which QA runs, brings the assets rules" \
    "$(run "$(bash_event 'make run LANGUAGE=fr' '' s24)" | delivered)" "deny assets qa simulator"

qa_subagent=$(event '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"qa-tester","prompt":"QA of a task"}}' s13)
expect "the start of a QA subagent is stopped once, with the live data rules" "$(run "$qa_subagent" | delivered)" "deny live-data"
expect "the start of another subagent brings nothing" \
    "$(run "$(event '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"software-engineer"}}' s13)" | delivered)" "none"

run "$(bash_event 'make e2e' '' s14)" > /dev/null
run "$(event '{"hook_event_name":"SessionStart","source":"compact"}' s14)" > /dev/null
expect "after a compact, the rules come again" "$(run "$(bash_event 'make e2e' '' s14)" | delivered)" "deny simulator tests"

printf 'not json' | CLAUDE_PROJECT_DIR="$project" TMPDIR="$state" python3 "$hook" > /dev/null 2>&1 && result="blocks" || result="fails"
expect "a hook that cannot read its input fails with a message, and blocks nothing" "$result" "fails"

ruby -ryaml -e '
bad = []
Dir[ARGV[0] + "/.claude/rules/**/*.md"].each do |path|
  text = File.read(path, encoding: "UTF-8")
  match = text.match(/\A---\n(.*?)\n---\n/m)
  front = (match && YAML.safe_load(match[1]) rescue nil)
  ok = front.is_a?(Hash) && front["paths"].is_a?(Array) && !front["paths"].empty?
  bad << File.basename(path) unless ok
end
puts bad.empty? ? "valid" : bad.join(" ")' "$root" > "$state/yaml"
expect "every rule file has front matter that YAML reads, with a paths list (with none, Claude Code loads it in every session)" \
    "$(cat "$state/yaml")" "valid"

expect "CLAUDE.md, which every session loads, stays at 200 lines at most" "$([ "$(wc -l < "$root/CLAUDE.md")" -le 200 ] && echo yes || echo no)" "yes"
expect "CLAUDE.md stays at 12,000 bytes at most" "$([ "$(wc -c < "$root/CLAUDE.md")" -le 12000 ] && echo yes || echo no)" "yes"

[ "$failures" -eq 0 ]
