# tmux AI-agent notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tmux flag which parallel Claude Code session needs attention — per-window `working`/`needs-input`/`done` chips in the status bar plus a terminal bell + OSC 9 notification — all plugin-free.

**Architecture:** Claude Code lifecycle hooks pipe JSON to a small `agent-notify` script that sets a per-window tmux `@agent_state` user option; `tmux.conf` renders it as a colored chip in the window list and an aggregate on the right. A focus hook clears attention states via `agent-clear`. `install.sh` idempotently `jq`-merges the hooks into `~/.claude/settings.json`.

**Tech Stack:** tmux 3.6, POSIX `sh` scripts, `jq`, GNU Stow. No TPM, no plugins.

## Global Constraints

- Target tmux **3.6+**; scripts must be **POSIX `sh`** (no bashisms) — they run over SSH on minimal hosts.
- **Plugin-free**: pure `tmux.conf` + scripts. No TPM, no external binaries beyond `jq` (installed by `install.sh`) and standard coreutils.
- Scripts live in `tmux/.config/tmux/scripts/` (stowed to `~/.config/tmux/scripts/`) and must be **executable** in git.
- Hooks/scripts must **never fail a Claude turn**: `agent-notify` exits 0 in all paths and is a no-op outside tmux.
- Inside `#(...)` and `run-shell`, use **shell** `${VAR:-default}`. tmux's own `#{VAR}` format does NOT support `:-` and errors on it.
- `@agent_state` is **per-window** (last writer wins if two agents share a window) — accepted limitation.
- `monitor-activity` stays **off** (streaming agents flag forever); `monitor-bell` is the native signal.
- Colors are 256-color codes and centralized; retuning is a one-block change. Chip glyphs: `● working` / `▲ input` / `✔ done`.

---

## File Structure

- Modify: `tmux/.config/tmux/tmux.conf` — plumbing, monitoring, keys (Task 1); status bar + chips + focus hook (Task 5)
- Create: `tmux/.config/tmux/scripts/agent-notify` — hook → `@agent_state` + bell/OSC (Task 2)
- Create: `tmux/.config/tmux/scripts/agent-clear` — clear attention state on focus (Task 3)
- Create: `tmux/.config/tmux/scripts/agent-summary` — status-right aggregate (Task 4)
- Create: `tmux/.config/tmux/scripts/agent-doctor` — report-only health check (Task 7)
- Create: `claude-hooks-merge.sh` (repo root) — idempotent jq-merge into settings.json (Task 6)
- Modify: `install.sh` — ensure `jq`; call the merge (Task 6)
- Modify: `doctor.sh` — call `agent-doctor` (Task 7)
- Modify: `README.md` — "tmux + AI agents" section (Task 7)
- Create tests: `tests/lib.sh`, `tests/run.sh`, `tests/test-tmux-conf.sh` (Task 1/5), `tests/test-agent-notify.sh` (Task 2), `tests/test-agent-clear.sh` (Task 3), `tests/test-agent-summary.sh` (Task 4), `tests/test-claude-hooks-merge.sh` (Task 6), `tests/test-agent-doctor.sh` (Task 7)

**Chip color reference (used verbatim in Tasks 2, 4, 5):**
- working: `#[fg=colour232,bg=colour220,bold] ● working #[default]`
- needs-input: `#[fg=colour232,bg=colour203,bold] ▲ input #[default]`
- done: `#[fg=colour232,bg=colour76,bold] ✔ done #[default]`

---

## Task 0: Test harness

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Produces: `assert_contains HAYSTACK NEEDLE MSG`, `assert_not_contains`, `assert_eq GOT WANT MSG`, `pass MSG`, `fail MSG`, `finish` (exit 0 if all passed, else 1). `tests/run.sh` runs every `tests/test-*.sh` and aggregates exit status.

- [ ] **Step 1: Write `tests/lib.sh`**

```sh
# tests/lib.sh — tiny assertion helpers for POSIX shell tests.
FAILED=0
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=1; }
pass() { printf '  ok: %s\n' "$1"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing: $2)" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected: $2)" ;; *) pass "$3" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1' want '$2')"; fi; }
finish() { if [ "$FAILED" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi; }
```

