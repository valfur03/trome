#!/bin/sh
# The guards of the release workflow (release-workflow-check.py): the real workflow passes, and each change below of a
# copy of it fails with its reason: a secret before the approval, on another branch, or before the E2E proof; a pull
# request trigger; another concurrency group, or one that cancels; a way to print a secret, Info.plist, the build
# settings or the commands; a keychain with no random masked password, or never deleted; an artifact, a cache, or an
# action not pinned to a full commit hash, here or in a workflow that it calls; "E2E passed"; a change of the version.
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
ios=$(cd "$tests/../.." && pwd)
root=$(cd "$ios/.." && pwd)
state=$(mktemp -d)
copy="$state/repo"
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

reset_copy() {
    rm -rf "$copy"
    mkdir -p "$copy/.github/workflows"
    cp "$root/.github/workflows/release.yml" "$root/.github/workflows/release-checks.yml" \
        "$root/.github/workflows/e2e-proof.yml" "$copy/.github/workflows/"
}

# change <workflow> <text> <new text>: the text must be in the file once, so that a change of the workflow that
# moves it fails this test instead of making a case pass for nothing.
change() {
    python3 - "$copy/.github/workflows/$1" "$2" "$3" << 'EOF'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    sys.exit(f"the test cannot change {path}: {old!r} is in it {text.count(old)} times")
open(path, "w").write(text.replace(old, new))
EOF
}

# The outcome of the check on the copy: OK, or the problems that it names.
outcome() {
    status=0
    "$ios/scripts/release-workflow-check.py" "$copy/.github/workflows/release.yml" > "$state/out" 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        echo OK
    else
        grep -v 'FAILED (' "$state/out" | sed 's/^release-workflow-check: //; s/^release.yml: //'
    fi
}

# case <name> <workflow> <text> <new text> <the problem that the check must name>
case_of() {
    reset_copy
    if change "$2" "$3" "$4"; then
        expect "$1" "$(outcome)" "$5"
    else
        failures=$((failures + 1))
    fi
}

reset_copy
expect "the release workflow passes" "$(outcome | cut -c1-2)" OK

build_if="    needs: checks
    if: github.ref == 'refs/heads/main'
    runs-on: xcode-27"

case_of "a pull request trigger fails" release.yml "  workflow_dispatch:
" "  workflow_dispatch:
  pull_request_target:
" "on: pull_request_target runs the workflow for code that is not on main"
case_of "a concurrency that cancels a running release fails" release.yml "  cancel-in-progress: false
" "  cancel-in-progress: true
" "the workflow does not share the concurrency group release with cancel-in-progress: false"
case_of "another concurrency group fails" release.yml "  group: release
" "  group: release-\${{ github.ref }}
" "the workflow does not share the concurrency group release with cancel-in-progress: false"
case_of "a job with secrets and no environment fails" release.yml "    environment: app-store
" "" "jobs.build holds a secret or an environment, but does not wait at the environment app-store, whose reviewer approves each run"
case_of "the environment with no reviewer fails" release.yml "    environment: app-store
" "    environment: app-store-watch
" "jobs.build holds a secret or an environment, but does not wait at the environment app-store, whose reviewer approves each run"
case_of "a job with secrets that runs when the checks failed fails" release.yml "$build_if" "    needs: checks
    if: always() && github.ref == 'refs/heads/main'
    runs-on: xcode-27" "jobs.build has not only the if: github.ref == 'refs/heads/main': a run from another branch would reach it, or it would run when the checks failed"
case_of "a job with secrets that another branch reaches fails" release.yml "$build_if" "    needs: checks
    if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'
    runs-on: xcode-27" "jobs.build has not only the if: github.ref == 'refs/heads/main': a run from another branch would reach it, or it would run when the checks failed"
case_of "a job with secrets with no if: fails" release.yml "$build_if" "    needs: checks
    runs-on: xcode-27" "jobs.build has not only the if: github.ref == 'refs/heads/main': a run from another branch would reach it, or it would run when the checks failed"
case_of "a job with secrets that does not wait for the checks fails" release.yml "$build_if" "    if: github.ref == 'refs/heads/main'
    runs-on: xcode-27" "jobs.build holds a secret but does not need the release checks (./.github/workflows/release-checks.yml), which read the E2E proof first"
