#!/bin/sh
# Loads tmux.conf in a private tmux server and asserts core options/keys.
cd "$(dirname "$0")" || exit 2
. ./lib.sh
CONF=../tmux/.config/tmux/tmux.conf
command -v tmux >/dev/null 2>&1 || { echo "SKIP: tmux not installed"; exit 0; }
L="dotfiles-test-$$"
cleanup() { tmux -L "$L" kill-server 2>/dev/null; rm -f err.log; }
trap cleanup EXIT
if ! tmux -L "$L" -f "$CONF" new-session -d -x 80 -y 24 2>err.log; then
  cat err.log; fail "tmux.conf failed to load"; finish
fi

assert_eq "$(tmux -L "$L" show -gv  allow-passthrough 2>/dev/null)" "on" "allow-passthrough on"
assert_eq "$(tmux -L "$L" show -sv  extended-keys 2>/dev/null)"     "on" "extended-keys on"
assert_eq "$(tmux -L "$L" show -gv  focus-events 2>/dev/null)"      "on" "focus-events on"
assert_eq "$(tmux -L "$L" show -gwv monitor-bell 2>/dev/null)"      "on" "monitor-bell on"
assert_eq "$(tmux -L "$L" show -gwv monitor-activity 2>/dev/null)"  "off" "monitor-activity off"

keys="$(tmux -L "$L" list-keys 2>/dev/null)"
assert_contains "$keys" "M-h" "M-h pane-nav bound"
assert_contains "$keys" "M-L" "M-L next-window bound"
assert_contains "$keys" "synchronize-panes" "sync-panes toggle bound"

assert_contains "$(tmux -L "$L" show -gwv window-status-format 2>/dev/null)" "@agent_state" "window list renders @agent_state chip"
assert_contains "$(tmux -L "$L" show -gv status-left 2>/dev/null)" "#S" "status-left shows session name"
assert_contains "$(tmux -L "$L" show -gv status-right 2>/dev/null)" "agent-summary" "status-right calls agent-summary"
assert_contains "$(tmux -L "$L" show-hooks -gw 2>/dev/null)" "pane-focus-in" "pane-focus-in clear hook is set"
finish
