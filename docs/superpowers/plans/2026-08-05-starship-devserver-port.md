# Starship dev-server port segment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show in the prompt which port a dev server is listening on *for the workspace you are standing in*, so several worktrees of the same project each report their own port instead of leaving you to hunt process lists.

**Architecture:** One new POSIX `sh` script in the existing `starship` Stow package maps workspace → port exactly (`ss` gives port → PID, `/proc/PID/cwd` gives where that PID started), and a starship `custom` module renders it. The script's *exit status* is the detection and its *stdout* is the content — starship's `when` and `command` both point at it. Because Claude Code's status line renders the real starship binary, the one module surfaces in the terminal prompt and in every Claude Code session.

**Tech Stack:** POSIX `sh`, `ss` (iproute2), `/proc`, starship 1.26.0 `custom` modules, GNU Stow, POSIX sh tests via `tests/lib.sh`.

**Spec:** `docs/superpowers/specs/2026-08-05-starship-devserver-port-design.md`

## Global Constraints

- **Conventional Commits**, imperative lower-case subject, scope preferred: `feat(starship):`, `test(starship):`, `docs(starship):`. Why goes in the commit body. Commits land **directly on `master`** in this repo — no PR flow.
- **Comments state the present mechanism.** Never history ("it used to…"), never point-in-time counts ("the three worktrees currently on the machine").
- **Nothing may ever leak into a prompt.** All stderr is discarded inside the script; every failure mode (missing `ss`, unreadable `/proc/PID/cwd`, a PID that exits mid-scan, a process owned by another user) degrades to "no match", never to an error message or a non-empty stdout.
- **The script prints exactly one line.** starship substitutes `$output` verbatim, so a newline inside it lands in the prompt and breaks the two-line layout. Verified: two lines of output render as two lines in the prompt.
- **The contract is stdout + exit status, nothing else.** No starship concepts inside the script; it must be fully exercisable without starship.
- **Linux-only detection, silent elsewhere.** Requires `/proc`. On macOS the script exits 1 and the segment never appears; name `lsof -a -p PID -d cwd` in a comment, do not implement it.
- **No name allowlist.** Any listening process whose cwd is in the workspace counts — `next dev`, `vite`, `supabase functions serve`, `python -m http.server`.
- **Tests are POSIX `sh`**, source `tests/lib.sh`, use `pass`/`fail`/`assert_eq`/`assert_contains`/`assert_not_contains`, end with `finish`. Missing optional dependencies print `  skip: …` rather than failing — but a skip must never be reachable when the thing under test *is* present, or the check passes vacuously. `tests/run.sh` globs `test-*.sh`; no registration needed.
- **Stow uses `--no-folding`** (`install.sh:54`, `doctor.sh:200`), so `~/.config/starship/` becomes a real directory holding a symlink to the script. `starship` is already in `install.sh`'s stow loop and `doctor.sh`'s `PACKAGES` — **no wiring changes are needed in either file.**
- **The script's executable bit must be committed** (`git update-index --chmod=+x` if it is lost). Verified: starship invokes the bare path through the stow symlink, so the mode matters.
- **Never type or paste the U+F233 glyph — write it with `printf '\357\210\263'`.** It is a private-use codepoint, and editors, clipboards and tool pipelines drop it silently: a first draft of this plan lost it between authoring and disk, leaving `symbol = " "` with nothing inside. The bytes are `ef 88 b3`, the test asserts them, and every step that writes the character does so through `printf`.
- **`starship.toml` is almost entirely ASCII.** Its only private-use character is U+F033E in `[directory] read_only`. `[nodejs] symbol` and `[git_branch] symbol` are bare spaces, *not* glyphs — do not assume a nerd-font icon is there to match or avoid. Check with `python3 -c` over the file rather than trusting what a terminal renders.

## Verified starship 1.26.0 behaviour

Everything below was established empirically against the installed binary, not from docs. Re-derive with a throwaway `STARSHIP_CONFIG=… starship prompt --path … --status 0`, and always `env -u STARSHIP_SHELL` — with `STARSHIP_SHELL` set, starship wraps colours in literal `\[ \]` readline markers.

