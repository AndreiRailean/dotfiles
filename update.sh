#!/usr/bin/env bash
# update.sh — install and update the tools no package manager looks after.
#
#   ./update.sh                 report installed vs latest; changes nothing
#   ./update.sh --missing       install the default tools that are absent
#   ./update.sh --apply         install what's missing, upgrade what's behind
#   ./update.sh --add <tool>…   install an optional tool on this machine
#
# install.sh runs --missing and then the report, so this file is the one place
# that knows where each of these tools comes from — and re-running install.sh
# still never upgrades anything behind your back. Upgrading is always a
# deliberate --apply.
#
# DEFAULT tools go on every machine. OPTIONAL tools go only where you ask with
# --add; after that, presence is the opt-in — a tool on PATH is reported and
# upgraded like any other, so there is no per-machine list to keep.
#
# Only a binary under $HOME is upgraded: that is where this script and the
# tools' own installers put them. A copy from brew, apt or pacman is reported
# with its owner and left to that package manager — upgrading it here would
# put two copies on PATH that drift apart.
#
# Every network lookup fails soft. Offline, a latest version shows as unknown
# and nothing is upgraded; the report still exits 0, so install.sh carries on.

set -euo pipefail

DEFAULT_TOOLS="starship"
OPTIONAL_TOOLS="herdr deno fnm claude lazygit"

OS="$(uname -s)"
ARCH="$(uname -m)"
BIN="$HOME/.local/bin"
# owner() compares resolved paths, so $HOME must be resolved too: a symlinked
# home (/home -> /data/home) or a trailing slash would otherwise make every
# copy under it look like someone else's, and nothing would ever upgrade.
HOME_REAL="$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "${HOME%/}")"
FNM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
# A new shell finds these through path.sh and tools.sh. This script may be what
# just created them, so it puts them on its own PATH up front.
PATH="$BIN:$FNM_DIR:$HOME/.deno/bin:$PATH"

usage() {
  sed -n '2,7s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
  echo "  default tools:  $DEFAULT_TOOLS" >&2
  echo "  optional tools: $OPTIONAL_TOOLS" >&2
  exit "${1:-2}"
}

MODE=report
ADD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --missing) MODE=missing ;;
    --apply)   MODE=apply ;;
    --add)
      MODE=add; shift
      [ $# -gt 0 ] || usage
      for t in "$@"; do
        case " $DEFAULT_TOOLS $OPTIONAL_TOOLS " in
          *" $t "*) ;;
          *) echo "update.sh: unknown tool '$t'" >&2; usage ;;
        esac
      done
      ADD=" $* "
      break ;;
    -h|--help) usage 0 ;;
    *) usage ;;
  esac
  shift
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Looking things up ────────────────────────────────────────
fetch() { curl -fsSL --connect-timeout 10 --max-time 120 "$@"; }

# json_field <name>: the first "name": "value" on stdin.
json_field() { grep -o "\"$1\": *\"[^\"]*\"" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'; }

# github_latest <owner/repo>: the latest release's tag, without a leading v.
github_latest() {
  local tag
  tag="$(fetch "https://api.github.com/repos/$1/releases/latest" 2>/dev/null | json_field tag_name)" || true
  printf '%s\n' "${tag#v}"
}

claude_channel() {
  if grep -q '"autoUpdatesChannel": *"stable"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo stable
  else
    echo latest
  fi
}

# latest <tool>: the newest released version, or nothing when it can't be had.
# Anything that isn't a version (a captive portal's HTML, say) counts as nothing.
latest() {
  latest_raw "$1" | tr -d '\r' | sed -n '1{/^[0-9][0-9.]*$/p;}'
}
latest_raw() {
  case "$1" in
    starship) github_latest starship/starship ;;
    deno)     github_latest denoland/deno ;;
    fnm)      github_latest Schniz/fnm ;;
    lazygit)  github_latest jesseduffield/lazygit ;;
    # herdr's installer and `herdr update` both read this manifest.
    herdr)    fetch https://herdr.dev/latest.json 2>/dev/null | json_field version || true ;;
    # The channel Claude Code updates itself from, so the two agree.
    claude)   fetch "https://downloads.claude.ai/claude-code-releases/$(claude_channel)" 2>/dev/null || true ;;
  esac
}

