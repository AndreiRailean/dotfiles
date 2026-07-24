# tests/lib.sh — tiny assertion helpers for POSIX shell tests.
FAILED=0
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; }
pass() { printf '  ok: %s\n' "$1"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing: $2)" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected: $2)" ;; *) pass "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1' want '$2')"; fi; }
finish() { if [ "$FAILED" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi; }
