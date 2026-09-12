---
type: ADR
status: rejected
date: 2026-09-12
summary: Inferring which repo a Claude session is working in — from /proc, from
  child processes, from any per-session label — cannot be made correct, so
  broadcasts name a repo and a SHA and let each recipient resolve it.
---

# Inferring a session's repo from the machine

## Context

Several Claude Code sessions run concurrently on this machine and can message
each other by name (`ListAgents` lists them; `SendMessage` addresses them).
A session that finishes a migration wants to tell the other sessions working
in that repo, and only those — the steps in such a message are usually
stateful, sometimes destructive, and always wrong somewhere else.

That reads as a routing problem: work out which repo each session is in, then
send to the matching ones.

## What was tried

Three ways of answering "which repo is this session in", from the outside:

1. **`/proc/<pid>/cwd`.** Every live session is a `claude` process, and
   `/run/user/0/cc-socks/<pid>.sock` names them, so the cwd of each session is
   one `readlink` away. It resolved all four sessions cleanly.
2. **Descendant process cwds.** Strictly more information and free — a
   long-lived dev server or similar child lives where the work is.
3. **A declared repo list per session**, defaulting to cwd.

## How it failed

`/proc/<pid>/cwd` answers "where was this session started", which is not
"which repo is it working in". A session reaching another repo by absolute
path never moves its cwd, and some harnesses reset cwd after every command, so
nothing under `/proc` could ever show otherwise. The reading looks
authoritative and is silently wrong for exactly the sessions that matter.

Two incidents, an hour apart, in the same recipient:

- A migration for `andreirailean.github.io` was broadcast to a session working
  in this repo. `pnpm exec astro dev stop` and `git merge origin/main` were
  both actively wrong here — this repo's default branch is `master`. The
  session bounced it with evidence, including
  `git cat-file -t a57c953` → not a valid object name.
- In the same broadcast, a *second* recipient was nearly excluded on the
  strength of the `/proc` reading. It was in fact the session doing the work.
  Excluding it would have been the expensive error.

The structural version: `showcase-8d`'s `/proc` entry says `workspace`, yet it
resolves `andrei.md` SHAs fine, because it has an `andrei.md` worktree and does
nearly all its building there. Same session, same evidence, opposite answers.
A session in two repos should answer yes to broadcasts for both, and **no
scheme assigning one label per session can reproduce that** — which is why the
label was never the missing piece. Approach 3 fixes the unusual session at a
cost of one line and is reasonable as a hint, but inherits the same ceiling.

## What would make it viable

Nothing; this is structural. "Was this meant for me" is not decidable from
either end. The replacement changes the question to "can I act on this", which
the recipient decides in one command: a broadcast names a repo and a commit
SHA, and each recipient runs `git cat-file -t <sha>`. Non-zero exit means
discard. See the `scope-a-broadcast` skill.

All three inference approaches survive as hints with named blind spots — for
choosing whom to send to first, or whom to ask. None is a gate.

The capability framing is `showcase-8d`'s; the `git cat-file` test is the
bounced session's; the mis-scoped broadcast was `ways-of-working-39`'s, which
is also what makes it a record rather than a rule someone thought up.
