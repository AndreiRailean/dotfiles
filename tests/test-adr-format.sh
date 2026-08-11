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

finish
