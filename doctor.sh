#!/usr/bin/env bash
# doctor.sh — detect config that has drifted out of the dotfiles repo.
#
# Because packages are stowed with --no-folding, the target dirs
# (~/.config/nvim, ~/.config/git, …) are REAL directories holding per-file
# symlinks. A tool — or you — writing a NEW file there creates a real file
# OUTSIDE the repo, invisible to `git status`. This finds those, plus broken
# and missing symlinks, and can adopt the new files into the repo.
#
#   ./doctor.sh          report drift (exit 1 if anything found)
#   ./doctor.sh --adopt  move untracked files into the repo, then re-stow
#
# Files matched by .gitignore (local.sh, git/local, …) are treated as
# intentionally per-machine and never reported.
#
# It also reports the reverse direction: config a TOOL rewrote inside the repo
# (see AUTO_WRITTEN) that you haven't committed, and commits you haven't pushed.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$DOTFILES_DIR"

PACKAGES="shell git nvim tmux starship herdr lazygit claude"
ADOPT=0
[ "${1:-}" = "--adopt" ] && ADOPT=1

# ── AI-agent tmux integration health (report-only; never affects drift) ──
if [ "$ADOPT" -eq 0 ] && [ -x "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" ]; then
  "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" || true
  echo
fi

# ── Editor health (report-only; never affects drift) ────────
# The vim -> nvim aliases only apply to interactive shells. If the `vim` binary
# itself still resolves to classic vim, scripts and sudo get the wrong editor.
if [ "$ADOPT" -eq 0 ] && command -v nvim >/dev/null 2>&1 && command -v vim >/dev/null 2>&1; then
  if ! vim --version 2>/dev/null | head -1 | grep -qi nvim; then
    echo "▲ The 'vim' binary is classic vim, not neovim (aliases only cover interactive shells)."
    if command -v update-alternatives >/dev/null 2>&1; then
      echo "    fix: re-run ./install.sh, or: sudo update-alternatives --set vim \"\$(command -v nvim)\""
    else
      echo "    fix: point vim at $(command -v nvim) however this OS manages it"
    fi
    echo
  fi
fi

# ── lazygit version health (report-only; never affects drift) ───
# install.sh's lazygit_meets_floor guarantees >= 0.64.0 on install, but this
# doesn't re-run on every shell — a machine that already had apt's older
# lazygit before install.sh last ran, or one that fell back to it when
# install_lazygit_release failed (no network, GitHub API rate-limited,
# unsupported arch, ...), can be left with a stale binary silently reading
# the managed config's git.diffRenderers and ignoring it: no delta, no
# warning, nothing from lazygit itself. Duplicates install.sh's
# lazygit_meets_floor comparison (no shared shell lib between the two
# scripts) — keep both in sync if the floor value ever changes. A missing
# lazygit is louder and different; only warn here when it's present and
# below the floor.
if [ "$ADOPT" -eq 0 ] && command -v lazygit >/dev/null 2>&1; then
  lg_out="$(lazygit --version 2>/dev/null)" || lg_out=""
  lg_ver="$(printf '%s\n' "$lg_out" | sed -n 's/.*version=[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)[^,]*, *os=.*/\1/p')"
  lg_major="${lg_ver%%.*}"
  lg_minor="${lg_ver#*.}"; lg_minor="${lg_minor%%.*}"
  case "$lg_major" in ''|*[!0-9]*) lg_major="" ;; esac
  case "$lg_minor" in ''|*[!0-9]*) lg_minor="" ;; esac
  if [ -n "$lg_ver" ] && [ -n "$lg_major" ] && [ -n "$lg_minor" ] \
     && [ "$lg_major" -eq 0 ] && [ "$lg_minor" -lt 64 ]; then
    echo "▲ lazygit $lg_ver is below the 0.64 floor — the managed config's git.diffRenderers"
    echo "    is ignored silently (no delta, no warning)."
    echo "    fix: re-run ./install.sh"
    echo
  fi
fi

untracked=()   # "target|pkg|rel"
broken=()      # dangling symlinks
missing=()     # repo files not linked into $HOME

is_ignored() { git check-ignore -q "$1" 2>/dev/null; }

