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
file ios/project.yml "name: TROME; packages: TROMECore; TROME_DEBUG_APP_BUNDLE_ID; RATP_SIM_SLOT; RATP_MERGE_LOCK; /tmp/ratp-sim.lock; the RATP network; RATP-Shared; git clone https://github.com/owner/ratp-activity-ios"
file README.md "The shared build cache is in ~/Library/Caches/TROME/. The trains of RATP-SIV and RATP.OCTAVE."
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
file docs/contact.ts "export const contactEmail = 'contact@trome.valfur.fr';"
file CLAUDE.md "Write to contact@trome.valfur.fr."
expect "the public contact address of the project passes, in any file" "$(check)" "passes"

file docs/help.md "Write to other@trome.valfur.fr or to support@trome.valfur.fr or to xcontact@trome.valfur.fr or to contact@trome.valfur.fr.example.fr."
expect "any other address on the domain of the project still fails" "$(check)" "fails"
expect "it finds another address of the domain" "$(hit 'docs/help.md:1: an email address: "other@trome.valfur.fr"')" "1"
expect "it finds the old contact address" "$(hit 'docs/help.md:1: an email address: "support@trome.valfur.fr"')" "1"
expect "it finds an address that only ends like the contact address" "$(hit 'docs/help.md:1: an email address: "xcontact@trome.valfur.fr"')" "1"
expect "it finds an address that only starts like the contact address" "$(hit 'docs/help.md:1: an email address: "contact@trome.valfur.fr.example.fr"')" "1"

reset_repo
file CLAUDE.md "Read decision-9 (TASK-44). The prompter decides; the agents wait for the manager."
file .claude/rules/merge.md "The factory merges one task at a time (TASK-159)."
expect "CLAUDE.md and .claude/ may cite the backlog and its words" "$(check)" "passes"
expect "a pass prints only its OK line, with no notice of the files that it checks only in part" "$(wc -l < "$state/out" | tr -d ' ') $(grep -c "^public-text-check: OK" "$state/out")" "1 1"
expect "with VERBOSE=1, it says which files it checks only for personal data, and why" \
    "$(VERBOSE=1 check > /dev/null; grep -c "checks only personal data, local paths and the old app name in" "$state/out")" "2"

file ios/README.md "See TASK-173 and decision-15."
expect "ios/README.md, rewritten for developers, may not cite the backlog" "$(check)" "fails"
expect "it finds the backlog id of ios/README.md" "$(hit 'ios/README.md:1: a backlog id: "TASK-173"')" "1"
rm "$repo/ios/README.md"
git -C "$repo" rm -q --cached ios/README.md

file server/README.md "The prompter decides (decision-40)."
expect "server/README.md, rewritten for developers, may not cite the backlog" "$(check)" "fails"
expect "a failure says which files it checks only for personal data" \
    "$(grep -c "checks only personal data, local paths and the old app name in" "$state/out")" "2"
expect "it finds the backlog id of server/README.md" "$(hit 'server/README.md:1: a backlog id: "decision-40"')" "1"
rm "$repo/server/README.md"
git -C "$repo" rm -q --cached server/README.md

file README.md "See TASK-173: the factory decides."
expect "the front page README.md may not cite the backlog" "$(check)" "fails"
expect "it finds the backlog id of the front page" "$(hit 'README.md:1: a backlog id: "TASK-173"')" "1"
expect "it finds the word of the team in the front page" "$(hit "README.md:1: a word of the team's own process: \"factory\"")" "1"

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
file README.md "Set RATP_BUNDLE_ID_PREFIX, then RATP_SHARED_CACHE=/tmp/cache make build."
file CLAUDE.md "The build cache is in ~/Library/Caches/RATPActivity/."
file docs/src/components/Checklist.astro "const key = \`ratp-docs-checklist:\${id}\`;"
file ios/project.yml "RATP_WANTED_APP_ID: \$(RATP_REFUSED_ID_x)"
file ios/scripts/merge.sh "check=\${RATP_MERGE_CHECK:-make check} e2e=\${RATP_MERGE_E2E:-make e2e}"
file ios/scripts/simulator.sh "\${RATP_SPRINGBOARD_WAIT_SECONDS:-60} \${RATP_WIDGET_HOST_WAIT_SECONDS:-240}"
file ios/scripts/old-setting-names.sh "old_names=\"RATP_BUNDLE_ID_PREFIX RATP_DEBUG_APP_BUNDLE_ID RATP_DEBUG_WIDGET_BUNDLE_ID\""
file ios/scripts/tests/git-hooks-test.sh "printf 'RATP_DEBUG_APP_BUNDLE_ID = x'"
expect "the old names of the settings, of the tool variables, of the cache folder and of the docs key fail, except in the refusal and its tests" "$(check)" "fails"
expect "it finds an old setting name in the README" "$(hit 'README.md:1: an old name of a build setting or of a variable of the tools: "RATP_BUNDLE_ID_PREFIX"')" "1"
expect "it finds an old variable of the tools" "$(hit 'README.md:1: an old name of a build setting or of a variable of the tools: "RATP_SHARED_CACHE"')" "1"
expect "it finds the old cache folder, once" "$(grep -c "CLAUDE.md:1:" "$state/out") $(hit 'CLAUDE.md:1: the old folder of the shared build cache: "Caches/RATPActivity"')" "1 1"
expect "it finds the old key of the docs site" "$(hit 'docs/src/components/Checklist.astro:1: an old key of the docs site: "ratp-docs-checklist"')" "1"
expect "it finds the old helper settings of the project, outside the refusal" "$(grep -c "^public-text-check: ios/project.yml:1:" "$state/out")" "2"
expect "it finds the old variables of merge and of the Simulator script" "$(grep -c "merge.sh:1:\|simulator.sh:1:" "$state/out")" "4"
expect "it lets the refusal and its tests name the old setting names" "$(grep -c "old-setting-names.sh\|git-hooks-test.sh" "$state/out")" "0"

