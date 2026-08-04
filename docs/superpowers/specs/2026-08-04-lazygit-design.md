# lazygit dotfiles package — design

Date: 2026-08-04
Repo: personal dotfiles (Stow-managed; macOS / WSL / Linux)

## Goal

Install [lazygit](https://github.com/jesseduffield/lazygit) from the dotfiles
and manage its config, closing a gap that already breaks on fresh machines: the
herdr auto-layout daemon opens a `lazygit` tab for every new git worktree
(`herdr/.config/herdr/scripts/herdr-autolayout:98`, `LAZYGIT_CMD`), but
`install.sh` never installs the binary — so that tab starts and immediately
dies.

## Decisions

- **Install: package manager first, GitHub release as fallback.** `pkg_install
  lazygit` covers brew and pacman (both current) and Debian trixie (0.50). It
  does *not* cover older Ubuntu LTS, where lazygit is absent from the archive
  entirely — hence the tarball fallback into `~/.local/bin`, the same shape as
  the existing win32yank / starship / herdr blocks. Best-effort: a failure
  prints `!!` and continues, never aborts the install.
- **No version pin.** Resolve the latest release at install time. lazygit is a
  single static binary with no config-format churn worth pinning against.
- **Config is managed, and diverges from the git config on one point:** delta
  without `--side-by-side`. See "The side-by-side divergence" below.
- **lazygit's own state stays out of the repo** via a scoped `.gitignore`
  entry, matching how the herdr package handles runtime files.

## Architecture

New Stow package `lazygit/` mirroring **only** the config file:

```
lazygit/.config/lazygit/config.yml  →  ~/.config/lazygit/config.yml
```

### The install block

Goes in `install.sh` **before** the herdr auto-layout section, so the daemon it
enables has its dependency in place.

Shape (illustrative, not final code):

```bash
# ── lazygit (git TUI; the herdr auto-layout tab runs it) ─────
if ! command -v lazygit &>/dev/null; then
  echo "Installing lazygit..."
  pkg_install lazygit || install_lazygit_release \
    || echo "!! lazygit install failed — install manually: https://github.com/jesseduffield/lazygit"
fi
```

`install_lazygit_release`, a helper defined alongside the block:

1. Resolve the latest tag from
   `https://api.github.com/repos/jesseduffield/lazygit/releases/latest`.
2. Map `uname -s` / `uname -m` onto the release asset name. Upstream publishes
   `lazygit_<version>_<Os>_<Arch>.tar.gz` — note the asset carries the version
   **without** the tag's leading `v`. Expected mapping: `Linux`/`Darwin` for the
   OS; `x86_64` → `x86_64`, `aarch64`/`arm64` → `arm64`.
3. Extract just the `lazygit` binary into `$HOME/.local/bin`, `chmod +x`, clean
   up the tarball.

The asset-name mapping is derived from upstream's current release layout and
**must be verified against the actual release assets during implementation** —
the whole fallback is dead weight if the URL is wrong on the one platform that
needs it.

### Config

`lazygit/.config/lazygit/config.yml`:

- `git.paging.pager` — delta, **not** side-by-side (see below).
- `git.paging.colorArg: always` — delta needs color forced through the pipe.
- `os.editPreset: nvim` — matches `EDITOR`/`VISUAL` from `shell/…/env.sh`
  instead of letting lazygit guess.
- `gui.nerdFontsVersion: "3"` — the install already places Monaspace Nerd Font,
  so lazygit may use glyphs.

Every key is to be verified against `lazygit --config` (which prints the
default config, and therefore the authoritative schema for the installed
version) rather than written from memory.

#### The side-by-side divergence (crux)

`git/.config/git/config` sets `delta.side-by-side = true`, which is right for a
diff filling the terminal. lazygit's diff panel is roughly half the terminal
width, and splitting *that* in two yields two unreadable columns. The lazygit
pager therefore invokes delta with side-by-side off, overriding the git
setting. This is deliberate, and gets a comment in the config saying so, so a
later reader doesn't "fix" the inconsistency.

#### Pager fallback

`tests/test-git-delta.sh` treats the delta guard in `core.pager` as
load-bearing, not decoration: git treats a missing pager as fatal. delta is
installed best-effort (`ensure_tool git-delta delta`), so a machine can end up
without it. lazygit's pager gets the same treatment — a guarded expression that
falls back when delta is absent, so the diff panel degrades instead of
breaking.

lazygit runs the pager as a shell command, which is what makes a guarded
expression viable; the test below proves it rather than assuming it.

### Wiring

- `install.sh`: add `lazygit` to the stow loop
  (`for pkg in shell git nvim tmux starship herdr claude`).
- `doctor.sh`: add `lazygit` to `PACKAGES`.
- `.gitignore`: `lazygit/.config/lazygit/state.yml` — lazygit writes its own
  state there, and `--no-folding` makes `~/.config/lazygit` a real directory,
  so without this `doctor.sh` reports the state file as drift on every run.

## Testing

`tests/test-lazygit.sh`, following the existing suite's style (`tests/lib.sh`
helpers, `pass`/`fail`/`assert_eq`, `finish`):

- `config.yml` parses as YAML.
- **Behavioural pager check**, mirroring `test-git-delta.sh`: run the real pager
  expression with a stubbed `delta` on a narrowed `PATH` and assert delta is
  invoked; remove the stub and assert it falls back instead of failing.
- The pager expression does not contain `--side-by-side` (locks in the
  divergence above, so it survives a future copy-paste from the git config).
- `install.sh` contains the lazygit install block and stows the `lazygit`
  package; `doctor.sh` lists it in `PACKAGES`.

No registration step needed — `tests/run.sh` globs `test-*.sh`.

## Docs

- `README.md`: a lazygit row in the CLI tools table, and a note in the herdr
  auto-layout section that the `lazygit` tab now has a binary behind it.

## Out of scope

- Custom keybindings, themes, and custom commands. Defaults first; opinions
  once there's a reason for them.
- Any change to `tmux/` — lazygit is launched by the herdr layout, and tmux
  stays the plain/SSH-only driver.
- Replacing the `delta.side-by-side` setting in the git config.
