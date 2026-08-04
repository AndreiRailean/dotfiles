#!/bin/sh
# lazygit package: the binary is installed by install.sh (package manager first,
# upstream release tarball as fallback), the config pins the intended settings,
# lazygit's own state stays out of the repo, and the package is wired into
# install.sh / doctor.sh.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"

# ── install.sh: the install block ────────────────────────────
INST="$REPO/install.sh"

grep -q 'command -v lazygit' "$INST" \
  && pass "install.sh guards on lazygit already being present" \
  || fail "install.sh guards on lazygit already being present"

grep -q 'pkg_install lazygit' "$INST" \
  && pass "install.sh tries the system package" \
  || fail "install.sh tries the system package"

grep -q 'install_lazygit_release' "$INST" \
  && pass "install.sh has a release fallback" \
  || fail "install.sh has a release fallback"

# Upstream publishes lazygit_<version>_<Os>_<Arch>.tar.gz; the asset carries the
# version WITHOUT the tag's leading v. Getting this string wrong makes the
# fallback dead weight on the one platform that needs it (Ubuntu LTS, where
# lazygit is absent from the archive entirely).
grep -q 'jesseduffield/lazygit/releases/download' "$INST" \
  && pass "release fallback points at the upstream download URL" \
  || fail "release fallback points at the upstream download URL"

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
# tab that dies on launch.
lg_line="$(grep -n 'command -v lazygit' "$INST" | head -1 | cut -d: -f1)"
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

# ── The lazygit Stow package ─────────────────────────────────
CONF="$REPO/lazygit/.config/lazygit/config.yml"

[ -f "$CONF" ] && pass "config.yml exists" || fail "config.yml exists"

# Valid YAML (skip where PyYAML isn't available)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$CONF" 2>/dev/null; then
    pass "config.yml is valid YAML"
  else
    fail "config.yml is valid YAML"
  fi
else
  echo "  skip: python3 PyYAML unavailable (YAML validation)"
fi

# Pinned settings
grep -q 'colorArg: always'      "$CONF" && pass "colorArg always"       || fail "colorArg always"
grep -q 'editPreset: nvim'      "$CONF" && pass "editPreset nvim"       || fail "editPreset nvim"
grep -q 'nerdFontsVersion: "3"' "$CONF" && pass "nerdFontsVersion 3"    || fail "nerdFontsVersion 3"

# ── The pager expression ─────────────────────────────────────
# Single-quoted YAML scalar, so plain sed extraction works and the behavioural
# check below needs no YAML parser.
PAGER_EXPR="$(sed -n "s/^[[:space:]]*pager:[[:space:]]*'\(.*\)'[[:space:]]*\$/\1/p" "$CONF" | head -1)"
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
