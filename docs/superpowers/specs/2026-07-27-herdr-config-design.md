# herdr dotfiles package — design

Date: 2026-07-27
Repo: personal dotfiles (Stow-managed; macOS / WSL / Linux)

## Goal

Adopt [herdr](https://herdr.dev) — an agent-aware, tmux-style terminal
multiplexer — into the dotfiles: a managed `config.toml` plus install
bootstrap, so preferences are reproducible across machines. herdr runs fully
on defaults (auto-detects agents), so the config is intentionally minimal.

## Decisions

- **Config pinned:** `onboarding = false`, `[theme] name = "tokyo-night"`,
  `[keys] prefix = "ctrl+a"` (match tmux muscle memory). Everything else stays
  herdr default.
- **Install bootstrap:** official installer `curl -fsSL https://herdr.dev/install.sh | sh`
  (Linux + macOS; drops the binary in `~/.local/bin`), idempotent (skip if
  `herdr` on PATH). No version pin — herdr self-updates via `herdr update`.
- **tmux is untouched** — it remains the driver for plain/SSH-only boxes; herdr
  is the agent-focused one. No herdr health-check script (herdr reports its own
  agent state; the tmux `agent-doctor` was tmux-specific).

## Architecture

New Stow package `herdr/` mirroring **only** the config file:

```
herdr/.config/herdr/config.toml  →  ~/.config/herdr/config.toml
```

### The runtime-state separation (crux)

`~/.config/herdr/` mixes config with live runtime state — `herdr.sock`,
`herdr-client.sock`, `herdr*.log`, `session.json`, `.plugins.lock`. The package
tracks **only** `config.toml`; `stow --no-folding` symlinks it into the existing
real directory without disturbing the runtime files. To keep `doctor.sh`'s
drift scan (and git) from flagging those, add scoped `.gitignore` entries —
`doctor.sh` skips anything `git check-ignore` matches:

```
herdr/.config/herdr/*.log
herdr/.config/herdr/*.sock
herdr/.config/herdr/session.json
herdr/.config/herdr/.plugins.lock
```

### Wiring

- Add `herdr` to the package loop in `install.sh` and to `PACKAGES` in
  `doctor.sh`.
- Add a herdr install block after the Starship block in `install.sh`.
- README: a short "herdr" section (what's managed, runtime state gitignored,
  tmux relationship).

## Edge case

If a machine already has a **real** `~/.config/herdr/config.toml`, `stow` will
conflict; adopt it via `./doctor.sh --adopt` or remove it first. On the current
machine none exists yet, so the first stow is clean.

## Testing

`tests/test-herdr-config.sh`:
- `config.toml` is valid TOML (via `python3 -c 'import tomllib'`; skip if
  unavailable) and contains the three pinned settings.
- `git check-ignore` matches sample runtime paths (proves `doctor.sh` skips
  them).
- `herdr` present in both `install.sh` package loop and `doctor.sh` PACKAGES;
  `install.sh` contains the `herdr.dev/install.sh` bootstrap; `bash -n` passes
  on `install.sh` and `doctor.sh`.
