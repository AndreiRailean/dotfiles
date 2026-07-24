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

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$DOTFILES_DIR"

PACKAGES="shell git nvim tmux starship claude"
ADOPT=0
[ "${1:-}" = "--adopt" ] && ADOPT=1

# ── AI-agent tmux integration health (report-only; never affects drift) ──
if [ "$ADOPT" -eq 0 ] && [ -x "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" ]; then
  "$DOTFILES_DIR/tmux/.config/tmux/scripts/agent-doctor" || true
  echo
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

# ── Report ──────────────────────────────────────────────────
found=0

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

echo "Run './doctor.sh --adopt' to move untracked files into the repo, then commit."
exit 1