- [ ] **Step 2: Write `tests/run.sh`**

```sh
#!/bin/sh
# Run every tests/test-*.sh; non-zero exit if any fail.
cd "$(dirname "$0")" || exit 2
rc=0
for t in test-*.sh; do
  [ -f "$t" ] || continue
  echo "=== $t ==="
  sh "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$rc"
```

- [ ] **Step 3: Make runner executable and verify it runs with no tests yet**

Run: `chmod +x tests/run.sh && sh tests/run.sh`
Expected: prints `ALL TESTS PASSED` (no `test-*.sh` yet), exit 0.

- [ ] **Step 4: Commit**

```bash
git add tests/lib.sh tests/run.sh
git commit -m "test: add shell test harness for tmux agent integration"
```

---

## Task 1: Core tmux plumbing, monitoring & ergonomics keys

**Files:**
- Modify: `tmux/.config/tmux/tmux.conf` (append new sections)
- Create: `tests/test-tmux-conf.sh`

**Interfaces:**
- Produces: a `tmux.conf` that, when loaded, sets `allow-passthrough on`, `extended-keys on`, `focus-events on`, `monitor-bell on`, `monitor-activity off`, and binds `M-h/j/k/l`, `M-H/M-L`, `S`, `Enter`, `g`.

- [ ] **Step 1: Write the failing test** — create `tests/test-tmux-conf.sh`

```sh
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
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-tmux-conf.sh`
Expected: FAIL on `allow-passthrough on` (option is `off`/unset in current conf).

- [ ] **Step 3: Append the config** to `tmux/.config/tmux/tmux.conf` (after the existing content)

```tmux

# ─────────────────────────────────────────────────────────────
# AI agents: terminal plumbing (required for Claude notifications)
# allow-passthrough lets OSC notifications escape tmux to the outer
# terminal; extended-keys fixes Shift+Enter inside Claude; focus-events
# is required for the pane-focus-in clear hook below.
# ─────────────────────────────────────────────────────────────
set  -g  allow-passthrough on
set  -s  extended-keys on
set  -as terminal-features 'xterm*:extkeys'
set  -g  focus-events on

# Native monitoring baseline (works even with no scripts/hooks present).
# monitor-activity stays OFF: a streaming agent pane would flag forever.
setw -g monitor-bell on
setw -g monitor-activity off
set  -g bell-action other
set  -g visual-bell off
set  -g window-status-bell-style     'fg=colour232,bg=colour203,bold'
set  -g window-status-activity-style 'fg=colour232,bg=colour220'

# Ergonomics for juggling many agent panes/windows.
bind -n M-h select-pane -L
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l select-pane -R
bind -n M-H previous-window
bind -n M-L next-window
# Broadcast the same prompt/command to every pane in the window (toggle).
bind S setw synchronize-panes \; display 'sync #{?pane_synchronized,ON,OFF}'
# Scratch shell popup over any window.
bind Enter display-popup -E -w 80% -h 70%
# Session/window tree with preview (native).
bind g choose-tree -Zw
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh tests/test-tmux-conf.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tmux/.config/tmux/tmux.conf tests/test-tmux-conf.sh
git commit -m "feat(tmux): add Claude passthrough, bell monitoring, and agent nav keys"
```

---

## Task 2: `agent-notify` script

**Files:**
- Create: `tmux/.config/tmux/scripts/agent-notify`
- Create: `tests/test-agent-notify.sh`

**Interfaces:**
- Consumes: Claude hook JSON on stdin (`{"hook_event_name": "..."}`); env `$TMUX`, `$TMUX_PANE`.
- Produces: runs `tmux set-window-option -t "$TMUX_PANE" @agent_state "<chip>"`; for `needs-input`/`done` also writes bell + OSC 9 to `/dev/tty`. Exit 0 always. No-op outside tmux. Event map: `UserPromptSubmit`→working, `Notification`→needs-input, `Stop`/`SubagentStop`→done.

- [ ] **Step 1: Write the failing test** — `tests/test-agent-notify.sh`

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-agent-notify.sh`
Expected: FAIL (`agent-notify` does not exist).

- [ ] **Step 3: Write `tmux/.config/tmux/scripts/agent-notify`**

```sh
#!/bin/sh
# agent-notify — Claude Code hook handler. Reads hook JSON on stdin and flags
# the agent's OWN tmux window with an @agent_state chip; rings the terminal
# bell + emits an OSC 9 desktop notification for attention states. Always
# exits 0 and is a no-op outside tmux, so it can never fail a Claude turn.

