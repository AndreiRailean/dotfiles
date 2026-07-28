#!/bin/sh
# git package: delta is wired in as the pager, and the wiring degrades safely
# on machines that don't have delta — git treats a missing pager as FATAL, so
# the guard in core.pager is load-bearing, not decoration.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
CONF="$REPO/git/.config/git/config"

# Config still parses after the additions
git config --file "$CONF" --list >/dev/null 2>&1 \
  && pass "git config parses" || fail "git config parses"

PAGER_EXPR="$(git config --file "$CONF" core.pager 2>/dev/null)"
FILTER_EXPR="$(git config --file "$CONF" interactive.diffFilter 2>/dev/null)"
[ -n "$PAGER_EXPR" ] && pass "core.pager is set" || fail "core.pager is set"
[ -n "$FILTER_EXPR" ] && pass "interactive.diffFilter is set" || fail "interactive.diffFilter is set"

# delta settings
assert_eq "$(git config --file "$CONF" delta.navigate)" "true" "delta.navigate on"
assert_eq "$(git config --file "$CONF" delta.line-numbers)" "true" "delta.line-numbers on"
assert_eq "$(git config --file "$CONF" diff.colorMoved)" "default" "diff.colorMoved default"

# ── Behavioural: run the real expressions with stubbed binaries ──
# git runs core.pager through the shell, so we can too.
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT INT TERM
printf '#!/bin/sh\necho USED_DELTA\n' >"$BIN/delta"
printf '#!/bin/sh\necho USED_LESS\n'  >"$BIN/less"
printf '#!/bin/sh\necho USED_CAT\n'   >"$BIN/cat"
chmod +x "$BIN/delta" "$BIN/less" "$BIN/cat"

# PATH is narrowed inside the child, not as an assignment prefix — the latter
# would hide the `sh` binary we're trying to launch.
run_expr() { echo x | sh -c "PATH='$BIN'; $1" 2>/dev/null; }

# delta present -> delta drives both
assert_eq "$(run_expr "$PAGER_EXPR")"  "USED_DELTA" "pager uses delta when installed"
assert_eq "$(run_expr "$FILTER_EXPR")" "USED_DELTA" "diffFilter uses delta when installed"

# delta absent -> falls back instead of the fatal 'unable to execute pager'
rm -f "$BIN/delta"
assert_eq "$(run_expr "$PAGER_EXPR")"  "USED_LESS" "pager falls back to less without delta"
assert_eq "$(run_expr "$FILTER_EXPR")" "USED_CAT"  "diffFilter falls back to cat without delta"

# install.sh asks for git-delta: on Debian/Ubuntu the plain `delta` package is
# an unrelated 2006-era binary-diff tool.
grep -q 'ensure_tool git-delta delta' "$REPO/install.sh" \
  && pass "install.sh installs git-delta" || fail "install.sh installs git-delta"
grep -Eq '^ensure_tool delta( |$)' "$REPO/install.sh" \
  && fail "install.sh avoids the wrong 'delta' package" || pass "install.sh avoids the wrong 'delta' package"

finish
