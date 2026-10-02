#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 render <output folder> <xcodebuild test command...>" >&2
    echo "       Run it through the Simulator lock, in ios/: ./scripts/sim-lock.sh job ./scripts/simulator.sh reset ./scripts/simulator.sh with-destination $0 render ..." >&2
    echo "       $0 report <output folder>   (on the Mac, after the render: the too tall renders, the cut texts and the breaches of the cut rules)" >&2
    echo "       It draws in the languages of RENDER_LANGUAGES (default: fr; for example \"fr en\"), each in its own folder: <output folder>/fr, <output folder>/en" >&2
    exit 1
}

[ $# -ge 2 ] || usage
mode=$1
out=$2
shift 2
scripts=$(cd "$(dirname "$0")" && pwd)
languages=${RENDER_LANGUAGES:-fr}

region() {
    case "$1" in
        fr) echo FR ;;
        *) echo US ;;
    esac
}

report() {
    dir=$1
    csv="$dir/heights.csv"
    [ -f "$csv" ] || { echo "No $csv: run make live-activity-render first" >&2; exit 1; }
    renders=$(($(wc -l < "$csv") - 1))
    over="$dir/too-tall.csv"
    head -1 "$csv" > "$over"
    grep ',true$' "$csv" >> "$over" || true
    cuts="$dir/cut-texts.txt"
    find "$dir" -name '*.png' -print0 | xargs -0 swift "$scripts/live-activity-render-ocr.swift" \
        | grep -E '(…|\.\.\.)$' | sort > "$cuts" || true
    images=$(find "$dir" -name '*.png' | wc -l | tr -d ' ')
    echo "== Language: $2"
    echo "Renders: $renders (every station and page). Images: $images, in $dir"
    echo "Too tall for their text size: $(($(wc -l < "$over") - 1)) (list: $over)"
    sed 1d "$over" | awk -F, '{ print "  " $(NF-4) " " $(NF-3) " (limit " $(NF-1) " pt)" }' | sort | uniq -c
    echo "Cut texts in the images (OCR, for a person to read): $(wc -l < "$cuts" | tr -d ' ') (list: $cuts)"
    head -40 "$cuts"
    swift "$scripts/live-activity-render-breaches.swift" "$dir"
}

case "$mode" in
    render)
        [ $# -gt 0 ] || usage
        rm -rf "$out"
        mkdir -p "$out"
        out=$(cd "$out" && pwd)
        start=$(date +%s)
        for language in $languages; do
            mkdir -p "$out/$language"
            TEST_RUNNER_RENDER_OUT="$out/$language" TEST_RUNNER_RENDER_LANGUAGE="$language" \
                "$@" -testLanguage "$language" -testRegion "$(region "$language")"
        done
        end=$(date +%s)
        echo "Simulator time of the render: $((end - start)) s" | tee "$out/simulator-seconds.txt"
        ;;
    report)
        for language in $languages; do
            report "$out/$language" "$language"
        done
        cat "$out/simulator-seconds.txt" 2> /dev/null || true
        ;;
    *)
        usage
        ;;
esac
