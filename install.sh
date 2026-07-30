#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DOTFILES_DIR"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

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

# ── Hand ~/.claude files over to the repo (once per machine) ─
# ~/.claude/settings.json is the live file Claude Code reads AND writes, so
# it can't be stowed while a real file already sits there. Claude writes
# *through* a symlink (verified: the link survives plugin/marketplace/config
# writes), so we track the real file and let its edits land in the repo
# instead of merging a patch into a machine-owned copy. Move any pre-existing
# file aside once; the backup keeps machine-local keys for manual re-add.
for f in settings.json statusline-command.sh; do
  t="$HOME/.claude/$f"
  if [ -e "$t" ] && [ ! -L "$t" ]; then
    mv "$t" "$t.pre-dotfiles.$(date +%s)"
    echo "Moved aside existing ~/.claude/$f — see $(basename "$t").pre-dotfiles.* backup"
  fi
done

# ── Symlink packages into $HOME ──────────────────────────────
# --no-folding: create real directories with per-file symlinks rather than
# symlinking whole dirs into the repo. This keeps ~/.config/shell (etc.) a
# real directory so per-machine files (local.sh, git 'local') land OUTSIDE
# the repo instead of inside it.
# shell must come first so XDG vars exist for anything sourced later.
for pkg in shell git nvim tmux starship herdr claude; do
  [ -d "$pkg" ] || continue
  echo "Stowing $pkg..."
  stow -v --no-folding --target="$HOME" --restow "$pkg"
done

# ── Wire the shell entrypoint into each shell's rc ───────────
# Keeps the distro-provided rc and its defaults; just appends one guarded
# line that sources our managed init.sh. Idempotent via a marker.
wire_shell_rc() {
  local rc="$1" marker="# >>> dotfiles (managed) >>>"
  [ -e "$rc" ] || return 0
  if ! grep -qF "$marker" "$rc"; then
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

# ── Seed per-machine files from templates (never overwrite) ──
[ -f "$HOME/.config/git/local" ]  || { cp "$DOTFILES_DIR/git/.config/git/local.example"       "$HOME/.config/git/local";  echo "Created ~/.config/git/local — set your name/email"; }
[ -f "$HOME/.config/shell/local.sh" ] || { cp "$DOTFILES_DIR/shell/.config/shell/local.sh.example" "$HOME/.config/shell/local.sh"; echo "Created ~/.config/shell/local.sh"; }

if [ "$IS_WSL" -eq 1 ] && ! command -v win32yank.exe &>/dev/null; then
  echo "Installing win32yank for clipboard bridge..."
  if curl -fsSLo /tmp/win32yank.zip \
      https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip 2>/dev/null; then
    unzip -oq /tmp/win32yank.zip win32yank.exe -d "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/win32yank.exe"
    rm /tmp/win32yank.zip
  else
    echo "!! win32yank download failed — clipboard sync in nvim won't work until installed"
  fi
fi

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
ensure_tool jq jq              # JSON processor (Claude status line, agent-doctor)
ensure_tool direnv direnv      # per-directory env (shell hook in tools.sh)
# delta (syntax-highlighted git diffs) — the package is git-delta on apt, brew
# AND pacman. Not `delta`: on Debian/Ubuntu that name belongs to an unrelated
# 2006-era binary-diff tool.
ensure_tool git-delta delta
# fd (friendlier find): apt calls the package fd-find, brew/pacman call it fd.
if command -v apt &>/dev/null; then ensure_tool fd-find fd fdfind; else ensure_tool fd fd fdfind; fi

# ── Neovim ───────────────────────────────────────────────────
# nvim is EDITOR/VISUAL and has a stowed config, so a fresh machine needs it.
# Distro repos lag (Ubuntu is a release or two behind; Debian stable much
# more), so on Ubuntu add the official PPA's stable channel first — tagged
# releases, and its .deb registers nvim with update-alternatives, which the
# pinning step below depends on. brew and pacman already ship current builds.
#
# Skipped entirely when nvim is already installed, so a machine deliberately
# tracking the unstable/nightly PPA keeps it.
if ! command -v nvim &>/dev/null; then
  echo "Installing neovim..."
  nvim_ppa=0
  if command -v apt &>/dev/null; then
    # PPAs are Ubuntu-only — Debian and other apt distros get the distro pkg.
    distro="$( . /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}" )" || distro=""
    case "$distro" in *ubuntu*) nvim_ppa=1 ;; esac
  fi
  if [ "$nvim_ppa" -eq 1 ]; then
    sudo apt install -y software-properties-common \
      && sudo add-apt-repository -y ppa:neovim-ppa/stable \
      && sudo apt update \
      || echo "!! neovim PPA setup failed — falling back to the distro package"
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

