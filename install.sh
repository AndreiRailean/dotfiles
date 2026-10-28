#!/usr/bin/env bash
set -euo pipefail

# `pwd -P`, not `pwd`: stow resolves the package directory physically, so the
# links it writes point at the repo's REAL path (verified: with the repo reached
# through a symlink, stow wrote ../../real/pkg/… not ../symlink/pkg/…). Anything
# comparing a link's target against this variable — prune_dead_links below —
# needs the same form, or the comparison silently never matches. doctor.sh
# derives it the same way; keep them identical.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$DOTFILES_DIR"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# ~/.local/bin is where update.sh and several installers below drop binaries,
# and nothing else creates it on a fresh Mac. path.sh only puts the dir on PATH
# if it exists at shell startup, so it has to be there before the first shell.
mkdir -p "$HOME/.local/bin"

# ── OS / environment detection ───────────────────────────────
OS="$(uname -s)"
IS_WSL=0
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then IS_WSL=1; fi

pkg_install() {
  # best-effort install of a package by name across managers
  if   command -v brew    &>/dev/null; then brew install "$@"
  elif command -v apt     &>/dev/null; then sudo apt install -y "$@"
  elif command -v pacman  &>/dev/null; then sudo pacman -S --noconfirm "$@"
  else return 1
  fi
}

# ── GNU Stow ─────────────────────────────────────────────────
if ! command -v stow &>/dev/null; then
  echo "Installing GNU Stow..."
  pkg_install stow || { echo "Install GNU Stow manually."; exit 1; }
fi

# ── Hand pre-existing config files over to the repo ──────────
# stow refuses to link over a target that is a real file rather than a symlink
# or a directory, and under `set -e` that refusal doesn't just skip the one
# package — it aborts this whole script at the loop below, silently skipping
# every later step (the remaining packages, the font). The trigger is ordinary: tools write a config on first
# run, so any machine that used a tool BEFORE this repo managed it has exactly
# such a file sitting on the target. lazygit is the case that surfaced this —
# it leaves an empty ~/.config/lazygit/config.yml on first launch — but
# nothing here is lazygit-specific.
#
# So move the machine's file aside and let the repo's copy win. Deliberately
# NOT `stow --adopt`, which resolves the conflict the other way round: adopt
# pulls the machine's file into the repo, so a fresh machine's empty config
# would overwrite the tracked one and surface as a real change to commit.
#
# The file is kept rather than deleted because of ~/.claude/settings.json:
# that's the live file Claude Code reads AND writes, so a machine's copy can
# hold machine-local keys worth re-adding by hand. (Claude writes *through* a
# symlink — verified: the link survives plugin/marketplace/config writes — so
# tracking the real file lets its edits land in the repo instead of needing a
# patch merged into a machine-owned copy.)
#
# Only real files are moved. An existing symlink is already ours, so re-runs
# are a no-op that sheds no extra backups. `find` stays on plain `-type f`:
# `-printf` is GNU-only and this script also runs on macOS.
clear_stow_conflicts() {
  local pkg="$1" rel t
  while IFS= read -r rel; do
    t="$HOME/$rel"
    if [ -e "$t" ] && [ ! -L "$t" ] && [ ! -d "$t" ]; then
      mv "$t" "$t.pre-dotfiles.$(date +%s)"
      echo "Moved aside existing ~/$rel — see $(basename "$t").pre-dotfiles.* backup"
    fi
  done < <(cd "$pkg" && find . -type f | sed 's|^\./||')
}

# ── Remove links to files the repo no longer has ─────────────
# Deleting a tracked file leaves every OTHER machine with a symlink pointing at
# it, and `stow --restow` will not clean that up: stow unlinks only what the
# package currently contains, so a link whose repo file is gone is invisible to
# it. Left alone it survives every future install and doctor.sh reports it as
# drift forever — one machine's `git rm` becoming a manual chore on all the
# others, which is the opposite of the point of keeping config in a repo.
# (Real case: 8fcfba8 dropped the tmux agent-* scripts.)
#
# This deletes things in $HOME, so the scope is deliberately narrow: a symlink
# must be dangling AND inside a directory one of our packages owns AND point
# back into this repo. A broken link the user made, or one aimed anywhere else,
# is not ours to remove.

