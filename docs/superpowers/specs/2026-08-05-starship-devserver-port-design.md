# Starship dev-server port segment — design

Date: 2026-08-05
Repo: personal dotfiles (Stow-managed; macOS / WSL / Linux)

## Goal

Show, in the prompt, whether a dev server is listening **for the directory you
are standing in**, and on which port. Several git worktrees of the same project
run `next dev` at once, so ports land wherever they land (3000, 3001, 3002, …)
and there is no way to tell from the shell which port belongs to which worktree
without hunting through process lists or a scrollback that has long since gone.

The segment goes in `starship.toml`, not in Claude Code's config. Claude Code's
status line (`claude/.claude/statusline-command.sh`) renders the *real* starship
prompt by invoking the binary, so one starship module surfaces in both the
terminal prompt and every Claude Code session, and cannot drift between them.

That holds for a `custom` module specifically because starship runs a custom
module's `command` with its working directory set to `--path`. The status line
passes `--path "$cwd"`, so the script resolves Claude Code's workspace rather
than whatever directory the status-line process happens to be started in — the
one property that makes "one module, two surfaces" true instead of merely
convenient.

## Decisions

- **A starship `custom` module**, not a Claude-only status-line branch — one
  implementation, two surfaces (see above).
- **Nothing at all when idle.** No "no server" placeholder: the segment's
  presence *is* the signal.
- **This workspace only.** Servers belonging to other worktrees are not
  reported, not even as a count.
- **Any listening process counts**, not just `node`/`next` — the rule is "its
  cwd is inside this workspace", so `vite`, `supabase functions serve` or a
  throwaway `python -m http.server` are all picked up with no name allowlist to
  maintain.
- **Linux-only detection, silent elsewhere.** `ss` + `/proc/PID/cwd`; on a host
  without `/proc` the script exits non-zero and the segment never appears. The
  macOS route (`lsof -a -p PID -d cwd`) is named in a comment, not implemented.
- **Format:** `[ $output ]($style)` in `bold green`, rendering as `  :3001`
  (nerd-font U+F233 server glyph, distinct from the `nodejs` module's ). Two
  matches render `  :3001,54321`.

## Architecture

The workspace→port mapping is exact and needs no port probing, log scraping or
guesswork: `ss` gives port→PID and `/proc/PID/cwd` gives the directory that PID
was started in.

```
git rev-parse --show-toplevel   →  workspace root (fallback: $PWD)
ss -ltnpH                       →  listening port + owning PIDs
readlink /proc/PID/cwd          →  where that listener lives
keep ports whose listener cwd == root, or is nested under root/
```

### `starship/.config/starship/devserver-port.sh` (new)

POSIX `sh`. One job, one contract:

> Print `:PORT[,PORT…]` as **exactly one line** and exit **0** when at least
> one listening socket belongs to this workspace. Print nothing and exit **1**
> otherwise.

The single-line part is load-bearing, not stylistic: starship substitutes
`$output` verbatim, so output spanning two lines puts a real newline inside the
prompt and breaks the two-line layout. A port-per-line pipeline is the natural
way to write this and the natural way to get it wrong, so the ports are joined
before printing and the test asserts the absence of a newline.

Exit status and stdout are the two things starship needs, so the whole module
is that one contract — nothing about starship leaks into the script, and the
script can be exercised without starship.

Ports are sorted numerically and deduplicated (one process can hold several
sockets; one socket can list several PIDs). stderr is discarded inside the
script: nothing may ever leak into a prompt. A PID that exits mid-scan, a
process owned by another user, or a missing `ss` all fall through to "no match"
rather than erroring.

### Why the exit status has to do the detecting (crux)

Verified against starship 1.26.0, because the module's shape depends on it:

| Module state | Renders |
|---|---|
| no `when` key at all | nothing — even with output |
| `when` passes, output empty | **the glyph, wrapped around nothing** |
| `when` passes, output non-empty | the segment |
| `when` fails | nothing |

So `when` cannot be a formality like `true`: a passing `when` with empty output
would leave a bare glyph sitting in the prompt. `when` and `command` both point
at the same script — its exit status gates the module, its stdout fills it.

The cost of that shape: starship runs `when`, then `command`, so the script runs
**twice** per prompt when a server is up (~5.4ms of `ss` each, plus a
`git rev-parse`). Accepted deliberately over a cache file, which would trade
~15ms for on-disk state and a race between concurrent prompts.

### `starship/.config/starship.toml` (edit)

`${custom.devserver}` is added to `format` after `$git_status` (workspace facts
grouped together, before the language modules), plus the module block. Named
custom modules need the braced `${custom.name}` form in `format`: written as
`$custom.devserver`, starship expands `$custom` and then emits `.devserver` as
literal text, so the prompt reads `  :3001.devserver`.

### Wiring

None. `starship` is already in `install.sh`'s package loop and `doctor.sh`'s
`PACKAGES`, and `stow --no-folding` creates the real `~/.config/starship/`
directory with the script symlinked inside it. Installing is
`stow --restow starship` (or `./install.sh`). The script needs its executable
bit committed.

## Testing

`tests/test-devserver-port.sh`, following `tests/lib.sh`. The script takes two
seams so the whole matrix runs hermetically with no live server:
`DEVSERVER_SS` (default `ss`) and `DEVSERVER_PROC` (default `/proc`). The test
builds a fake `ss` printing canned lines and a fake proc tree of `cwd`
symlinks.

- listener whose cwd **is** the workspace root → `:3001`, exit 0
- invoked from a **subdirectory** of the root → same result (root is resolved
  via git, not taken from `$PWD`)
- listener whose cwd is a **sibling worktree** → no output, exit 1. The sibling
  is named so that the root is a **string prefix** of it (root `…/app`, sibling
  `…/app-next`): that is what distinguishes matching on `$root/` from matching
  on `$root*`, and a sibling with an unrelated name passes either way.
- listener in a **subdirectory** of the workspace → matched
- two matching listeners → `:3001,54321`, sorted numerically and deduplicated
- output of a two-port match contains **no newline** — one line, per the
  contract
- no listeners at all → no output, exit 1
- `DEVSERVER_PROC` pointing at a non-existent path (the macOS case) → no
  output, exit 1
- `sh -n` parses the script

Then a live smoke test across the worktrees present on the machine, with the
current picture taken from `ss -ltnpH` plus `readlink /proc/PID/cwd` rather
than assumed: each worktree running a server shows its own port and no other
worktree's, and worktrees without one show no segment.
