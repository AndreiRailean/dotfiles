#!/bin/sh
# Run every tests/test-*.sh; non-zero exit if any fail.
cd "$(dirname "$0")" || exit 2
rc=0
for t in test-*.sh; do
  [ -f "$t" ] || continue
  echo "=== $t ==="
  sh "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