[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)"
event=""
if command -v jq >/dev/null 2>&1; then
  event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
fi

case "$event" in
  UserPromptSubmit)   state="working" ;;
  Notification)       state="needs-input" ;;
  Stop|SubagentStop)  state="done" ;;
  *) exit 0 ;;
esac

case "$state" in
  working)     chip='#[fg=colour232,bg=colour220,bold] ● working #[default]' ;;
  needs-input) chip='#[fg=colour232,bg=colour203,bold] ▲ input #[default]' ;;
  done)        chip='#[fg=colour232,bg=colour76,bold] ✔ done #[default]' ;;
esac

# Target the agent's own window explicitly via its pane — never the active one.
tmux set-window-option -t "$TMUX_PANE" @agent_state "$chip" 2>/dev/null

# Attention signal only for needs-input/done (not on every prompt submit).
if [ "$state" != "working" ]; then
  case "$state" in
    needs-input) msg="Claude needs your input" ;;
    done)        msg="Claude finished" ;;
  esac
  printf '\a' > /dev/tty 2>/dev/null || true
  # OSC 9, DCS-wrapped so tmux allow-passthrough forwards it (inner ESC doubled).
  printf '\033Ptmux;\033\033]9;%s\007\033\\' "$msg" > /dev/tty 2>/dev/null || true
fi

exit 0
```

- [ ] **Step 4: Make executable and run test to verify it passes**

Run: `chmod +x tmux/.config/tmux/scripts/agent-notify && sh tests/test-agent-notify.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tmux/.config/tmux/scripts/agent-notify tests/test-agent-notify.sh
git commit -m "feat(tmux): add agent-notify hook handler for agent-state chips"
```

---

## Task 3: `agent-clear` script

**Files:**
- Create: `tmux/.config/tmux/scripts/agent-clear`
- Create: `tests/test-agent-clear.sh`

**Interfaces:**
- Consumes: args `<window_id> <current @agent_state value>`.
- Produces: runs `tmux set-window-option -t "$win" @agent_state ""` only when the current value is a non-empty attention state (anything other than empty or a `working` chip). Exit 0 always.

- [ ] **Step 1: Write the failing test** — `tests/test-agent-clear.sh`

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-agent-clear.sh`
Expected: FAIL (`agent-clear` does not exist).

- [ ] **Step 3: Write `tmux/.config/tmux/scripts/agent-clear`**

```sh
#!/bin/sh
# agent-clear <window_id> <current @agent_state> — clear the chip on focus,
# but only for attention states (leave a "working" chip in place).
win="$1"
state="$2"
[ -n "$win" ] || exit 0
case "$state" in
  ""|*working*) : ;;                                   # empty or working → keep
  *) tmux set-window-option -t "$win" @agent_state "" 2>/dev/null ;;
esac
exit 0
```

- [ ] **Step 4: Make executable and run test to verify it passes**

Run: `chmod +x tmux/.config/tmux/scripts/agent-clear && sh tests/test-agent-clear.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tmux/.config/tmux/scripts/agent-clear tests/test-agent-clear.sh
git commit -m "feat(tmux): add agent-clear to reset attention chips on focus"
```

---

## Task 4: `agent-summary` script

**Files:**
- Create: `tmux/.config/tmux/scripts/agent-summary`
- Create: `tests/test-agent-summary.sh`

**Interfaces:**
- Consumes: reads `tmux list-windows -a -F '#{@agent_state}'`.
- Produces: prints a compact styled aggregate to stdout, e.g. `#[fg=colour203,bold]▲2 #[default]#[fg=colour220]●1 #[default]`; prints nothing when no windows are flagged. Exit 0.

