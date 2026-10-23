#!/bin/sh
# agents-md-probe.sh reports, at session start, AGENTS.md files whose
# conventions are not in context. Since 2.1.277 Claude Code loads AGENTS.md on
# its own, but only in a project with no CLAUDE.md, .claude/CLAUDE.md or
# CLAUDE.local.md — any one of those switches the fallback off for the whole
# session. So the probe must stay quiet in the first case and fire in the
# second, where an un-imported AGENTS.md is silently dropped.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/agents-md-probe.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

G="git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false"
run_in() { ( cd "$1" && printf '%s' '{}' | sh "$PROBE" ); }
fresh() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"
  $G init --quiet "$TMP/r"
  echo '# Conventions' > "$TMP/r/AGENTS.md"
}
track() { ( cd "$TMP/r" && $G add -- "$@" ); }

# ── no CLAUDE.md anywhere: Claude Code loads AGENTS.md itself ──
fresh; track AGENTS.md
out="$(run_in "$TMP/r")"
assert_eq "$out" "" "silent when no CLAUDE.md switches the native fallback off"

# Nested AGENTS.md load where a CLAUDE.md would, so they're covered too.
mkdir -p "$TMP/r/pkg"; echo '# Pkg' > "$TMP/r/pkg/AGENTS.md"; track pkg/AGENTS.md
out="$(run_in "$TMP/r")"
assert_eq "$out" "" "silent for nested AGENTS.md when the fallback is on"

# ── a CLAUDE.md that never mentions AGENTS.md ─────────────────
fresh; echo '# Notes' > "$TMP/r/CLAUDE.md"; track AGENTS.md CLAUDE.md
out="$(run_in "$TMP/r")"
assert_contains "$out" 'hookSpecificOutput' "an unconnected CLAUDE.md emits a probe"
assert_contains "$out" 'SessionStart' "the probe names the SessionStart event"
assert_contains "$out" 'point-claude-at-agents-md' "the probe points at the skill"
assert_not_contains "$out" 'does not read AGENTS.md' "the probe no longer claims AGENTS.md is never read"

# ── a CLAUDE.md that imports it ───────────────────────────────
printf '@AGENTS.md\n' >> "$TMP/r/CLAUDE.md"
out="$(run_in "$TMP/r")"
assert_eq "$out" "" "silent once CLAUDE.md imports AGENTS.md"

# ── the other two names switch the fallback off as well ───────
# CLAUDE.local.md is usually gitignored, so it has to be found on disk, not
# through git ls-files.
fresh; echo '# mine' > "$TMP/r/CLAUDE.local.md"; track AGENTS.md
out="$(run_in "$TMP/r")"
assert_contains "$out" 'hookSpecificOutput' "an untracked CLAUDE.local.md alone still emits a probe"

fresh; mkdir -p "$TMP/r/.claude"; echo '# Notes' > "$TMP/r/.claude/CLAUDE.md"; track AGENTS.md .claude/CLAUDE.md
out="$(run_in "$TMP/r")"
assert_contains "$out" 'hookSpecificOutput' ".claude/CLAUDE.md alone emits a probe"

# ── a monorepo leaf with no import of its own ─────────────────
fresh; printf '@AGENTS.md\n' > "$TMP/r/CLAUDE.md"
mkdir -p "$TMP/r/pkg"; echo '# Pkg' > "$TMP/r/pkg/AGENTS.md"
track AGENTS.md CLAUDE.md pkg/AGENTS.md
out="$(run_in "$TMP/r")"
assert_contains "$out" 'pkg/' "a leaf AGENTS.md is reported once the fallback is off"

# A CLAUDE.md in a subdirectory only counts when the session starts there.
fresh; mkdir -p "$TMP/r/sub"; echo '# Notes' > "$TMP/r/sub/CLAUDE.md"; track AGENTS.md sub/CLAUDE.md
out="$(run_in "$TMP/r")"
assert_eq "$out" "" "a CLAUDE.md below the session directory doesn't switch the fallback off"
out="$(run_in "$TMP/r/sub")"
assert_contains "$out" 'hookSpecificOutput' "starting in that directory does"

# ── it never disrupts a session ───────────────────────────────
mkdir -p "$TMP/plain"
( cd "$TMP/plain" && printf '%s' '{}' | sh "$PROBE" ); rc=$?
assert_eq "$rc" "0" "exits 0 outside a git repo"

finish