# Owned roots for a package: the top dir it introduces under $HOME
# (.config/<name>) or a top-level file, derived from its tracked files.
owned_roots() {
  find "$1" -type f | while IFS= read -r f; do
    rel="${f#"$1"/}"
    case "$rel" in
      .config/*/*) printf '.config/%s\n' "$(printf '%s' "$rel" | cut -d/ -f2)" ;;
      *)           printf '%s\n' "$rel" ;;
    esac
  done | sort -u
}

for pkg in $PACKAGES; do
  [ -d "$pkg" ] || continue

  # (a) every tracked file should be a live symlink in $HOME
  while IFS= read -r f; do
    target="$HOME/${f#"$pkg"/}"
    if [ -L "$target" ] && [ -e "$target" ]; then :          # linked, resolves
    elif [ -L "$target" ]; then broken+=("$target")          # dangling
    else missing+=("$target  (run: stow --no-folding --target=\"\$HOME\" $pkg)")
    fi
  done < <(find "$pkg" -type f)

  # (b) scan each owned directory tree for REAL files (= untracked) and
  #     for dangling symlinks introduced elsewhere
  while IFS= read -r root; do
    troot="$HOME/$root"
    [ -d "$troot" ] && [ ! -L "$troot" ] || continue
    while IFS= read -r entry; do
      if [ -L "$entry" ]; then
        [ -e "$entry" ] || broken+=("$entry")
      elif [ -f "$entry" ]; then
        rel="${entry#"$HOME"/}"
        is_ignored "$pkg/$rel" || untracked+=("$entry|$pkg|$rel")
      fi
    done < <(find "$troot" \( -type f -o -type l \))
  done < <(owned_roots "$pkg")
done

# ── Machine-written config: uncommitted / unpushed ──────────
# Some tracked files are rewritten by the tool that owns them, not by you.
# The list lives in .auto-written so drift.sh can share it; see that file for
# why it is scoped rather than covering the whole repo.
AUTO_WRITTEN=()
if [ -r "$DOTFILES_DIR/.auto-written" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"                      # strip comments
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && AUTO_WRITTEN+=("$line")
  done < "$DOTFILES_DIR/.auto-written"
fi

# An empty list would make `git status -- ` cover the WHOLE repo and report
# every ordinary edit, so skip the check rather than cry wolf.
autodirty=()
if [ "${#AUTO_WRITTEN[@]}" -gt 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && autodirty+=("$line")
  done < <(git status --porcelain -- "${AUTO_WRITTEN[@]}" 2>/dev/null || true)
fi

# Committed but never pushed = the change isn't on your other machines yet,
# which defeats the point of keeping this config in a repo at all.
unpushed=0
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  unpushed=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
fi

# ── Report ──────────────────────────────────────────────────
found=0

if [ "${#autodirty[@]}" -gt 0 ]; then
  found=1
  echo "▲ Machine-written config changed but not committed:"
  for e in "${autodirty[@]}"; do echo "    $e"; done
  echo "    review: git -C \"$DOTFILES_DIR\" diff -- ${AUTO_WRITTEN[*]}"
  echo
fi
if [ "$unpushed" -gt 0 ]; then
  found=1
  echo "▲ $unpushed commit(s) not pushed — your other machines don't have them:"
  echo "    fix: git -C \"$DOTFILES_DIR\" push"
  echo
fi

if [ "${#untracked[@]}" -gt 0 ]; then
  found=1
  echo "▲ Untracked config living in a managed tree (not in the repo):"
  for e in "${untracked[@]}"; do echo "    ${e%%|*}"; done
  echo
fi
if [ "${#broken[@]}" -gt 0 ]; then
  found=1
  echo "✗ Broken symlinks (repo file was moved or deleted):"
  for e in "${broken[@]}"; do echo "    $e"; done
  echo
fi
if [ "${#missing[@]}" -gt 0 ]; then
  found=1
  echo "✗ Tracked files not linked into \$HOME:"
  for e in "${missing[@]}"; do echo "    $e"; done
  echo
fi

if [ "$found" -eq 0 ]; then
  echo "✓ No drift — every managed config is tracked and linked."
  exit 0
fi

# ── Adopt ───────────────────────────────────────────────────
if [ "$ADOPT" -eq 1 ] && [ "${#untracked[@]}" -gt 0 ]; then
  echo "Adopting untracked files into the repo…"
  declare -A restow=()
  for e in "${untracked[@]}"; do
    IFS='|' read -r target pkg rel <<<"$e"
    dest="$DOTFILES_DIR/$pkg/$rel"
    mkdir -p "$(dirname "$dest")"
    mv "$target" "$dest"
    restow["$pkg"]=1
    echo "    adopted $rel  ->  $pkg/"
  done
  for pkg in "${!restow[@]}"; do
    stow --no-folding --target="$HOME" --restow "$pkg"
  done
  echo "Done. Review with 'git status' and commit."
  exit 0
fi

if [ "${#untracked[@]}" -gt 0 ]; then
  echo "Run './doctor.sh --adopt' to move untracked files into the repo, then commit."
fi
exit 1
