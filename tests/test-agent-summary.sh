#!/bin/sh
cd "$(dirname "$0")" || exit 2
. ./lib.sh
SCRIPT=../tmux/.config/tmux/scripts/agent-summary
BIN="$(mktemp -d)"
cat > "$BIN/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  list-windows) cat "$AGENT_STUB_WINDOWS" ;;
  *) : ;;
esac
EOF
chmod +x "$BIN/tmux"
export PATH="$BIN:$PATH"

WIN="$(mktemp)"; export AGENT_STUB_WINDOWS="$WIN"
printf '%s\n' \
  '#[fg=colour232,bg=colour203,bold] ▲ input #[default]' \
  '#[fg=colour232,bg=colour203,bold] ▲ input #[default]' \
  '#[fg=colour232,bg=colour220,bold] ● working #[default]' \
  '' > "$WIN"
out="$(sh "$SCRIPT")"
assert_contains "$out" "▲2" "counts two needs-input windows"
assert_contains "$out" "●1" "counts one working window"

: > "$WIN"
assert_eq "$(sh "$SCRIPT")" "" "prints nothing when nothing is flagged"
finish
