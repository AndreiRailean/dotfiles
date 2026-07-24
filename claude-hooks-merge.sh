#!/bin/sh
# claude-hooks-merge.sh <settings_path> <scripts_dir>
# Idempotently merge the tmux agent-notify hooks into a Claude settings.json.
# Safeguards: skips if jq is missing; backs up; aborts on invalid existing
# JSON; validates the result before writing; never duplicates our hooks;
# never overrides an existing preferredNotifChannel.
set -eu

settings="${1:-$HOME/.claude/settings.json}"
scripts_dir="${2:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/scripts}"
cmd="$scripts_dir/agent-notify"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found — skipping Claude hook install (see README to add manually)." >&2
  exit 0
fi

mkdir -p "$(dirname "$settings")"

if [ -f "$settings" ] && [ -s "$settings" ]; then
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "ERROR: $settings is not valid JSON; refusing to modify it." >&2
    exit 1
  fi
  cp "$settings" "$settings.bak"
  base="$(cat "$settings")"
else
  base='{}'
fi

tmp="$(mktemp)"
printf '%s' "$base" | jq --arg cmd "$cmd" '
  def ensure($ev; $group):
    .hooks[$ev] = ((.hooks[$ev] // [])
      | if any(.[]; any(.hooks[]?; .command == $cmd)) then . else . + [$group] end);
  (. // {})
  | .hooks = (.hooks // {})
  | ensure("UserPromptSubmit"; {hooks: [{type: "command", command: $cmd}]})
  | ensure("Stop";            {hooks: [{type: "command", command: $cmd}]})
  | ensure("Notification";    {matcher: "", hooks: [{type: "command", command: $cmd}]})
  | .preferredNotifChannel = (.preferredNotifChannel // "terminal_bell")
' > "$tmp"

if ! jq -e . "$tmp" >/dev/null 2>&1; then
  echo "ERROR: merge produced invalid JSON; leaving $settings unchanged." >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$settings"
