#!/bin/sh
# update.sh installs and upgrades the tools no package manager looks after.
# What has to hold: the report changes nothing; --missing installs only absent
# DEFAULT tools and looks nothing up for the rest; --apply upgrades only what
# lives under $HOME; a download that fails its checksum is never installed;
# and offline, the report still succeeds so install.sh carries on.
#
# Hermetic: curl is a stub serving release data from $T/net, the tools are
# stubs, and PATH is built from symlinks to the few system utilities the
# script needs — so a real starship or an apt lazygit on the machine running
# the tests can't leak in.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
UPDATE="$REPO/update.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }
BASH_BIN="$(command -v bash)"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/util" "$T/sys" "$T/net" "$T/build"

# No `sort`: version comparison must not depend on `sort -V`, which macOS 12
# and earlier lack.
for c in bash sh env awk sed grep head tr wc mktemp rm mkdir cp mv chmod ln \
         tar gzip unzip sha256sum shasum readlink dirname basename cat uname printf; do
  # Only a path: command -v names a function or alias by its bare name.
  p="$(command -v "$c" 2>/dev/null)" || continue
  case "$p" in /*) ln -s "$p" "$T/util/$c" ;; esac
done

# The curl stub: logs every URL, fails everything when $T/net/offline exists,
# and otherwise answers from files in $T/net.
cat >"$T/util/curl" <<EOF
#!/bin/sh
out=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    http*) url="\$1" ;;
  esac
  shift
done
echo "\$url" >>"$T/curl.log"
[ -e "$T/net/offline" ] && exit 7
emit() { if [ -n "\$out" ]; then cat >"\$out"; else cat; fi; }
case "\$url" in
  https://api.github.com/repos/starship/starship/*) f=starship ;;
  https://api.github.com/repos/jesseduffield/lazygit/*) f=lazygit ;;
  https://api.github.com/repos/denoland/deno/*) f=deno ;;
  https://api.github.com/repos/Schniz/fnm/*) f=fnm ;;
  https://herdr.dev/latest.json) [ -f "$T/net/herdr" ] || exit 22
    printf '{\n  "version": "%s",\n  "protocol": 22\n}\n' "\$(cat "$T/net/herdr")" | emit; exit 0 ;;
  https://downloads.claude.ai/*) [ -f "$T/net/claude" ] || exit 22; emit <"$T/net/claude"; exit 0 ;;
  */starship-*.tar.gz.sha256) emit <"$T/net/starship.sha"; exit 0 ;;
  */starship-*.tar.gz) emit <"$T/net/starship.tar.gz"; exit 0 ;;
  */lazygit/*/checksums.txt) emit <"$T/net/lazygit.sums"; exit 0 ;;
  */lazygit_*.tar.gz) emit <"$T/net/lazygit.tar.gz"; exit 0 ;;
  *) exit 22 ;;
esac
[ -f "$T/net/\$f" ] || exit 22
printf '{\n  "url": "x",\n  "tag_name": "v%s",\n  "name": "y"\n}\n' "\$(cat "$T/net/\$f")" | emit
EOF
chmod +x "$T/util/curl"

# tool <path> <name> <version>: a stub that reports its version the way the
# real tool does. herdr's `update` subcommand moves it to $T/net/herdr.
tool() {
  case "$2" in
    lazygit) line="commit=abc, build date=x, build source=binaryRelease, version=$3, os=linux, arch=amd64, git version=2.53.0" ;;
    claude)  line="$3 (Claude Code)" ;;
    *)       line="$2 $3" ;;
  esac
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<EOF
#!/bin/sh
if [ "\$1" = update ]; then echo "\$0 update" >>"$T/calls"; cp "$T/net/herdr" "$T/herdr.ver"; exit 0; fi
if [ -f "$T/herdr.ver" ] && [ "$2" = herdr ]; then echo "herdr \$(cat "$T/herdr.ver")"; exit 0; fi
echo "$line"
EOF
  chmod +x "$1"
}

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{ print $1 }'; }

# Release archives the curl stub serves.
tool "$T/build/starship" starship 1.1.0
tar -czf "$T/net/starship.tar.gz" -C "$T/build" starship
sha "$T/net/starship.tar.gz" >"$T/net/starship.sha"
rm "$T/build/starship"
tool "$T/build/lazygit" lazygit 0.66.2
tar -czf "$T/net/lazygit.tar.gz" -C "$T/build" lazygit
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64) lgp=darwin_arm64 ;; Darwin/*) lgp=darwin_x86_64 ;;
  */aarch64|*/arm64) lgp=linux_arm64 ;; *) lgp=linux_x86_64 ;;
