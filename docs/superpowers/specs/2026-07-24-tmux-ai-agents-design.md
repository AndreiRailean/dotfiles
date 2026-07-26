# tmux for AI agents — design (v1)

Date: 2026-07-24
Repo: personal dotfiles (Stow-managed; macOS / WSL / Linux / SSH-only servers)
Target: tmux 3.6, Claude Code as the primary agent

## Goal

Make tmux a comfortable place to run **multiple Claude Code sessions in
parallel** and know, at a glance, **which session needs attention**. Do it
plugin-free (pure tmux + small POSIX scripts) so it works instantly on an
SSH-only box, and keep it portable across macOS/WSL/Linux.

## Scope

**v1 (this spec):**

1. Core tmux settings needed for Claude notifications to work at all.
2. A redesigned, information-dense status bar (no green theme) whose **window
   list flags the windows that need attention** with colored chips.
3. Claude Code hook integration that drives per-window agent state
   (`working` → `needs-input` → `done`) plus a terminal bell + OSC 9 desktop
   notification.
4. A `jq`-merge in `install.sh` that wires the hooks into
   `~/.claude/settings.json` with safeguards.
5. Navigation/ergonomics keys that are pure config (no scripts).
6. README + `doctor.sh` updates.

**Phase 2 (explicitly out of scope here):** an fzf `sessionizer` popup and a
git-`worktree` launcher script. Noted at the end; not built in v1.

## Non-goals / accepted limitations

- **Per-window (not per-pane) agent state.** `@agent_state` is a window option,
  so two agent panes in one window share one chip (last writer wins). Clean
  signals therefore assume roughly **one agent per window/session** — which is
  what the multi-project and (phase-2) worktree workflows naturally produce.
  Side-by-side agents in one window still work, just with a coarser single chip.
  Per-pane aggregation is possible later; excluded from v1 for simplicity.
- No WSL-specific Windows-toast bridge. Notifications are **in-tmux (chips) +
  terminal bell + OSC 9**, which any capable terminal (iTerm2, Kitty, Ghostty,
  Windows Terminal) turns into its own desktop notification. This keeps the
  setup identical on macOS and over SSH.
- `monitor-activity` is intentionally **off** globally: a streaming agent pane
  emits output constantly and would flag forever. The bell (precise) plus the
  hook-driven chips (precise) are the signals; activity is not.

## Architecture

Four cooperating pieces:

```
Claude Code ──hook (stdin JSON)──> scripts/agent-notify ──> tmux set-window-option @agent_state
                                                        └──> printf bell + OSC 9 to /dev/tty
tmux pane-focus-in ─────────────> scripts/agent-clear  ──> clear attention state for that window
tmux.conf ──renders──> #{?@agent_state, #{E:@agent_state},}  in the window list + status-right summary
install.sh ──jq-merge──> ~/.claude/settings.json (hooks + preferredNotifChannel)
```

### Layering (so a bare box still works)

- **Baseline layer (no scripts required):** `monitor-bell on` + a styled bell
  flag + `preferredNotifChannel: "terminal_bell"`. On any machine where only
  `tmux.conf` is present, a finished/waiting Claude still rings the bell and
  flags its window. Distinguishes nothing finer than "wants you."
- **Rich layer (scripts + hooks present):** colored `working`/`needs-input`/
  `done` chips via `@agent_state`. Degrades gracefully to the baseline if the
  hooks or scripts are absent.

## Component 1 — `tmux.conf` additions

Added to the existing `tmux/.config/tmux/tmux.conf`, preserving `C-a` prefix,
vi keys, splits, reload, mouse, scrollback.

### 1a. Claude/terminal plumbing (required)

```tmux
set  -g  allow-passthrough on
set  -s  extended-keys on
set  -as terminal-features 'xterm*:extkeys'
set  -g  focus-events on
```

`allow-passthrough` lets OSC notifications escape tmux to the outer terminal;
the extended-keys pair fixes Shift+Enter inside Claude; `focus-events` is
required for the `pane-focus-in` clear hook.

### 1b. Native monitoring baseline