# Absolute, lexically-resolved target of a symlink. The filesystem is no help
# here — a link to a deleted file usually has deleted ancestor dirs too, which
# rules out `readlink -f`, realpath and `cd`. Collapsing `..` textually is
# sound for stow's links, which never traverse a symlinked directory.
link_target_abs() {
  local tgt seg out=()
  tgt="$(readlink "$1")" || return 1
  case "$tgt" in /*) : ;; *) tgt="$(dirname "$1")/$tgt" ;; esac
  local IFS=/
  for seg in $tgt; do
    case "$seg" in
      ''|.) : ;;
      ..)   [ "${#out[@]}" -gt 0 ] && out=("${out[@]:0:${#out[@]}-1}") || : ;;
      *)    out+=("$seg") ;;
    esac
  done
  printf '/%s\n' "${out[*]}"      # IFS=/ joins the segments back together
}

# The top directory a package introduces under $HOME (.config/<name>, or a
# top-level entry). Must cover subdirectories, because that's where deleted
# files leave their links behind. Byte-identical copy in doctor.sh; see
# docs/adr/0001-no-shared-shell-library.md for why the two scripts share no
# library, and tests/test-shared-logic-sync.sh which enforces the copies.
owned_roots() {
  find "$1" -type f | while IFS= read -r f; do
    rel="${f#"$1"/}"
    case "$rel" in
      .config/*/*) printf '.config/%s\n' "$(printf '%s' "$rel" | cut -d/ -f2)" ;;
      *)           printf '%s\n' "$rel" ;;
    esac
  done | sort -u
}

prune_dead_links() {
  local pkg="$1" root troot entry tgt d
  local pruned=()
  while IFS= read -r root; do
    troot="$HOME/$root"
    [ -d "$troot" ] && [ ! -L "$troot" ] || continue
    while IFS= read -r entry; do
      [ -L "$entry" ] && [ ! -e "$entry" ] || continue   # dangling only
      tgt="$(link_target_abs "$entry")" || continue
      case "$tgt" in
        "$DOTFILES_DIR"/*)
          rm -f "$entry"
          pruned+=("$(dirname "$entry")")
          echo "Removed dead link ~/${entry#"$HOME"/} — ${tgt#"$DOTFILES_DIR"/} is no longer in the repo"
          ;;
      esac
    done < <(find "$troot" -type l)
    # A directory that existed only to hold those links is now clutter. rmdir
    # refuses non-empty dirs, so this can't take anything else with it, and
    # $troot is skipped: stow needs the owned root on the next run.
    if [ "${#pruned[@]}" -gt 0 ]; then
      for d in "${pruned[@]}"; do
        [ "$d" = "$troot" ] || rmdir "$d" 2>/dev/null || true
      done
      pruned=()
    fi
  done < <(owned_roots "$pkg")
}

# Roots no package stows into any more: a package removed from the repo
# altogether (lazygit), or a root a package dropped (herdr's systemd unit).
# prune_dead_links only visits the roots packages still own, so either `git rm`
# would leave links dangling on every other machine. Same narrow rule — dangling and
# pointing into this repo — and each directory those links leave empty goes
# too, up to and including the root, since no package stows there any more.
# Only those: other tools write into a root like ~/.config/systemd, and an
# empty directory of theirs isn't ours to remove. Binaries an old install put
# in ~/.local/bin are left alone: they may still be in use.
RETIRED_ROOTS=".config/lazygit .config/systemd"
prune_retired_roots() {
  local root troot entry tgt d
  local emptied=()
  for root in $RETIRED_ROOTS; do
    troot="$HOME/$root"
    [ -d "$troot" ] && [ ! -L "$troot" ] || continue
    while IFS= read -r entry; do
      [ -L "$entry" ] && [ ! -e "$entry" ] || continue   # dangling only
      tgt="$(link_target_abs "$entry")" || continue
      case "$tgt" in
        "$DOTFILES_DIR"/*)
          rm -f "$entry"
          emptied+=("$(dirname "$entry")")
          echo "Removed dead link ~/${entry#"$HOME"/} — no package stows there any more"
          ;;
      esac
    done < <(find "$troot" -type l)
    # Walk up from each, stopping at the first directory that isn't empty
    # (rmdir refuses those) or at the root. Every removal is done by now, so
    # the order the directories come in doesn't matter.
    if [ "${#emptied[@]}" -gt 0 ]; then
      for d in "${emptied[@]}"; do
        while rmdir "$d" 2>/dev/null && [ "$d" != "$troot" ]; do
          d="$(dirname "$d")"
        done
      done
      emptied=()
    fi
  done
}

# quiet_restow filters `stow -v --restow` output down to what changed. A restow
# plans an UNLINK of every link and then a LINK of each again, tagged "(reverts
# previous action)": a no-op on disk, but -v prints both, about 60 lines per run.
# Those pairs are dropped. A new link, a removed one, and errors still show:
# that's why -v stays. Paths can hold spaces, so they're cut at " => ".
quiet_restow() {
  awk '{ line[NR] = $0 }
    /^LINK: .* \(reverts previous action\)$/ {
      p = $0; sub(/^LINK: /, "", p); sub(/ => .*/, "", p); undone[p] = 1 }
    END {
      for (i = 1; i <= NR; i++) {
        s = line[i]
        if (s ~ /\(reverts previous action\)$/) continue
        if (s ~ /^UNLINK: /) { p = s; sub(/^UNLINK: /, "", p); if (p in undone) continue }
        print s
      }
    }'
}

