#!/bin/sh
# Runs the full E2E suite once per scheme given, inside one Simulator lock job. Usage: ab.sh <label> <scheme>...
label=$1; shift
t84=$(cd "$(dirname "$0")" && pwd)
cd "$t84/../.."
out="$t84/../../.build/timing/$label"; mkdir -p "$out"
XCB='./scripts/shared-cache.sh use '"$HOME"'/Library/Caches/RATPActivity xcodebuild -quiet -project RATPActivity.xcodeproj -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages COMPILER_INDEX_STORE_ENABLE=NO SDK_EXPLICIT_MODULES_OUTPUT_PATH='"$HOME"'/Library/Caches/RATPActivity/SDKExplicitPrecompiledModules SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -xcconfig Config/NoKey.xcconfig'
APP=.build/DerivedData/Build/Products/Debug-iphonesimulator/RATPActivity.app
cat > "$out/inner.sh" <<INNER
#!/bin/sh
( top -l 0 -s 5 -n 0 | grep --line-buffered "CPU usage" | while read l; do echo "\$(date +%H:%M:%S) \$l"; done ) > "$out/cpu.log" 2>&1 &
cpupid=\$!
( while :; do echo "--- \$(date +%H:%M:%S) \$(uptime | sed 's/.*averages: //')"; ps -Ao pcpu,comm -r | sed -n '2,9p' | sed 's|/.*/||'; sleep 10; done ) > "$out/procs.log" 2>&1 &
procpid=\$!
n=0
for scheme in $*; do
  n=\$((n + 1))
  echo "\$scheme start \$(date +%H:%M:%S)" >> "$out/summary.txt"
  ./scripts/simulator.sh reset ./scripts/simulator.sh grant-location "$APP" ./scripts/simulator.sh with-destination $XCB -scheme \$scheme -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -resultBundlePath "$out/\$scheme-\$n.xcresult" test-without-building > "$out/\$scheme-\$n.log" 2>&1
  echo "\$scheme end \$(date +%H:%M:%S) status \$?" >> "$out/summary.txt"
done
kill \$cpupid \$procpid
pkill -f "top -l 0 -s 5 -n 0" || true
INNER
chmod +x "$out/inner.sh"
echo "queued $(date +%H:%M:%S)" > "$out/summary.txt"
./scripts/sim-lock.sh job "$out/inner.sh" 2>&1 | "$t84/ts.pl" > "$out/lock.log"
echo "done $(date +%H:%M:%S)" >> "$out/summary.txt"