case_of "release checks with no E2E proof fail" release-checks.yml "    uses: ./.github/workflows/e2e-proof.yml
" "    runs-on: ubuntu-latest
" "./.github/workflows/release-checks.yml does not run the E2E proof (./.github/workflows/e2e-proof.yml, which runs ios/scripts/e2e-proof.sh read)"
case_of "a secret in the env: of a job fails" release.yml "      APP_ID: io.github.valfur03.trome
" "      APP_ID: io.github.valfur03.trome
      KEY: \${{ secrets.APP_STORE_CONNECT_KEY }}
" "jobs.build.env.KEY names a secret outside the env: or with: of a step"
case_of "a secret passed to the called checks fails" release.yml "    uses: ./.github/workflows/release-checks.yml
" "    uses: ./.github/workflows/release-checks.yml
    secrets: inherit
" "jobs.checks passes secrets to a called workflow"
case_of "a secret in the text of a run: fails" release.yml "        run: make release-server-check
" "        run: make release-server-check \${{ secrets.TRAIN_SERVER_HOST }}
" "jobs.build.steps.6.run names a secret outside the env: or with: of a step
jobs.build.steps.6 puts an expression in its run: (pass it through env:)"
case_of "an echo of a secret fails" release.yml "          umask 077
          printf 'TRAIN_SERVER_HOST" "          echo \"token \$TRAIN_SERVER_APP_TOKEN\"
          umask 077
          printf 'TRAIN_SERVER_HOST" "jobs.build.steps.5 prints the secret TRAIN_SERVER_APP_TOKEN"
case_of "an echo of a secret to the error output fails" release.yml "          umask 077
          printf 'TRAIN_SERVER_HOST" "          echo \"token \$TRAIN_SERVER_APP_TOKEN\" >&2
          umask 077
          printf 'TRAIN_SERVER_HOST" "jobs.build.steps.5 prints the secret TRAIN_SERVER_APP_TOKEN"
case_of "every secret at once fails" release.yml "        run: make release-server-check
" "        env:
          ALL: \${{ toJSON(secrets) }}
        run: make release-server-check
" "jobs.build.steps.6.env.ALL reads every secret at once: each secret goes by its name to the step that uses it"
case_of "a secret named in brackets in the env: of a job fails" release.yml "      APP_ID: io.github.valfur03.trome
" "      APP_ID: io.github.valfur03.trome
      KEY: \${{ secrets['APP_STORE_CONNECT_KEY'] }}
" "jobs.build.env.KEY names a secret outside the env: or with: of a step"
case_of "a secret written for the later steps fails" release.yml "          umask 077
          printf 'TRAIN_SERVER_HOST" "          echo \"HOST=\$TRAIN_SERVER_HOST\" >> \"\$GITHUB_ENV\"
          umask 077
          printf 'TRAIN_SERVER_HOST" "jobs.build.steps.5 writes the secret TRAIN_SERVER_HOST where the log or a later step can read it"
case_of "a here-document of a secret to the log fails" release.yml "cat > \"\$dir/ExportOptions.plist\" << EOF" "cat << EOF" \
    "jobs.build.steps.8 writes the secret TROME_RELEASE_TEAM with a here-document that does not go to a file"
case_of "a group of lines with a secret to the log fails" release.yml "          } > ios/Config/Signing.xcconfig" "          }" \
    "jobs.build.steps.8 prints the secret TROME_RELEASE_TEAM in a group that does not go to a file"
case_of "a host that is not masked fails" release.yml "          echo \"::add-mask::\$TRAIN_SERVER_HOST\"
" "" "jobs.build.steps.5 does not mask TRAIN_SERVER_HOST before its first use"
case_of "a keychain with a fixed password fails" release.yml "password=\$(openssl rand -hex 32)" "password=runner" \
    "jobs.build.steps.7 makes a keychain with no random password (openssl rand)"