esac
printf '%s  lazygit_0.66.2_%s.tar.gz\n' "$(sha "$T/net/lazygit.tar.gz")" "$lgp" >"$T/net/lazygit.sums"
echo 1.1.0 >"$T/net/starship"
echo 0.66.2 >"$T/net/lazygit"
echo 0.9.5 >"$T/net/herdr"

H="$T/home"
# fresh: a HOME with an old starship and a current herdr under ~/.local/bin,
# and lazygit from the "system package manager" (outside $HOME).
fresh() {
  rm -rf "$H" "$T/sys" "$T/curl.log" "$T/calls" "$T/herdr.ver" "$T/net/offline"
  mkdir -p "$H/.local/bin" "$T/sys"
  tool "$H/.local/bin/starship" starship 1.0.0
  tool "$H/.local/bin/herdr" herdr 0.9.5
  tool "$T/sys/lazygit" lazygit 0.57.0
}
run() { HOME="$H" PATH="$T/sys:$T/util" "$BASH_BIN" "$UPDATE" "$@" 2>&1; }

# ── report: says what's behind, changes nothing ───────────────
fresh
out="$(run)"; rc=$?
assert_eq "$rc" 0 "the report exits 0"
assert_contains "$out" "1.1.0 available — ./update.sh --apply" "an old starship under \$HOME is offered an upgrade"
assert_contains "$out" "herdr     0.9.5      up to date (optional)" "a current herdr is up to date, and optional"
assert_contains "$out" "0.66.2 available (optional) — from the system package manager" "a system lazygit is left to its package manager"
assert_contains "$out" "lazygit   0.57.0" "lazygit's version, not the git version it also prints"
assert_contains "$out" "./update.sh --add deno" "an absent optional tool says how to add it"
assert_contains "$("$H/.local/bin/starship" --version)" "1.0.0" "the report upgraded nothing"

# ── offline: the report still succeeds ────────────────────────
fresh; touch "$T/net/offline"
out="$(run)"; rc=$?
assert_eq "$rc" 0 "the report exits 0 offline"
assert_contains "$out" "latest unknown (offline?)" "offline, latest versions show as unknown"

# ── --missing: installs absent defaults, looks nothing else up ─
fresh; rm "$H/.local/bin/starship"
out="$(run --missing)"; rc=$?
assert_eq "$rc" 0 "--missing exits 0 after installing"
assert_contains "$("$H/.local/bin/starship" --version 2>&1)" "1.1.0" "--missing installs an absent starship into ~/.local/bin"
log="$(cat "$T/curl.log")"
assert_not_contains "$log" "herdr.dev" "--missing looks nothing up for a tool that is present"
assert_not_contains "$log" "lazygit" "--missing leaves optional tools alone"

# herdr is optional: an absent one stays absent until it's added.
fresh; rm "$H/.local/bin/herdr"
out="$(run --missing)"; rc=$?
assert_eq "$rc" 0 "--missing exits 0 with herdr absent"
assert_not_contains "$(cat "$T/curl.log" 2>/dev/null)" "herdr.dev" "--missing doesn't install an absent herdr"
assert_contains "$(run)" "not installed (optional) — ./update.sh --add herdr" "an absent herdr says how to add it"
assert_not_contains "$out" "Tools not managed" "--missing prints no report"

# Offline the download fails, so nothing is installed — and it says so.
fresh; rm "$H/.local/bin/starship"; touch "$T/net/offline"
out="$(run --missing)"; rc=$?
[ "$rc" -ne 0 ] && pass "--missing offline exits non-zero" || fail "--missing offline exits non-zero"
assert_contains "$out" "(offline?)" "--missing offline says why nothing was installed"

# starship installs from releases/latest/download, not through the rate-limited
# API, so an install needs no version lookup at all.
assert_not_contains "$(cat "$T/curl.log")" "api.github.com" "installing starship makes no API call"

