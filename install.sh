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

# ── Symlink packages into $HOME ──────────────────────────────
# --no-folding: create real directories with per-file symlinks rather than
# symlinking whole dirs into the repo. This keeps ~/.config/shell (etc.) a
# real directory so per-machine files (local.sh, git 'local') land OUTSIDE
# the repo instead of inside it.
# shell must come first so XDG vars exist for anything sourced later.
for pkg in shell git nvim tmux starship claude; do
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

# ── bat (a nicer cat) ────────────────────────────────────────
# On Debian/Ubuntu the apt package installs the binary as `batcat`; the shell
# aliases handle either name.
if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
  echo "Installing bat..."
  pkg_install bat || echo "!! bat install failed — install manually: https://github.com/sharkdp/bat"
fi

# ── eza (a nicer ls) ─────────────────────────────────────────
if ! command -v eza &>/dev/null; then
  echo "Installing eza..."
  pkg_install eza || echo "!! eza install failed — see https://github.com/eza-community/eza/blob/main/INSTALL.md"
fi

# ── Starship ─────────────────────────────────────────────────
if ! command -v starship &>/dev/null; then
  echo "Installing Starship..."
  # official installer; -y skips the confirm prompt, BIN_DIR keeps it in ~/.local/bin
  curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" \
    || pkg_install starship \
    || echo "!! Starship install failed — install manually: https://starship.rs/installing"
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

# ── Drift check ──────────────────────────────────────────────
# Surface any config that lives next to managed files but isn't tracked
# (see doctor.sh). Report-only; never blocks the install.
if [ -x "$DOTFILES_DIR/doctor.sh" ]; then
  echo ""
  "$DOTFILES_DIR/doctor.sh" || true
fi

echo "Done. Restart your terminal (and 'exec \$SHELL') to load Starship."
