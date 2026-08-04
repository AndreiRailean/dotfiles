#!/bin/sh
# install.sh's 1Password CLI block must survive being re-run.
#
# `gpg --dearmor --output FILE` PROMPTS ("File 'FILE' exists. Overwrite?") when
# FILE already exists. install.sh is designed to be re-run on the same machine,
# and the block's guard is `command -v op` — so on any machine where a previous
# run created the keyring but didn't finish installing op, every later run stops
# dead at that prompt with no timeout and no way forward.
#
# The stall lands BEFORE `apt install 1password-cli` in the same && chain, so op
# never gets installed, the guard never starts passing, and the machine is stuck
# in that state permanently. That makes this a idempotency bug, not a cosmetic
# prompt: the fix is --batch --yes on every dearmor call.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

# ── Static: every dearmor call is non-interactive ─────────────
DEAR="$(mktemp)"
trap 'rm -f "$DEAR"' EXIT INT TERM
grep -n 'gpg .*--dearmor' "$INST" >"$DEAR" || true

n_total="$(wc -l <"$DEAR" | tr -d ' ')"
if [ "$n_total" -ge 2 ]; then
  pass "found install.sh's gpg --dearmor calls ($n_total)"
else
  fail "found install.sh's gpg --dearmor calls (got $n_total, expected >= 2)"
fi

# Both flags are needed, and for different reasons: --yes answers the overwrite
# question, --batch stops gpg asking anything at all if a future edit introduces
# another prompt. Checked per-line so adding a third call can't skip the check.
bad_batch="$(grep -v -- '--batch' "$DEAR" || true)"
bad_yes="$(grep -v -- '--yes' "$DEAR" || true)"
[ -z "$bad_batch" ] && pass "every gpg --dearmor passes --batch" \
  || fail "gpg --dearmor missing --batch on install.sh line(s): $bad_batch"
[ -z "$bad_yes" ] && pass "every gpg --dearmor passes --yes" \
  || fail "gpg --dearmor missing --yes on install.sh line(s): $bad_yes"

# ── Behavioural: prove the flags are what makes it safe ───────
# Uses a locally generated armored blob, so no network and no dependency on
# 1Password's key. `gpg --enarmor` is the inverse of --dearmor, so round-tripping
# a known payload proves the overwrite really wrote the new content.
if command -v gpg >/dev/null 2>&1 \
   && command -v script >/dev/null 2>&1 \
   && command -v timeout >/dev/null 2>&1; then
  T="$(mktemp -d)"
  trap 'rm -f "$DEAR"; rm -rf "$T"' EXIT INT TERM
  printf 'dearmor-probe' | gpg --enarmor >"$T/in.asc" 2>/dev/null

  # Unflagged, onto an existing file: must NOT complete. A pty is required for
  # gpg to prompt rather than fail, which is why this goes through `script` —
  # install.sh runs on a terminal, so that's the faithful reproduction.
  printf 'old' >"$T/bare.bin"
  timeout 3 script -q -c "gpg --dearmor --output $T/bare.bin < $T/in.asc" /dev/null >/dev/null 2>&1
  rc_bare=$?
  # 124 = timeout killed it; 143 = SIGTERM reached it through `script`. Either
  # means it sat waiting for input. Any other code would mean gpg failed fast
  # for some unrelated reason, which would make this test prove nothing.
  case "$rc_bare" in
    124|143) pass "bare gpg --dearmor hangs on an existing file (rc=$rc_bare)" ;;
    *)       fail "bare gpg --dearmor didn't hang (rc=$rc_bare) — this gpg may not prompt, so the static checks above are the only guard" ;;
  esac

  # With the flags: completes, and actually replaces the content.
  printf 'old' >"$T/flagged.bin"
  timeout 3 script -q -c "gpg --batch --yes --dearmor --output $T/flagged.bin < $T/in.asc" /dev/null >/dev/null 2>&1
  assert_eq "$?" "0" "gpg --batch --yes --dearmor overwrites an existing file"
  grep -q 'dearmor-probe' "$T/flagged.bin" \
    && pass "the overwrite wrote the new content" \
    || fail "the overwrite wrote the new content"
else
  echo "  skip: behavioural gpg check needs gpg, script and timeout"
fi

# ── The block still has to be wired the way it was ────────────
grep -q 'command -v op' "$INST" \
  && pass "install.sh still guards on op already being present" \
  || fail "install.sh still guards on op already being present"
grep -q '1password-cli' "$INST" \
  && pass "install.sh still installs the 1password-cli package" \
  || fail "install.sh still installs the 1password-cli package"

bash -n "$INST" && pass "install.sh parses" || fail "install.sh parses"

finish
