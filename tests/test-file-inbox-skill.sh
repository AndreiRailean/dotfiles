#!/bin/sh
# file-inbox exists because, without it, four fresh sessions given the same
# "how do I get this folder to you?" picked four different landing paths, none
# of them per-session, invented four different ways to tell a finished copy
# from a half one, and three of four ended their turn waiting for the user to
# come back and say "sent". All four also found rsync missing on the VM, which
# is why the default command is scp. These pin the parts that fixed that.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SKILL="$REPO/claude/.claude/skills/file-inbox/SKILL.md"

[ -f "$SKILL" ] && pass "SKILL.md exists" || fail "SKILL.md exists"
body="$(cat "$SKILL" 2>/dev/null)"

assert_contains "$body" "name: file-inbox" "skill declares its name"
# The need arises mid-task; nobody types the skill's name.
assert_not_contains "$body" "disable-model-invocation" "skill is model-invocable"

desc="$(sed -n 's/^description: //p' "$SKILL")"
assert_contains "$desc" "give you files" "description names the inbound trigger"
assert_contains "$desc" "hand files back" "description names the outbound trigger"
# The description is always in context; the protocol belongs in the body.
assert_not_contains "$desc" ".done" "description does not restate the protocol"

# One inbox per session: mktemp makes the name unique and prints it, so the
# session holds its own path instead of having to recall or guess it later.
assert_contains "$body" 'mktemp -d "$HOME/inbox/' "inbox is a unique per-session dir"

# Completion is a marker the user's own command writes only on success.
assert_contains "$body" '&& ssh <user>@<host> touch <inbox>/.done' \
  "the user's command writes .done only after the copy succeeds"
# rsync over SSH needs both ends; the VM this was written on had none.
assert_contains "$body" "command -v rsync" "rsync is offered only where it is installed"
# ...and install.sh puts it everywhere, so that fallback stays the exception.
grep -q '^ensure_tool rsync rsync' "$REPO/install.sh" \
  && pass "install.sh installs rsync" || fail "install.sh installs rsync"

# The session watches; the user does not have to report back.
assert_contains "$body" 'until [ -e <inbox>/.done ]' "the session waits on .done in the background"
assert_contains "$body" "run_in_background" "the wait runs in the background, not the foreground"
# The reply ends the turn, so "after replying" never comes. Three of four reps
# flagged the original "as soon as the reply is sent" as unfollowable.
assert_contains "$body" "before the reply text" "the watch starts in the same turn as the reply"
# Agent shells keep no variables between calls. The draft relied on \$INBOX
# persisting; every rep wrote the literal path instead, one saying so.
assert_contains "$body" "Shell variables do not survive" "the inbox path is written literally into later commands"

# A watch that expires is the failure signal, not a reason to stop watching.
assert_contains "$body" "If the watch times out" "body says what a timed-out watch means"

# Routes that need no transfer at all.
assert_contains "$body" "/proc/version" "WSL is detected"
assert_contains "$body" "tailscale status --self --peers=false" "the tailnet host is looked up, not guessed"
assert_contains "$body" "SSH_CONNECTION" "plain-SSH machines get an address the user already reached"

# Taildrop is one queue for the whole machine.
assert_contains "$body" "machine-wide" "body warns that Taildrop is shared between sessions"

assert_contains "$body" "~/outbox/" "body covers the outbound direction"

finish
