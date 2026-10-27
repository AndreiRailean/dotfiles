---
type: ADR
status: accepted
date: 2026-10-27
summary: The dotfiles track the per-user config common to most machines and
  stop installing apps; what a machine has installed belongs to its definition
  in the private machines repo.
supersedes: 20261026-update-sh-owns-tool-acquisition
---

# The dotfiles are config, not apps

## Context

Over a few weeks the install side of this repo grew past the config side.
`update.sh` gained optional tools (herdr, deno, fnm, Claude Code, lazygit), an
`--ask` prompt and Homebrew branches. `install.sh` installs 1Password, Ghostty,
a Nerd Font, a neovim PPA and unzip. Together `install.sh`, `update.sh` and
`doctor.sh` came to about 1,400 lines of shell.

Setting up minirat, a Mac mini hosting an Ubuntu VM, tested that growth on two
real hosts:

- The VM used nearly all the config. Its apps went into the private machines
  repo (Docker, gh, the Node version), except fnm and Claude Code, which came
  from `update.sh --add`.
- On the Mac, which is infrastructure nobody works at, the app layer was only
  in the way. `brew services start herdr` fails on every `install.sh` run,
  because the formula defines no service, and `doctor.sh` recommends re-running
  the step that fails. The neovim PPA had no build for Ubuntu 26.04 and broke
  apt on the VM (#28).
- The macOS install branches had never run before (#36), and the first run
  found a bug.

The user runs two kinds of machine:

- **workstations:** the desktop or laptop the user sits at, used to reach the
  network (the Windows desktop with WSL, the home Mac);
- **network hosts:** machines the user reaches rather than sits at, each split
  by what it does (minirat hosts a VM; minirat-dev is the VM, where
  development happens). minirat has a GUI the user opens now and then, but
  it's still a host: the desk is the Windows box.

Shell work, and Claude Code with it, mostly happens on a Linux VM: minirat-dev
at work, and a VM at home. The home Mac is a workstation, but the user doesn't
work in its own shell.

What a machine needs installed depends on its kind and its job, and the
machines repo already describes that per host. The config is the part that's
the same everywhere.

## Decision

- **The dotfiles track per-user config common to most machines:** the stow
  packages, and the work of linking them (prerequisites, stow, pruning dead
  links, `doctor.sh`).
- **They stop installing apps.** Tool acquisition, optional tools, upgrades,
  casks, PPAs and services move to each machine's definition in the machines
  repo. That includes workstations, not only servers.
- **Config must be harmless when its app is missing,** as herdr's
  `config.toml` already is. Shell init that calls a tool checks for it first.
  That's what lets one set of config serve every machine it goes on: Ghostty's
  config can sit unused on a host with no GUI, while a workstation's
  definition installs Ghostty and the Nerd Font.
- **The dotfiles go on every machine where the user works in a shell:** WSL on
  the Windows desktop, and a network host whose job is development
  (minirat-dev, the VM at home). A machine where the user doesn't work in a
  shell (minirat, the home Mac) doesn't need them.

## Consequences

- `update.sh` and the app sections of `install.sh` stay until every machine
  that relies on them gets its tools from the machines repo. Then they go.
  minirat-dev relies on `update.sh --add` for fnm and Claude Code today, and
  the machines repo's own ADR (20261026-plain-scripts-per-host) says so. It
  changes in the same migration.
- The machines repo currently leaves clients out of scope. WSL and the home VM
  would need definitions there.
- Every machine the dotfiles go on runs Linux. The macOS branches in
  `install.sh`, `update.sh` and `doctor.sh` serve no current target, and are
  candidates for removal in the migration. What a Mac workstation still wants,
  such as its terminal app and font, belongs in that Mac's definition. The
  home Mac's years of its own dotfiles never have to be reconciled with this
  repo.
- The herdr brew-service failure is fixed by deleting that step, not by
  repairing it.