voice="a word of a team's voice (one person speaks: say I, or je in French)"

reset_repo
file docs/en/about.mdx "---
title: Our app
description: \"We made it\"
---
## Our server
We run it, so let us know; Let's talk, Let’s go. It is ours, made by ourselves.
<Screenshot alt=\"We show the lock screen\" />"
file docs/fr/aide.mdx "Nous écrivons notre page pour nos usagers : la nôtre, les nôtres.
Ce que nous faisons nous-mêmes. Contactez-nous ! Écrivez-nous."
file CLAUDE.md "Us too: we decide."
file docs/en/apostrophe.md "A straight single quote is also an apostrophe, so 'we' is the page's own word."
expect "a team's voice in the prose of a Markdown or MDX file fails, in English and in French, CLAUDE.md included" "$(check)" "fails"
expect "it finds we, with the file, the line and the reason" "$(hit "docs/en/about.mdx:6: $voice: \"We\"")" "1"
expect "it finds our in a heading and in the front matter, quoted or not" \
    "$(hit "docs/en/about.mdx:5: $voice: \"Our\"") $(hit "docs/en/about.mdx:2: $voice: \"Our\"") $(hit "docs/en/about.mdx:3: $voice: \"We\"")" "1 1 1"
expect "it finds let us, let's with both apostrophes, ours and ourselves" \
    "$(hit "docs/en/about.mdx:6: $voice: \"us\"") $(hit "docs/en/about.mdx:6: $voice: \"Let's\"") $(hit "docs/en/about.mdx:6: $voice: \"Let’s\"") $(hit "docs/en/about.mdx:6: $voice: \"ours\"") $(hit "docs/en/about.mdx:6: $voice: \"ourselves\"")" \
    "1 1 1 1 1"
expect "it finds we in the text of an attribute, which is the page's own text" "$(hit "docs/en/about.mdx:7: $voice: \"We\"")" "1"
expect "it finds nous, notre, nos, la nôtre and les nôtres" \
    "$(hit "docs/fr/aide.mdx:1: $voice: \"Nous\"") $(hit "docs/fr/aide.mdx:1: $voice: \"notre\"") $(hit "docs/fr/aide.mdx:1: $voice: \"nos\"") $(hit "docs/fr/aide.mdx:1: $voice: \"nôtre\"") $(hit "docs/fr/aide.mdx:1: $voice: \"nôtres\"")" \
    "1 1 1 1 1"
expect "it finds nous inside a sentence, nous-mêmes, and nous after a hyphen" \
    "$(hit "docs/fr/aide.mdx:2: $voice: \"nous\"") $(hit "docs/fr/aide.mdx:2: $voice: \"nous-mêmes\"")" "3 1"
expect "it finds a capital Us and the we of CLAUDE.md" "$(hit "CLAUDE.md:1: $voice: \"Us\"") $(hit "CLAUDE.md:1: $voice: \"we\"")" "1 1"
expect "it finds a word in straight single quotes, which also mark an apostrophe" "$(hit "docs/en/apostrophe.md:1: $voice: \"we\"")" "1"
expect "it says how one person speaks" "$(grep -c "says I (je in French), never we, us, our, nous, notre or nos" "$state/out")" "1"