# ── Symlink packages into $HOME ──────────────────────────────
# --no-folding: create real directories with per-file symlinks rather than
# symlinking whole dirs into the repo. This keeps ~/.config/shell (etc.) a
# real directory so per-machine files (local.sh, git 'local') land OUTSIDE
# the repo instead of inside it.
# shell must come first so XDG vars exist for anything sourced later.
for pkg in shell git nvim tmux starship herdr claude; do
  [ -d "$pkg" ] || continue
  echo "Stowing $pkg..."
  clear_stow_conflicts "$pkg"
  stow -v --no-folding --target="$HOME" --restow "$pkg" 2>&1 | quiet_restow
  prune_dead_links "$pkg"
done
prune_retired_roots

# ── Wire the shell entrypoint into each shell's rc ───────────
# Keeps the distro-provided rc and its defaults; just appends one guarded
# line that sources our managed init.sh. Idempotent via a marker.
#
# An absent rc is skipped — unless it belongs to the login shell. macOS ships
# no ~/.zshrc, so skipping it there would leave the whole shell package inert
# on a fresh Mac (no aliases, no PATH, no prompt); the append creates it.
wire_shell_rc() {
  local rc="$1" marker="# >>> dotfiles (managed) >>>" login_rc=""
  case "${SHELL##*/}" in
    zsh)  login_rc="$HOME/.zshrc" ;;
    bash) login_rc="$HOME/.bashrc" ;;
  esac
  [ -e "$rc" ] || [ "$rc" = "$login_rc" ] || return 0
  if ! grep -qF "$marker" "$rc" 2>/dev/null; then
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' '[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/shell/init.sh"'
      printf '%s\n' "# <<< dotfiles (managed) <<<"
    } >>"$rc"
    echo "Wired dotfiles loader into $rc"
  fi
}
wire_shell_rc "$HOME/.bashrc"
wire_shell_rc "$HOME/.zshrc"

# ~/.zshenv is the one file every zsh reads, including the non-interactive one
# that runs `ssh host 'cmd'`, which reads neither ~/.zshrc nor ~/.zprofile. So
# a command over SSH to a Mac got /usr/bin:/bin:/usr/sbin:/sbin: Apple's bash
# 3.2 for `env bash`, and nothing from Homebrew or ~/.local/bin. Sourcing
# path.sh gives it the PATH an interactive shell builds. Created when zsh is
# the login shell, as ~/.zshrc is.
wire_zshenv() {
  local rc="$HOME/.zshenv" marker="# >>> dotfiles (managed) >>>"
  [ -e "$rc" ] || [ "${SHELL##*/}" = zsh ] || return 0
  grep -qF "$marker" "$rc" 2>/dev/null && return 0
  {
    printf '\n%s\n' "$marker"
    printf '%s\n' '[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh"'
    printf '%s\n' "# <<< dotfiles (managed) <<<"
  } >>"$rc"
  echo "Wired dotfiles PATH into $rc"
}
wire_zshenv

# ── Seed per-machine files from templates (never overwrite) ──
[ -f "$HOME/.config/git/local" ]  || { cp "$DOTFILES_DIR/git/.config/git/local.example"       "$HOME/.config/git/local";  echo "Created ~/.config/git/local — set your name/email"; }
[ -f "$HOME/.config/shell/local.sh" ] || { cp "$DOTFILES_DIR/shell/.config/shell/local.sh.example" "$HOME/.config/shell/local.sh"; echo "Created ~/.config/shell/local.sh"; }

