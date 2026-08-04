#!/bin/sh
# lazygit package: the binary is installed by install.sh from the upstream
# release ONLY, gated on a >= 0.64.0 version floor (Amendment 1 — never the
# distro package), the config pins the intended settings, lazygit's own
# state stays out of the repo, and the package is wired into
# install.sh / doctor.sh.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"

# ── install.sh: the install block ────────────────────────────
INST="$REPO/install.sh"

grep -q 'lazygit_meets_floor' "$INST" \
  && pass "install.sh gates on lazygit meeting the version floor" \
  || fail "install.sh gates on lazygit meeting the version floor"

# lazygit 0.64 replaced git.paging with git.diffRenderers, and Debian trixie's
# apt package (0.50) ignores diffRenderers silently — no delta, no warning —
# so a distro package can no longer be relied on to clear the floor.
if grep -q 'pkg_install lazygit' "$INST"; then
  fail "install.sh no longer falls back through the system package manager"
else
  pass "install.sh no longer falls back through the system package manager"
fi

grep -q 'install_lazygit_release' "$INST" \
  && pass "install.sh installs lazygit from the upstream release" \
  || fail "install.sh installs lazygit from the upstream release"

# Upstream publishes lazygit_<version>_<Os>_<Arch>.tar.gz; the asset carries
# the version WITHOUT the tag's leading v. Getting this string wrong makes
# the install dead on arrival — the release tarball is the only path lazygit
# is ever installed through now (Amendment 1: never the distro package).
grep -q 'jesseduffield/lazygit/releases/download' "$INST" \
  && pass "the release install points at the upstream download URL" \
  || fail "the release install points at the upstream download URL"

grep -q 'lazygit_${ver}_${os}_${arch}.tar.gz' "$INST" \
  && pass "release asset name matches upstream's naming" \
  || fail "release asset name matches upstream's naming"

# Best-effort: a failed install must warn, not abort the run.
grep -q '!! lazygit install failed' "$INST" \
  && pass "lazygit install failure warns instead of aborting" \
  || fail "lazygit install failure warns instead of aborting"

# ── Ordering: lazygit before the auto-layout daemon ──────────
# The daemon enabled at the end of install.sh runs lazygit in every new
# worktree's second tab; installing it afterwards leaves a fresh machine with a
# tab that dies on launch. Anchor on the gate itself (not the helper
# definitions above it) — that's the line whose position actually determines
# when the install happens.
lg_line="$(grep -n 'if ! lazygit_meets_floor' "$INST" | head -1 | cut -d: -f1)"
al_line="$(grep -n 'herdr-autolayout.service' "$INST" | head -1 | cut -d: -f1)"
if [ -n "$lg_line" ] && [ -n "$al_line" ] && [ "$lg_line" -lt "$al_line" ]; then
  pass "lazygit is installed before the auto-layout daemon is enabled"
else
  fail "lazygit is installed before the auto-layout daemon is enabled (lazygit@${lg_line:-?} autolayout@${al_line:-?})"
fi

bash -n "$INST" && pass "install.sh parses" || fail "install.sh parses"

# ── install_lazygit_release: failure contract ────────────────
# Contract: "returns 0 on success, 1 on any failure". Exercise the extracted
# function directly, with curl/tar stubbed on a narrowed PATH so no network
# call is ever made, and check the placement step (mkdir + install) actually
# gates the return value instead of reporting success no matter what.
FN="$(mktemp -d)/fn.sh"
sed -n '/^install_lazygit_release() {/,/^}/p' "$INST" > "$FN"

STUBDIR="$(mktemp -d)"
# Stub curl: answers both calls the function makes — the release-metadata GET
# and the tarball download (-o FILE) — without touching the network.
cat > "$STUBDIR/curl" <<'STUB'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    *releases/latest*) echo '{"tag_name":"v0.0.0-test"}'; exit 0 ;;
  esac
done
prev=""
out=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
[ -n "$out" ] && : > "$out"
exit 0
STUB
chmod +x "$STUBDIR/curl"

# Stub tar: fakes extraction by dropping a placeholder "lazygit" file into the
# -C target directory.
cat > "$STUBDIR/tar" <<'STUB'
#!/bin/sh
prev=""
outdir=""
for a in "$@"; do
  [ "$prev" = "-C" ] && outdir="$a"
  prev="$a"
done
[ -n "$outdir" ] || exit 1
printf '#!/bin/sh\necho stub\n' > "$outdir/lazygit"
chmod +x "$outdir/lazygit"
exit 0
STUB
chmod +x "$STUBDIR/tar"

