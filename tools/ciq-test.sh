#!/usr/bin/env bash
# Build a Connect IQ project with unit tests and run them in the simulator.
#   tools/ciq-test.sh <jungle> <out.prg> [device]
# Exit 0 only when the run reports "PASSED (". Full output: <out.prg>.log
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$here/ciq-env.sh"
if [[ $# -lt 2 ]]; then echo "usage: $0 <jungle> <out.prg> [device]" >&2; exit 64; fi
jungle="$1"; out="$2"; dev="${3:-edge1050}"
mkdir -p "$(dirname "$out")"
# The SDK's monkeyc wrapper runs the compiler on Java's default 2 MB stack. That is borderline for the
# generated replay arrays (an intermittent StackOverflowError), so run the same class with a larger one.
java -Xss64m -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true -classpath "$CIQ_SDK/bin/monkeybrains.jar" \
  com.garmin.monkeybrains.Monkeybrains -d "$dev" -f "$jungle" -o "$out" -y "$CIQ_KEY" --unit-test -w > "$out.build.log" 2>&1 \
  || { cat "$out.build.log" >&2; exit 1; }
if ! pgrep -x simulator > /dev/null; then
  (connectiq > /dev/null 2>&1 &)
  for _ in $(seq 1 30); do pgrep -x simulator > /dev/null && break; sleep 1; done
  sleep 5
fi
perl -e 'alarm 600; exec @ARGV' -- monkeydo "$out" "$dev" -t > "$out.log" 2>&1 || true
grep -E "^(Ran [0-9]+ tests?|PASSED \(|FAILED \()" "$out.log" || true
grep -q "^PASSED (" "$out.log"