# version <tool>: the installed version, digits and dots only; empty if absent.
version() {
  command -v "$1" >/dev/null 2>&1 || return 0
  local v=""
  case "$1" in
    claude)  v="$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }')" ;;
    # ", version=" — the line ends with ", git version=…", which isn't it.
    lazygit) v="$(lazygit --version 2>/dev/null | sed -n 's/.*, version=\([^,]*\).*/\1/p')" ;;
    *)       v="$("$1" --version 2>/dev/null | awk 'NR == 1 { print $2 }')" ;;
  esac
  # lazygit's apt build quotes it and adds a packaging suffix: '0.57.0+ds1-1'.
  v="${v#v}"; v="${v#\'}"
  printf '%s\n' "${v%%[!0-9.]*}"
}

# older <a> <b>: is version a older than version b? Field by field, numerically
# — not `sort -V`, which macOS 12 and earlier lack, and whose absence would make
# everything look up to date.
older() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, x, "."); m = split(b, y, ".")
    for (i = 1; i <= (n > m ? n : m); i++) {
      if (x[i] + 0 < y[i] + 0) exit 0
      if (x[i] + 0 > y[i] + 0) exit 1
    }
    exit 1
  }'
}

# owner <tool>: self (under $HOME), brew, or system.
owner() {
  local p
  p="$(command -v "$1")"
  p="$(readlink -f "$p" 2>/dev/null || printf '%s' "$p")"
  case "$p" in
    */Cellar/*|/opt/homebrew/*|/home/linuxbrew/*) echo brew ;;
    "$HOME_REAL"/*|"${HOME%/}"/*) echo self ;;
    *) echo system ;;
  esac
}

# ── Getting things ───────────────────────────────────────────
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{ print $1 }'
}

# download <url> <file> <sha256>: fetch url into file and refuse it unless it
# matches the checksum. Pass "-" only where the project publishes none.
download() {
  if [ -z "$3" ]; then
    echo "!! couldn't fetch the checksum for $1 (offline?) — not installed"
    return 1
  fi
  fetch -o "$2" "$1" || { echo "!! download failed (offline?): $1"; return 1; }
  if [ "$3" != - ] && [ "$(sha256 "$2")" != "$3" ]; then
    echo "!! checksum mismatch for $1 — not installed"
    return 1
  fi
}

# place <file> <dir>: install an executable by rename, so a copy that is
# running is replaced rather than overwritten mid-use ("text file busy").
place() {
  local name="${1##*/}"
  mkdir -p "$2"
  cp "$1" "$2/.$name.new"
  chmod 755 "$2/.$name.new"
  mv -f "$2/.$name.new" "$2/$name"
}

# dest <tool> <default dir>: beside the copy being upgraded, else the default.
dest() {
  if command -v "$1" >/dev/null 2>&1; then dirname "$(command -v "$1")"; else echo "$2"; fi
}

unsupported() { echo "!! no $1 release for $OS/$ARCH — install it by hand"; return 1; }

# starship, deno and fnm name their release assets without a version, so they
# come from GitHub's releases/latest/download redirect. That isn't the API, so
# its 60-an-hour unauthenticated limit — easy to hit behind a shared NAT or in
# CI — can't stop an install. lazygit's asset names carry the version, so it
# still needs the lookup.

install_starship() {
  local t a u
  # musl on Linux, as starship's own installer chooses: the static build runs
  # on an old-glibc server, where the gnu one dies with "GLIBC_x.y not found".
  case "$OS/$ARCH" in
    Linux/x86_64)              t=x86_64-unknown-linux-musl ;;
    Linux/aarch64|Linux/arm64) t=aarch64-unknown-linux-musl ;;
    Linux/armv7l|Linux/armv6l) t=arm-unknown-linux-musleabihf ;;
    Darwin/arm64)              t=aarch64-apple-darwin ;;
    Darwin/x86_64)             t=x86_64-apple-darwin ;;
    *) unsupported starship; return 1 ;;
  esac
  a="starship-$t.tar.gz"
  u="https://github.com/starship/starship/releases/latest/download"
  download "$u/$a" "$TMP/$a" "$(fetch "$u/$a.sha256" 2>/dev/null | awk '{ print $1 }')" &&
    tar -xzf "$TMP/$a" -C "$TMP" starship &&
    place "$TMP/starship" "$(dest starship "$BIN")"
}