| Module state | Renders |
| --- | --- |
| no `when` key at all | nothing — even with output |
| `when` succeeds, output empty | **the glyph wrapped around nothing** |
| `when` succeeds, output non-empty | the segment |
| `when` fails (`exit 1`, not just the string `false`) | nothing |

Consequences the implementation depends on:

1. **`when` cannot be a formality.** A passing `when` with empty output leaves a bare glyph sitting in the prompt in every directory without a server. That is why `when` and `command` both point at the same script and the exit status does the detecting.
2. **Custom commands run with cwd set to `--path`.** This is what makes "one module, two surfaces" true: `claude/.claude/statusline-command.sh` passes `--path "$cwd"`, so the script resolves Claude Code's workspace. `$PWD` is also reset to that path — verified even when a stale `PWD` is exported into the environment, as the status line does.
3. **`$HOME` expands** in `command`/`when` (they run through `sh -c`), and invocation **through a symlink works**, which is how Stow deploys the script.
4. **Braced `${custom.devserver}` is required** in `format`. Written `$custom.devserver`, starship expands `$custom` and emits `.devserver` as literal text, so the prompt reads `  :3001.devserver`.
5. **Cost:** starship runs `when` then `command`, so the script runs **twice per prompt** when a server is up (~5.4ms of `ss` each, plus a `git rev-parse`). Accepted deliberately over a cache file, which would trade ~15ms for on-disk state and a race between concurrent prompts. The doubling compounds in Claude Code, which re-invokes starship on every status-line refresh.

## File Structure

| File | Responsibility |
| --- | --- |
| `starship/.config/starship/devserver-port.sh` (create, mode 755) | the whole detection: workspace root → listening ports → one line of stdout + an exit status |
| `starship/.config/starship.toml` (modify) | `${custom.devserver}` in `format`, plus the `[custom.devserver]` block |
| `tests/test-devserver-port.sh` (create) | the script's contract via the `DEVSERVER_SS` / `DEVSERVER_PROC` seams, plus the toml wiring and a real-starship render check |
| `README.md` (modify) | one line in the symlink map |

The script is the only unit with logic; the toml is declaration and the README is documentation, which is why they split across two tasks — a reviewer can reject the module's placement or glyph while accepting the detection, and vice versa.

---

### Task 1: The detection script

**Files:**
- Create: `starship/.config/starship/devserver-port.sh` (mode 755)
- Test: `tests/test-devserver-port.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: an executable at `starship/.config/starship/devserver-port.sh`, deployed to `$HOME/.config/starship/devserver-port.sh`, honouring two environment seams — `DEVSERVER_SS` (default `ss`) and `DEVSERVER_PROC` (default `/proc`). Contract: print `:PORT[,PORT…]` as exactly one line and exit `0` when at least one listening socket's process was started in this workspace; print nothing and exit `1` otherwise. Task 2's toml points `command` and `when` at this path.

- [ ] **Step 1: Write the failing test**

Create `tests/test-devserver-port.sh`. The toml assertions arrive in Task 2; this file covers the script's contract only.

```sh
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/test-devserver-port.sh`
Expected: `FAIL: the detection script exists`, then `FAILED` — the run stops at `finish` because every later assertion would be meaningless without the script.

- [ ] **Step 3: Write the script**

Create `starship/.config/starship/devserver-port.sh`:

```sh
#!/bin/sh
# Print the ports of dev servers listening from inside THIS workspace as a
# single line ":PORT[,PORT…]" and exit 0; print nothing and exit 1 when none
# match.
#
# starship's custom module reads both halves of that contract: the exit status
# decides whether the segment renders at all, stdout fills it. A `when` that
# always succeeded would leave a bare glyph in the prompt in every directory
# without a server, which is why the detecting lives in the exit status.
#
# The workspace -> port mapping is exact rather than probed: `ss` gives
# port -> owning PID, and /proc/PID/cwd gives the directory that PID was
# started in. A listener belongs here when its cwd is the workspace root or
# sits under it. Any listening process counts; there is no name allowlist to
# keep in step with reality.
#
# Linux only. Without /proc (macOS) nothing matches, the script exits 1 and the
# segment never appears; the macOS route would be `lsof -a -p PID -d cwd`.
#
# Every failure degrades to "no match": a missing `ss`, a PID that exits
# mid-scan, a process owned by another user. stderr is discarded throughout —
# nothing may leak into a prompt.
#
# DEVSERVER_SS and DEVSERVER_PROC are seams so the contract can be tested
# without a live server.

