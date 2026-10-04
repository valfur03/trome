#!/bin/sh
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
script="$tests/../upload-check.py"
state=$(mktemp -d)
app="$state/Sample.app"
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

passes() {
    if "$script" "$app" > "$state/out" 2>&1; then echo yes; else echo no; fi
}

says() {
    if grep -qF -- "$1" "$state/out"; then echo yes; else cat "$state/out"; echo no; fi
}

executable() {
    printf '%s\n' "$2" > "$state/main.m"
    xcrun clang -o "$1" "$state/main.m" -framework Foundation
}

info() {
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<plist version="1.0"><dict>'
        echo "<key>CFBundleExecutable</key><string>$2</string>"
        echo "<key>CFBundleShortVersionString</key><string>$3</string>"
        echo '<key>CFBundleVersion</key><string>1</string>'
        printf '%s\n' "$4"
        echo '</dict></plist>'
    } > "$1/Info.plist"
}

manifest() {
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<plist version="1.0"><dict>'
        echo '<key>NSPrivacyTracking</key><false/>'
        echo '<key>NSPrivacyTrackingDomains</key><array/>'
        echo '<key>NSPrivacyCollectedDataTypes</key><array/>'
        echo '<key>NSPrivacyAccessedAPITypes</key><array>'
        printf '%s\n' "$2"
        echo '</array>'
        printf '%s\n' "${3:-}"
        echo '</dict></plist>'
    } > "$1/PrivacyInfo.xcprivacy"
}

stat_reason='<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array></dict>'
no_encryption='<key>ITSAppUsesNonExemptEncryption</key><false/>'
uses_stat='#include <sys/stat.h>
int main(int argc, char **argv) { struct stat s; return stat(argv[0], &s); }'

mkdir -p "$app/PlugIns/Sample.appex"
executable "$app/Sample" "$uses_stat"
executable "$app/PlugIns/Sample.appex/Extension" 'int main(void) { return 0; }'
info "$app" Sample 1.0.0 "$no_encryption"
info "$app/PlugIns/Sample.appex" Extension 1.0.0 ""
manifest "$app" "$stat_reason"
expect "an app with its manifest, its answer on encryption and version 1.0.0 passes" "$(passes)" yes

rm "$app/PrivacyInfo.xcprivacy"
expect "an app with no privacy manifest fails" "$(passes)" no
expect "it says that the app has no privacy manifest" "$(says 'the app has no privacy manifest')" yes
manifest "$app" "$stat_reason"

manifest "$app" ""
expect "an app whose code uses an API of a category that its manifest does not declare fails" "$(passes)" no
expect "it names the API, the category and the refusal code" \
    "$(says 'its code uses _stat, an API of NSPrivacyAccessedAPICategoryFileTimestamp')$(says 'ITMS-91053')" yesyes

manifest "$app" "$(echo "$stat_reason" | sed 's/C617.1/CA92.1/')"
expect "a reason that is not approved for its category fails" "$(passes)" no
expect "it names the reason" "$(says "'CA92.1' is not a reason that an app may give")" yes

manifest "$app" "$stat_reason" '<key>NSPrivacyExtra</key><true/>'
expect "a manifest with an unknown key fails" "$(passes)" no
manifest "$app" "$stat_reason"

executable "$app/Sample" '#import <Foundation/Foundation.h>
int main(void) { return (int)NSProcessInfo.processInfo.systemUptime; }'
expect "an app whose code calls an Objective-C method of such an API, with no reason, fails" "$(passes)" no
expect "it names the method" "$(says 'its code uses systemUptime, an API of NSPrivacyAccessedAPICategorySystemBootTime')" yes
executable "$app/Sample" "$uses_stat"

info "$app" Sample 1.0.0 ""
expect "an app with no answer on encryption fails" "$(passes)" no
expect "it says that the answer on encryption is missing" "$(says 'has no answer on encryption (ITSAppUsesNonExemptEncryption')" yes

for version in 1.0 1.0.0b 0.1.0.1 ''; do
    info "$app" Sample "$version" "$no_encryption"
    expect "the version '$version' fails" "$(passes)" no
done
expect "it says what a version must be" "$(says 'it must be three numbers with dots, such as 1.0.0')" yes

info "$app" Sample 1.0.1 "$no_encryption"
expect "an extension whose version is not the app's fails" "$(passes)" no
expect "it says that the versions differ" "$(says 'the app and its extensions must have the same version')" yes
info "$app" Sample 1.0.0 "$no_encryption"

executable "$app/PlugIns/Sample.appex/Extension" "$uses_stat"
expect "an extension whose code uses such an API, with no manifest of its own, fails" "$(passes)" no
expect "it asks for a manifest in the extension" "$(says 'so a PrivacyInfo.xcprivacy at the top of Sample.appex must declare')" yes
manifest "$app/PlugIns/Sample.appex" "$stat_reason"
expect "an extension with its own manifest passes" "$(passes)" yes

[ "$failures" -eq 0 ] || exit 1
