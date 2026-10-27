---
type: ADR
status: superseded
date: 2026-10-26
summary: Tools no package manager looks after are installed and upgraded only by
  update.sh, which install.sh calls with --missing; optional tools opt in by
  being installed, and only copies under $HOME are ever upgraded.
superseded_by: 20261027-dotfiles-are-config-not-apps
---

# update.sh owns the tools no package manager looks after

## Context

`install.sh` skips anything already installed, so it's safe to re-run but
never updates anything. apt, Homebrew and pacman keep their own packages
current. Nothing kept the rest current, so they fell behind unnoticed: on
2026-10-23 starship, herdr and deno were all behind on this machine.

There was also a group of tools some machines want and others don't (deno,
fnm, Claude Code, lazygit). lazygit had been a default and was dropped. The
dotfiles had no way to manage a tool short of installing it everywhere.

## Decision

`update.sh` is the only place that knows where these tools come from. It
installs them and upgrades them:

- `update.sh` reports installed vs latest and changes nothing.
- `--missing` installs absent default tools only.
- `--apply` also upgrades what's behind.
- `--add <tool>` installs an optional tool.

`install.sh` runs `--missing` and then the report. Re-running it still never
upgrades anything, because some upgrades need a follow-up check (herdr's
auto-layout retest). Upgrading is always a deliberate `--apply`.

**Optional tools opt in by being installed.** There is no per-machine list. A
tool on `PATH` is reported and upgraded, and one that isn't present is shown
with the `--add` command.

**Only a copy under `$HOME` is upgraded.** A copy from apt, Homebrew or
pacman is reported with its owner and left alone. Upgrading it here would put
a second copy on `PATH` that drifts from the first. `install.sh` already
removes a stray copy of herdr on macOS for exactly this reason.

**Downloads are checked against the project's published sha256** (starship,
deno, lazygit). The exceptions are fnm, which publishes none, and herdr and
Claude Code, whose own installers verify their downloads. Starship's install
moved from piping its install script into `sh` to a release download for this
reason.

## Considered Options

- **An `install.sh --update` flag.** Each `install.sh` section has its own
  "skip if present" branch, so the flag would add an update path to every
  section of a 700-line script, all to cover about five tools.
- **A separate `update.sh` alongside `install.sh`'s own install code.** That
  copies each tool's download source into two scripts. The duplication between
  `install.sh` and `doctor.sh` is already accepted and guarded by a sync test
  (see 20260805-no-shared-shell-library). Making `update.sh` the only owner
  avoids adding another copy to guard.
- **`install.sh` running `--apply` on its first run only.** It would need a
  marker file to know it's the first run, and that misjudges a half-finished
  install or a machine set up before the marker existed. Asking per tool ("is
  it here?") gets the same result without the marker.
- **A per-machine list of optional tools** in a gitignored file. It would be
  one more thing to keep in step with what's actually installed. Checking
  whether the tool is installed gives the same answer.

## Consequences

- The Nerd Font and win32yank stay in `install.sh`. The font has no version to
  compare (a folder of files, kept current by brew on macOS), and win32yank
  hasn't had a release since 2023.
- Adding a tool means editing `update.sh` in four places: the
  `DEFAULT_TOOLS`/`OPTIONAL_TOOLS` lists, `latest`, `version` if it doesn't
  print "name X.Y.Z", and an `install_<tool>`. Also add a case to the curl
  stub in `tests/test-update.sh`.
- Every `install.sh` run now ends with network lookups. They time out and
  fail soft, so a machine without a network still finishes.
- Installing starship, deno and fnm uses GitHub's `releases/latest/download`
  links rather than the API, so the API's limit of 60 unauthenticated requests
  an hour can't block an install. lazygit's asset names include the version,
  so installing it still needs an API lookup. The report always needs the API
  for latest versions, and a lookup that fails shows as unknown.

Landed in 9a8f624 and 48d6216.