# A binary that installs but can't run (wrong libc, say) is a failure, not a
# silent success that every later install.sh run repeats.
fresh; rm "$H/.local/bin/starship"
mkdir -p "$T/broken"; printf '#!/bin/sh\nexit 1\n' >"$T/broken/starship"; chmod +x "$T/broken/starship"
cp "$T/net/starship.tar.gz" "$T/net/starship.tar.gz.good"; cp "$T/net/starship.sha" "$T/net/starship.sha.good"
tar -czf "$T/net/starship.tar.gz" -C "$T/broken" starship
sha "$T/net/starship.tar.gz" >"$T/net/starship.sha"
out="$(run --missing)"; rc=$?
mv "$T/net/starship.tar.gz.good" "$T/net/starship.tar.gz"; mv "$T/net/starship.sha.good" "$T/net/starship.sha"
[ "$rc" -ne 0 ] && pass "a binary that doesn't run fails the install" || fail "a binary that doesn't run fails the install"
assert_contains "$out" "doesn't work on this machine" "a binary that doesn't run is reported"

# ── a checksum mismatch is never installed ────────────────────
fresh; rm "$H/.local/bin/starship"
cp "$T/net/starship.sha" "$T/net/starship.sha.good"
echo 0000000000000000000000000000000000000000000000000000000000000000 >"$T/net/starship.sha"
out="$(run --missing)"; rc=$?
mv "$T/net/starship.sha.good" "$T/net/starship.sha"
[ "$rc" -ne 0 ] && pass "a checksum mismatch exits non-zero" || fail "a checksum mismatch exits non-zero"
assert_contains "$out" "checksum mismatch" "a checksum mismatch is reported"
[ ! -e "$H/.local/bin/starship" ] && pass "a checksum mismatch installs nothing" || fail "a checksum mismatch installs nothing"

# ── --apply: upgrades what's under $HOME, nothing else ────────
fresh; echo 0.9.4 >"$T/herdr.ver"
out="$(run --apply)"; rc=$?
assert_eq "$rc" 0 "--apply exits 0"
assert_contains "$("$H/.local/bin/starship" --version)" "1.1.0" "--apply upgrades starship in place"
assert_contains "$(cat "$T/calls" 2>/dev/null)" "herdr update" "--apply upgrades herdr with herdr update"
assert_contains "$("$T/sys/lazygit" --version)" "version=0.57.0" "--apply leaves the system lazygit alone"
[ ! -e "$H/.local/bin/lazygit" ] && pass "--apply installs no optional tool" || fail "--apply installs no optional tool"

# ── versions compare numerically ──────────────────────────────
fresh; tool "$H/.local/bin/starship" starship 1.9.0; echo 1.10.0 >"$T/net/starship"
out="$(run)"
assert_contains "$out" "1.10.0 available" "1.9.0 is older than 1.10.0"
tool "$H/.local/bin/starship" starship 1.10.0; echo 1.9.0 >"$T/net/starship"
out="$(run)"
assert_contains "$out" "starship  1.10.0     up to date" "a newer local version is never offered a downgrade"
echo 1.1.0 >"$T/net/starship"

# ── a symlinked or slash-terminated HOME is still "under \$HOME" ─
fresh; ln -s "$H" "$T/home-link"
out="$(HOME="$T/home-link" PATH="$T/sys:$T/util" "$BASH_BIN" "$UPDATE" 2>&1)"
assert_contains "$out" "1.1.0 available — ./update.sh --apply" "a symlinked HOME still owns ~/.local/bin"
out="$(HOME="$H/" PATH="$T/sys:$T/util" "$BASH_BIN" "$UPDATE" 2>&1)"
assert_contains "$out" "1.1.0 available — ./update.sh --apply" "a HOME with a trailing slash still owns ~/.local/bin"
rm "$T/home-link"

# ── a failing package-manager query doesn't fail the report ───
fresh; printf '#!/bin/sh\nexit 1\n' >"$T/sys/brew"; chmod +x "$T/sys/brew"
out="$(run)"; rc=$?
assert_eq "$rc" 0 "the report exits 0 when brew outdated fails"

# ── a latest "version" that isn't one is ignored ──────────────
fresh; printf '<html>captive portal</html>\n' >"$T/net/claude"; tool "$H/.local/bin/claude" claude 2.1.0
out="$(run)"
assert_contains "$out" "claude    2.1.0      latest unknown" "HTML in place of a version counts as unknown"
rm "$T/net/claude"

# ── --add: installs an optional tool, verified ────────────────
fresh; rm "$T/sys/lazygit"
out="$(run --add lazygit)"; rc=$?
assert_eq "$rc" 0 "--add lazygit exits 0"
assert_contains "$("$H/.local/bin/lazygit" --version 2>&1)" "version=0.66.2" "--add installs lazygit from its release"

out="$(run --add bogus)"; rc=$?
assert_eq "$rc" 2 "--add with an unknown tool is a usage error"

finish