# Happy path: stubbed curl/tar succeed, HOME is a real writable directory —
# expect 0 and the binary actually placed.
GOODHOME="$(mktemp -d)"
export STUBDIR FN GOODHOME
rc_good="$(bash -c 'PATH="$STUBDIR:$PATH"; HOME="$GOODHOME"; . "$FN"; install_lazygit_release; echo $?' 2>/dev/null)"
if [ "$rc_good" = "0" ] && [ -x "$GOODHOME/.local/bin/lazygit" ]; then
  pass "install_lazygit_release returns 0 and installs the binary on the happy path"
else
  fail "install_lazygit_release returns 0 and installs the binary on the happy path (got '${rc_good:-?}')"
fi

# Placement fails: point HOME at a path nested under a regular file, so
# mkdir -p genuinely cannot create it. This holds even when running as root,
# where permission-based "unwritable" directories aren't actually unwritable.
BLOCKER="$(mktemp)"
if [ -f "$BLOCKER" ]; then
  BADHOME="$BLOCKER/nested"
  export BADHOME
  rc_bad="$(bash -c 'PATH="$STUBDIR:$PATH"; HOME="$BADHOME"; . "$FN"; install_lazygit_release; echo $?' 2>/dev/null)"
  if [ -n "$rc_bad" ] && [ "$rc_bad" != "0" ]; then
    pass "install_lazygit_release returns non-zero when the binary can't be placed"
  else
    fail "install_lazygit_release returns non-zero when the binary can't be placed (got '${rc_bad:-?}')"
  fi
else
  echo "  skip: could not create a blocking path for the unplaceable-binary case"
fi

rm -rf "$(dirname "$FN")" "$STUBDIR" "$GOODHOME" "$BLOCKER"

# ── lazygit_meets_floor: the version gate ────────────────────
# 0.64 replaced git.paging with git.diffRenderers; below the floor a binary
# ignores the new keys silently instead of erroring, so mere presence on
# PATH isn't enough. Extract the helper and drive it with a stubbed
# `lazygit` on a minimal PATH — never the real system PATH, since this very
# machine's own apt package (0.50) would otherwise leak through and skew
# every case.
FN2="$(mktemp -d)/floor.sh"
sed -n '/^lazygit_meets_floor() {/,/^}/p' "$INST" > "$FN2"
SEDBIN="$(command -v sed)"

# $1: the line a stubbed `lazygit --version` should print, or empty for no
# lazygit binary on PATH at all. The line is written to a data file and read
# back with the `read` builtin (not `cat`) — the stub's own PATH is narrowed
# to just $d, and `read` needs no external command to reproduce apt's build,
# whose version is wrapped in single quotes, verbatim.
run_floor() {
  d="$(mktemp -d)"
  ln -s "$SEDBIN" "$d/sed"
  if [ -n "$1" ]; then
    printf '%s\n' "$1" > "$d/out.txt"
    cat > "$d/lazygit" <<STUB
#!/bin/sh
IFS= read -r line < "$d/out.txt"
echo "\$line"
STUB
    chmod +x "$d/lazygit"
  fi
  export FN2 d
  rc="$(bash -c 'PATH="$d"; . "$FN2"; lazygit_meets_floor; echo $?' 2>/dev/null)"
  rm -rf "$d"
  printf '%s' "$rc"
}

# Real line shapes, both verified live: apt's build (Debian trixie) quotes
# the version and appends its own package revision; the upstream release
# binary prints it bare. Both end in `git version=A.B.C`, which is why the
# helper anchors its extraction rather than grabbing the last `version=`.
VER_APT_050="commit=, build date=, build source='debian', version='0.50.0+ds1-1+b2', os=linux, arch=amd64, git version=2.47.3"
VER_REL_064="commit=aee0e40, build date=2026-08-04T07:26:19Z, build source=binaryRelease, version=0.64.0, os=linux, arch=amd64, git version=2.47.3"
VER_REL_100="commit=aee0e40, build date=2026-08-04T07:26:19Z, build source=binaryRelease, version=1.0.0, os=linux, arch=amd64, git version=2.47.3"

rc="$(run_floor "$VER_APT_050")"
[ "$rc" = "1" ] && pass "floor: apt's 0.50.0 does not meet the floor" \
  || fail "floor: apt's 0.50.0 does not meet the floor (got '${rc:-?}')"

rc="$(run_floor "$VER_REL_064")"
[ "$rc" = "0" ] && pass "floor: 0.64.0 meets the floor" \
  || fail "floor: 0.64.0 meets the floor (got '${rc:-?}')"

rc="$(run_floor "$VER_REL_100")"
[ "$rc" = "0" ] && pass "floor: 1.0.0 meets the floor (major beats minor)" \
  || fail "floor: 1.0.0 meets the floor (major beats minor) (got '${rc:-?}')"

