#!/bin/sh
# docs/agents/domain.md is the repo's ADR format contract. It has to be
# complete on its own: a collaborator, a CI agent, or a session on a machine
# without these dotfiles has no record-decision skill, and the only thing
# telling them what a record looks like is this file.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
DOMAIN="$REPO/docs/agents/domain.md"

d="$(cat "$DOMAIN")"
assert_contains "$d" "## Writing ADRs" "domain.md has a production section"
assert_contains "$d" "YYYYMMDD-slug.md" "domain.md documents date-stem naming"
for s in proposed accepted rejected superseded deprecated; do
  assert_contains "$d" "\`$s\`" "domain.md documents the $s status"
done
for f in "type:" "status:" "date:" "summary:"; do
  assert_contains "$d" "$f" "domain.md documents the $f field"
done
assert_contains "$d" "overrides" "domain.md states it overrides bundled templates"

# The old sequential convention must be gone, or agents keep reading it.
assert_not_contains "$d" "0001-event-sourced-orders.md" "old sequential example removed"

# ── every record conforms ─────────────────────────────────────
# Applies to the whole directory rather than a list, so records added later are
# covered without anyone remembering to extend this test.

# A glob that matches nothing expands to itself, so the loop below would run
# zero assertions and report success. A validator with nothing to validate is
# a failure, not a pass.
n=0
for f in "$REPO"/docs/adr/*.md; do
  [ -f "$f" ] && n=$((n + 1))
done
[ "$n" -gt 0 ] && pass "docs/adr/ contains at least one record" \
  || fail "docs/adr/ contains at least one record (glob matched nothing)"

for f in "$REPO"/docs/adr/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  c="$(cat "$f")"

  # Date-stem naming: 8 digits, a dash, a slug.
  echo "$n" | grep -q '^[0-9]\{8\}-.*\.md$' \
    && pass "$n uses a date-stem filename" \
    || fail "$n uses a date-stem filename"

  # Frontmatter must open on line 1 or the YAML is not parsed at all.
  assert_eq "$(head -1 "$f")" "---" "$n opens with frontmatter"

  for k in "type:" "status:" "date:" "summary:"; do
    assert_contains "$c" "$k" "$n has $k"
  done

  # Status must be one of the five.
  st="$(sed -n 's/^status: *//p' "$f" | head -1)"
  case "$st" in
    proposed|accepted|rejected|superseded|deprecated)
      pass "$n has a valid status ($st)" ;;
    *)
      fail "$n has a valid status (got '$st')" ;;
  esac

  # The old bold status line must not survive the migration.
  assert_not_contains "$c" "**Status:**" "$n does not use the old bold status line"
done

finish