# ── Give `git config --global` somewhere that isn't the repo ─
# `git config --global` writes to ~/.gitconfig, falling back to
# ~/.config/git/config ONLY when ~/.gitconfig doesn't exist — and that file is a
# symlink into this (public) repo. So on a machine without ~/.gitconfig, every
# tool that configures git for you writes into the tracked config. Real case:
# 1Password's "set up SSH commit signing" added a macOS-only op-ssh-sign path
# there, which would have broken committing on every Linux/WSL machine.
#
# An existing ~/.gitconfig catches those writes instead. git reads it AFTER the
# XDG file, so whatever lands in it overrides the shared defaults, the same way
# the [include]d ~/.config/git/local does. Never overwritten.
seed_global_gitconfig() {
  [ -e "$HOME/.gitconfig" ] && return 0
  cat >"$HOME/.gitconfig" <<'EOF'
# Machine-local git config, written by tools via `git config --global`.
#
# It exists so those writes land here rather than in ~/.config/git/config,
# which is tracked in the dotfiles repo. Hand-written per-machine settings
# (identity, signing) go in ~/.config/git/local; either file is fine.
EOF
  echo "Created ~/.gitconfig — catches 'git config --global' writes outside the repo"
}
seed_global_gitconfig

# ── CLI tools (best-effort; each is optional) ────────────────
# ensure_tool <package> <cmd>...: install <package> unless one of <cmd> is
# already on PATH. (bat is `batcat` on Debian/Ubuntu, `bat` elsewhere.)
ensure_tool() {
  local pkg="$1"; shift
  local c
  for c in "$@"; do command -v "$c" &>/dev/null && return 0; done
  echo "Installing $pkg..."
  pkg_install "$pkg" || echo "!! $pkg install failed — install it manually"
}
ensure_tool bat bat batcat     # cat with syntax highlighting
ensure_tool eza eza            # nicer ls
ensure_tool ripgrep rg         # fast recursive grep
ensure_tool fzf fzf            # fuzzy finder (shell integration in tools.sh)
ensure_tool jq jq              # JSON processor (Claude status line)
ensure_tool direnv direnv      # per-directory env (shell hook in tools.sh)
# rsync over SSH needs the binary on both ends, so a machine without it can't
# receive a resumable copy (the file-inbox skill falls back to scp). macOS ships
# one, so this only installs on Linux/WSL.
ensure_tool rsync rsync
# delta (syntax-highlighted git diffs) — the package is git-delta on apt, brew
# AND pacman. Not `delta`: on Debian/Ubuntu that name belongs to an unrelated
# 2006-era binary-diff tool.
ensure_tool git-delta delta
# fd (friendlier find): apt calls the package fd-find, brew/pacman call it fd.
if command -v apt &>/dev/null; then ensure_tool fd-find fd fdfind; else ensure_tool fd fd fdfind; fi
# unzip: update.sh unpacks fnm and deno with it, and the Nerd Font and
# win32yank below arrive as zips. Ubuntu's cloud images ship without it, so
# on a fresh VM fnm's install failed. macOS ships one.
ensure_tool unzip unzip

if [ "$IS_WSL" -eq 1 ] && ! command -v win32yank.exe &>/dev/null; then
  echo "Installing win32yank for clipboard bridge..."
  if curl -fsSLo /tmp/win32yank.zip \
      https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip 2>/dev/null; then
    # Guarded: under set -e a failed unzip (it couldn't be installed above)
    # would otherwise end the whole install here.
    if unzip -oq /tmp/win32yank.zip win32yank.exe -d "$HOME/.local/bin/"; then
      chmod +x "$HOME/.local/bin/win32yank.exe"
    else
      echo "!! couldn't unpack win32yank (is unzip installed?) — clipboard sync in nvim won't work until installed"
    fi
    rm -f /tmp/win32yank.zip
  else
    echo "!! win32yank download failed — clipboard sync in nvim won't work until installed"
  fi
fi