```tmux
setw -g monitor-bell on
setw -g monitor-activity off
set  -g visual-bell off            # keep the audible/passed-through bell; rely on flags for visuals
set  -g bell-action other          # flag bells in other windows, not the one you're looking at
set  -g window-status-bell-style   'fg=colour232,bg=colour203,bold'
set  -g window-status-activity-style 'fg=colour232,bg=colour220'
```

### 1c. Agent-state chip + status bar redesign

Neutral dark bar, blue active highlight, explicit 256-colors for cross-platform
consistency. Chips carry their own backgrounds so they pop on any bar color.

The `agent-notify` script stores a **pre-styled** string in `@agent_state`, e.g.
`#[fg=colour232,bg=colour203,bold] ▲ input #[default]`. The window list expands
it a second time with `#{E:...}` so the embedded styling renders:

```tmux
set  -g status-interval 5
set  -g status-position bottom
set  -g status-style 'bg=colour236,fg=colour245'

# Left: session name + prefix-armed indicator
set  -g status-left '#[fg=colour232,bg=colour110,bold] #S #{?client_prefix,#[fg=colour232,bg=colour214,bold] ⌘ ,}#[default] '
set  -g status-left-length 40

# Window list: index:name flags then the agent chip when set
setw -g window-status-format         ' #I:#W#F #{?@agent_state,#{E:@agent_state},}'
setw -g window-status-current-format '#[fg=colour232,bg=colour110,bold] #I:#W#F #[default]#{?@agent_state,#{E:@agent_state},}'
setw -g window-status-separator ''

# Right: aggregate agent summary + host (only over SSH) + clock.
# The #(...) body runs in a shell, so use shell-style ${VAR:-default}; tmux's
# own #{VAR} format does NOT support ":-" defaults (it errors).
set  -g status-right '#(${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts/agent-summary) #{?SSH_CONNECTION,#[fg=colour109] #h ,}#[fg=colour245] %H:%M '
set  -g status-right-length 60
```

Chip strings the notify script writes (readable on the dark bar and against each
other):

| State        | Stored `@agent_state` value                                      |
|--------------|-------------------------------------------------------------------|
| working      | `#[fg=colour232,bg=colour220,bold] ● working #[default]`          |
| needs-input  | `#[fg=colour232,bg=colour203,bold] ▲ input #[default]`            |
| done         | `#[fg=colour232,bg=colour077,bold] ✔ done #[default]`             |

(Exact colors are a single-line change; the plan will keep them in one block.)

### 1d. Clear-on-focus hook

```tmux
# run-shell body is a shell command, so use shell-style ${VAR:-default}.
set-hook -g pane-focus-in "run-shell -b '\"${XDG_CONFIG_HOME:-$HOME/.config}\"/tmux/scripts/agent-clear #{window_id} \"#{@agent_state}\"'"
```

`agent-clear` clears the window's `@agent_state` **only when it is an attention
state** (`done` or `needs-input`), leaving `working` in place so a still-running
agent you glance at keeps its chip.

### 1e. Navigation / ergonomics (pure config, no scripts)

```tmux
# prefix-less pane navigation while juggling many panes
bind -n M-h select-pane -L
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l select-pane -R
# window switching
bind -n M-H previous-window
bind -n M-L next-window
# broadcast the same prompt to every pane (toggle)
bind S setw synchronize-panes \; display 'sync #{?pane_synchronized,ON,OFF}'
# scratch shell popup over any window
bind Enter display-popup -E -w 80% -h 70%
# choose-tree with preview (native), already prefix+s; add prefix+g as alias
bind g choose-tree -Zw
```

## Component 2 — `tmux/.config/tmux/scripts/` (new)

Three small POSIX-`sh` scripts, executable, stowed with the tmux package.

### `agent-notify`
Called by Claude hooks. Reads hook JSON from stdin.
- Resolve the target window from `$TMUX_PANE` (the agent's own pane — must be
  explicit, not the active window).
- Branch on `hook_event_name`:
  - `UserPromptSubmit` → `working`
  - `Notification` → `needs-input` (regardless of matcher in v1)
  - `Stop` → `done`
- `tmux set-window-option -t "$TMUX_PANE" @agent_state '<styled chip>'`.
- Emit attention signal to the terminal: `printf '\a' > /dev/tty` (bell) and an
  OSC 9 desktop notification, tmux-DCS-wrapped when `$TMUX` is set so
  passthrough forwards it. Suppress the bell/OSC for `working` (only signal
  `needs-input` and `done`, to avoid a bell on every prompt submit).
