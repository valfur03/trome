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

catalog() {
    cat << JSON
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "new",
            "value" : "$1"
          }
        }
      }
    },
    "NSLocationWhenInUseUsageDescription" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "new",
            "value" : "$2 uses your location, not Old Names."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "$3 utilise votre position, pas Old Names."
          }
        }
      }
    }
  },
  "version" : "1.0"
}
JSON
}

name() {
    printf 'MARKETING_VERSION = 0.1.0\nAPP_NAME = %s\n' "$1" > "$repo/Base.xcconfig"
}

sync() {
    "$scripts/app-name-sync.py" "$repo/Base.xcconfig" "$repo/InfoPlist.xcstrings" > /dev/null
}

rm -rf "$repo"
git init -q "$repo"
catalog "Old Name" "Old Name" "Old Name" > "$repo/InfoPlist.xcstrings"
git -C "$repo" add InfoPlist.xcstrings
git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q -m catalog

name "Old Name"
sync
expect "the same name changes nothing" "$(git -C "$repo" status --short InfoPlist.xcstrings)" ""

name NOVA
sync
expect "a new name replaces the old one in each text, and only as a whole word" \
    "$(cat "$repo/InfoPlist.xcstrings")" "$(catalog NOVA NOVA NOVA)"

catalog NOVA NOVA "Old Name" > "$repo/InfoPlist.xcstrings"
sync
expect "after a build in Xcode wrote the new English texts, the old name of the commit is replaced in the French texts" \
    "$(cat "$repo/InfoPlist.xcstrings")" "$(catalog NOVA NOVA NOVA)"

printf 'MARKETING_VERSION = 0.1.0\n' > "$repo/Base.xcconfig"
expect "an xcconfig with no APP_NAME fails" "$(sync 2> /dev/null && echo passes || echo fails)" "fails"

[ "$failures" -eq 0 ]