# ── Neovim ───────────────────────────────────────────────────
# nvim is EDITOR/VISUAL and has a stowed config, so a fresh machine needs it.
# Distro repos lag (Ubuntu is a release or two behind; Debian stable much
# more), so on Ubuntu add the official PPA's stable channel first — tagged
# releases, and its .deb registers nvim with update-alternatives, which the
# pinning step below depends on. brew and pacman already ship current builds.
#
# Skipped entirely when nvim is already installed, so a machine deliberately
# tracking the unstable/nightly PPA keeps it.
#
# The PPA only publishes for the Ubuntu releases its maintainers have built
# for, and a new release has none at launch (26.04 had none). add-apt-repository
# adds the source anyway, and a source with no Release file makes EVERY later
# `apt update` fail — on a fresh 26.04 VM that broke the Docker and gh installs
# that ran after this. So probe for the release first, and if setup still
# fails, take the source back out rather than leave apt broken.
add_nvim_ppa() {
  local codename="$1"
  local release="https://ppa.launchpadcontent.net/neovim-ppa/stable/ubuntu/dists/$codename/Release"
  if [ -z "$codename" ] || ! curl -fsLI --max-time 10 -o /dev/null "$release"; then
    echo "neovim PPA has no build for '${codename:-unknown}' — using the distro package"
    return 1
  fi
  if sudo apt install -y software-properties-common \
     && sudo add-apt-repository -y ppa:neovim-ppa/stable \
     && sudo apt update; then
    return 0
  fi
  echo "!! neovim PPA setup failed — removing it and falling back to the distro package"
  sudo add-apt-repository -y --remove ppa:neovim-ppa/stable >/dev/null 2>&1 || true
  return 1
}

if ! command -v nvim &>/dev/null; then
  echo "Installing neovim..."
  nvim_ppa=0 codename=""
  if command -v apt &>/dev/null; then
    # PPAs are Ubuntu-only — Debian and other apt distros get the distro pkg.
    distro="$( . /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}" )" || distro=""
    case "$distro" in *ubuntu*) nvim_ppa=1 ;; esac
    # Mint/Pop set ID_LIKE=ubuntu and carry the base Ubuntu codename here.
    codename="$( . /etc/os-release 2>/dev/null && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" )" || codename=""
  fi
  if [ "$nvim_ppa" -eq 1 ]; then
    add_nvim_ppa "$codename" || true
  fi
  pkg_install neovim \
    || echo "!! neovim install failed — see https://github.com/neovim/neovim/blob/master/INSTALL.md"
fi

# ── Editor alternatives (Debian/Ubuntu) ──────────────────────
# Debian's neovim package registers nvim in the vim/vi/editor alternative
# groups at the SAME priority as vim.basic, so "auto" mode resolves by install
# order — which is why `vim` keeps opening the preinstalled vim on a box that
# had it first. Pin the vim-named commands to nvim system-wide; the aliases in
# aliases.sh only cover interactive shells.
#
# Only groups where nvim is already a registered candidate are touched, so this
# is a no-op on macOS/Arch (no update-alternatives) and on machines where nvim
# came from a tarball rather than a package. 'editor' is deliberately left
# alone — that's the distro-wide default for other users' tools, and our own
# shells already get nvim via EDITOR/VISUAL.
if command -v update-alternatives &>/dev/null && command -v nvim &>/dev/null; then
  for group in vim vi view ex vimdiff rvim rview; do
    cand="$(update-alternatives --list "$group" 2>/dev/null | grep -E '/nvim$' | head -1)" || true
    [ -n "$cand" ] || continue     # nvim not a candidate for this group
    current="$(update-alternatives --query "$group" 2>/dev/null | awk '/^Value:/{print $2}')" || true
    [ "$current" = "$cand" ] && continue
    echo "Pointing '$group' at $cand (was ${current:-unset})..."
    sudo update-alternatives --set "$group" "$cand" >/dev/null \
      || echo "!! could not set $group -> nvim (run: sudo update-alternatives --set $group $cand)"
  done
fi

# ── Editor links (no update-alternatives, i.e. macOS) ────────
# macOS's /usr/bin/vim is classic vim on the sealed system volume, so it can't
# be repointed the Debian way above. ~/.local/bin precedes /usr/bin on PATH
# (path.sh), so vim/vi links there reach scripts too (doctor.sh included), not
# just the interactive shells aliases.sh covers. A real file at either name is the
# user's own and is left alone; an existing link is refreshed so it follows
# nvim if its install location moves.
link_vim_to_nvim() {
  local nvim_path name dest
  nvim_path="$(command -v nvim)" || return 0
  for name in vim vi; do
    dest="$HOME/.local/bin/$name"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "!! $dest is a real file, not linking it to nvim"
      continue
    fi
    ln -sfn "$nvim_path" "$dest"
  done
}
if ! command -v update-alternatives &>/dev/null; then
  link_vim_to_nvim
fi

