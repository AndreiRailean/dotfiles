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

- **Install: upstream release, gated on a version floor of 0.64.0.** Not the
  system package. lazygit 0.64 replaced the `git.paging` config block with
  `git.diffRenderers`, and an older binary ignores the new keys *silently* — no
  warning, no delta, no signal. Debian trixie ships 0.50 and older Ubuntu ships
  nothing at all, so the package manager cannot be relied on to clear the floor.
  A single static binary in `~/.local/bin` can, and `~/.local/bin` precedes
  `/usr/bin` (`shell/.config/shell/path.sh:14`), so it supersedes a distro
  lazygit that's already installed. Same shape as the existing starship and
  herdr blocks. Best-effort: a failure prints `!!` and continues.
- **The floor is a version check, not just a presence check.** A machine that
  already has 0.50 from apt must be *upgraded*, not skipped — so the guard asks
  "is lazygit ≥ 0.64 on PATH", not "is lazygit on PATH". brew and pacman track
  current, so on those platforms an already-installed lazygit clears the floor
  and is left alone.
- **No upper version pin.** Resolve the latest release at install time.
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
if ! lazygit_meets_floor; then
  echo "Installing lazygit..."
  install_lazygit_release \
    || echo "!! lazygit install failed — install manually: https://github.com/jesseduffield/lazygit"
fi
```

`lazygit_meets_floor` parses `version=<x.y.z>` out of `lazygit --version` and
returns 0 only when the version is ≥ 0.64.0. A missing binary, unparseable
output, or an older version all return 1. No `sort -V` — that's GNU-only;
compare the major and minor components numerically.

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

`lazygit/.config/lazygit/config.yml`, on the 0.64 schema:

- `git.diffRenderers` — a single-entry array. `type` is left at its
  `stdinFilter` default.
  - `command` — delta, **not** side-by-side (see below).
  - `colorArg: always` — delta needs color forced through the pipe.
  - `name: delta` — shown when cycling renderers. Not cosmetic filler: the
    default is derived from the command's *first word*, and ours begins
    `command -v delta …`, so without this the renderer displays as "command".
- `os.editPreset: nvim` — matches `EDITOR`/`VISUAL` from `shell/…/env.sh`
  instead of letting lazygit guess.
- `gui.nerdFontsVersion: "3"` — the install already places Monaspace Nerd Font,
  so lazygit may use glyphs.

Verified against the v0.64.0 `DiffRendererConfig` JSON schema
(`schema/config.json`) and `lazygit --config`, not written from memory.

#### Why not `git.paging`

The pre-0.64 form works on both versions — 0.64 migrates it in memory — but it
migrates *on disk* too, rewriting the tracked file through the stow symlink on
first launch (verified: `git.paging` → `git.diffRenderers[]`, `pager` →
`command`, comments preserved). Shipping the current schema avoids a config the
tool rewrites behind you. The trade-off accepted deliberately: this config
requires lazygit ≥ 0.64, which is what the install's version floor guarantees.

A *future* schema migration would rewrite the file the same way. It would
surface as ordinary `git status` drift in this repo, which is signal enough —
`.auto-written` is for files a tool rewrites routinely, and registering one that
gets rewritten once per major version would make the drift nudge fire on every
hand edit instead.

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
- The config uses the 0.64 `diffRenderers`/`command` keys, not the migrated-away
  `paging`/`pager` ones.
- The version floor: a stubbed `lazygit` reporting 0.50.0 does not clear it; one
  reporting 0.64.0 does; a missing binary does not.
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