case_of "a keychain password that is not masked fails" release.yml "          echo \"::add-mask::\$password\"
" "" "jobs.build.steps.7 does not mask the password of the keychain before it makes the keychain"
case_of "a keychain outside the temporary folder fails" release.yml "keychain=\"\$RUNNER_TEMP/release/release.keychain-db\"" \
    "keychain=\"\$HOME/Library/Keychains/release.keychain-db\"" "jobs.build.steps.7 makes the keychain outside RUNNER_TEMP, or with another password"
case_of "the keys of the keychain printed fail" release.yml "-k \"\$password\" \"\$keychain\" > /dev/null" "-k \"\$password\" \"\$keychain\"" \
    "jobs.build.steps.7 prints the keys of the keychain (security set-key-partition-list with no > /dev/null)"
case_of "a keychain never deleted fails" release.yml "      - name: Delete the keychain, the key, the profiles and the archive
        if: always()
" "      - name: Delete the keychain, the key, the profiles and the archive
" "jobs.build does not delete its keychain in a step with if: always()"
case_of "a step that prints its commands fails" release.yml "          make project
" "          set -ex
          make project
" "jobs.build.steps.9 prints each command with its values"
case_of "a step that prints the build settings fails" release.yml "          make project
" "          make project
          xcodebuild -project ios/TROME.xcodeproj -showBuildSettings
" "jobs.build.steps.9 prints the build settings, which hold the server and its token"
case_of "a step that reads an Info.plist fails" release.yml "          cd ios
          scripts/release-entitlements-check.py" "          cd ios
          cat \"\$RUNNER_TEMP/release/TROME.xcarchive/Products/Applications/TROME.app/Info.plist\"
          scripts/release-entitlements-check.py" "jobs.build.steps.10 reads an Info.plist, which holds the server and its token"
case_of "a step that prints the environment fails" release.yml "          make project
" "          make project
          env | sort
" "jobs.build.steps.9 prints the environment"
case_of "Xcode allowed to make certificates fails" release.yml "-exportPath \"\$dir/export\" \\" "-exportPath \"\$dir/export\" -allowProvisioningUpdates \\" \
    "jobs.build.steps.11 lets Xcode make certificates and profiles with the key, with no approval"
case_of "a change of the version fails" release.yml "CURRENT_PROJECT_VERSION=\"\$BUILD\" \\" "CURRENT_PROJECT_VERSION=\"\$BUILD\" MARKETING_VERSION=1.0.1 \\" \
    "jobs.build.steps.9 sets the version, which is the one of the repo"
case_of "'E2E passed' in the summary fails" release.yml "- E2E: proven at merge, for commit" "- E2E passed, for commit" \
    "jobs.build.steps.12 says that the E2E suite passed here: it says 'E2E: proven at merge'
the summary does not say 'E2E: proven at merge'"
case_of "an artifact fails" release.yml "      - name: Delete the keychain" "      - name: Keep the archive
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          path: \${{ runner.temp }}/release
      - name: Delete the keychain" "jobs.build.steps.13 uses actions/upload-artifact: the archive and the .ipa are never an artifact nor a cache"
case_of "an action that is not pinned fails" release.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "actions/checkout@v7" \
    "jobs.build.steps.0 uses actions/checkout@v7, which is not pinned to a full commit hash"
case_of "an action that is not pinned in a called workflow fails" e2e-proof.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" \
    "actions/checkout@main" "e2e-proof.yml: jobs.proof.steps.0 uses actions/checkout@main, which is not pinned to a full commit hash"
case_of "a cache in a called workflow fails" release-checks.yml "      - name: make check
" "      - uses: actions/cache@0400d5f644dc74513175e3cd8d07132dd4860809 # v4.2.4
        with:
          path: ios/.build
          key: build
      - name: make check
" "release-checks.yml: jobs.checks.steps.5 uses actions/cache: the archive and the .ipa are never an artifact nor a cache"

reset_copy
printf 'jobs: [\n' > "$copy/.github/workflows/release.yml"
expect "a file that is not YAML fails" "$(outcome | head -n 1)" "FAILED: release.yml is not YAML that Ruby reads: (<unknown>): did not find expected node content while parsing a flow node at line 2 column 1"

if [ "$failures" -ne 0 ]; then
    echo "release-workflow-check-test: $failures FAILED"
    exit 1
fi
echo "release-workflow-check-test: OK"