# ── 1Password CLI (op) ───────────────────────────────────────
# Not in distro repos; use 1Password's own channels. See
# https://developer.1password.com/docs/cli/get-started/
#
# --batch --yes on both dearmor calls is load-bearing, not tidiness. gpg PROMPTS
# ("File '…' exists. Overwrite?") when --output names an existing file, and this
# script is meant to be re-run: any machine where an earlier run wrote the
# keyring but didn't finish installing op would stall here forever on every
# later run. The stall lands before `apt install` in the same && chain, so op
# never arrives, `command -v op` never starts passing, and the machine stays
# stuck. --yes answers the overwrite question; --batch stops gpg asking anything
# at all.
if ! command -v op &>/dev/null; then
  echo "Installing 1Password CLI (op)..."
  if command -v brew &>/dev/null; then
    brew install 1password-cli || echo "!! op install via brew failed"
  elif command -v apt &>/dev/null; then
    if curl -sS https://downloads.1password.com/linux/keys/1password.asc \
         | sudo gpg --batch --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg \
       && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
         | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null \
       && sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
       && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
         | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null \
       && sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
       && curl -sS https://downloads.1password.com/linux/keys/1password.asc \
         | sudo gpg --batch --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
       && sudo apt update && sudo apt install -y 1password-cli; then
      :
    else
      echo "!! op install failed — see https://developer.1password.com/docs/cli/get-started/"
    fi
  else
    echo "!! Install 1Password CLI manually: https://developer.1password.com/docs/cli/get-started/"
  fi
fi

# ── Ghostty (terminal, macOS only) ───────────────────────────
# A GUI app, so it comes from a Homebrew cask, not pkg_install. Checked by the
# app bundle rather than PATH: the cask doesn't put `ghostty` on PATH, and an
# app installed from the DMG instead of brew should count as installed too.
if [ "$OS" = "Darwin" ] && [ ! -d /Applications/Ghostty.app ]; then
  if command -v brew &>/dev/null; then
    echo "Installing Ghostty..."
    brew install --cask ghostty \
      || echo "!! Ghostty install failed — download it from https://ghostty.org/download"
  else
    echo "!! Install Ghostty manually: https://ghostty.org/download"
  fi
fi

# ── Tools no package manager looks after ─────────────────────
# Starship (and, where you add them, herdr, deno, fnm, Claude Code and
# lazygit) come from update.sh, the one place that knows where each comes from.
# --missing installs only what's absent, so re-running this script never
# upgrades anything; `./update.sh --apply` does that when you choose to. Not
# fatal: a tool that fails to install is reported and the rest carries on.
"$DOTFILES_DIR/update.sh" --missing || echo "!! some tools failed to install — see above, then run ./update.sh"

# Offer the optional tools that aren't here, but only to a person: piped or in
# CI there's nobody to answer, and the defaults are all a machine needs.
if [ -t 0 ] && [ -t 1 ]; then
  "$DOTFILES_DIR/update.sh" --ask || echo "!! some tools failed to install — see above, then run ./update.sh"
fi

