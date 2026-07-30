# ~/.config/shell/drift.sh — nudge when a tool rewrote tracked dotfiles config
#
# Some files in the dotfiles repo are rewritten by the tool that owns them
# rather than by you: Claude Code rewrites claude/.claude/settings.json
# whenever a setting changes (/config, /effort, /fast, plugin toggles,
# accepted dialogs). Those edits land in the repo silently, so without a
# prompt like this they sit uncommitted until you happen to run `git status`
# in ~/dotfiles — which is exactly the thing you forget to do.
#
# Prints two short lines (what changed, what to run), only when something
# needs attention, and at most once every $DOTFILES_DRIFT_NUDGE_HOURS
# (default 4). Set DOTFILES_DRIFT_NUDGE=0 to silence it entirely, or call
# `_dotfiles_drift_nudge force` to check on demand, ignoring the rate limit.
# `./doctor.sh` remains the deliberate deep check; this is only the ambient
# reminder to go run it.
#
# POSIX sh: sourced by both bash and zsh via init.sh.

_dotfiles_drift_nudge() {
  [ "${DOTFILES_DRIFT_NUDGE:-1}" = "1" ] || return 0

  # Interactive shells only — never pollute scripts, scp, or rsync streams.
  case $- in *i*) ;; *) return 0 ;; esac
  command -v git >/dev/null 2>&1 || return 0

  # Locate the repo without hardcoding a path: ~/.config/shell/env.sh is a
  # symlink into it, so resolve that and ask git for the worktree root. Falls
  # back to ~/dotfiles if readlink -f is unavailable (older BSD/macOS).
  _dn_repo="${DOTFILES_DIR:-}"
  if [ -z "$_dn_repo" ]; then
    _dn_link=$(readlink -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh" 2>/dev/null)
    if [ -n "$_dn_link" ]; then
      _dn_repo=$(git -C "${_dn_link%/*}" rev-parse --show-toplevel 2>/dev/null)
    fi
  fi
  [ -n "$_dn_repo" ] || _dn_repo="$HOME/dotfiles"
  git -C "$_dn_repo" rev-parse --show-toplevel >/dev/null 2>&1 || return 0

  # Rate limit. The stamp is written only when we actually print, so drift
  # appearing right after a quiet check is still reported promptly.
  _dn_stamp="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/drift-nudge"
  if [ "${1:-}" != "force" ] && [ -r "$_dn_stamp" ]; then
    _dn_last=$(cat "$_dn_stamp" 2>/dev/null)
    case $_dn_last in '' | *[!0-9]*) _dn_last=0 ;; esac
    _dn_window=$(( ${DOTFILES_DRIFT_NUDGE_HOURS:-4} * 3600 ))
    if [ $(( $(date +%s) - _dn_last )) -lt "$_dn_window" ]; then
      unset _dn_repo _dn_link _dn_stamp _dn_last _dn_window
      return 0
    fi
  fi

  # Keep this list in sync with AUTO_WRITTEN in doctor.sh.
  _dn_dirty=$(git -C "$_dn_repo" status --porcelain -- \
    claude/.claude/settings.json 2>/dev/null)

  _dn_unpushed=0
  if git -C "$_dn_repo" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    _dn_unpushed=$(git -C "$_dn_repo" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
    case $_dn_unpushed in '' | *[!0-9]*) _dn_unpushed=0 ;; esac
  fi

  _dn_msg=""
  if [ -n "$_dn_dirty" ]; then
    _dn_msg="uncommitted: $(printf '%s\n' "$_dn_dirty" | awk '{print $NF}' | tr '\n' ' ')"
    _dn_msg="${_dn_msg% }"
  fi
  if [ "$_dn_unpushed" -gt 0 ]; then
    _dn_msg="${_dn_msg:+$_dn_msg · }${_dn_unpushed} unpushed"
  fi

  if [ -n "$_dn_msg" ]; then
    case $_dn_repo in
      "$HOME"/*) _dn_disp="~${_dn_repo#"$HOME"}" ;;
      *) _dn_disp="$_dn_repo" ;;
    esac
    printf '▲ dotfiles: %s\n' "$_dn_msg"
    printf '    review: cd %s && ./doctor.sh\n' "$_dn_disp"
    mkdir -p "${_dn_stamp%/*}" 2>/dev/null && date +%s >"$_dn_stamp" 2>/dev/null
  fi

  unset _dn_repo _dn_link _dn_stamp _dn_last _dn_window _dn_dirty _dn_unpushed _dn_msg _dn_disp
}

_dotfiles_drift_nudge