# ── 1Password CLI (op) ───────────────────────────────────────
# Not in distro repos; use 1Password's own channels. See
# https://developer.1password.com/docs/cli/get-started/
if ! command -v op &>/dev/null; then
  echo "Installing 1Password CLI (op)..."
  if command -v brew &>/dev/null; then
    brew install 1password-cli || echo "!! op install via brew failed"
  elif command -v apt &>/dev/null; then
    if curl -sS https://downloads.1password.com/linux/keys/1password.asc \
         | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg \
       && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
         | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null \
       && sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
       && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
         | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null \
       && sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
       && curl -sS https://downloads.1password.com/linux/keys/1password.asc \
         | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
       && sudo apt update && sudo apt install -y 1password-cli; then
      :
    else
      echo "!! op install failed — see https://developer.1password.com/docs/cli/get-started/"
    fi
  else
    echo "!! Install 1Password CLI manually: https://developer.1password.com/docs/cli/get-started/"
  fi
fi

# ── Starship ─────────────────────────────────────────────────
if ! command -v starship &>/dev/null; then
  echo "Installing Starship..."
  # official installer; -y skips the confirm prompt, BIN_DIR keeps it in ~/.local/bin
  curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" \
    || pkg_install starship \
    || echo "!! Starship install failed — install manually: https://starship.rs/installing"
fi

# ── herdr (agent-aware terminal multiplexer) ─────────────────
# Static, self-updating binary (`herdr update`); not in distro repos. The
# official installer covers Linux + macOS and drops it in ~/.local/bin. On
# macOS you can alternatively `brew install herdr` (see https://herdr.dev).
if ! command -v herdr &>/dev/null; then
  echo "Installing herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh \
    || echo "!! herdr install failed — install manually: https://herdr.dev"
fi

# ── Nerd Font (best-effort; see note printed at end) ─────────
FONT_ARCHIVE="Monaspace"                    # the release .zip name
FONT_FACE="MonaspiceAr Nerd Font Mono"      # what you select in the terminal
FONT_DIR="$XDG_DATA_HOME/fonts"
if [ ! -d "$FONT_DIR/$FONT_ARCHIVE" ]; then
  echo "Downloading $FONT_ARCHIVE Nerd Font (contains $FONT_FACE)..."
  mkdir -p "$FONT_DIR/$FONT_ARCHIVE"
  FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_ARCHIVE}.zip"
  if curl -fsSL "$FONT_URL" -o /tmp/${FONT_ARCHIVE}.zip 2>/dev/null; then
    unzip -oq /tmp/${FONT_ARCHIVE}.zip -d "$FONT_DIR/$FONT_ARCHIVE" && rm /tmp/${FONT_ARCHIVE}.zip
    command -v fc-cache &>/dev/null && fc-cache -f "$FONT_DIR" >/dev/null 2>&1
    echo "Font files placed in $FONT_DIR/$FONT_ARCHIVE"
  else
    echo "!! Font download failed — grab Monaspace manually from https://www.nerdfonts.com"
  fi
fi


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
 On macOS: the font files were downloaded, but you still must
 select the font in your terminal app:
   1. Install: open the .ttf files in ~/.local/share/fonts/ > "Install Font"
      (or: brew install --cask font-monaspace-nerd-font)
   2. Terminal/iTerm2/Ghostty > Settings > Profile > Font
      > "MonaspiceAr Nerd Font Mono"
EOF
fi
echo "────────────────────────────────────────────────────────"

# ── herdr auto-layout daemon ─────────────────────────────────
# Splits every new git-worktree workspace and opens a lazygit tab. herdr has no
# on_worktree_create hook, so this is a socket-API subscriber that needs to be
# running; see herdr/.config/herdr/scripts/herdr-autolayout.
if command -v systemctl &>/dev/null && systemctl --user show-environment &>/dev/null; then
  systemctl --user daemon-reload
  if systemctl --user enable --now herdr-autolayout.service &>/dev/null; then
    echo "Enabled herdr-autolayout.service (user unit)"
  else
    echo "!! could not enable herdr-autolayout.service — run: systemctl --user enable --now herdr-autolayout.service"
  fi
else
  echo "!! no systemd --user — start the herdr auto-layout daemon yourself:"
  echo "   ~/.config/herdr/scripts/herdr-autolayout &"
fi

# ── Drift check ──────────────────────────────────────────────
# Surface any config that lives next to managed files but isn't tracked
# (see doctor.sh). Report-only; never blocks the install.
if [ -x "$DOTFILES_DIR/doctor.sh" ]; then
  echo ""
  "$DOTFILES_DIR/doctor.sh" || true
fi

echo "Done. Restart your terminal (and 'exec \$SHELL') to load Starship."