reset_repo
file docs/en/quote.mdx "import Card from '../ours/us/Card.astro';
A page never says \"we\" or “our”, the title ‘Our Daily Trains’ is quoted, and the French never says « nous » or « nos ».
<a href=\"/fr/us/\">Help</a> <img src=\"/our/lock.png\" alt=\"The lock screen\" />
Run \`let us = load()\` or \`\`we\`\`, and read [Apple's help](https://support.apple.com/en-us/108971) or https://example.com/our/us.
The US store, the Notre-Dame-des-Champs station, a user, the status, a bonus, focus, Wed, nose.
<Screenshot alt=\"The lock screen\" title=\"Help\" />
\`\`\`sh
# we build it, then let us run our tests
make check
\`\`\`
~~~
nous écrivons
~~~"
file docs/fr/page.mdx "Les horaires reçus, les nouveautés, le nouveau train, les nombreux usagers, Notre-Dame-de-Lorette."
file ios/App/Model.swift "// we keep our state here"
expect "code, MDX imports, link addresses (href and src too), double and curly quotes, names and words that only contain the pronoun pass, and only Markdown and MDX are read for it" "$(check)" "passes"

reset_repo
file ios/changes/pause.txt "kind: item
fr: Nous avons ajouté une pause (TASK-12).
en: We added a pause."
expect "a note of the changes, which riders read in the notes of a version, fails on a backlog id and on a team's voice" "$(check)" "fails"
expect "it finds the backlog id and the voice of the note, in each language" \
    "$(hit 'ios/changes/pause.txt:2: a backlog id: "TASK-12"') $(hit "ios/changes/pause.txt:2: $voice: \"Nous\"") $(hit "ios/changes/pause.txt:3: $voice: \"We\"")" "1 1 1"

reset_repo
file ios/scripts/public-text-check.py "INTERNAL_RULES = [\"prompter\", \"/Users/\"]"
file ios/scripts/tests/public-text-check-test.sh "file docs/page.mdx \"TASK-140\""
printf 'docs/draft.md\n' > "$repo/.gitignore"
printf 'The factory, /Users/jane.\n' > "$repo/docs/draft.md"
printf 'TASK-1\0binary\n' > "$repo/docs/image.png"
git -C "$repo" add docs/image.png
expect "it skips its own word list and examples, the files that git ignores, and binary files" "$(check)" "passes"
expect "with VERBOSE=1, it says which files it skips, and why" "$(VERBOSE=1 check > /dev/null; grep -c "skips ios/scripts/public-text-check.py: it holds the word list" "$state/out")" "1"

mkdir "$state/allowing"
cp "$scripts/public-text-check.py" "$scripts/repo_files.py" "$scripts/markdown_prose.py" "$state/allowing/"
sed -i '' 's|^ALLOWED_TEXTS: list\[Allowed\] = \[$|ALLOWED_TEXTS: list[Allowed] = [Allowed("ios/App/Factory.swift", "factory", "the name of a type"), Allowed("docs/en/history.md", "we", "a title of a book"),|' \
    "$state/allowing/public-text-check.py"
reset_repo
file ios/App/Factory.swift "let factory = StationFactory()"
file ios/App/Other.swift "let factory = StationFactory()"
file docs/en/history.md "Read the book we, a novel."
file docs/en/other.md "Read the book we, a novel."
(cd "$repo" && "$state/allowing/public-text-check.py") > "$state/out" 2>&1 && result="passes" || result="fails"
expect "a text of ALLOWED_TEXTS passes in its own file only" "$result $(hit "ios/App/Other.swift:1: a word of the team's own process: \"factory\"") \
$(grep -c "Factory.swift" "$state/out")" "fails 1 0"
expect "a word of a team's voice in ALLOWED_TEXTS passes in its own file only" \
    "$(hit "docs/en/other.md:1: $voice: \"we\"") $(grep -c "history.md" "$state/out")" "1 0"

reset_repo
file docs/page.mdx "The Simulator runs one job at a time."
printf 'echo "the factory runs it"\n' > "$repo/ios/scripts/new.sh"
expect "a new file that git does not track yet is checked, so a mistake in it shows before the commit" "$(check)" "fails"
expect "it finds the word of the team in the new file" "$(hit "ios/scripts/new.sh:1: a word of the team's own process: \"factory\"")" "1"

# The scratch folder of a worktree, with the real .gitignore of the repo: its notes never change the result of a check.
reset_repo
cp "$scripts/../../.gitignore" "$repo/.gitignore"
git -C "$repo" add .gitignore
file docs/page.mdx "The Simulator runs one job at a time."
mkdir -p "$repo/.review/images"
printf 'TASK-465: the factory agent, /Users/jane, jane.doe@company.fr. We passed.\n' > "$repo/.review/notes.md"
printf 'doc-3 %0500d\n' 0 > "$repo/.review/images/log.md"
expect "the notes in the scratch folder .review/ of a worktree pass" "$(check)" "passes"
(cd "$repo/docs" && "$scripts/prose-check.py") > "$state/out" 2>&1 && result="passes" || result="fails"
expect "the prose check skips the scratch folder too" "$result" "passes"
printf 'echo "the factory runs it"\n' > "$repo/ios/scripts/new.sh"
mkdir -p "$repo/docs/.review"
printf 'Ask the prompter.\n' > "$repo/docs/.review/page.md"
expect "with notes in the scratch folder, a new file of a part of the repo still fails" "$(check)" "fails"
expect "it finds the new script and a .review folder inside a part of the repo, and nothing of the scratch folder" \
    "$(hit "ios/scripts/new.sh:1: a word of the team's own process: \"factory\"") $(hit "docs/.review/page.md:1: a word of the team's own process: \"prompter\"") $(grep -c "^public-text-check: \.review/" "$state/out")" "1 1 0"

(cd "$state" && "$scripts/public-text-check.py") > /dev/null 2>&1 && result="passes" || result="fails"
expect "outside a git repo, it fails" "$result" "fails"

(cd "$repo" && "$scripts/public-text-check.py" docs/page.mdx) > /dev/null 2>&1 && result="passes" || result="fails"
expect "a file named on the command line fails: it always checks the whole repo" "$result" "fails"

[ "$failures" -eq 0 ]
