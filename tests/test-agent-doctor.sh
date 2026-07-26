#!/bin/sh
cd "$(dirname "$0")" || exit 2
. ./lib.sh
SCRIPT=../tmux/.config/tmux/scripts/agent-doctor
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
# stub tmux that fails (simulate no running server) to exercise the rest
BIN="$(mktemp -d)"; printf '#!/bin/sh\nexit 1\n' > "$BIN/tmux"; chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

D="$(mktemp -d)"; S="$D/settings.json"
printf '%s' '{"hooks":{"UserPromptSubmit":[{}],"Notification":[{}],"Stop":[{}]}}' > "$S"
out="$(AGENT_DOCTOR_SETTINGS="$S" XDG_CONFIG_HOME=/nonexistent sh "$SCRIPT")"
assert_contains "$out" "Claude hooks present" "detects hooks in settings.json"
assert_contains "$out" "agent-notify" "reports on agent-notify script"
assert_contains "$out" "no tmux server" "notes when no server is running"

# missing hooks → flagged
printf '%s' '{}' > "$S"
out="$(AGENT_DOCTOR_SETTINGS="$S" XDG_CONFIG_HOME=/nonexistent sh "$SCRIPT")"
assert_contains "$out" "hooks not found" "flags missing hooks"
finish