- [ ] **Step 1: Write the failing test** — `tests/test-agent-summary.sh`

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-agent-summary.sh`
Expected: FAIL (`agent-summary` does not exist).

- [ ] **Step 3: Write `tmux/.config/tmux/scripts/agent-summary`**

```sh
#!/bin/sh
# agent-summary — compact status-right aggregate of agent states across all
# windows on the server, e.g. "▲2 ●1". Prints nothing when none are flagged.
command -v tmux >/dev/null 2>&1 || exit 0
states="$(tmux list-windows -a -F '#{@agent_state}' 2>/dev/null)" || exit 0

icount=0; wcount=0; dcount=0
IFS='
'
for s in $states; do
  case "$s" in
    *input*)   icount=$((icount + 1)) ;;
    *working*) wcount=$((wcount + 1)) ;;
    *done*)    dcount=$((dcount + 1)) ;;
  esac
done

out=""
[ "$icount" -gt 0 ] && out="$out#[fg=colour203,bold]▲$icount #[default]"
[ "$wcount" -gt 0 ] && out="$out#[fg=colour220]●$wcount #[default]"
[ "$dcount" -gt 0 ] && out="$out#[fg=colour76]✔$dcount #[default]"
printf '%s' "$out"
```

- [ ] **Step 4: Make executable and run test to verify it passes**

Run: `chmod +x tmux/.config/tmux/scripts/agent-summary && sh tests/test-agent-summary.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tmux/.config/tmux/scripts/agent-summary tests/test-agent-summary.sh
git commit -m "feat(tmux): add agent-summary aggregate for the status bar"
```

---

## Task 5: Status bar redesign, chips & focus hook

**Files:**
- Modify: `tmux/.config/tmux/tmux.conf` (replace the existing "Status bar" block, lines 50-58; append status/hook block)
- Modify: `tests/test-tmux-conf.sh` (add assertions)

**Interfaces:**
- Consumes: `agent-summary` (status-right), `agent-clear` (focus hook), `@agent_state` chips written by `agent-notify`.
- Produces: window list rendering `#{?@agent_state,#{E:@agent_state},}`, a session segment in `status-left`, an agent-summary + SSH-host + clock in `status-right`, and a `pane-focus-in` hook.

- [ ] **Step 1: Add failing assertions** to `tests/test-tmux-conf.sh` (insert before the final `finish`)

```sh
assert_contains "$(tmux -L "$L" show -gwv window-status-format 2>/dev/null)" "@agent_state" "window list renders @agent_state chip"
assert_contains "$(tmux -L "$L" show -gv status-left 2>/dev/null)" "#S" "status-left shows session name"
assert_contains "$(tmux -L "$L" show -gv status-right 2>/dev/null)" "agent-summary" "status-right calls agent-summary"
assert_contains "$(tmux -L "$L" show-hooks -g 2>/dev/null)" "pane-focus-in" "pane-focus-in clear hook is set"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-tmux-conf.sh`
Expected: FAIL on the new `window-status-format`/`status-left`/hook assertions.

- [ ] **Step 3: Replace the old status-bar block.** In `tmux/.config/tmux/tmux.conf` delete the current block (the `# Status bar — classic tmux look...` comment through the `setw -g window-status-current-style ...` line, ~lines 50-58) and replace with:

```tmux
# ─────────────────────────────────────────────────────────────
# Status bar — information-dense, agent-aware. Neutral dark bar; blue
# active window; per-window agent chips (working/needs-input/done) written
# by scripts/agent-notify into @agent_state and expanded here with #{E:}.
# ─────────────────────────────────────────────────────────────
set  -g status-interval 5
set  -g status-position bottom
set  -g status-style 'bg=colour236,fg=colour245'

set  -g status-left '#[fg=colour232,bg=colour110,bold] #S #{?client_prefix,#[fg=colour232,bg=colour214,bold] * ,}#[default] '
set  -g status-left-length 40

setw -g window-status-separator ''
setw -g window-status-format         ' #I:#W#F #{?@agent_state,#{E:@agent_state},}'
setw -g window-status-current-format '#[fg=colour232,bg=colour110,bold] #I:#W#F #[default]#{?@agent_state,#{E:@agent_state},}'

# status-right runs in a shell, so use shell ${VAR:-default} (tmux #{VAR}
# has no ":-"). Show agent aggregate, host only over SSH, then the clock.
set  -g status-right '#(${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/agent-summary) #{?SSH_CONNECTION,#[fg=colour109] #h ,}#[fg=colour245] %H:%M '
set  -g status-right-length 60

# Clear attention chips (done/needs-input) when you focus the window.
set-hook -g pane-focus-in "run-shell -b '\"${XDG_CONFIG_HOME:-$HOME/.config}\"/tmux/scripts/agent-clear #{window_id} \"#{@agent_state}\"'"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh tests/test-tmux-conf.sh`
Expected: PASS.

