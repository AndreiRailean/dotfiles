#!/bin/sh
# agent-notify: hook event → @agent_state chip on the agent's own pane.
cd "$(dirname "$0")" || exit 2
. ./lib.sh
SCRIPT=../tmux/.config/tmux/scripts/agent-notify
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

BIN="$(mktemp -d)"; LOG="$BIN/calls.log"
cat > "$BIN/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LOG"
EOF
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

emit() { : > "$LOG"; printf '{"hook_event_name":"%s"}' "$1" | TMUX=1 TMUX_PANE=%3 sh "$SCRIPT"; cat "$LOG"; }

out="$(emit Stop)"
assert_contains "$out" "set-window-option -t %3 @agent_state" "Stop targets the agent pane"
assert_contains "$out" "done" "Stop → done chip"
assert_contains "$(emit Notification)"     "input"   "Notification → needs-input chip"
assert_contains "$(emit UserPromptSubmit)" "working" "UserPromptSubmit → working chip"

: > "$LOG"
printf '{"hook_event_name":"Stop"}' | env -u TMUX -u TMUX_PANE sh "$SCRIPT"
assert_eq "$(cat "$LOG")" "" "no tmux calls when not inside tmux"
finish
