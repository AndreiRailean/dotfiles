#!/bin/sh
# devserver-port.sh contract: print ":PORT[,PORT…]" on ONE line and exit 0 when
# a listening socket's process was started inside this workspace; print nothing
# and exit 1 otherwise. Driven through the DEVSERVER_SS / DEVSERVER_PROC seams
# with a fake `ss` and a fake proc tree, so the whole matrix runs with no live
# server and no root.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$REPO/starship/.config/starship/devserver-port.sh"

if [ -f "$SCRIPT" ]; then
  pass "the detection script exists"
else
  fail "the detection script exists"
  finish
fi

[ -x "$SCRIPT" ] && pass "the detection script is executable" \
  || fail "the detection script is executable"
sh -n "$SCRIPT" && pass "devserver-port.sh parses" \
  || fail "devserver-port.sh parses"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A real git repo, because the script resolves the workspace with
# `git rev-parse --show-toplevel`. The sibling is named so the ROOT path is a
# string prefix of it: that is what distinguishes matching on "$root/" from
# matching on "$root*", and a sibling with an unrelated name passes either way.
ROOT="$TMP/app"
mkdir -p "$ROOT/src" "$TMP/app-next" "$TMP/plain" "$TMP/proc" "$TMP/bin"
git -C "$ROOT" init -q 2>/dev/null

# Fake ss: ignores the flags it is handed and replays the staged lines.
cat > "$TMP/bin/ss" <<'STUB'
#!/bin/sh
cat "$FAKE_SS_LINES" 2>/dev/null
exit 0
STUB
chmod +x "$TMP/bin/ss"

reset_ss() { : > "$TMP/ss.txt"; }

# Real `ss -ltnpH` output for a Next.js dev server. The process name is
# truncated mid-token, leaving an unbalanced paren and a stray quote —
# `(("next-server (v1",pid=…,fd=22))` — so the parse must not depend on
# punctuation being balanced.
add_listener() { # add_listener PORT PID
  printf 'LISTEN 0 511 *:%s *:* users:(("next-server (v1",pid=%s,fd=22))\n' \
    "$1" "$2" >> "$TMP/ss.txt"
}

# A resolver socket: scope-id in the address and no process column at all.
add_noise() {
  printf 'LISTEN 0 4096 127.0.0.53%%lo:53 0.0.0.0:*\n' >> "$TMP/ss.txt"
}

mkproc() { # mkproc PID CWD
  mkdir -p "$TMP/proc/$1"
  ln -sfn "$2" "$TMP/proc/$1/cwd"
}

run() { # run FROM_DIR [PROC_ROOT] [SS_PATH] -> stdout, status in $?
  ( cd "$1" && FAKE_SS_LINES="$TMP/ss.txt" \
      DEVSERVER_SS="${3:-$TMP/bin/ss}" \
      DEVSERVER_PROC="${2:-$TMP/proc}" sh "$SCRIPT" )
}

# ── cwd IS the workspace root ────────────────────────────────
reset_ss; add_noise; add_listener 3001 1001
mkproc 1001 "$ROOT"
out="$(run "$ROOT")"; rc=$?
assert_eq "$out" ":3001" "a listener started in the workspace root reports its port"
assert_eq "$rc" "0" "a match exits 0"

# ── invoked from a subdirectory ──────────────────────────────
# The root comes from git, not from the directory the script happens to run in.
out="$(run "$ROOT/src")"; rc=$?
assert_eq "$out" ":3001" "from a subdirectory, the root is still resolved via git"
assert_eq "$rc" "0" "a match from a subdirectory exits 0"

# ── sibling worktree, prefix-colliding name ──────────────────
reset_ss; add_listener 3002 1002
mkproc 1002 "$TMP/app-next"
out="$(run "$ROOT")"; rc=$?
assert_eq "$out" "" "a sibling whose path merely starts with the root is not claimed"
assert_eq "$rc" "1" "a sibling-only listener exits 1"

# ── listener in a subdirectory of the workspace ──────────────
reset_ss; add_listener 3003 1003
mkproc 1003 "$ROOT/src"
out="$(run "$ROOT")"
assert_eq "$out" ":3003" "a listener started under the workspace is matched"

# ── two listeners, deduplicated ──────────────────────────────
# The same port twice stands for one process holding several sockets.
reset_ss; add_listener 54321 1004; add_listener 3001 1005; add_listener 3001 1005
mkproc 1004 "$ROOT"; mkproc 1005 "$ROOT"
out="$(run "$ROOT")"
assert_eq "$out" ":3001,54321" "two listeners report both ports, deduplicated"

# ── ports sort numerically, not lexically ────────────────────
# 999 vs 3001 is the discriminating pair: a lexical sort puts 3001 first.
reset_ss; add_listener 3001 1006; add_listener 999 1007
mkproc 1006 "$ROOT"; mkproc 1007 "$ROOT"
out="$(run "$ROOT")"
assert_eq "$out" ":999,3001" "ports are ordered numerically"

# ── one line, always ─────────────────────────────────────────
# starship substitutes $output verbatim, so an embedded newline would land in
# the prompt. $(…) strips only the trailing one, so wc counts what is left.
nl="$(printf '%s' "$out" | wc -l | tr -d ' ')"
assert_eq "$nl" "0" "multi-port output is a single line"

# ── one socket naming several PIDs ───────────────────────────
reset_ss
printf 'LISTEN 0 511 *:4000 *:* users:(("a b (c",pid=1008,fd=1),("d",pid=1009,fd=2))\n' \
  > "$TMP/ss.txt"
mkproc 1008 "$TMP/app-next"; mkproc 1009 "$ROOT"
out="$(run "$ROOT")"
assert_eq "$out" ":4000" "a socket naming several PIDs matches when any lives here"

# ── outside a git repo, the directory is the scope ───────────
reset_ss; add_listener 5000 1010
mkproc 1010 "$TMP/plain"
out="$(run "$TMP/plain")"; rc=$?
assert_eq "$out" ":5000" "outside a repo the current directory is the workspace"
assert_eq "$rc" "0" "a match outside a repo exits 0"

# ── nothing listening ────────────────────────────────────────
reset_ss
out="$(run "$ROOT")"; rc=$?
assert_eq "$out" "" "no listeners produces no output"
assert_eq "$rc" "1" "no listeners exits 1"

# ── no /proc: the macOS case ─────────────────────────────────
reset_ss; add_listener 3001 1001
out="$(run "$ROOT" "$TMP/no-such-proc")"; rc=$?
assert_eq "$out" "" "a host without /proc produces no output"
assert_eq "$rc" "1" "a host without /proc exits 1"

# ── no ss binary ─────────────────────────────────────────────
out="$(run "$ROOT" "$TMP/proc" "$TMP/bin/no-such-ss" 2>/dev/null)"; rc=$?
assert_eq "$out" "" "a missing ss produces no output"
assert_eq "$rc" "1" "a missing ss exits 1"

# ── stderr stays empty ───────────────────────────────────────
# Anything on stderr is a candidate for leaking into a prompt.
err="$( run "$ROOT" "$TMP/no-such-proc" "$TMP/bin/no-such-ss" 2>&1 1>/dev/null )"
assert_eq "$err" "" "nothing is written to stderr even when everything is missing"

finish
