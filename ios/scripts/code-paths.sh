# Which files the E2E suite and the render check of the Live Activity read.
# Sourced by merge.sh, which skips a check when a merge changes none of its files, and picks the E2E test classes
# of the files that it changes (e2e_classes); and by e2e-proof.sh, which applies the same rule of app code when it reads
# the record of a full run on a commit of main: one list, so the release never accepts a commit whose app code no full run tested.

# App code is what the E2E suite exercises (.claude/rules/tests.md, "Which E2E tests to run").
# The notes of the changes (ios/changes/) are text for the notes of a version: no build and no test reads them.
is_app_code() {
    case "$1" in
        ios/Packages/TROMECore/Tests/*) return 1 ;;
        ios/App/* | ios/Widget/* | ios/UITests/* | ios/DocsScreenshots/* | ios/RenderCheck/* | ios/ReleaseRun/* | ios/Packages/*) return 0 ;;
        docs/* | server/* | contracts/* | video/* | ios/changes/* | .claude/* | .github/* | *.md | *.mdx | LICENSE) return 1 ;;
    esac
    return 0
}

# What the drawings of the render check depend on: the widget and its texts, the render check, the value types
# that the widget draws, and the build settings. Wide on purpose: a missed file would keep the counts of old views.
is_render_input() {
    case "$1" in
        ios/Packages/TROMECore/Tests/*) return 1 ;;
        ios/Widget/* | ios/RenderCheck/* | ios/Packages/* | ios/project.yml | ios/Config/* | ios/scripts/live-activity-render*) return 0 ;;
    esac
    return 1
}

# Exits 0 when the diff of the commits $1 and $2 changes a file for which the rule $3 (is_app_code, is_render_input) is true.
# A diff that git cannot make counts as a change: a doubt never skips a check.
diff_touches() {
    diff_paths=$(git diff --name-only --no-renames "$1" "$2") || return 0
    printf '%s\n' "$diff_paths" | {
        while IFS= read -r path; do
            [ -z "$path" ] || ! "$3" "$path" || exit 0
        done
        exit 1
    }
}

# The E2E test classes that run at every merge of app code, whatever it changed: the flows where a rider loses the
# Live Activity at the right station. make release-run-check is a core check too.
core_e2e_classes="LiveActivityTests AutoLiveActivityTests SnoozeTests"

# Prints the E2E test classes that a merge of the commits $1..$2 runs: nothing when the diff changes no app code;
# "all" (the full suite) when a changed file of app code has no line in the map (e2e-paths.txt, next to this file),
# or when git cannot make the diff or the map cannot be read: a doubt never skips a test;
# else the core classes, then the classes that the map gives to the changed files, each once.
e2e_classes() {
    e2e_map=${TROME_E2E_PATHS:-$scripts/e2e-paths.txt}
    e2e_paths=$(git diff --name-only --no-renames "$1" "$2") || { echo all; return 0; }
    [ -r "$e2e_map" ] || { echo all; return 0; }
    e2e_found=
    e2e_extra=
    while IFS= read -r e2e_path; do
        [ -n "$e2e_path" ] && is_app_code "$e2e_path" || continue
        e2e_found=1
        e2e_mapped=
        while read -r e2e_pattern e2e_line; do
            case "$e2e_pattern" in "" | "#"*) continue ;; esac
            # The pattern is unquoted on purpose: it is a shell pattern.
            # shellcheck disable=SC2254
            case "$e2e_path" in
                $e2e_pattern)
                    e2e_mapped=1
                    for e2e_class in $e2e_line; do
                        case " - $core_e2e_classes $e2e_extra " in
                            *" $e2e_class "*) ;;
                            *) e2e_extra="$e2e_extra $e2e_class" ;;
                        esac
                    done
                    ;;
            esac
        done < "$e2e_map"
        [ -n "$e2e_mapped" ] || { echo all; return 0; }
    done << PATHS
$e2e_paths
PATHS
    [ -z "$e2e_found" ] || echo "$core_e2e_classes$e2e_extra"
}
