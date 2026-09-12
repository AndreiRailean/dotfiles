#!/bin/sh
# scope-a-broadcast exists because the machine cannot tell you which repo
# another session is working in. These assertions pin the parts that make it
# fire and the parts that make it correct: the description must carry the
# triggers (only it is ever in context), and the body must keep the capability
# test above the destructive steps, where it is read in time.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SKILL="$REPO/claude/.claude/skills/scope-a-broadcast/SKILL.md"

[ -f "$SKILL" ] && pass "SKILL.md exists" || fail "SKILL.md exists"
body="$(cat "$SKILL" 2>/dev/null)"

assert_contains "$body" "name: scope-a-broadcast" "skill declares its name"

# A broadcast is composed, not requested — nothing types this skill's name.
assert_not_contains "$body" "disable-model-invocation" "skill is model-invocable"

desc="$(sed -n 's/^description: //p' "$SKILL")"
assert_contains "$desc" "peer Claude sessions" "description names the sending trigger"
assert_contains "$desc" "migration" "description names the migration trigger"
assert_contains "$desc" "another session" "description names the receiving trigger"

# Only the triggers belong in the description. A description that states the
# protocol gets followed instead of the body, and the body is where the
# ordering rule lives.
assert_not_contains "$desc" "cat-file" "description does not restate the protocol"

# The rule, both halves.
assert_contains "$body" "names a repo and a SHA" "body states the sender's half"
assert_contains "$body" "git cat-file -t" "body states the recipient's command"

# Ordering is the mechanism: a SHA below a git merge has already failed.
assert_contains "$body" "above everything stateful" "body puts the test above the steps"

# Wording of the failure varies by git version; only the exit status doesn't.
assert_contains "$body" "exit status" "body tests exit status, not the message"

# The two errors that both mean discard.
assert_contains "$body" "not a git repository" "body covers the no-repo case"

# False negatives are the expensive direction.
assert_contains "$body" "When in doubt, send" "body biases toward over-including"

# A SHA the sender can resolve and nobody else can excludes everyone, silently.
assert_contains "$body" "git branch -r" "body says how to check a peer could have the SHA"
assert_contains "$body" "one false negative" "body names the stale-clone exclusion"

# The finding is that the detector cannot exist. A skill that ends up
# recommending one has inverted its own conclusion.
assert_contains "$body" "The detector cannot exist" "body forbids building a detector"
assert_contains "$body" "/proc" "body names the inference that looks authoritative"
assert_contains "$body" "Never to decide" "body keeps the hints out of the include/exclude decision"

finish