# ── Nerd Font (best-effort; see note printed at end) ─────────
# macOS gets it from Homebrew: the cask installs into ~/Library/Fonts, where
# macOS actually looks, and `brew upgrade` keeps it current. The Linux route
# below — unzip into ~/.local/share/fonts — does nothing on a Mac: macOS never
# reads that dir, so the font was downloaded but not installed.
#
# On Linux it goes only where something local draws with it. Over SSH the
# client's terminal renders the glyphs, and in WSL it's Windows Terminal (WSLg
# sets DISPLAY, so WSL is ruled out first). A shell reached over SSH has no
# DISPLAY even on a desktop, so an installed X/Wayland session type also
# counts. `systemctl get-default` is no help: headless VMs report
# graphical.target too.
FONT_ARCHIVE="Monaspace"                    # the release .zip name
FONT_FACE="MonaspiceAr Nerd Font Mono"      # what you select in the terminal
FONT_CASK="font-monaspice-nerd-font"        # Homebrew cask with the same fonts
FONT_DIR="$XDG_DATA_HOME/fonts"
FONT_SESSION_DIRS="/usr/share/xsessions /usr/share/wayland-sessions"
FONT_SKIPPED=0                              # set when this box has no display
install_nerd_font() {
  if [ "$OS" = "Darwin" ]; then
    if ! command -v brew &>/dev/null; then
      echo "!! Install the font manually: brew install --cask $FONT_CASK, or https://www.nerdfonts.com"
      return 0
    fi
    if ! brew list --cask "$FONT_CASK" &>/dev/null; then
      echo "Installing $FONT_FACE (Homebrew)..."
      brew install --cask "$FONT_CASK" \
        || { echo "!! $FONT_CASK install failed — run: brew install --cask $FONT_CASK"; return 0; }
    fi
    # An earlier run's Linux-style download: unused by macOS, and now a stale
    # duplicate that brew upgrades won't touch.
    if [ -d "$FONT_DIR/$FONT_ARCHIVE" ]; then
      rm -rf "${FONT_DIR:?}/$FONT_ARCHIVE"
      rmdir "$FONT_DIR" 2>/dev/null || true
      echo "Removed $FONT_DIR/$FONT_ARCHIVE — the font comes from Homebrew on macOS"
    fi
    return 0
  fi
  local has_display=0 d
  if [ "${IS_WSL:-0}" -ne 1 ]; then
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && has_display=1
    for d in $FONT_SESSION_DIRS; do [ -d "$d" ] && has_display=1; done
  fi
  if [ "$has_display" -eq 0 ]; then
    FONT_SKIPPED=1
    # An earlier run's download, from before headless boxes were skipped.
    if [ -d "$FONT_DIR/$FONT_ARCHIVE" ]; then
      rm -rf "${FONT_DIR:?}/$FONT_ARCHIVE"
      rmdir "$FONT_DIR" 2>/dev/null || true
      command -v fc-cache &>/dev/null && fc-cache -f >/dev/null 2>&1
      echo "Removed $FONT_DIR/$FONT_ARCHIVE — nothing on this machine draws with it"
    fi
    return 0
  fi
  # Files, not just the folder: a run that couldn't unpack (no unzip) used to
  # leave an empty one, and every later run then skipped the font for good.
  [ -n "$(ls -A "$FONT_DIR/$FONT_ARCHIVE" 2>/dev/null)" ] && return 0
  echo "Downloading $FONT_ARCHIVE Nerd Font (contains $FONT_FACE)..."
  FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_ARCHIVE}.zip"
  if curl -fsSL "$FONT_URL" -o /tmp/${FONT_ARCHIVE}.zip 2>/dev/null; then
    mkdir -p "$FONT_DIR/$FONT_ARCHIVE"
    if unzip -oq /tmp/${FONT_ARCHIVE}.zip -d "$FONT_DIR/$FONT_ARCHIVE"; then
      command -v fc-cache &>/dev/null && fc-cache -f "$FONT_DIR" >/dev/null 2>&1
      echo "Font files placed in $FONT_DIR/$FONT_ARCHIVE"
    else
      rm -rf "${FONT_DIR:?}/$FONT_ARCHIVE"
      echo "!! couldn't unpack the font (is unzip installed?) — re-run ./install.sh to retry"
    fi
    rm -f /tmp/${FONT_ARCHIVE}.zip
  else
    echo "!! Font download failed — grab Monaspace manually from https://www.nerdfonts.com"
  fi
}
install_nerd_font

# ── Manual step that cannot be scripted ──────────────────────
echo ""
echo "────────────────────────────────────────────────────────"
echo " MANUAL STEP REQUIRED — terminal font"
echo "────────────────────────────────────────────────────────"
if [ "$IS_WSL" -eq 1 ]; then
  cat <<'EOF'
 You are in WSL. The font must be installed on WINDOWS, not here,
 because Windows Terminal draws the glyphs — not WSL.
   1. In Windows: download Monaspace Nerd Font from nerdfonts.com
   2. Select the .ttf files > right-click > Install
   3. Windows Terminal > Settings > your WSL profile > Appearance
      > Font face > "MonaspiceAr Nerd Font Mono"
EOF
elif [ "$OS" = "Darwin" ]; then
  cat <<'EOF'
 On macOS the font is installed (Homebrew), but you still must
 select it in your terminal app:
   Terminal/iTerm2/Ghostty > Settings > Profile > Font
   > "MonaspiceAr Nerd Font Mono"
EOF
elif [ "$FONT_SKIPPED" -eq 1 ]; then
  cat <<'EOF'
 No display here, so the font was not installed: over SSH your
 local terminal draws the glyphs. Install the font on the machine
 you SSH from (nerdfonts.com, or on macOS:
 brew install --cask font-monaspice-nerd-font), then select
 "MonaspiceAr Nerd Font Mono" in that terminal.