rc="$(run_floor "")"
[ "$rc" = "1" ] && pass "floor: no lazygit on PATH does not meet the floor" \
  || fail "floor: no lazygit on PATH does not meet the floor (got '${rc:-?}')"

rc="$(run_floor "not a version line at all")"
[ "$rc" = "1" ] && pass "floor: unparseable --version output does not meet the floor" \
  || fail "floor: unparseable --version output does not meet the floor (got '${rc:-?}')"

# ── doctor.sh: lazygit version health ────────────────────────
# install.sh only clears the floor at install time; nothing else re-checks
# it afterwards. If the floor is unmet and install_lazygit_release also
# fails (no network, a GitHub API rate limit, an unsupported arch, ...), a
# machine is left reading the managed diffRenderers config with a binary
# that ignores it silently — the exact failure mode this branch exists to
# prevent. Extract doctor.sh's block and drive it the same way as the floor
# tests above: a stubbed `lazygit` on a minimal PATH, never the real system
# PATH.
FN3="$(mktemp -d)/health.sh"
sed -n '/^# ── lazygit version health/,/^fi$/p' "$REPO/doctor.sh" > "$FN3"

# $1: the line a stubbed `lazygit --version` should print, or empty for no
# lazygit binary on PATH at all.
run_health() {
  d="$(mktemp -d)"
  ln -s "$SEDBIN" "$d/sed"
  if [ -n "$1" ]; then
    printf '%s\n' "$1" > "$d/out.txt"
    cat > "$d/lazygit" <<STUB
#!/bin/sh
IFS= read -r line < "$d/out.txt"
echo "\$line"
STUB
    chmod +x "$d/lazygit"
  fi
  export FN3 d
  out="$(bash -c 'PATH="$d"; ADOPT=0; . "$FN3"' 2>/dev/null)"
  rm -rf "$d"
  printf '%s' "$out"
}

out="$(run_health "$VER_APT_050")"
assert_contains "$out" "below the 0.64 floor" "doctor.sh warns when lazygit is below the floor"

out="$(run_health "$VER_REL_064")"
assert_not_contains "$out" "below the 0.64 floor" "doctor.sh stays quiet when lazygit meets the floor"

out="$(run_health "")"
assert_not_contains "$out" "below the 0.64 floor" "doctor.sh stays quiet when lazygit is missing (that's louder, elsewhere)"

rm -rf "$(dirname "$FN3")"

# ── Recommendation: pin the schema coupling with a real launch ──
# The whole floor exists because a future lazygit could migrate the schema
# again and rewrite the tracked config in place, exactly as 0.64 does to a
# git.paging config (Amendment 1, verified live). Launch a REAL lazygit on
# this machine's real PATH against a COPY of the tracked config in scratch
# HOME/XDG dirs — never ~/.config/lazygit itself, that symlinks into this
# repo — and assert the copy is byte-identical afterwards. Skips cleanly
# without a real lazygit >= 0.64 or a pty (`script`); touches no network.
if command -v script >/dev/null 2>&1 \
   && bash -c ". \"$FN2\"; lazygit_meets_floor" 2>/dev/null; then
  LAUNCH="$(mktemp -d)"
  mkdir -p "$LAUNCH/home" "$LAUNCH/xdgconf/lazygit" "$LAUNCH/xdgstate"
  cp "$REPO/lazygit/.config/lazygit/config.yml" "$LAUNCH/xdgconf/lazygit/config.yml"
  SUM_BEFORE="$(sha256sum "$LAUNCH/xdgconf/lazygit/config.yml" | awk '{print $1}')"
  ( cd "$REPO" && timeout 8 script -q -c \
      "env HOME=$LAUNCH/home XDG_CONFIG_HOME=$LAUNCH/xdgconf XDG_STATE_HOME=$LAUNCH/xdgstate lazygit" \
      /dev/null ) >/dev/null 2>&1 || true
  SUM_AFTER="$(sha256sum "$LAUNCH/xdgconf/lazygit/config.yml" | awk '{print $1}')"
  assert_eq "$SUM_AFTER" "$SUM_BEFORE" "a real lazygit launch doesn't rewrite the tracked config"
  rm -rf "$LAUNCH"
else
  echo "  skip: no lazygit >= 0.64 and/or no pty ('script') available for the real-launch config check"
fi

rm -rf "$(dirname "$FN2")"

# ── The lazygit Stow package ─────────────────────────────────
CONF="$REPO/lazygit/.config/lazygit/config.yml"

[ -f "$CONF" ] && pass "config.yml exists" || fail "config.yml exists"