- [ ] **Step 5: Full end-to-end sanity in a live server** (manual, no assertion)

Run: `tmux -L e2e -f tmux/.config/tmux/tmux.conf new-session -d && tmux -L e2e set-window-option @agent_state '#[fg=colour232,bg=colour203,bold] ▲ input #[default]' && tmux -L e2e list-windows -F '#{@agent_state}' && tmux -L e2e kill-server`
Expected: prints the chip string; no errors.

- [ ] **Step 6: Commit**

```bash
git add tmux/.config/tmux/tmux.conf tests/test-tmux-conf.sh
git commit -m "feat(tmux): agent-aware status bar with per-window attention chips"
```

---

## Task 6: Claude hooks jq-merge + install.sh wiring

**Files:**
- Create: `claude-hooks-merge.sh` (repo root)
- Modify: `install.sh` (add `ensure_tool jq jq`; call the merge before the drift check)
- Create: `tests/test-claude-hooks-merge.sh`

**Interfaces:**
- Consumes: args `<settings_path> <scripts_dir>` (defaults `~/.claude/settings.json`, `~/.config/tmux/scripts`).
- Produces: settings.json containing `hooks.UserPromptSubmit`, `hooks.Notification` (matcher `""`), `hooks.Stop`, each with a command object `"<scripts_dir>/agent-notify"`; sets `preferredNotifChannel: "terminal_bell"` only if absent. Idempotent; backs up to `<settings>.bak`; aborts (exit 1) on invalid existing JSON; preserves unrelated hooks. Skips gracefully (exit 0) if `jq` is missing.

- [ ] **Step 1: Write the failing test** — `tests/test-claude-hooks-merge.sh`

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-claude-hooks-merge.sh`
Expected: FAIL (`claude-hooks-merge.sh` does not exist).

- [ ] **Step 3: Write `claude-hooks-merge.sh`**

```sh
#!/bin/sh
# claude-hooks-merge.sh <settings_path> <scripts_dir>
# Idempotently merge the tmux agent-notify hooks into a Claude settings.json.
# Safeguards: skips if jq is missing; backs up; aborts on invalid existing
# JSON; validates the result before writing; never duplicates our hooks;
# never overrides an existing preferredNotifChannel.
set -eu

settings="${1:-$HOME/.claude/settings.json}"
scripts_dir="${2:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts}"
cmd="$scripts_dir/agent-notify"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found — skipping Claude hook install (see README to add manually)." >&2
  exit 0
fi

mkdir -p "$(dirname "$settings")"

if [ -f "$settings" ] && [ -s "$settings" ]; then
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "ERROR: $settings is not valid JSON; refusing to modify it." >&2
    exit 1
  fi
  cp "$settings" "$settings.bak"
  base="$(cat "$settings")"
else
  base='{}'
fi

