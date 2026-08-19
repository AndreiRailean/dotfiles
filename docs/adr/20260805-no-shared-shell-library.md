---
type: ADR
status: accepted
date: 2026-08-05
summary: install.sh and doctor.sh duplicate logic deliberately, enforced by a
  sync test rather than by comments, because a third consumer (drift.sh) is
  POSIX sh and cannot source a bash library.
---

# No shared shell library (yet) between install.sh and doctor.sh

## Context

`install.sh` and `doctor.sh` duplicate several pieces of logic. Comments in both
say "keep these in sync", which is a reminder, not a mechanism. This ADR records
what is duplicated, why extraction was not done now, and what would need to be
known to do it later.

The duplication is **not** forced by any technical constraint. Bootstrap is
`git clone` then `./install.sh` from inside the repo (README → Bootstrap), and
both scripts are bash that `cd` to the repo root before doing anything. A
`lib/common.sh` sourced by both would work today. The reasons it hasn't happened
are that there were only two copies of anything, the scripts are read top-to-bottom
as standalone documents, and each copy carries long explanatory comments that a
shared function would have to either lose or centralise away from its use site.

There **is** a real constraint, but it applies to a third consumer, not these
two. `shell/.config/shell/drift.sh` also knows about repo state, and it cannot
source a bash library: it is POSIX `sh` sourced into every interactive bash and
zsh shell, it must not assume the current directory, and it has to locate the
repo itself (resolving `~/.config/shell/env.sh` back through its symlink). The
pattern that already works across that boundary is **sharing data, not code**:
`.auto-written` is a plain list at the repo root, read by both `doctor.sh` and
`drift.sh`. Any extraction should keep that split — a bash library for the two
scripts, data files for anything `drift.sh` needs.

### What is duplicated

Each row is enforced by `tests/test-shared-logic-sync.sh`, so this list cannot
silently go stale.

| Knowledge | `install.sh` | `doctor.sh` | Failure mode if they drift |
|---|---|---|---|
| Package list | `for pkg in …` loop | `PACKAGES=` | A package is stowed but never checked for drift, or reported unlinked forever because nothing links it |
| `owned_roots()` | byte-identical copy | byte-identical copy | One script acts on a `$HOME` tree the other doesn't know about |
| lazygit version parse | `lazygit_meets_floor` | inline health check | The two disagree about whether the machine is healthy |
| lazygit floor constant (`64`) | `-ge 64` | `-lt 64` | Same |
| `DOTFILES_DIR` derivation | `pwd -P` | `pwd -P` | See the bug below |
| stow flag set | `--no-folding --target --restow` | same, in `--adopt` | Dropping `--no-folding` silently changes the layout from per-file symlinks to one directory symlink |
| `.pre-dotfiles.*` name | writes it | skips it | doctor.sh offers to adopt the backups, committing them to the repo |

Note the last row is a shared *convention*, not shared code — a producer and a
consumer agreeing on a filename. Extraction wouldn't remove it; only a shared
constant would.

### The duplication has already cost a bug

`install.sh` derived the repo root with `pwd` while `doctor.sh` used `pwd -P`.
`prune_dead_links` compares a resolved symlink target against `$DOTFILES_DIR`,
and stow writes its links via the repo's **physical** path (verified: with the
repo reached through a symlink, stow wrote `../../real/pkg/…`, not
`../dotfiles/pkg/…`). So on any machine where `~/dotfiles` was itself a symlink,
pruning matched nothing and did nothing — silently. Both scripts now use
`pwd -P`, and a behavioural test covers the symlinked-repo case.

This is the argument for extraction in miniature: the two copies were each
locally defensible, and the divergence was invisible until something compared
their outputs.

## Decision

Keep the duplication for now. Enforce it with `tests/test-shared-logic-sync.sh`
rather than with comments, so drift fails loudly and cheaply.

## When to extract

Any one of these is sufficient reason:

- **A third bash consumer appears.** Two copies are maintainable; three are not.
- **A fifth row joins the table above**, or any row grows past a few lines.
- **`test-shared-logic-sync.sh` fails for real** (an actual drift, not a
  refactor breaking a pattern). That means the reminders didn't work.
- **A copy needs to become a genuine abstraction** — e.g. `owned_roots` needing
  to understand nested packages or per-package overrides.

## How to extract

1. `lib/common.sh`, sourced by both after `DOTFILES_DIR` is set:
   `. "$DOTFILES_DIR/lib/common.sh"`. It must not run anything at source time —
   pure definitions only, so sourcing order stays irrelevant.
2. Move, in this order (cheapest and least coupled first): `PACKAGES`,
   `DOTFILES_DIR` derivation, the `.pre-dotfiles` suffix as a constant, the
   stow flag set, `owned_roots`, then the lazygit version parse and floor.
3. Keep each function's explanatory comment attached to the function, and leave
   a one-line pointer at the old site. The comments are the reason these scripts
   are readable; centralising the code must not orphan the reasoning.
4. Rewrite `test-shared-logic-sync.sh` as it goes: each copy-pair assertion
   becomes either unnecessary (one definition remains) or a check that both
   scripts actually source the library. Do not delete the file — the
   `.pre-dotfiles` producer/consumer rows survive extraction.
5. Leave `drift.sh` alone. If it needs something from the library, export it as
   a data file at the repo root, the way `.auto-written` already is.

### Traps worth knowing before starting

- **`pwd -P`, not `pwd`** — stow resolves package paths physically; see above.
- **No GNU-only tools.** These scripts run on macOS. No `find -printf`, no
  `sort -V`, no `readlink -f` in code paths that must work there.
- **`set -euo pipefail` is on in both.** A helper returning non-zero as ordinary
  signalling (like `lazygit_meets_floor`) must be called in a condition, never
  bare, or it aborts the script.
- **bash 4+ is already assumed** (`declare -A` in `doctor.sh`), so arrays and
  `${arr[@]:0:n}` are fine — but only in the bash library, never in anything
  `drift.sh` might read.
- **Lexical path resolution is deliberate** in `link_target_abs`: a link to a
  deleted file usually has deleted ancestor directories too, which rules out
  `realpath`, `readlink -f`, and `cd`. Don't "simplify" it to one of those.
