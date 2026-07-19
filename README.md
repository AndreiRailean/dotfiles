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
```

Everything is XDG-based (`~/.config`, `~/.local/share`, …).

## Shell configuration

The shell config is a set of POSIX-`sh` **fragments** that both bash and zsh
source, so there's a single source of truth across shells:

```
~/.bashrc / ~/.zshrc          # per-machine (NOT in repo); one line sources ↓
  └─ ~/.config/shell/init.sh   # entrypoint — sources the fragments below
       ├─ env.sh     # XDG vars, EDITOR/VISUAL/PAGER
       ├─ path.sh     # idempotent PATH building (path_prepend)
       ├─ aliases.sh  # ls/grep/git/cd shortcuts
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
