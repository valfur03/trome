# Which files the E2E suite and the render check of the Live Activity read.
# Sourced by merge.sh, which skips a check when a merge changes none of its files,
# and by e2e-proof.sh, which applies the same rules when it reads the record of a commit of main:
# one list, so the release never accepts a commit that make merge would have tested.

# App code is what the E2E suite exercises (.claude/rules/tests.md, "Which E2E tests to run").
# The notes of the changes (ios/changes/) are text for the notes of a version: no build and no test reads them.
is_app_code() {
    case "$1" in
        ios/Packages/TROMECore/Tests/*) return 1 ;;
        ios/App/* | ios/Widget/* | ios/UITests/* | ios/DocsScreenshots/* | ios/RenderCheck/* | ios/Packages/*) return 0 ;;
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
diff_touches() {
    git diff --name-only --no-renames "$1" "$2" | {
        while IFS= read -r path; do
            ! "$3" "$path" || exit 0
        done
        exit 1
    }
}