- Depends on: `jq` (parse stdin), `tmux`. Must be a no-op (exit 0) when not
  running inside tmux, so hooks never fail a Claude turn.

### `agent-clear`
Args: `<window_id> <current @agent_state>`. Clears the window's `@agent_state`
if the current value is an attention state; otherwise exits 0. Runs backgrounded
(`run-shell -b`) so focus is never blocked.

### `agent-summary`
No args. Prints a compact aggregate for `status-right`, e.g. `▲2 ●1`, by reading
each window's `@agent_state` (`tmux list-windows -a -F ...`) and counting states.
Prints nothing when no agent windows are flagged. Kept cheap (single tmux call);
runs every `status-interval` (5s).

## Component 3 — Claude Code integration

### Settings merged into `~/.claude/settings.json`
- `preferredNotifChannel: "terminal_bell"` — **only set if the key is absent**
  (respect an existing user choice).
- `hooks` with three events, each running `agent-notify`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "<scripts>/agent-notify" }] }
    ],
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "<scripts>/agent-notify" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "<scripts>/agent-notify" }] }
    ]
  }
}
```

`<scripts>` resolves to the stowed path
`$HOME/.config/tmux/scripts/agent-notify` (written absolute at merge time, since
settings.json is not shell-expanded).

`Stop` fires on every response turn (not just final completion) and not on
interrupts — acceptable because the chip is cleared on focus and overwritten by
the next `UserPromptSubmit`.

## Component 4 — `install.sh` jq-merge (with safeguards)

A new idempotent step. Safeguards:

1. **Ensure `jq`** the same way Stow is ensured (brew/apt/pacman); if it can't
   be installed, skip the merge with a printed manual-paste snippet instead of
   failing.
2. **Backup**: copy existing `~/.claude/settings.json` to
   `settings.json.bak` before any write.
3. **Validate input**: if the existing file is present but not valid JSON,
   abort the merge (don't clobber) and tell the user.
4. **Idempotent merge**: append our hook command objects only if an entry with
   the same `command` path is not already present (dedupe by command path), so
   re-running `install.sh` never duplicates hooks and never removes the user's
   own hooks. `preferredNotifChannel` set only if absent.
5. **Atomic write**: write to a temp file, validate it parses, then move into
   place. Create the file (and `~/.claude`) if missing.
6. Merge logic lives in a small self-contained jq program (kept in `install.sh`
   or a sibling file); no network, no side effects beyond the one file.

## Component 5 — Docs & doctor

- **README**: a "tmux + AI agents" section — what the chips mean, the keys, how
  the notification pipeline works, and how to retune colors. Note phase-2
  launchers as planned.
- **`doctor.sh`**: checks that (a) `allow-passthrough`/`extended-keys` are set
  in the running tmux (`tmux show -g`), (b) the scripts are executable, (c)
  `~/.claude/settings.json` contains our hooks, (d) `jq` is present. Report-only.

## Testing strategy (plugin-free, mostly harness-free)

- **Scripts** are unit-testable by piping fixture hook JSON to `agent-notify`
  with a fake `$TMUX_PANE` and asserting the `tmux set-window-option` call /
  emitted bell (use a stub `tmux` on `PATH`, or run inside a throwaway tmux
  server and read back `@agent_state`). `agent-summary` tested by setting
  `@agent_state` on windows in a scratch server and asserting output.
- **jq-merge** tested against fixtures: empty/missing file, file with unrelated
  hooks, file already containing our hooks (idempotency), invalid JSON (abort).
  Assert the backup is created and the result parses.
- **tmux.conf** validated with `tmux -f tmux.conf new-session -d` + `tmux show`
  in a scratch server; confirm no parse errors and options are set.
- **End-to-end** manual check documented in README: run Claude in a pane, submit
  a prompt (chip → working), let it ask for permission (→ input + bell), let it
  finish (→ done + bell), focus the window (chip clears).

## Phase 2 (not built now)

- `scripts/sessionizer` — fzf popup over project dirs + live sessions, bound to
  `prefix f`.
- `scripts/worktree` — create a git worktree on a new branch, open a session
  there, launch Claude; bound to `prefix W`.
