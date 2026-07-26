#!/bin/sh
cd "$(dirname "$0")" || exit 2
. ./lib.sh
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
MERGE=../claude-hooks-merge.sh
SD=/home/x/.config/tmux/scripts

# 1) missing file → created with three hooks + preferredNotifChannel
D="$(mktemp -d)"; S="$D/settings.json"
sh "$MERGE" "$S" "$SD"
assert_eq "$(jq -r '.preferredNotifChannel' "$S")" "terminal_bell" "sets preferredNotifChannel when absent"
assert_eq "$(jq '.hooks.UserPromptSubmit | length' "$S")" "1" "adds UserPromptSubmit hook"
assert_eq "$(jq '.hooks.Stop | length' "$S")" "1" "adds Stop hook"
assert_eq "$(jq -r '.hooks.Notification[0].matcher' "$S")" "" "Notification matcher empty"
assert_contains "$(jq -r '.hooks.Stop[0].hooks[0].command' "$S")" "agent-notify" "hook points at agent-notify"

# 2) idempotent
sh "$MERGE" "$S" "$SD"
assert_eq "$(jq '.hooks.UserPromptSubmit | length' "$S")" "1" "idempotent on re-run"

# 3) preserves unrelated hooks + existing preferredNotifChannel + backup
D="$(mktemp -d)"; S="$D/settings.json"
printf '%s' '{"preferredNotifChannel":"iterm2","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$S"
sh "$MERGE" "$S" "$SD"
assert_eq "$(jq -r '.preferredNotifChannel' "$S")" "iterm2" "does not override existing preferredNotifChannel"
assert_eq "$(jq '.hooks.PreToolUse | length' "$S")" "1" "keeps unrelated PreToolUse hook"
assert_eq "$(jq '.hooks.Stop | length' "$S")" "1" "adds Stop hook alongside"
[ -f "$S.bak" ] && pass "creates a backup" || fail "creates a backup"

# 4) invalid JSON → abort, file unchanged
D="$(mktemp -d)"; S="$D/settings.json"
printf '%s' 'not json {' > "$S"
if sh "$MERGE" "$S" "$SD" 2>/dev/null; then fail "aborts on invalid JSON"; else pass "aborts on invalid JSON"; fi
assert_eq "$(cat "$S")" 'not json {' "leaves invalid file unchanged"
finish
