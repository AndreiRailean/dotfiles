#!/bin/sh
# install.sh must install the Nerd Font through Homebrew on macOS, and on
# Linux only where something local draws with it.
#
# It used to unzip the release into ~/.local/share/fonts on every OS, but
# macOS never reads that dir — the font was "downloaded" yet not installed, and
# the closing note sent you off to install 150 files by hand. The cask puts
# them in ~/Library/Fonts and lets `brew upgrade` keep them current.
#
# On a headless box or WSL the 388 MB download is dead weight: over SSH the
# client's terminal draws the glyphs, and in WSL it's Windows Terminal.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

FN="$(sed -n '/^install_nerd_font() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found install_nerd_font in install.sh" || fail "found install_nerd_font in install.sh"
VARS="$(grep -E '^FONT_(ARCHIVE|FACE|CASK|DIR|SESSION_DIRS)=' "$INST")"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/bin"
# Stubs log their arguments; `brew list` reports the cask as not installed.
cat >"$T/bin/brew" <<EOF
#!/bin/sh
echo "brew \$*" >>"$T/calls"
[ "\$1" = list ] && exit 1
exit 0
EOF
cat >"$T/bin/curl" <<EOF
#!/bin/sh
echo "curl \$*" >>"$T/calls"
exit 1
EOF
chmod +x "$T/bin/brew" "$T/bin/curl"

# run <OS> [stale]: run install_nerd_font in a fresh HOME with the stubs first
# on PATH. stale pre-creates an earlier run's download. The display signals
# come from the caller's DISPLAY / WAYLAND_DISPLAY / IS_WSL / SESSIONS, so the
# host running the test can't leak its own into the result.
run() {
  rm -rf "$T/home" "$T/calls"; mkdir -p "$T/home"; : >"$T/calls"
  [ -n "${2:-}" ] && mkdir -p "$T/home/.local/share/fonts/Monaspace" && : >"$T/home/.local/share/fonts/Monaspace/x.otf"
  env -u DISPLAY -u WAYLAND_DISPLAY ${DISPLAY:+DISPLAY="$DISPLAY"} ${WAYLAND_DISPLAY:+WAYLAND_DISPLAY="$WAYLAND_DISPLAY"} \
    HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" PATH="$T/bin:/usr/bin:/bin" OS="$1" IS_WSL="${IS_WSL:-0}" \
    bash -c "$VARS
FONT_SESSION_DIRS=\"${SESSIONS:-$T/none}\"
$FN
install_nerd_font" >/dev/null 2>&1
}
STALE="$T/home/.local/share/fonts/Monaspace"
mkdir -p "$T/xsessions"

run Darwin
C="$(cat "$T/calls")"
assert_contains "$C" "brew install --cask font-monaspice-nerd-font" "macOS: installs the cask"
assert_not_contains "$C" "curl" "macOS: does not download the release zip"
[ ! -e "$T/home/.local/share/fonts" ] && pass "macOS: nothing written to ~/.local/share/fonts" \
  || fail "macOS: nothing written to ~/.local/share/fonts"

run Darwin stale
[ ! -e "$T/home/.local/share/fonts/Monaspace" ] && pass "macOS: an earlier run's unused download is removed" \
  || fail "macOS: an earlier run's unused download is removed"

unset DISPLAY WAYLAND_DISPLAY IS_WSL SESSIONS

DISPLAY=:0 run Linux
C="$(cat "$T/calls")"
assert_contains "$C" "curl" "Linux with DISPLAY: downloads the release zip"
assert_not_contains "$C" "brew" "Linux: does not use Homebrew"

WAYLAND_DISPLAY=wayland-0 run Linux
assert_contains "$(cat "$T/calls")" "curl" "Linux with WAYLAND_DISPLAY: downloads the release zip"

# A desktop box reached over SSH: no DISPLAY in this shell, but a session
# type is installed, so a local terminal there can use the font.
SESSIONS="$T/none $T/xsessions" run Linux
assert_contains "$(cat "$T/calls")" "curl" "Linux with an installed X/Wayland session: downloads the release zip"

run Linux
assert_not_contains "$(cat "$T/calls")" "curl" "headless Linux: does not download the font"
[ ! -e "$T/home/.local/share/fonts" ] && pass "headless Linux: nothing written to ~/.local/share/fonts" \
  || fail "headless Linux: nothing written to ~/.local/share/fonts"

run Linux stale
[ ! -e "$STALE" ] && pass "headless Linux: an earlier run's unused download is removed" \
  || fail "headless Linux: an earlier run's unused download is removed"

IS_WSL=1 DISPLAY=:0 run Linux stale
assert_not_contains "$(cat "$T/calls")" "curl" "WSL: does not download the font, even with WSLg's DISPLAY"
[ ! -e "$STALE" ] && pass "WSL: an earlier run's unused download is removed" \
  || fail "WSL: an earlier run's unused download is removed"

DISPLAY=:0 run Linux stale
[ -e "$STALE" ] && pass "Linux with a display: an existing download is kept" \
  || fail "Linux with a display: an existing download is kept"

finish
