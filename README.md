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
claude/.claude/CLAUDE.md   ->  ~/.claude/CLAUDE.md
```

Everything is XDG-based (`~/.config`, `~/.local/share`, …).

The `claude` package deploys global agent conventions (e.g. Conventional
Commits) to `~/.claude/CLAUDE.md`, which Claude Code reads for **every** project
on the machine. Only that one file is symlinked into `~/.claude`; the rest of
that directory (state, sessions) is left alone.

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
