#!/bin/sh
# install.sh must not abort when a tool already wrote its own config file.
#
# THE BUG THIS PINS DOWN: `stow` refuses to link over a target that is a real
# file rather than a symlink or directory ("cannot stow ... since neither a link
# nor a directory and --adopt not specified", exit 1). install.sh runs under
# `set -euo pipefail`, so that refusal doesn't just skip one package — it kills
# the whole install at the stow loop, and EVERY later step is silently skipped:
# the remaining packages, the lazygit binary install, the Nerd Font, the
# auto-layout unit. The observed symptom was "install.sh doesn't install the
# right lazygit version": in fact it never reached that block at all.
#
# The trigger is ordinary. Tools write a config on first run, so any machine
# that used a tool BEFORE this repo started managing it has a real file sitting
# on the stow target. lazygit is the case that surfaced it — it creates an empty
# ~/.config/lazygit/config.yml on first launch — but nothing about it is
# lazygit-specific, so this is tested against the stow loop as a whole.
#
# The fix is to move such a file aside before stowing, the same way install.sh
# already does for the pre-existing ~/.claude files. NOT `stow --adopt`: adopt
# pulls the machine's file INTO the repo, so a fresh machine's empty config
# would overwrite the tracked one and the loss would be committed as a real
# change. That trap is asserted against below.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

# ── Static: the loop clears conflicts, and never via --adopt ──
# Guards the resolver against being dropped or reordered after `stow`, which
# would restore the abort without changing any test that only checks behaviour.
loop="$(sed -n '/^for pkg in /,/^done$/p' "$INST")"
assert_contains "$loop" "clear_stow_conflicts" \
  "stow loop clears conflicting targets before stowing"

# Order matters: clearing after stow would run only once stow had already failed.
before="$(printf '%s\n' "$loop" | grep -n 'clear_stow_conflicts' | head -1 | cut -d: -f1)"
after="$(printf '%s\n' "$loop" | grep -n '[^_]stow -' | head -1 | cut -d: -f1)"
if [ -n "$before" ] && [ -n "$after" ] && [ "$before" -lt "$after" ]; then
  pass "conflicts are cleared before the stow call, not after"
else
  fail "conflicts are cleared before the stow call, not after (clear=$before stow=$after)"
fi

# --adopt would silently overwrite tracked config with the machine's version.
# Scoped to the invocations, not the whole file: the prose explaining why adopt
# is wrong necessarily names the flag.
stow_calls="$(grep -n '^[[:space:]]*stow ' "$INST" || true)"
if [ -n "$stow_calls" ]; then
  pass "found install.sh's stow invocation(s)"
else
  fail "found install.sh's stow invocation(s) (none matched)"
fi
assert_not_contains "$stow_calls" "--adopt" \
  "no stow invocation passes --adopt"

# ── Behavioural: prove the conflict aborts, and the fix clears it ──
# bash, not sh: install.sh has a bash shebang and the resolver uses bash
# process substitution, so running it under dash would fail for a reason that
# has nothing to do with the bug.
if ! command -v stow >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
  echo "  skip: stow and bash are both needed for the behavioural checks"
  finish
fi

# Extract the resolver from install.sh so the test exercises the real code
# rather than a paraphrase of it.
FN="$(awk '/^clear_stow_conflicts\(\)/,/^}/' "$INST")"
if [ -z "$FN" ]; then
  fail "install.sh defines clear_stow_conflicts() at column 0 (extractable)"
  finish
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

# A miniature dotfiles package: pkg/.config/demo/demo.yml -> $HOME/.config/demo/
mkdir -p "$T/repo/pkg/.config/demo" "$T/home/.config/demo"
printf 'tracked-config\n' >"$T/repo/pkg/.config/demo/demo.yml"
# The pre-existing real file, exactly as a tool leaves it on first run.
printf '' >"$T/home/.config/demo/demo.yml"

