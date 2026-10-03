#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$tests/.." && pwd)
state=$(mktemp -d)
repo="$state/repo"
failures=0
trap 'rm -rf "$state"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE || true

expect() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

reset_repo() {
    rm -rf "$repo"
    git init -q "$repo"
    mkdir -p "$repo/ios/scripts/tests" "$repo/docs" "$repo/.claude/rules"
}

file() {
    mkdir -p "$(dirname "$repo/$1")"
    printf '%s\n' "$2" > "$repo/$1"
    git -C "$repo" add "$1"
}

check() {
    (cd "$repo/docs" && "$scripts/public-text-check.py") > "$state/out" 2>&1 && echo "passes" || echo "fails"
}

hit() {
    grep -c "^public-text-check: $1$" "$state/out" || true
}

reset_repo
file docs/page.mdx "The Simulator runs one job at a time, so a second job waits for the lock."
file ios/App/Location.swift "    private let manager = CLLocationManager()"
file ios/App/Agent.swift "request.setValue(\"TROME\", forHTTPHeaderField: \"User-Agent\") // a user agent"
file ios/package.json "\"micromark-factory-space\": \"^2.0.0\", \"package-manager-detector\": \"^1.6.0\""
file ios/scripts/tests/git-test.sh "export GIT_AUTHOR_EMAIL=test@example.com OTHER=jane@mail.example ALSO=ci@build.test"
file ios/scripts/tests/cache-test.sh "[ -f \"\$cache/users/\$build\" ]"
file ios/App/Bundle.swift "let id = \"io.github.trome\"; let task = Task { }; let decision = \"doc\""
file ios/project.yml "name: TROME; packages: TROMECore; RATP_DEBUG_APP_BUNDLE_ID; RATP_SIM_SLOT; /tmp/ratp-sim.lock; the RATP network; RATP-Shared; git clone https://github.com/owner/ratp-activity-ios"
file README.md "The shared build cache is in ~/Library/Caches/RATPActivity/."
file ios/App/Assets.xcassets/AppIcon.appiconset/Contents.json "{ \"filename\" : \"AppIcon@2x.png\" }, { \"filename\" : \"AppIcon@3x.png\" } git clone git@github.com:owner/trome.git"
expect "a public text with no internal word, no personal data and no local path passes" "$(check)" "passes"
expect "it says how many files it checked" "$(grep -c "OK (10 files" "$state/out")" "1"

reset_repo
file docs/page.mdx "Wait: the factory agents use the Simulator (TASK-140, decision-15, doc-3)."
file ios/scripts/merge.sh "echo \"The manager asks the prompter.\""
file ios/scripts/lock.sh "echo \"an agent took it\"; echo \"the Prompters decide\""
file docs/help.md "Write to jane.doe@company.fr. Built in /Users/jane/repo.
Or to legit@github.com."
expect "a public text with internal words, personal data or a local path fails" "$(check)" "fails"
expect "it names the file, the line and a backlog id" "$(hit 'docs/page.mdx:1: a backlog id: "TASK-140"')" "1"
expect "it finds a decision id" "$(hit 'docs/page.mdx:1: a backlog id: "decision-15"')" "1"
expect "it finds a doc id" "$(hit 'docs/page.mdx:1: a backlog id: "doc-3"')" "1"
expect "it finds the word factory" "$(hit "docs/page.mdx:1: a word of the team's own process: \"factory\"")" "1"
expect "it finds the word agents" "$(hit "docs/page.mdx:1: a word of the team's own process: \"agents\"")" "1"
expect "it finds the word agent" "$(hit "ios/scripts/lock.sh:1: a word of the team's own process: \"agent\"")" "1"
expect "it finds the manager" "$(hit "ios/scripts/merge.sh:1: a word of the team's own process: \"The manager\"")" "1"
expect "it finds the word prompter" "$(hit "ios/scripts/merge.sh:1: a word of the team's own process: \"prompter\"")" "1"
expect "it finds the word prompters, in any case" "$(hit "ios/scripts/lock.sh:1: a word of the team's own process: \"Prompters\"")" "1"
expect "it finds a real email address" "$(hit 'docs/help.md:1: an email address: "jane.doe@company.fr"')" "1"
expect "it finds an email address of a git host that is not its SSH user" "$(hit 'docs/help.md:2: an email address: "legit@github.com"')" "1"
expect "it finds a local path" "$(hit 'docs/help.md:1: a local path: "/Users/"')" "1"
expect "it says what to write instead" "$(grep -c "write the rule and its reason instead" "$state/out")" "1"
expect "it says how to allow a word" "$(grep -c "add it to ALLOWED_TEXTS in ios/scripts/public-text-check.py" "$state/out")" "1"

reset_repo
file CLAUDE.md "Read decision-9 (TASK-44). The prompter decides; the agents wait for the manager."
file .claude/rules/merge.md "The factory merges one task at a time (TASK-159)."
file README.md "See TASK-173 and decision-15."
expect "CLAUDE.md, .claude/ and, for now, README.md may cite the backlog and its words" "$(check)" "passes"
expect "it says which files it checks only for personal data, and why" \
    "$(grep -c "checks only personal data, local paths and the old app name in" "$state/out")" "3"

file CLAUDE.md "Ask jane.doe@company.fr, or look in /Users/jane/repo."
file .claude/rules/merge.md "Logs go to /Users/jane/logs."
expect "CLAUDE.md and .claude/ still fail on personal data and local paths" "$(check)" "fails"
expect "it finds the email address of CLAUDE.md" "$(hit 'CLAUDE.md:1: an email address: "jane.doe@company.fr"')" "1"
expect "it finds the local path of CLAUDE.md" "$(hit 'CLAUDE.md:1: a local path: "/Users/"')" "1"
expect "it finds the local path of .claude/" "$(hit '.claude/rules/merge.md:1: a local path: "/Users/"')" "1"

reset_repo
file README.md "# RATP Activity"
file docs/page.mdx "Open Settings > Apps > RATP&nbsp;Activity."
file ios/App/InfoPlist.xcstrings "\"value\" : \"Ratp  activité\""
expect "the old name of the app fails in every file, the README too" "$(check)" "fails"
expect "it finds the old name in the README" "$(hit 'README.md:1: the old name of the app: "RATP Activit"')" "1"
expect "it finds the old name with a no-break space" "$(hit 'docs/page.mdx:1: the old name of the app: "RATP&nbsp;Activit"')" "1"
expect "it finds the old name in any case and spacing" "$(hit 'ios/App/InfoPlist.xcstrings:1: the old name of the app: "Ratp  activit"')" "1"
expect "it says the new name" "$(grep -c "not the old names of the app, of the Xcode project or of its module (it is TROME)" "$state/out")" "1"

reset_repo
file README.md "Open ios/RATPActivity.xcodeproj."
file CLAUDE.md "The composition root is ratpactivityApp.swift."
file ios/scripts/merge.sh "scheme=RATPActivityE2E"
file ios/App/Model.swift "import RATPCore"
file ios/scripts/simulator.sh "pattern='RATPActivity(RenderCheckHost)?'"
file ios/scripts/tests/sim-lock-test.sh "printf '%s\\n' com.example.RATPActivity"
file ios/Makefile "OLD_PROJECT := RATPActivity.xcodeproj"
expect "the old names of the project and of its module fail in every file, except where a leftover of the old name is removed" "$(check)" "fails"
expect "it finds the old project name in the README" "$(hit 'README.md:1: an old name of the project or of its module: "RATPActivity"')" "1"
expect "it finds the old project name in any case, in CLAUDE.md too" "$(hit 'CLAUDE.md:1: an old name of the project or of its module: "ratpactivity"')" "1"
expect "it finds the old project name inside a longer name" "$(hit 'ios/scripts/merge.sh:1: an old name of the project or of its module: "RATPActivity"')" "1"
expect "it finds the old name of the module" "$(hit 'ios/App/Model.swift:1: an old name of the project or of its module: "RATPCore"')" "1"
expect "it lets the Simulator script, its test and the Makefile name the old project, to remove its leftovers" \
    "$(grep -c "simulator.sh\|sim-lock-test.sh\|Makefile" "$state/out")" "0"

reset_repo
file ios/scripts/public-text-check.py "INTERNAL_RULES = [\"prompter\", \"/Users/\"]"
file ios/scripts/tests/public-text-check-test.sh "file docs/page.mdx \"TASK-140\""
printf 'The factory, /Users/jane.\n' > "$repo/docs/draft.md"
printf 'TASK-1\0binary\n' > "$repo/docs/image.png"
git -C "$repo" add docs/image.png
expect "it skips its own word list and examples, the files that git does not track, and binary files" "$(check)" "passes"
expect "it says which files it skips, and why" "$(grep -c "skips ios/scripts/public-text-check.py: it holds the word list" "$state/out")" "1"

mkdir "$state/allowing"
cp "$scripts/public-text-check.py" "$scripts/repo_files.py" "$state/allowing/"
sed -i '' 's|^ALLOWED_TEXTS: list\[Allowed\] = \[$|ALLOWED_TEXTS: list[Allowed] = [Allowed("ios/App/Factory.swift", "factory", "the name of a type"),|' \
    "$state/allowing/public-text-check.py"
reset_repo
file ios/App/Factory.swift "let factory = StationFactory()"
file ios/App/Other.swift "let factory = StationFactory()"
(cd "$repo" && "$state/allowing/public-text-check.py") > "$state/out" 2>&1 && result="passes" || result="fails"
expect "a text of ALLOWED_TEXTS passes in its own file only" "$result $(hit "ios/App/Other.swift:1: a word of the team's own process: \"factory\"") \
$(grep -c "Factory.swift" "$state/out")" "fails 1 0"

(cd "$state" && "$scripts/public-text-check.py") > /dev/null 2>&1 && result="passes" || result="fails"
expect "outside a git repo, it fails" "$result" "fails"

(cd "$repo" && "$scripts/public-text-check.py" docs/page.mdx) > /dev/null 2>&1 && result="passes" || result="fails"
expect "a file named on the command line fails: it always checks the whole repo" "$result" "fails"

[ "$failures" -eq 0 ]