EOF
fi
echo "────────────────────────────────────────────────────────"

# ── Retire the herdr auto-layout daemon ──────────────────────
# Removed on 2026-10-26: see docs/adr/20261026-drop-herdr-autolayout.md. Its
# files left the repo, so the stow loop has already pruned their links; what
# can remain is the daemon itself, still running from memory. Silent where it
# was never installed.
if [ "$OS" = "Darwin" ]; then
  plist="$HOME/Library/LaunchAgents/dotfiles.herdr-autolayout.plist"
  if [ -f "$plist" ]; then
    launchctl bootout "gui/$(id -u)/dotfiles.herdr-autolayout" &>/dev/null || true
    rm -f "$plist"
    echo "Removed the retired herdr auto-layout launchd agent"
  fi
elif command -v systemctl &>/dev/null && systemctl --user show-environment &>/dev/null; then
  # A unit whose file is gone stays loaded, and stoppable, until a reload.
  # Ask for its state rather than is-active: with Restart=always and its script
  # gone, it sits in "activating" (auto-restart) or "failed", which is-active
  # calls inactive. Never fatal: a failed stop mustn't skip the steps below.
  case "$(systemctl --user show -p ActiveState --value herdr-autolayout.service 2>/dev/null)" in
    active|activating|deactivating|reloading|failed)
      systemctl --user stop herdr-autolayout.service &>/dev/null || true
      systemctl --user reset-failed herdr-autolayout.service &>/dev/null || true
      echo "Stopped the retired herdr-autolayout.service"
      ;;
  esac
  systemctl --user daemon-reload &>/dev/null || true
fi

# ── Repo-side pre-push guard ─────────────────────────────────
# Unlike everything above, this touches the CLONE rather than $HOME.
# claude/.claude/settings.json is the one tracked file that Claude Code itself
# writes to (see clear_stow_conflicts), and this repo is public — so a session
# can append organisational detail to a public repo with no human in the loop.
# tests/test-claude-settings-scope.sh detects that; this hook is what makes it
# unmissable, by running it before anything leaves the machine.
#
# .git/hooks is not tracked by git, so a fresh clone starts with no hooks at
# all — installing it here is the only way it reaches every machine. Guarded by
# a marker so re-runs don't stack copies, and skipped when .git is absent (a
# tarball download rather than a clone).
HOOK_MARKER="# >>> dotfiles settings-scope guard >>>"
if [ -d "$DOTFILES_DIR/.git" ]; then
  hook="$DOTFILES_DIR/.git/hooks/pre-push"
  if [ -f "$hook" ] && grep -qF "$HOOK_MARKER" "$hook"; then
    : # already installed
  else
    mkdir -p "$(dirname "$hook")"
    # Append rather than overwrite: a machine may already have its own hook.
    # A fresh file needs the shebang; an existing one already has one.
    [ -s "$hook" ] || printf '#!/bin/sh\n' >"$hook"
    {
      printf '\n%s\n' "$HOOK_MARKER"
      printf '%s\n' 'if ! sh "$(git rev-parse --show-toplevel)/tests/test-claude-settings-scope.sh"; then'
      printf '%s\n' '  echo "" >&2'
      printf '%s\n' '  echo "push blocked: claude/.claude/settings.json holds machine- or org-specific" >&2'
      printf '%s\n' '  echo "content, and this repo is public. Move it into the relevant project as" >&2'
      printf '%s\n' '  echo ".claude/settings.local.json (gitignored). Override once with --no-verify." >&2'
      printf '%s\n' '  exit 1'
      printf '%s\n' 'fi'
      printf '%s\n' "# <<< dotfiles settings-scope guard <<<"
    } >>"$hook"
    chmod +x "$hook"
    echo "Installed pre-push settings-scope guard in .git/hooks/pre-push"
  fi
fi

# ── Drift check ──────────────────────────────────────────────
# Surface any config that lives next to managed files but isn't tracked
# (see doctor.sh). Report-only; never blocks the install.
if [ -x "$DOTFILES_DIR/doctor.sh" ]; then
  echo ""
  "$DOTFILES_DIR/doctor.sh" || true
fi

# ── Tool versions ────────────────────────────────────────────
# Report-only, and soft offline. Upgrading is ./update.sh --apply.
echo ""
"$DOTFILES_DIR/update.sh" || true

echo "Done. Restart your terminal (and 'exec \$SHELL') to load Starship."