tmp="$(mktemp)"
printf '%s' "$base" | jq --arg cmd "$cmd" '
  def ensure($ev; $group):
    .hooks[$ev] = ((.hooks[$ev] // [])
      | if any(.[]; any(.hooks[]?; .command == $cmd)) then . else . + [$group] end);
  (. // {})
  | .hooks = (.hooks // {})
  | ensure("UserPromptSubmit"; {hooks: [{type: "command", command: $cmd}]})
  | ensure("Stop";            {hooks: [{type: "command", command: $cmd}]})
  | ensure("Notification";    {matcher: "", hooks: [{type: "command", command: $cmd}]})
  | .preferredNotifChannel = (.preferredNotifChannel // "terminal_bell")
' > "$tmp"

if ! jq -e . "$tmp" >/dev/null 2>&1; then
  echo "ERROR: merge produced invalid JSON; leaving $settings unchanged." >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$settings"
```

- [ ] **Step 4: Make executable and run test to verify it passes**

Run: `chmod +x claude-hooks-merge.sh && sh tests/test-claude-hooks-merge.sh`
Expected: PASS.

- [ ] **Step 5: Wire into `install.sh`.** Add `jq` to the CLI-tools block — insert after the `ensure_tool fzf fzf` line (install.sh:89):

```bash
ensure_tool jq jq             # JSON processor (Claude hook merge, tooling)
```

Then add the merge step immediately before the "Drift check" block (before install.sh:175, `# ── Drift check`):

```bash
# ── Claude Code agent hooks (tmux notifications) ─────────────
# Idempotent jq-merge into ~/.claude/settings.json (NOT symlinked — Claude
# rewrites that file). Safe to re-run; see claude-hooks-merge.sh.
if command -v jq &>/dev/null; then
  if "$DOTFILES_DIR/claude-hooks-merge.sh" "$HOME/.claude/settings.json" "$XDG_CONFIG_HOME/tmux/scripts"; then
    echo "Wired Claude Code agent hooks into ~/.claude/settings.json"
  else
    echo "!! Claude hook merge failed — see README to add hooks manually"
  fi
else
  echo "!! jq missing — skipped Claude hook merge (see README)"
fi

```

- [ ] **Step 6: Verify install.sh still parses**

Run: `bash -n install.sh && echo OK`
Expected: `OK` (no syntax errors).

- [ ] **Step 7: Commit**

```bash
git add claude-hooks-merge.sh install.sh tests/test-claude-hooks-merge.sh
git commit -m "feat(install): jq-merge Claude agent-notify hooks into settings.json"
```

---

## Task 7: Health check (`agent-doctor`), doctor.sh wiring & README

**Files:**
- Create: `tmux/.config/tmux/scripts/agent-doctor`
- Modify: `doctor.sh` (call `agent-doctor`, report-only)
- Modify: `README.md` (add "tmux + AI agents" section)
- Create: `tests/test-agent-doctor.sh`

**Interfaces:**
- Consumes: env `AGENT_DOCTOR_SETTINGS` (default `~/.claude/settings.json`), `XDG_CONFIG_HOME`.
- Produces: prints `✓`/`▲` health lines for passthrough/extended-keys/monitor-bell (when a server runs), script executability, `jq`, and hooks-in-settings. Exit 0 always.

- [ ] **Step 1: Write the failing test** — `tests/test-agent-doctor.sh`

```sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-agent-doctor.sh`
Expected: FAIL (`agent-doctor` does not exist).

- [ ] **Step 3: Write `tmux/.config/tmux/scripts/agent-doctor`**

```sh
#!/bin/sh
# agent-doctor — report-only health check for the AI-agent tmux integration.
# Prints ✓/▲ lines; always exits 0.
settings="${AGENT_DOCTOR_SETTINGS:-$HOME/.claude/settings.json}"
scripts="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts"

echo "AI-agent tmux integration:"

if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  [ "$(tmux show -gv  allow-passthrough 2>/dev/null)" = "on" ] && echo "  ✓ allow-passthrough on" || echo "  ▲ allow-passthrough not on (reload tmux)"
  [ "$(tmux show -sv  extended-keys 2>/dev/null)" = "on" ]     && echo "  ✓ extended-keys on"      || echo "  ▲ extended-keys not on"
  [ "$(tmux show -gwv monitor-bell 2>/dev/null)" = "on" ]      && echo "  ✓ monitor-bell on"       || echo "  ▲ monitor-bell not on"
else
  echo "  … no tmux server running; start tmux to check live options"
fi

for s in agent-notify agent-clear agent-summary; do
  if [ -x "$scripts/$s" ]; then echo "  ✓ $s executable"; else echo "  ▲ $s missing/not executable ($scripts/$s)"; fi
done

if command -v jq >/dev/null 2>&1; then
  echo "  ✓ jq present"
  if [ -f "$settings" ] && jq -e '.hooks.Stop and .hooks.Notification and .hooks.UserPromptSubmit' "$settings" >/dev/null 2>&1; then
    echo "  ✓ Claude hooks present in $settings"
  else
    echo "  ▲ Claude hooks not found in $settings (re-run install.sh)"
  fi
else
  echo "  ▲ jq not present (needed for hook install)"
fi
exit 0
```

- [ ] **Step 4: Make executable and run test to verify it passes**

Run: `chmod +x tmux/.config/tmux/scripts/agent-doctor && sh tests/test-agent-doctor.sh`
Expected: PASS.

- [ ] **Step 5: Wire into `doctor.sh`.** Insert after the `ADOPT` parsing line (doctor.sh:23, `[ "${1:-}" = "--adopt" ] && ADOPT=1`):

```bash

# ── AI-agent tmux integration health (report-only; never affects drift) ──
if [ "$ADOPT" -eq 0 ] && [ -x "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" ]; then
  "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" || true
  echo
fi
```

- [ ] **Step 6: Verify doctor.sh still parses**

Run: `bash -n doctor.sh && echo OK`
Expected: `OK`.

- [ ] **Step 7: Add the README section.** Append to `README.md`:

```markdown
## tmux + AI agents

The tmux config is tuned for running several Claude Code sessions in parallel
and seeing, at a glance, which one needs you.

**Attention chips.** Each window shows a colored chip when its agent changes
state, driven by Claude Code hooks:

| Chip        | Meaning                          |
|-------------|----------------------------------|
| `● working` | you submitted a prompt (yellow)  |
| `▲ input`   | Claude is waiting on you (red)   |
| `✔ done`    | Claude finished a turn (green)   |

`▲ input` / `✔ done` also ring the terminal bell and emit an OSC 9 desktop
notification (your terminal shows a native toast). Chips clear when you focus
the window. The right side of the status bar aggregates across windows, e.g.
`▲2 ●1`.

**How it's wired.** Three Claude hooks (`UserPromptSubmit`, `Notification`,
`Stop`) call `~/.config/tmux/scripts/agent-notify`, which sets a per-window
`@agent_state` tmux option. `install.sh` merges these hooks into
`~/.claude/settings.json` with `jq` (idempotent; backs up first; never
overrides your own `preferredNotifChannel` or other hooks). That file is **not**
symlinked because Claude rewrites it.

Add the hooks manually if you skipped the merge — put this in
`~/.claude/settings.json` (adjust the path):

    {
      "preferredNotifChannel": "terminal_bell",
      "hooks": {
        "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.config/tmux/scripts/agent-notify" }] }],
        "Notification":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.config/tmux/scripts/agent-notify" }] }],
        "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.config/tmux/scripts/agent-notify" }] }]
      }
    }

**Keys** (prefix is `C-a`): `M-h/j/k/l` move between panes, `M-H`/`M-L`
previous/next window, `prefix S` toggles `synchronize-panes` (type into every
pane at once), `prefix Enter` opens a scratch popup, `prefix g` opens the
session tree.

**Limitation.** `@agent_state` is per-window, so two agents in one window share
one chip — run roughly one agent per window/session for clean signals.

**Health check.** `./doctor.sh` prints an "AI-agent tmux integration" section;
`~/.config/tmux/scripts/agent-doctor` runs it standalone.

_Phase 2 (planned): an fzf `sessionizer` popup (`prefix f`) and a git-`worktree`
launcher (`prefix W`)._
```

- [ ] **Step 8: Run the full suite**

Run: `sh tests/run.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 9: Commit**

```bash
git add tmux/.config/tmux/scripts/agent-doctor doctor.sh README.md tests/test-agent-doctor.sh
git commit -m "feat(tmux): add agent-doctor health check and document agent workflow"
```

---

## Final verification (after all tasks)

- [ ] **Run the whole suite:** `sh tests/run.sh` → `ALL TESTS PASSED`.
- [ ] **Re-stow and load live:** `./install.sh` (or `stow --no-folding --target="$HOME" --restow tmux`), then in tmux `prefix r` to reload; confirm no errors and the status bar renders.
- [ ] **Manual E2E:** open a window, run `claude`, submit a prompt (chip → `● working`), trigger a permission prompt (→ `▲ input` + bell), let it finish (→ `✔ done` + bell), focus the window (chip clears), check `status-right` shows the aggregate.
- [ ] **Idempotency:** re-run `./install.sh`; confirm `~/.claude/settings.json` hooks are not duplicated (`jq '.hooks.Stop | length'` stays `1`).
```
