#!/bin/sh
# install.sh must install the Nerd Font through Homebrew on macOS.
#
# It used to unzip the release into ~/.local/share/fonts on every OS, but
# macOS never reads that dir — the font was "downloaded" yet not installed, and
# the closing note sent you off to install 150 files by hand. The cask puts
# them in ~/Library/Fonts and lets `brew upgrade` keep them current.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

FN="$(sed -n '/^install_nerd_font() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found install_nerd_font in install.sh" || fail "found install_nerd_font in install.sh"
VARS="$(grep -E '^FONT_(ARCHIVE|FACE|CASK|DIR)=' "$INST")"

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

# run <OS>: run install_nerd_font in a fresh HOME with the stubs first on PATH.
run() {
  rm -rf "$T/home" "$T/calls"; mkdir -p "$T/home"; : >"$T/calls"
  [ -n "${2:-}" ] && mkdir -p "$T/home/.local/share/fonts/Monaspace" && : >"$T/home/.local/share/fonts/Monaspace/x.otf"
  HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" PATH="$T/bin:/usr/bin:/bin" OS="$1" \
    bash -c "$VARS
$FN
install_nerd_font" >/dev/null 2>&1
}

run Darwin
C="$(cat "$T/calls")"
assert_contains "$C" "brew install --cask font-monaspice-nerd-font" "macOS: installs the cask"
assert_not_contains "$C" "curl" "macOS: does not download the release zip"
[ ! -e "$T/home/.local/share/fonts" ] && pass "macOS: nothing written to ~/.local/share/fonts" \
  || fail "macOS: nothing written to ~/.local/share/fonts"

run Darwin stale
[ ! -e "$T/home/.local/share/fonts/Monaspace" ] && pass "macOS: an earlier run's unused download is removed" \
  || fail "macOS: an earlier run's unused download is removed"

run Linux
C="$(cat "$T/calls")"
assert_contains "$C" "curl" "Linux: still downloads the release zip"
assert_not_contains "$C" "brew" "Linux: does not use Homebrew"

finish