install_deno() {
  local t a u
  case "$OS/$ARCH" in
    Linux/x86_64)              t=x86_64-unknown-linux-gnu ;;
    Linux/aarch64|Linux/arm64) t=aarch64-unknown-linux-gnu ;;
    Darwin/arm64)              t=aarch64-apple-darwin ;;
    Darwin/x86_64)             t=x86_64-apple-darwin ;;
    *) unsupported deno; return 1 ;;
  esac
  a="deno-$t.zip"
  u="https://github.com/denoland/deno/releases/latest/download"
  download "$u/$a" "$TMP/$a" "$(fetch "$u/$a.sha256sum" 2>/dev/null | awk '{ print $1 }')" &&
    unzip -oq "$TMP/$a" deno -d "$TMP" &&
    place "$TMP/deno" "$(dest deno "$BIN")"
}

install_fnm() {
  local a
  case "$OS/$ARCH" in
    Linux/x86_64)              a=fnm-linux.zip ;;
    Linux/aarch64|Linux/arm64) a=fnm-arm64.zip ;;
    Darwin/*)                  a=fnm-macos.zip ;;
    *) unsupported fnm; return 1 ;;
  esac
  # fnm publishes no checksums, so this rests on HTTPS from GitHub alone. Its
  # home is FNM_DIR, which tools.sh puts on PATH and hands to `fnm env`.
  download "https://github.com/Schniz/fnm/releases/latest/download/$a" "$TMP/$a" - &&
    unzip -oq "$TMP/$a" fnm -d "$TMP" &&
    place "$TMP/fnm" "$(dest fnm "$FNM_DIR")"
}

install_lazygit() {
  local p a u
  case "$OS/$ARCH" in
    Linux/x86_64)              p=linux_x86_64 ;;
    Linux/aarch64|Linux/arm64) p=linux_arm64 ;;
    Darwin/arm64)              p=darwin_arm64 ;;
    Darwin/x86_64)             p=darwin_x86_64 ;;
    *) unsupported lazygit; return 1 ;;
  esac
  a="lazygit_$1_$p.tar.gz"
  u="https://github.com/jesseduffield/lazygit/releases/download/v$1"
  download "$u/$a" "$TMP/$a" "$(fetch "$u/checksums.txt" 2>/dev/null | awk -v a="$a" '$2 == a { print $1 }')" &&
    tar -xzf "$TMP/$a" -C "$TMP" lazygit &&
    place "$TMP/lazygit" "$(dest lazygit "$BIN")"
}

# herdr and Claude Code come from their own installers, which pick the release,
# verify its checksum against their manifest, and know where the binary lives.
install_herdr() {
  download https://herdr.dev/install.sh "$TMP/herdr-install.sh" - && sh "$TMP/herdr-install.sh"
}
install_claude() {
  download https://claude.ai/install.sh "$TMP/claude-install.sh" - && bash "$TMP/claude-install.sh"
}

# On macOS with Homebrew, herdr comes from brew, which also ships the launchd
# service install.sh starts. A copy from the official installer (a run before
# herdr came from brew) shadows brew's, since ~/.local/bin precedes
# /opt/homebrew/bin on PATH — and `herdr update` / `brew upgrade` then each
# update a different binary, so the two drift apart. brew owns herdr there.
# herdr is optional, so this only acts where it's installed or being added.
herdr_from_brew() {
  [ "$OS" = Darwin ] && command -v brew >/dev/null 2>&1 || return 0
  if ! brew list --formula herdr >/dev/null 2>&1; then
    case "$ADD" in *" herdr "*) ;; *) [ -n "$(version herdr)" ] || return 0 ;; esac
    echo "Installing herdr (Homebrew)..."
    brew install herdr \
      || { echo "!! brew install herdr failed — falling back to the official installer"; return 0; }
    BREWED_HERDR=1
    # install.sh starts the service itself right after its --missing run.
    [ "$MODE" != add ] || echo "   re-run ./install.sh to start herdr's server at login (brew services)"
  fi
  if [ -f "$BIN/herdr" ] && [ ! -L "$BIN/herdr" ]; then
    rm -f "$BIN/herdr"
    hash -r
    echo "Removed ~/.local/bin/herdr — superseded by Homebrew's herdr"
  fi
}

# runs <tool>: does the tool now report a version? A binary can install cleanly
# and still not run (wrong libc, wrong arch); without this check it would look
# absent, so every install.sh run would reinstall it and say nothing.
runs() {
  hash -r
  [ -n "$(version "$1")" ] && return 0
  echo "!! $1 was installed but \`$1 --version\` doesn't work on this machine"
  return 1
}

# install_tool <tool>: put an absent tool on this machine.
install_tool() {
  local v=""
  if [ "$1" = lazygit ]; then
    v="$(latest lazygit)"
    [ -n "$v" ] || { echo "!! can't find the latest lazygit release (offline?) — not installed"; return 1; }
  fi
  echo "Installing $1${v:+ $v}..."
  "install_$1" "$v" && runs "$1"
}

# upgrade_tool <tool> <version>: bring a copy this script owns up to version.
upgrade_tool() {
  echo "Upgrading $1 to $2..."
  case "$1" in
    herdr)  herdr update ;;
    claude) claude update ;;
    deno)   deno upgrade ;;
    *)      "install_$1" "$2" ;;
  esac && runs "$1"
}

# ── Main ─────────────────────────────────────────────────────
BREWED_HERDR=0
is_optional() { case " $OPTIONAL_TOOLS " in *" $1 "*) return 0 ;; esac; return 1; }

row() { printf '  %-9s %-10s %s\n' "$1" "${2:--}" "$3"; }

FAILED=0
case "$MODE" in
  missing|apply) herdr_from_brew ;;
  add)           case "$ADD" in *" herdr "*) herdr_from_brew ;; esac ;;
esac
[ "$MODE" = report ] || [ "$MODE" = apply ] && echo "Tools not managed by a package manager:"

for tool in $DEFAULT_TOOLS $OPTIONAL_TOOLS; do
  have="$(version "$tool")"
  tag=""; is_optional "$tool" && tag=" (optional)"

  if [ -z "$have" ]; then
    case "$MODE" in
      missing|apply) is_optional "$tool" || { install_tool "$tool" || FAILED=1; } ;;
      add)           case "$ADD" in *" $tool "*) install_tool "$tool" || FAILED=1 ;; esac ;;
    esac
    have="$(version "$tool")"
    if [ -z "$have" ] && { [ "$MODE" = report ] || [ "$MODE" = apply ]; }; then
      if is_optional "$tool"; then
        row "$tool" "" "not installed$tag — ./update.sh --add $tool"
      else
        row "$tool" "" "not installed — ./update.sh --missing"
      fi
    fi
    [ -n "$have" ] && [ "$MODE" = apply ] && row "$tool" "$have" "installed$tag"
    continue
  fi

  case "$MODE" in
    missing) continue ;;
    add)
      case "$ADD" in
        *" $tool "*)
          if [ "$tool" = herdr ] && [ "$BREWED_HERDR" -eq 1 ]; then
            echo "herdr $have installed from Homebrew"
          else
            echo "$tool $have is already installed"
          fi ;;
      esac
      continue ;;
  esac

  new="$(latest "$tool")"
  own="$(owner "$tool")"
  if [ "$MODE" = apply ] && [ "$own" = self ] && [ -n "$new" ] && older "$have" "$new"; then
    upgrade_tool "$tool" "$new" || FAILED=1
    have="$(version "$tool")"
  fi

  if [ -z "$new" ]; then
    row "$tool" "$have" "latest unknown (offline?)$tag"
  elif ! older "$have" "$new"; then
    row "$tool" "$have" "up to date$tag"
  else
    case "$own" in
      self)   row "$tool" "$have" "$new available$tag — ./update.sh --apply" ;;
      brew)   row "$tool" "$have" "$new available$tag — from Homebrew: brew upgrade $tool" ;;
      system) row "$tool" "$have" "$new available$tag — from the system package manager, not upgraded here" ;;
    esac
  fi
done

# Upgrades the package managers own are theirs to run; just say they're waiting.
if [ "$MODE" = report ] || [ "$MODE" = apply ]; then
  if command -v brew >/dev/null 2>&1; then
    n="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')" || n=0
    if [ "${n:-0}" -gt 0 ]; then echo "  brew: $n outdated — brew upgrade"; fi
  fi
  if command -v apt >/dev/null 2>&1; then
    n="$(apt list --upgradable 2>/dev/null | grep -c 'upgradable from')" || n=0
    if [ "${n:-0}" -gt 0 ]; then echo "  apt: $n upgradable as of the last apt update — sudo apt upgrade"; fi
  fi
fi

[ "$MODE" = report ] && exit 0
exit "$FAILED"