# 1. The trap is real: bare stow fails on this layout. Without this, a passing
#    test below would prove nothing — it could be passing because stow never
#    minded in the first place.
( cd "$T/repo" && stow --no-folding --target="$T/home" --restow pkg ) >/dev/null 2>&1
assert_eq "$?" "1" "bare stow fails on a pre-existing real file (the trap)"

# 2. And it is fatal under install.sh's shell options, not merely noisy.
( set -euo pipefail
  cd "$T/repo" && stow --no-folding --target="$T/home" --restow pkg
  echo REACHED ) >"$T/after" 2>&1
assert_not_contains "$(cat "$T/after")" "REACHED" \
  "under set -e the failure aborts the script (later steps are skipped)"

# 3. With the resolver, stow succeeds and the repo's copy wins.
out="$( cd "$T/repo" && HOME="$T/home" bash -c "$FN
        clear_stow_conflicts pkg
        stow --no-folding --target=\"$T/home\" --restow pkg" 2>&1 )"
rc=$?
assert_eq "$rc" "0" "stow succeeds after conflicts are cleared"
if [ -L "$T/home/.config/demo/demo.yml" ]; then
  pass "target is now a symlink into the repo"
else
  fail "target is now a symlink into the repo (output: $out)"
fi
assert_eq "$(cat "$T/home/.config/demo/demo.yml" 2>/dev/null)" "tracked-config" \
  "the tracked config is what the target resolves to"

# 4. The displaced file is recoverable, not deleted.
backups="$(find "$T/home/.config/demo" -name 'demo.yml.pre-dotfiles.*' | wc -l | tr -d ' ')"
assert_eq "$backups" "1" "the machine's file is kept as a .pre-dotfiles.* backup"

# 5. The repo's copy is untouched — this is what --adopt would have destroyed.
assert_eq "$(cat "$T/repo/pkg/.config/demo/demo.yml")" "tracked-config" \
  "the tracked file in the repo is not overwritten by the machine's version"

# 6. Idempotent: re-running must not move correct symlinks aside. Otherwise
#    every install would shed another backup file and churn the links.
( cd "$T/repo" && HOME="$T/home" bash -c "$FN
  clear_stow_conflicts pkg" ) >/dev/null 2>&1
again="$(find "$T/home/.config/demo" -name 'demo.yml.pre-dotfiles.*' | wc -l | tr -d ' ')"
assert_eq "$again" "1" "a second run leaves the existing symlink alone (no new backup)"
if [ -L "$T/home/.config/demo/demo.yml" ]; then
  pass "the symlink survives a second run"
else
  fail "the symlink survives a second run"
fi

# ── doctor.sh must not offer to adopt those backups ───────────
# The backup lands beside the symlink, i.e. inside a managed .config/<name>
# root that doctor.sh scans for untracked real files. Left unfiltered it is
# reported as drift and `./doctor.sh --adopt` moves it INTO the repo and stows
# it back — committing the stale empty file forever, which is the same loss
# --adopt-ing the stow conflict would have caused.
DOC="$REPO/doctor.sh"
mkdir -p "$T/dhome/.config/lazygit"
ln -s "$REPO/lazygit/.config/lazygit/config.yml" "$T/dhome/.config/lazygit/config.yml"
printf '' >"$T/dhome/.config/lazygit/config.yml.pre-dotfiles.1234567890"
# A genuinely untracked file, so a pass can't come from the scan being broken
# or from this root being skipped altogether. Deliberately NOT state.yml —
# .gitignore lists that one, so doctor.sh is meant to stay quiet about it.
printf 'probe\n' >"$T/dhome/.config/lazygit/probe-untracked.yml"
doc_out="$(HOME="$T/dhome" bash "$DOC" 2>&1 || true)"
assert_contains "$doc_out" "probe-untracked.yml" \
  "doctor.sh does scan the managed root (control: a real untracked file is found)"
assert_not_contains "$doc_out" "pre-dotfiles" \
  "doctor.sh does not report the .pre-dotfiles.* backup as adoptable drift"

finish
