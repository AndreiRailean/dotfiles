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
