#!/bin/sh
# The record-decision skill is the half of the system that exercises judgment.
# These assertions pin the properties that make it fire at all: it must be
# model-invocable, and its description must carry the triggers, because only
# the description is in context when the decision to invoke is made.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SKILL="$REPO/claude/.claude/skills/record-decision/SKILL.md"

[ -f "$SKILL" ] && pass "SKILL.md exists" || fail "SKILL.md exists"
body="$(cat "$SKILL" 2>/dev/null)"

assert_contains "$body" "name: record-decision" "skill declares its name"

# The whole point. disable-model-invocation is what makes the mattpocock
# slash-commands inert unless typed, and inert is the failure being fixed.
assert_not_contains "$body" "disable-model-invocation" "skill is model-invocable"

# Only the description is always in context, so the triggers must live there.
desc="$(sed -n 's/^description: //p' "$SKILL")"
assert_contains "$desc" "abandoned" "description names the abandoned-approach trigger"
assert_contains "$desc" "commit" "description names the commit trigger"

# Both gates must be stated or the model invents its own threshold.
assert_contains "$body" "hard to reverse" "body states the decision gate"
assert_contains "$body" "plausibly try this again" "body states the rejection gate"

# The five statuses.
for s in proposed accepted rejected superseded deprecated; do
  assert_contains "$body" "\`$s\`" "body documents the $s status"
done

# Redaction: rejection records quote error output, which quotes credentials.
assert_contains "$body" "Redact" "body requires redaction"

finish