# Valid YAML, and (where PyYAML is available) shaped the way lazygit's
# DiffRendererConfig schema expects: git.diffRenderers is a list, and its
# first element carries the name/colorArg/command triple this file relies on.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  if python3 - "$CONF" <<'PY' 2>/dev/null
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
renderers = data["git"]["diffRenderers"]
assert isinstance(renderers, list) and len(renderers) >= 1
first = renderers[0]
assert first.get("name") == "delta"
assert first.get("colorArg") == "always"
assert isinstance(first.get("command"), str) and first["command"]
PY
  then
    pass "config.yml is valid YAML shaped as a diffRenderers list"
  else
    fail "config.yml is valid YAML shaped as a diffRenderers list"
  fi
else
  echo "  skip: python3 PyYAML unavailable (YAML validation)"
fi

# Pinned settings
grep -q 'name: delta'           "$CONF" && pass "diff renderer named delta" || fail "diff renderer named delta"
grep -q 'colorArg: always'      "$CONF" && pass "colorArg always"       || fail "colorArg always"
grep -q 'editPreset: nvim'      "$CONF" && pass "editPreset nvim"       || fail "editPreset nvim"
grep -q 'nerdFontsVersion: "3"' "$CONF" && pass "nerdFontsVersion 3"    || fail "nerdFontsVersion 3"

# ── Schema regression guard (Amendment 1) ────────────────────
# lazygit >= 0.64 replaced git.paging with git.diffRenderers; below the floor
# a binary ignores diffRenderers silently, so the old paging/pager shape
# must never quietly creep back in via a migration or a copy-paste from an
# older example / from git/.config/git/config.
grep -q 'diffRenderers:' "$CONF" && pass "config uses the diffRenderers schema" || fail "config uses the diffRenderers schema"
grep -Eq '^[[:space:]]*paging:' "$CONF" && fail "config doesn't reintroduce the old paging block" || pass "config doesn't reintroduce the old paging block"
# Anchored to line-start (after whitespace) so prose like "git's core.pager:"
# in a comment doesn't false-positive on the substring "pager:".
grep -Eq '^[[:space:]]*pager:' "$CONF" && fail "config doesn't reintroduce the old pager key" || pass "config doesn't reintroduce the old pager key"

# ── The pager expression ─────────────────────────────────────
# Single-quoted YAML scalar (now the diffRenderers[0].command field), so
# plain sed extraction still works and the behavioural check below needs no
# YAML parser.
PAGER_EXPR="$(sed -n "s/^[[:space:]]*command:[[:space:]]*'\(.*\)'[[:space:]]*\$/\1/p" "$CONF" | head -1)"
[ -n "$PAGER_EXPR" ] && pass "pager expression extracted" || fail "pager expression extracted"

# delta's side-by-side layout is right for a full-width terminal and wrong for
# lazygit's half-width diff panel, which is why the repo's delta.side-by-side
# is dropped with --no-gitconfig. Lock the divergence in so a future
# copy-paste from git/config can't quietly undo it.
assert_contains "$PAGER_EXPR" "--no-gitconfig" "pager ignores the repo's delta gitconfig"
assert_not_contains "$PAGER_EXPR" "side-by-side" "pager doesn't force side-by-side"

# Behavioural: run the real expression with stubbed binaries, exactly as
# tests/test-git-delta.sh does for core.pager.
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT INT TERM
printf '#!/bin/sh\necho USED_DELTA\n' >"$BIN/delta"
printf '#!/bin/sh\necho USED_LESS\n'  >"$BIN/less"
chmod +x "$BIN/delta" "$BIN/less"

# PATH is narrowed inside the child, not as an assignment prefix — the latter
# would hide the `sh` binary we're trying to launch.
run_expr() { echo x | sh -c "PATH='$BIN'; $1" 2>/dev/null; }

assert_eq "$(run_expr "$PAGER_EXPR")" "USED_DELTA" "pager uses delta when installed"
rm -f "$BIN/delta"
assert_eq "$(run_expr "$PAGER_EXPR")" "USED_LESS"  "pager falls back to less without delta"

# ── Tool-written state stays out of the repo ─────────────────
# --no-folding makes ~/.config/lazygit a real dir, so lazygit's state.yml is a
# real file outside the repo; doctor.sh skips anything git check-ignore matches.
git -C "$REPO" check-ignore -q "lazygit/.config/lazygit/state.yml" \
  && pass "git-ignored: state.yml" || fail "git-ignored: state.yml"

# ── Package machinery ────────────────────────────────────────
grep -Eq 'for pkg in .*\blazygit\b' "$INST" \
  && pass "install.sh stows lazygit" || fail "install.sh stows lazygit"
grep -Eq 'PACKAGES=.*\blazygit\b' "$REPO/doctor.sh" \
  && pass "doctor.sh scans lazygit" || fail "doctor.sh scans lazygit"
bash -n "$REPO/doctor.sh" && pass "doctor.sh parses" || fail "doctor.sh parses"

finish
