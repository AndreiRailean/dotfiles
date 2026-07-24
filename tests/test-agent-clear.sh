#!/bin/sh
cd "$(dirname "$0")" || exit 2
. ./lib.sh
SCRIPT=../tmux/.config/tmux/scripts/agent-clear
BIN="$(mktemp -d)"; LOG="$BIN/calls.log"
cat > "$BIN/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LOG"
EOF
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

: > "$LOG"; sh "$SCRIPT" @2 '#[fg=colour232,bg=colour203,bold] ▲ input #[default]'
assert_contains "$(cat "$LOG")" "set-window-option -t @2 @agent_state" "clears needs-input on focus"
: > "$LOG"; sh "$SCRIPT" @2 '#[x] ✔ done #[default]'
assert_contains "$(cat "$LOG")" "set-window-option -t @2 @agent_state" "clears done on focus"
: > "$LOG"; sh "$SCRIPT" @2 '#[x] ● working #[default]'
assert_eq "$(cat "$LOG")" "" "keeps working chip"
: > "$LOG"; sh "$SCRIPT" @2 ''
assert_eq "$(cat "$LOG")" "" "empty state is a no-op"
: > "$LOG"; sh "$SCRIPT" '' 'anything'
assert_eq "$(cat "$LOG")" "" "missing window id is a no-op"
finish
