---
name: point-claude-at-agents-md
description: Use when a repo has both a CLAUDE.md and an AGENTS.md the CLAUDE.md never imports, when the agents-md-probe hook reports conventions missing from context, or when a session has been working from codebase discovery in a repo that documented its conventions somewhere Claude Code never loaded.
---

# Point Claude at AGENTS.md

Since 2.1.277 Claude Code loads `AGENTS.md` itself, but only as a fallback:
a `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the session
directory or above it switches the fallback off for the whole session, and
then no `AGENTS.md` loads unless a `CLAUDE.md` imports it. A repo with both
files and no import hands Claude half its conventions, and the session never
finds out — it cannot distinguish "no conventions here" from "conventions I
was never given", so it silently works from discovery instead.

Fix it by importing the `AGENTS.md` from its sibling `CLAUDE.md`.

A repo with only `AGENTS.md` needs nothing: the fallback loads it. Adding a
`CLAUDE.md` there is still worth it when someone keeps a `CLAUDE.local.md`,
which would otherwise switch the fallback off on their machine alone.

## Write the pointer, not the rules

`CLAUDE.md` loads **in full, on every request, forever**. So it carries the
import and the reason it exists — nothing else.

```markdown
# Project conventions

Claude Code skips `AGENTS.md` once a `CLAUDE.md` exists, so this file imports it.

@AGENTS.md
```

Copying AGENTS.md's contents in instead of importing is the failure to avoid:
two files that drift with nothing connecting them, and the drift is invisible
until someone diffs them.

## Judgment calls

**A `CLAUDE.md` already exists and does not mention `AGENTS.md`.** Do not
overwrite it — someone wrote it for a reason. Append the `@AGENTS.md` line and
tell your partner the two files had been unconnected. If the two disagree on a
rule, that is a real conflict: surface it, do not silently merge.

**Several `AGENTS.md` files (a monorepo).** Give each one its own sibling
`CLAUDE.md`. Nested files load only when a session touches that directory, so
a single root import does not cover the leaves.

**The repo is not yours.** Adding the file changes what every future agent in
that repo is given. Say what you are adding and why before writing it in
someone else's repo.

**`AGENTS.md` is huge.** Import it anyway, then say so — a large import is a
standing per-request cost in that repo, and trimming AGENTS.md is the repo
owner's call, not a reason to skip the pointer.

## Verify

The import resolving is the only thing worth checking, and reading the file
proves nothing — you would read it with or without the import. Ask a fresh
session something only `AGENTS.md` answers, with file tools denied:

```sh
echo "<question only AGENTS.md answers>. If your context does not say, answer UNKNOWN." \
  | claude -p --permission-mode plan \
    --disallowed-tools "Read" "Glob" "Grep" "Bash" "Agent" "Task" "WebFetch"
```

`UNKNOWN` means the import did not resolve. Anything else means it did.
