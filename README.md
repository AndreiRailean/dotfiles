# dotfiles

Personal cross-platform dotfiles for **macOS, WSL, and Linux** (desktops and
SSH-only servers), managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Bootstrap

Clone into `~/dotfiles` and run the installer:

```sh
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then restart your shell (or `exec "$SHELL"`).

`install.sh` is safe to re-run; it's idempotent. It will:

1. Install GNU Stow if missing (brew / apt / pacman).
2. Symlink every package into `$HOME` with `stow --no-folding`.
3. Append a one-line loader to `~/.bashrc` / `~/.zshrc` (if they exist),
   sourcing the managed shell entrypoint. Your distro rc and its defaults are
   left intact.
4. Seed the per-machine files (`~/.config/git/local`, `~/.config/shell/local.sh`)
   from their `*.example` templates — never overwriting an existing one.
5. Best-effort install Starship, a Nerd Font, and (on WSL) `win32yank` for
   clipboard bridging. Terminal font selection is a manual step it prints.

## Layout

Each top-level directory is a **Stow package** that mirrors `$HOME`. Stowing a
package symlinks its contents into the matching location under your home dir.

```
shell/.config/shell/*.sh   ->  ~/.config/shell/*.sh
git/.config/git/config     ->  ~/.config/git/config
nvim/.config/nvim/          ->  ~/.config/nvim/
tmux/.config/tmux/          ->  ~/.config/tmux/
starship/.config/starship.toml -> ~/.config/starship.toml
starship/.config/starship/devserver-port.sh -> ~/.config/starship/devserver-port.sh
claude/.claude/CLAUDE.md   ->  ~/.claude/CLAUDE.md
claude/.claude/settings.json -> ~/.claude/settings.json
claude/.claude/statusline-command.sh -> ~/.claude/statusline-command.sh
herdr/.config/herdr/config.toml -> ~/.config/herdr/config.toml
herdr/.config/herdr/scripts/    -> ~/.config/herdr/scripts/
herdr/.config/systemd/user/     -> ~/.config/systemd/user/
lazygit/.config/lazygit/config.yml -> ~/.config/lazygit/config.yml
```

Everything is XDG-based (`~/.config`, `~/.local/share`, …).

The `claude` package deploys global agent conventions (e.g. Conventional
Commits) to `~/.claude/CLAUDE.md`, which Claude Code reads for **every** project
on the machine, plus the global `settings.json` and the status-line script.
Only those three files are symlinked into `~/.claude`; the rest of that
directory (state, sessions, history) is left alone.

`settings.json` is the live file Claude Code reads **and writes** — it rewrites
it whenever you change a setting via `/config`, toggle a plugin, or accept a
permission dialog. Claude writes *through* the symlink, so those edits land in
this repo as a normal diff: run `git diff` after tweaking settings and commit
what you want to keep. Two consequences worth knowing:

- Paths inside it must be portable. Both the hook commands and `statusLine`
  run in a shell, so use `$HOME/…`, never `/home/<user>/…`.
- Never put secrets in it (e.g. an `env` block with an API token) — it's a
  tracked file. Machine-local secrets belong in `~/.config/shell/local.sh`.

On a machine that already has its own `~/.claude/settings.json`, `install.sh`
moves it aside to `settings.json.pre-dotfiles.<epoch>` before stowing, so
nothing is silently overwritten.

This applies to every package, not just this one. `stow` refuses to link over a
target that is a real file, and under `set -e` that refusal aborts the whole
install — so a config a tool wrote before this repo managed it (lazygit creates
an empty `~/.config/lazygit/config.yml` on first launch) would otherwise stop
the run before it installed anything further. `install.sh` displaces any such
file to `<name>.pre-dotfiles.<epoch>`; `doctor.sh` ignores those backups, so
delete them once you've salvaged anything machine-local.

## Shell configuration

The shell config is a set of POSIX-`sh` **fragments** that both bash and zsh
source, so there's a single source of truth across shells:

```
~/.bashrc / ~/.zshrc          # per-machine (NOT in repo); one line sources ↓
  └─ ~/.config/shell/init.sh   # entrypoint — sources the fragments below
       ├─ env.sh     # XDG vars, EDITOR/VISUAL/PAGER
       ├─ path.sh     # idempotent PATH building (path_prepend)
       ├─ aliases.sh  # ls/grep/git/cd shortcuts, vim -> nvim
       ├─ tools.sh    # fnm, deno (shell-detected)
       ├─ prompt.sh   # starship (shell-detected, interactive only)
       └─ local.sh    # per-machine overrides (gitignored)
```

Anything shell-specific (e.g. `starship init bash` vs `zsh`) is handled inside
the fragment by checking `$BASH_VERSION` / `$ZSH_VERSION` at runtime.

**Why `.bashrc`/`.zshrc` stay per-machine:** each host keeps its distro-provided
rc (with its own defaults) and just sources the managed `init.sh`. This avoids
clobbering OS defaults and keeps SSH-only boxes low-risk. Promoting them into a
managed package later is a non-breaking change — the fragments stay the same.

### `vim` → neovim

Most distros ship a preinstalled vim, and on Debian/Ubuntu the neovim package
registers `nvim` in the `vim`/`vi` alternative groups at the *same priority* as
`vim.basic` — so "auto" mode resolves by install order and `vim` keeps opening
classic vim. Three layers cover it:

| Layer                                  | Covers                                   |
| -------------------------------------- | ---------------------------------------- |
| `EDITOR`/`VISUAL` (`env.sh`)           | git, `crontab -e`, anything reading them |
| `vim`/`vi`/`vimdiff` aliases (`aliases.sh`) | what you type at an interactive prompt |
| `update-alternatives --set` (`install.sh`) | the binary itself — scripts, `sudo vim` |

`install.sh` pins the alternative on every machine (idempotent, needs `sudo`,
skipped where nvim isn't a registered candidate — macOS, Arch, tarball
installs). `doctor.sh` warns if the `vim` binary is still classic vim. The
distro-wide `editor` group is left alone on purpose.

`install.sh` also installs neovim when it's missing: on Ubuntu (and Mint/Pop)
from the official `ppa:neovim-ppa/stable`, because the distro package trails by
a release or two and the PPA's `.deb` is what registers nvim with
`update-alternatives`. Debian and other apt distros get the distro package;
brew and pacman already ship current builds. If nvim is *already* installed the
whole step is skipped, so a machine deliberately tracking the nightly
`unstable` PPA keeps it.

### Paging: `less` → bat, git diffs → delta

`bat` provides the highlighting, with the split chosen so each name keeps the
behaviour you expect:

| Command | Behaviour                                                       |
| ------- | --------------------------------------------------------------- |
| `cat`   | `--paging=never` — a true drop-in for `cat`, safe in pipelines    |
| `bat`   | `--paging=auto` — pages only when output doesn't fit             |
| `less`  | `--paging=always` — always pages, like real `less`               |

bat runs `less` underneath, so `/`, `g`/`G` and `q` behave normally. It does
*not* understand less's own flags (`+F` to follow, `-N`, `-S`) — use
`command less` for those.

Git diffs go through [delta](https://github.com/dandavison/delta) (`git-delta`
on apt/brew/pacman — *not* `delta`, which on Debian/Ubuntu is an unrelated
2006-era binary-diff tool). `core.pager` is written as a guarded expression:

```gitconfig
pager = command -v delta >/dev/null 2>&1 && delta || less
```

The guard is load-bearing, not decoration — git treats a missing pager as
**fatal** (`unable to execute pager`), so a bare `pager = delta` would break
git outright on any machine that hasn't installed it yet. `core.pager` is run
through a shell, so the `||` fallback works. `interactive.diffFilter` is
guarded the same way, falling back to `cat`.

Diffs render side-by-side (delta falls back to unified on a narrow terminal),
and `merge.conflictstyle = zdiff3` adds the common ancestor to conflict markers
while hoisting the lines both sides already agree on out of the conflict.
zdiff3 needs git ≥ 2.35 — a test performs a real conflicting merge to confirm
the running git accepts it.

`$PAGER` itself stays plain `less`, so non-interactive callers (`man`,
`systemctl`, …) are unaffected.

[lazygit](https://github.com/jesseduffield/lazygit) reuses delta for its own
diffs, with the same guarded `|| less` fallback — but adds `--no-gitconfig`, so
it ignores the `delta` block above. That's deliberate: `side-by-side` is right
for a diff filling the terminal and unreadable in lazygit's half-width panel,
and delta's `--side-by-side` is a plain flag that can't be switched off with
`=false`.

`install.sh` installs lazygit from the **upstream release**, not the distro
package, and gates on a version floor of **0.64.0** — upgrading an older binary
rather than skipping it. 0.64 replaced the `git.paging` config block with
`git.diffRenderers`, which is what `lazygit/.config/lazygit/config.yml` uses;
older lazygit ignores those keys silently, so a Debian-packaged 0.50 would give
you no delta and no warning. If a future lazygit migrates the schema again it
rewrites the config in place, through the stow symlink — that shows up as
ordinary drift in `git status` here.

## Per-machine settings

Machine-local, secret, or identity settings live in files seeded from templates
and **ignored by git**:

| Copy from                                   | To                          | For                          |
| ------------------------------------------- | --------------------------- | ---------------------------- |
| `git/.config/git/local.example`             | `~/.config/git/local`       | git identity, signing, creds |
| `shell/.config/shell/local.sh.example`      | `~/.config/shell/local.sh`  | per-host PATH, env, aliases  |

`git/config` pulls in `~/.config/git/local` via an `[include]`; `init.sh`
sources `local.sh` last so it can override anything.

## Adding a package

```sh
mkdir -p newtool/.config/newtool
# put config under newtool/.config/newtool/...
echo '  newtool \' # add it to the stow loop in install.sh
stow --no-folding --target="$HOME" newtool
```

## Detecting drift (`doctor.sh`)

Because of `--no-folding` (see below), a tool that writes a *new* file into a
managed dir — e.g. `~/.config/nvim/lazy-lock.json` — creates a real file
**outside** the repo, so it never shows up in the dotfiles `git status`.
`doctor.sh` catches exactly that:

```sh
./doctor.sh          # report untracked files, broken symlinks, unlinked configs
./doctor.sh --adopt  # move untracked files into the repo and re-stow them
```

It runs automatically (report-only) at the end of `install.sh`, and uses
`.gitignore` as the source of truth — anything intentionally per-machine
(`local.sh`, `git/local`) is never flagged.

### Deleting a tracked file

`git rm`-ing a file from a package leaves every *other* machine with a symlink
pointing at something that no longer exists, and `stow --restow` won't clean
that up: stow only unlinks what the package currently contains, so a link whose
repo file is gone is invisible to it. Left alone it would survive every future
install and `doctor.sh` would report it as drift forever — one machine's
deletion becoming a manual chore on all the others.

So `install.sh` prunes them, and removes any directory left empty as a result.
The scope is narrow, because this deletes things in `$HOME`: a symlink must be
dangling **and** inside a directory one of our packages owns **and** point back
into this repo. A broken link you made yourself, or one aimed anywhere else, is
left alone. Deleting a tracked file is therefore just: commit the removal, then
run `./install.sh` on each machine as usual.

### Drift in the other direction

Some tracked files are rewritten by the tool that owns them rather than by you
— Claude Code rewrites `claude/.claude/settings.json` on every `/config`,
`/effort`, or `/fast` change, plugin toggle, and accepted dialog. Those edits
land *inside* the repo, so stow and symlinks are all healthy; they just sit
uncommitted until you happen to run `git status` in `~/dotfiles`.

Two things watch for that:

- **`doctor.sh`** reports uncommitted changes to the files listed in
  `.auto-written`, plus any commits you haven't pushed (unpushed commits
  aren't on your other machines, which defeats the point of the repo).
- **`shell/.config/shell/drift.sh`** prints a two-line nudge at terminal
  startup when either applies — so you hear about it even on a day you never
  open Claude. Interactive shells only, ~5 ms, and rate-limited to once every
  4 h so a wall of tmux panes doesn't each report it.

    DOTFILES_DRIFT_NUDGE=0          # silence it
    DOTFILES_DRIFT_NUDGE_HOURS=24   # nudge at most once a day
    _dotfiles_drift_nudge force     # check right now, ignoring the rate limit

Both read the same list from `.auto-written` in the repo root, so a new
machine-written file only has to be added once. Both are deliberately scoped to
those files rather than the whole repo: a warning that fires on every ordinary
dotfiles edit is one you learn to ignore.

**Not covered:** a brand-new tool writing to a location no package touches yet
(e.g. `~/.config/bat/`). `~/.config` is too full of cache/state to scan blindly,
so the workflow there is to notice the new tool and add it as a package
(see above).

## Notes / gotchas

- **`stow --no-folding` is deliberate.** Without it, Stow symlinks whole
  directories into the repo, so a machine-local file created in
  `~/.config/shell/` would land *inside* the repo. `--no-folding` keeps those
  as real directories with per-file symlinks.
- **git `include.path` is absolute (`~/.config/git/local`), not relative.**
  Because `~/.config/git/config` is a symlink into this repo, git resolves a
  *relative* include against the symlink's target (inside the repo) — not where
  the per-machine file actually lives.

## tmux

tmux is kept for plain and SSH-only boxes. [herdr](#herdr) is the driver for
agent work.

**Keys** (prefix is `C-a`): `M-h/j/k/l` move between panes, `M-H`/`M-L`
previous/next window, `prefix S` toggles `synchronize-panes` (type into every
pane at once), `prefix Enter` opens a scratch popup, `prefix g` opens the
session tree.

The config also sets `allow-passthrough` (so OSC sequences reach the outer
terminal), `extended-keys` (Shift+Enter in TUIs that want it), and
`focus-events` (what makes nvim's `autoread` and `FocusGained` fire).

**No agent integration here.** An earlier version showed per-window Claude Code
attention chips, driven by three Claude hooks calling `scripts/agent-notify`.
That was removed in favour of herdr, which reports agent state natively. See
`docs/superpowers/specs/2026-07-24-tmux-ai-agents-design.md` for what it did and
why, if you ever want it back.

_Phase 2 (planned): an fzf `sessionizer` popup (`prefix f`) and a git-`worktree`
launcher (`prefix W`)._

## herdr

[herdr](https://herdr.dev) is an agent-aware, tmux-style terminal multiplexer
purpose-built for running multiple AI coding agents at once — it gives each
agent a real persistent pane and surfaces working/blocked/done/idle state
natively (what the tmux setup above approximates with hooks). It's the
agent-focused driver; **tmux stays** for plain and SSH-only boxes.

`install.sh` installs it via the official installer
(`curl -fsSL https://herdr.dev/install.sh | sh`; on macOS you can also
`brew install herdr`). It's a static, self-updating binary — `herdr update`
keeps it current, so there's no version pin here.

**Managed config** lives at `~/.config/herdr/config.toml` (a normal Stow
package). It's deliberately minimal — herdr auto-detects agents with zero
config — pinning only:

- `prefix = "ctrl+a"` to match the tmux prefix,
- the `tokyo-night` theme,
- `onboarding = false`.

Run `herdr --default-config` to see everything else you could set, and
`herdr server reload-config` (or `prefix+shift+r`) after editing.

**Only `config.toml` is tracked.** herdr also writes runtime state into that
same directory (`herdr*.sock`, `herdr*.log`, `session.json`, `.plugins.lock`);
those are git-ignored so they're never committed and `doctor.sh` doesn't flag
them as drift. If a machine already has a real `config.toml` there, `stow` will
conflict — adopt it with `./doctor.sh --adopt` or remove it first.

### Auto-layout for new worktrees

Every new git-worktree workspace gets the same treatment automatically:

```
┌────────────────┬────────────────┐   tab 1: "claude"
│ claude         │ plain shell    │   left pane focused
└────────────────┴────────────────┘
tab 2: "lazygit"
```

`install.sh` installs lazygit itself, so the tab has a binary behind it on a
fresh machine; set `HERDR_AUTOLAYOUT_LAZYGIT_CMD=` to skip the tab entirely.

herdr has **no declarative hook** for this — there's no `on_worktree_create` in
`config.toml`, and `herdr integration` only manages agent integrations. So
`herdr/.config/herdr/scripts/herdr-autolayout` subscribes to the socket API's
event stream instead, which keeps the native `prefix+shift+G` flow untouched and
fires however the worktree was created (TUI, CLI, or API).

**Or apply it by hand: `prefix+shift+L`.** Same code path, for a workspace that
predates the daemon or one you've since rearranged. It's idempotent — the split
only happens when the tab has one pane, an existing lazygit tab is reused, and a
command is only sent if it isn't already running — so pressing it twice is a
no-op. Two entry points, one implementation:

    herdr-autolayout                  # daemon: arrange every new worktree
    herdr-autolayout arrange [WS_ID]  # arrange one workspace now

With no argument it targets the workspace it was invoked from, via the
`HERDR_WORKSPACE_ID` that herdr exports into every pane — no API call, and
correct even when the herdr client's focus is elsewhere.

The binding is a `[[keys.command]]` of `type = "popup"` rather than `"pane"`: a
popup is session-modal and doesn't alter the tab layout, and it doubles as a
progress log since it stays up until the script finishes.

There's deliberately no attempt to have the daemon *press* the shortcut.
`pane.send_keys` targets a pane's program, not herdr's input layer, and
registering a real plugin action (`plugin.action.invoke`) needs an undocumented
plugin manifest. Calling the same function is simpler and works on an unfocused
workspace.

It runs as a systemd **user** unit (`herdr-autolayout.service`), enabled by
`install.sh`. Logs go to `$XDG_STATE_HOME/herdr/autolayout.log` — deliberately
outside `~/.config/herdr/`, which `doctor.sh` treats as a managed tree.

    systemctl --user status herdr-autolayout    # is it running?
    systemctl --user restart herdr-autolayout   # after editing the script
    tail -f ~/.local/state/herdr/autolayout.log

Tunable by setting environment variables on the unit (`systemctl --user edit
herdr-autolayout`) — `HERDR_AUTOLAYOUT_` plus:

| | |
| --- | --- |
| `LEFT_CMD` | left pane command (default `claude`; empty = plain shell) |
| `RIGHT_CMD` | right pane command (default: none, just a shell) |
| `LAZYGIT_CMD` | lazygit tab command (empty skips the tab entirely) |
| `MAIN_TAB` | first tab's label (default `claude`; empty keeps herdr's number) |
| `LAZYGIT_TAB` | lazygit tab's label (default `lazygit`) |
| `FOCUS` | `left` (default) / `right` / `lazygit` / `none` |
| `DIRECTION` | `right` (default) / `down` |
| `RATIO` | split ratio, e.g. `0.5` |
| `READY_SECS` | how long to wait for a shell prompt (default 90) |

Four things worth knowing before touching it:

- **Typing into a pane is the hard part.** Neither `pane split` nor
  `tab create` takes a `--command`, so commands are typed with
  `pane send-text` — and text sent before the shell reaches its prompt is
  echoed to the screen then discarded. Shell init here takes ~5s, so this bites
  every time. `fg == shell_pid` does *not* mean ready (bash is its own
  foreground group the instant it spawns); the daemon also waits for the pane to
  have drawn something, then **verifies the process actually started** and
  retries with a ctrl-u if it didn't.
- **Each new worktree is a new directory, so Claude Code shows its "trust this
  folder" prompt** the first time. Press enter; there's no way around it from
  here.

- **Subscribing replays recent `workspace_created` events.** Without a guard, a
  restart would re-split workspaces you'd already arranged. The daemon only acts
  on a workspace that still has exactly one tab and one pane, which makes it
  idempotent — already-arranged and since-deleted workspaces are skipped.
- **It leans on two undocumented API behaviours.** `events.wait` advertises
  workspace matches in the schema but the server rejects them
  (`unsupported_event_wait_match`), and `workspace_created` *is* delivered on a
  subscription even though `SubscriptionEventKind` doesn't list it. A herdr
  upgrade could change either. Failures are logged and the loop reconnects, so
  the worst case is layouts quietly stop — never a broken herdr.
- **The `herdr` package now also owns `~/.config/systemd`** (for the unit), so
  `doctor.sh` scans it. A hand-added user unit there will show up as untracked
  drift — adopt it or add it to `.gitignore`.
