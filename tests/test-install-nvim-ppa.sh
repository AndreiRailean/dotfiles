#!/bin/sh
# install.sh adds the neovim PPA only for an Ubuntu release it publishes for,
# and never leaves a broken PPA source behind.
#
# add-apt-repository adds the source even for a release the PPA has no build
# for (Ubuntu 26.04 at launch). A source with no Release file makes every later
# `apt update` fail, which broke the Docker and gh installs on a fresh VM.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

FN="$(sed -n '/^add_nvim_ppa() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found add_nvim_ppa in install.sh" || fail "found add_nvim_ppa in install.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/bin"
# Stubs log their argv; CURL_RC / APT_UPDATE_RC choose the outcome.
cat >"$T/bin/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >>"$LOG"; exit "${CURL_RC:-0}"
EOF
cat >"$T/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat >"$T/bin/apt" <<'EOF'
#!/bin/sh
echo "apt $*" >>"$LOG"
[ "$1" = update ] && exit "${APT_UPDATE_RC:-0}"; exit 0
EOF
cat >"$T/bin/add-apt-repository" <<'EOF'
#!/bin/sh
echo "add-apt-repository $*" >>"$LOG"
EOF
chmod +x "$T/bin/"*

# run <codename> [VAR=value...] — prints the function's exit code; log in $T/log
run() {
  codename="$1"; shift
  : >"$T/log"
  env LOG="$T/log" PATH="$T/bin:/usr/bin:/bin" "$@" bash -c "$FN
add_nvim_ppa '$codename' >/dev/null; echo \$?"
}

rc="$(run resolute CURL_RC=22)"
log="$(cat "$T/log")"
assert_eq "$rc" "1" "unpublished release: returns failure"
assert_contains "$log" "dists/resolute/Release" "unpublished release: probes the PPA for it"
assert_not_contains "$log" "add-apt-repository" "unpublished release: never adds the PPA"

rc="$(run "")"
log="$(cat "$T/log")"
assert_eq "$rc" "1" "unknown codename: returns failure"
assert_not_contains "$log" "add-apt-repository" "unknown codename: never adds the PPA"

rc="$(run noble)"
log="$(cat "$T/log")"
assert_eq "$rc" "0" "published release: succeeds"
assert_contains "$log" "add-apt-repository -y ppa:neovim-ppa/stable" "published release: adds the PPA"
assert_not_contains "$log" "--remove" "published release: keeps the PPA"

rc="$(run noble APT_UPDATE_RC=100)"
log="$(cat "$T/log")"
assert_eq "$rc" "1" "apt update fails: returns failure"
assert_contains "$log" "add-apt-repository -y --remove ppa:neovim-ppa/stable" "apt update fails: removes the PPA again"

finish