SS=${DEVSERVER_SS:-ss}
PROC=${DEVSERVER_PROC:-/proc}

# starship runs a custom module's command with its working directory set to the
# directory being prompted for, so git resolves the workspace from there.
# `pwd` rather than $PWD: the value is read from the process, not from an
# inherited environment variable. Outside a repo, the directory is the scope.
root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root=$(pwd)

ports=$(
  "$SS" -ltnpH 2>/dev/null | while read -r _ _ _ laddr _ rest; do
    # The local address is host:port, where host may be *, 1.2.3.4,
    # 1.2.3.4%lo or [::1] — the port is always what follows the last colon.
    port=${laddr##*:}
    case $port in '' | *[!0-9]*) continue ;; esac

    # One socket can name several PIDs, and the process name is truncated
    # arbitrarily: real output includes (("next-server (v1",pid=123,fd=22)),
    # with an unbalanced paren and a stray quote. Pulling `pid=N` out by
    # pattern is immune to that; splitting on punctuation is not.
    printf '%s\n' "$rest" | grep -oE 'pid=[0-9]+' | cut -d= -f2 |
      while read -r pid; do
        cwd=$(readlink "$PROC/$pid/cwd" 2>/dev/null) || continue
        [ -n "$cwd" ] || continue
        # "$root"/* and not "$root"*: a sibling worktree whose name merely
        # starts with this one's (…/app vs …/app-next) must not be claimed.
        case $cwd in
          "$root" | "$root"/*) printf '%s\n' "$port" ;;
        esac
      done
  done | sort -un
)

[ -n "$ports" ] || exit 1

# One line, always: starship substitutes $output verbatim, so a newline here
# would land inside the prompt and break the two-line layout.
printf ':%s\n' "$(printf '%s' "$ports" | tr '\n' ',')"
```

- [ ] **Step 4: Make it executable**

Run: `chmod 755 starship/.config/starship/devserver-port.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `sh tests/test-devserver-port.sh`
Expected: every line `  ok: …`, ending in `PASS`.

If `a listener started in the workspace root reports its port` fails with an empty result, check `git -C "$ROOT" init -q` actually created a repo — without it `git rev-parse` walks up out of `$TMP` and the root never matches.

- [ ] **Step 6: Confirm the whole suite still passes**

Run: `sh tests/run.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add starship/.config/starship/devserver-port.sh tests/test-devserver-port.sh
git commit -m "feat(starship): detect the dev-server port for this workspace

Several worktrees of the same project run a dev server at once, so ports
land wherever they land and the shell gives no way to tell which one
belongs to the directory you are standing in. ss gives port -> PID and
/proc/PID/cwd gives where that PID started, which makes the mapping exact
with no port probing or log scraping.

The contract is one line of stdout plus an exit status, so the script is
exercisable without starship and starship's custom module can gate on it."
```

Verify the mode was recorded: `git ls-tree HEAD starship/.config/starship/devserver-port.sh` should show mode `100755`. If it shows `100644`, run `git update-index --chmod=+x starship/.config/starship/devserver-port.sh` and amend.

---

### Task 2: The starship module

**Files:**
- Modify: `starship/.config/starship.toml:10-20` (the `format` block) and append a `[custom.devserver]` block
- Modify: `README.md:35-48` (the symlink map)
- Test: `tests/test-devserver-port.sh` (append)

**Interfaces:**
- Consumes: `$HOME/.config/starship/devserver-port.sh` from Task 1 — one line of stdout, exit 0 on a match.
- Produces: a `custom.devserver` module rendering `  :3001` in `bold green`. Nothing else depends on it.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-devserver-port.sh`, **above** the final `finish` line:

```sh
# ── starship.toml wiring ─────────────────────────────────────
TOML="$REPO/starship/.config/starship.toml"

# U+F233, the nerd-font server glyph, as its UTF-8 bytes. Compared by bytes so
# an editor that mangles the character on the way in is caught here rather than
# showing up as a missing glyph in the prompt.
GLYPH="$(printf '\357\210\263')"

grep -qF '${custom.devserver}' "$TOML" \
  && pass "format references the module in braced form" \
  || fail "format references the module in braced form"

# Written $custom.devserver, starship expands $custom and emits ".devserver" as
# literal text, so the prompt reads "  :3001.devserver".
if grep -qE '\$custom\.devserver' "$TOML"; then
  fail "format does not use the unbraced \$custom.devserver form"
else
  pass "format does not use the unbraced \$custom.devserver form"
fi

grep -qF "$GLYPH" "$TOML" \
  && pass "the module carries the U+F233 server glyph" \
  || fail "the module carries the U+F233 server glyph"

# Distinct from the neighbouring nodejs symbol, or the two segments read as one.
# Read both out of the file rather than hardcoding: nodejs currently carries a
# bare space, and this stays correct if a glyph is added there later.
sym_of() { # sym_of SECTION_HEADER -> the section's symbol value
  sed -n "/^\\[$1\\]/,/^\\[/p" "$TOML" |
    sed -n 's/^symbol *= *"\(.*\)"/\1/p' | head -1
}
dev_sym="$(sym_of 'custom\.devserver')"
node_sym="$(sym_of 'nodejs')"
if [ -n "$dev_sym" ] && [ "$dev_sym" != "$node_sym" ]; then
  pass "the devserver symbol is non-empty and distinct from nodejs's"
else
  fail "the devserver symbol is non-empty and distinct from nodejs's (devserver='$dev_sym' nodejs='$node_sym')"
fi

grep -qF '[custom.devserver]' "$TOML" \
  && pass "the module block exists" \
  || fail "the module block exists"

# Both keys must point at the script: the exit status gates the segment, the
# stdout fills it. A `when` of "true" would leave a bare glyph everywhere.
cnt="$(grep -cF 'devserver-port.sh' "$TOML")"
assert_eq "$cnt" "2" "command and when both point at the script"

grep -qE '^when *= *.*devserver-port\.sh' "$TOML" \
  && pass "when runs the script rather than a placeholder" \
  || fail "when runs the script rather than a placeholder"

# Workspace facts grouped together: after git_status, before the language
# modules.
gs="$(grep -n '\$git_status' "$TOML" | head -1 | cut -d: -f1)"
dv="$(grep -nF '${custom.devserver}' "$TOML" | head -1 | cut -d: -f1)"
nj="$(grep -n '\$nodejs' "$TOML" | head -1 | cut -d: -f1)"
if [ -n "$gs" ] && [ -n "$dv" ] && [ -n "$nj" ] \
  && [ "$gs" -lt "$dv" ] && [ "$dv" -lt "$nj" ]; then
  pass "the segment sits after git_status and before the language modules"
else
  fail "the segment sits after git_status and before the language modules (git_status@${gs:-?} devserver@${dv:-?} nodejs@${nj:-?})"
fi

grep -qF 'starship/.config/starship/devserver-port.sh' "$REPO/README.md" \
  && pass "README's symlink map lists the script" \
  || fail "README's symlink map lists the script"

# ── real starship render ─────────────────────────────────────
# Behavioural, not textual: prove the segment stays absent where no server is
# running. Guarded on the STOWED script, because the toml points at
# $HOME/.config/starship/devserver-port.sh — without it the command fails, the
# segment is absent for the wrong reason and the check would pass vacuously.
# STARSHIP_SHELL must be unset or starship wraps colours in literal \[ \].
if command -v starship >/dev/null 2>&1 \
  && [ -x "$HOME/.config/starship/devserver-port.sh" ]; then
  render="$(env -u STARSHIP_SHELL STARSHIP_CONFIG="$TOML" \
    starship prompt --path "$TMP/plain" --logical-path "$TMP/plain" \
    --status 0 2>/dev/null)"
  assert_not_contains "$render" "$GLYPH" \
    "no segment renders in a directory with no dev server"
else
  echo "  skip: starship or the stowed script is missing — render check not run"
fi
```

- [ ] **Step 2: Run the test to verify the new assertions fail**

Run: `sh tests/test-devserver-port.sh`
Expected: the Task 1 assertions still `ok`, then failures beginning `FAIL: format references the module in braced form`, ending `FAILED`.

- [ ] **Step 3: Add the module to `format`**

In `starship/.config/starship.toml`, insert one line into the `format` block between `$git_status\` and `$nodejs\`:

```toml
format = """
$directory\
$git_branch\
$git_status\
${custom.devserver}\
$nodejs\
$python\
$rust\
$golang\
$cmd_duration\
$line_break\
$character"""
```

- [ ] **Step 4: Append the module block**

Do **not** hand-type this block — the `symbol` value is U+F233, a private-use codepoint that editors and clipboards drop silently. Run the append instead, so `printf` puts the bytes there:

```bash
{
  printf '%s\n' ''
  printf '%s\n' '# Dev-server port for THIS workspace — nothing at all when idle, so the'
  printf '%s\n' "# segment's presence is the signal. Several worktrees of one project each run"
  printf '%s\n' '# a dev server, and this reports only the one whose process was started here.'
  printf '%s\n' '#'
  printf '%s\n' '# Both keys run the same script on purpose: its exit status decides whether the'
  printf '%s\n' '# segment renders, its stdout fills it. starship renders a passing `when` with'
  printf '%s\n' '# empty output as the glyph wrapped around nothing, so a `when` of "true" would'
  printf '%s\n' '# park a bare glyph in every serverless directory. The cost is that starship'
  printf '%s\n' '# runs the script twice per prompt when a server is up.'
  printf '%s\n' '#'
  printf '%s\n' '# symbol is U+F233, the nerd-font server glyph. Written with printf because a'
  printf '%s\n' '# private-use character does not survive an ordinary edit.'
  printf '%s\n' '[custom.devserver]'
  printf '%s\n' 'command = "$HOME/.config/starship/devserver-port.sh"'
  printf '%s\n' 'when = "$HOME/.config/starship/devserver-port.sh"'
  printf 'symbol = "\357\210\263 "\n'
  printf '%s\n' 'format = "[ $symbol$output]($style)"'
  printf '%s\n' 'style = "bold green"'
} >> starship/.config/starship.toml
```

Single-quoted `printf` arguments throughout, so `$HOME`, `$symbol`, `$output` and `$style` reach the file unexpanded — starship expands them, not the shell.

- [ ] **Step 5: Verify the glyph actually landed**

Byte-level, because a terminal will happily render a missing glyph as a blank and a present one as a box:

```bash
python3 -c "
src = open('starship/.config/starship.toml', encoding='utf-8').read()
print('U+F233 present:', chr(0xF233) in src)
"
```

`chr(0xF233)` and not the character itself, for the same reason the append uses `printf`: a literal glyph pasted into this command is liable to be stripped on the way to the shell, leaving `'' in src` — `True` for every file, passing vacuously. Pure-ASCII escapes are the only form that survives being copied around.

Expected: `U+F233 present: True`. If it is `False`, delete the partial block and re-run Step 4.

- [ ] **Step 6: Add the script to the README symlink map**

In `README.md`, in the fenced block at lines 35-48, after the `starship.toml` line:

```
starship/.config/starship.toml -> ~/.config/starship.toml
starship/.config/starship/devserver-port.sh -> ~/.config/starship/devserver-port.sh
```

- [ ] **Step 7: Deploy, then run the test to verify it passes**

The render check is guarded on the stowed script, so stow first or it silently skips:

```bash
stow --no-folding --target="$HOME" --restow starship
sh tests/test-devserver-port.sh
```

Expected: all `ok`, ending `PASS`. The output must **not** contain `skip: starship or the stowed script is missing` — that line means the behavioural check never ran.

- [ ] **Step 8: Confirm the whole suite still passes**

Run: `sh tests/run.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 9: Commit**

```bash
git add starship/.config/starship.toml README.md tests/test-devserver-port.sh
git commit -m "feat(starship): show the workspace's dev-server port in the prompt

Renders as \`  :3001\` after git_status, and nothing at all when no server
is listening — the segment's presence is the signal.

command and when both run devserver-port.sh because starship renders a
passing when with empty output as a bare glyph, so the exit status has to
do the detecting. The braced \${custom.devserver} form is required;
\$custom.devserver emits '.devserver' as literal text."
```

---

### Task 3: Live verification

No files change. This is the gate before calling the feature done, and it is the only step that exercises the real `ss`, the real `/proc` and real dev servers.

**Files:** none.

**Interfaces:**
- Consumes: the stowed script and toml from Tasks 1 and 2.
- Produces: nothing. A failure here sends you back to Task 1 or 2.

- [ ] **Step 1: Re-derive the current picture**

Do not trust a remembered port — ports move. Get the real mapping, which is also exactly the mechanism the script implements, so it doubles as a sanity check:

```bash
ss -ltnpH | while read -r _ _ _ laddr _ rest; do
  pid=$(printf '%s\n' "$rest" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
  [ -n "$pid" ] && printf '%s -> %s\n' "${laddr##*:}" "$(readlink /proc/$pid/cwd)"
done
```

Write down which directories have a server and which do not. Every worktree under `~/.herdr/worktreesignore/` may be pruned by a cleanup script mid-session, so re-run this if a path vanishes.

- [ ] **Step 2: Confirm the script agrees, per directory**

For each directory from Step 1 — one with a server, one without:

```bash
( cd <dir> && ~/.config/starship/devserver-port.sh; echo "rc=$?" )
```

Expected: a directory running a server prints `:PORT` for **its own** port only and `rc=0`; a directory without one prints nothing and `rc=1`. A worktree must never report a sibling's port.

- [ ] **Step 3: Confirm the segment renders in a real prompt**

```bash
cd <a worktree with a server> && env -u STARSHIP_SHELL starship prompt --status 0
cd <a worktree without one>   && env -u STARSHIP_SHELL starship prompt --status 0
```

Expected: the first shows `  :PORT` in green after the git status; the second shows no glyph and no stray whitespace where the segment would be.

- [ ] **Step 4: Confirm Claude Code's status line agrees**

This is the second surface, and the one that would silently report the wrong workspace if the cwd handling were wrong:

```bash
printf '{"cwd":"%s"}' "<a worktree with a server>" | bash claude/.claude/statusline-command.sh; echo
printf '{"cwd":"%s"}' "<a worktree without one>"   | bash claude/.claude/statusline-command.sh; echo
```

Expected: the first contains that worktree's port, the second contains no glyph. If the first shows the *wrong* port, the script is resolving the status-line process's directory rather than `--path`.

- [ ] **Step 5: Confirm no drift**

Run: `./doctor.sh`
Expected: the `starship` package reports no missing symlinks and no untracked drift. The new file is inside an existing package, so nothing should need adopting.

- [ ] **Step 6: Report the results**

State per directory what was observed in Steps 2-4, with the ports. If anything failed, say which step and the actual output — do not summarise a partial pass as working.

---

## Self-Review

**Spec coverage.** Goal → Tasks 1-3. `custom` module not a Claude-only branch → Task 2 Step 4, verified in Task 3 Step 4. Nothing when idle → the `exit 1` path, asserted in Task 1 (`no listeners exits 1`) and Task 2 (render check). This workspace only → the prefix-collision and sibling cases. Any listening process → no name filter in the script; noted in Global Constraints. Linux-only, silent elsewhere → the `no /proc` case. Format/glyph/style → Task 2 Steps 1 and 4. Architecture's four-line pipeline → the script, line for line. Single-line contract → the `wc -l` assertion. Exit-status crux → both keys pointing at the script, plus the `when`-is-not-a-placeholder assertion. Wiring: none → asserted by omission; Global Constraints records that `starship` is already in both lists, verified at `install.sh:54` and `doctor.sh:200`. Every one of the spec's test-matrix bullets maps to a named assertion, plus four the spec did not list: numeric-vs-lexical ordering, a socket naming several PIDs, the non-repo fallback, and stderr staying empty.

**Placeholders.** None. Every code step carries the literal content; the only bracketed text is `<dir>` in Task 3, which is a runtime value the operator reads out of Step 1 and cannot be known in advance.

**Consistency.** The path `starship/.config/starship/devserver-port.sh`, the seam names `DEVSERVER_SS` / `DEVSERVER_PROC`, the module name `custom.devserver` and the glyph U+F233 are identical in the script, the toml, the test, the README line and all three tasks. The test's `$TMP/plain` directory is created in Task 1's `mkdir -p` and reused by Task 2's render check, which is why the two tasks share one test file rather than two.
