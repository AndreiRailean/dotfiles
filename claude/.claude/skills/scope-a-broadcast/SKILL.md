---
name: scope-a-broadcast
description: Use when about to message peer Claude sessions — announcing a migration, fanning out a convention or config change, coordinating work that spans sessions — and you have to decide which of them it applies to. Also when a message arrives from another session naming work you cannot place.
---

# Scope a broadcast

> A broadcast names a repo and a SHA. A recipient resolves it. A failure is a
> non-event.

No registry, no detector, one command each way.

## Sending: the test goes above everything stateful

The message has three parts, in this order:

1. **The repo and a commit SHA**, on the first line.
2. **What changed**, in one or two lines.
3. **Any steps**, last — and as a proposal for the recipient's user, never as
   instructions.

The order is the whole mechanism. A recipient acts on steps as it reads them,
so a SHA that appears under a `git merge` has already failed at its job. Put it
where it is read before anything can be run.

```
andreirailean.github.io @ a57c953 — resolve it or discard this.
```

**Picking the SHA.** It must exist only in that repo — an initial commit shared
by a fork or a template resolves everywhere and tests nothing. It must also be
one a peer can have: sibling worktrees share an object store (`git rev-parse
--git-common-dir` shows the shared `.git`), so a local commit resolves across
them, but a separate clone needs it pushed. `git rev-parse --short HEAD` of the
work is usually right — confirm a peer could have it with `git branch -r
--contains <sha>`, and if no remote branch lists it, name one on the default
branch instead.

A SHA only you can resolve excludes everyone, which is the expensive direction.
It is also the protocol's one false negative: a separate clone that has not
fetched since you pushed will fail the test correctly and be excluded wrongly.
Sibling worktrees share the object store and never have this problem.

You cannot know when another clone last fetched, so do not try to pick a SHA
old enough to be safe. When the work you are announcing is recent and a peer
might be a separate clone, name a second, older SHA from the same repo and say
that either one resolving is enough. Any commit that has been on the default
branch for a while does the job — it is one they have if they have the repo at
all, and it costs the recipient the same single command.

## Receiving: one command

```sh
git cat-file -t <sha>   # non-zero exit: discard the message
```

Test the **exit status**, not the message. `Not a valid object name` (wrong
repo) and `not a git repository` (no repo here at all) both exit non-zero and
both mean the same thing; the wording varies by git version.

Discarding costs nothing and needs no reply. If the sender is waiting on you,
send one line with the failing command and stop — do not open a negotiation
about whether it was meant for you.

## The test scopes action, not correspondence

A reply has an addressee. It goes to whoever wrote to you, and "was this meant
for me" is already answered by the fact that you were written to — so a reply
carries no test, however stateful it is. A broadcast has no addressee, which is
the only reason the test exists at all.

Name a SHA in a reply where it anchors something the reader will look up; do
not attach the test to it. Asking a session that has just told you it is in the
repo to prove it is in the repo is ritual, and a ritual test gets read as noise,
then ignored, then deleted — taking the real one with it.

The ordering rule is not an exception: a reply that carries steps still puts
what they are against above them.

## Why a SHA and not an identity

Naming a SHA does not identify the recipient. **It tests capability, and only
capability is decidable by the recipient.** "Was this meant for me" cannot be
answered reliably from either end; "can I act on this" is one command.

It also degrades correctly. `showcase-8d` is started in `workspace` by every
outward sign, yet resolves `andrei.md` SHAs fine, because it has an `andrei.md`
worktree and does nearly all its building there. A session in two repos should
answer yes to broadcasts for both — and no scheme assigning one label per
session can reproduce that, which is why the label was never the missing piece.

## Over-include on purpose

A wasted message costs a peer ten seconds of reading. A false negative excludes
a session part-way through the work the message concerns, which is the thing
the scoping was for. **When in doubt, send.** Recipients are free; senders are
guessing.

## Do not build a detector

The detector cannot exist. Everything the machine can tell you about another
session is a hint with a named blind spot:

| Hint | Actually answers | Blind spot |
|---|---|---|
| `/proc/<pid>/cwd` — each session is a `claude` process, named by `/run/user/0/cc-socks/<pid>.sock` | where the session was **started** | a session reaching another repo by absolute path never moves its cwd, and some harnesses reset cwd after every command |
| descendant process cwds | where a long-lived child (a preview server) lives | a session doing pure edits still looks like its start directory |
| a declared repo list, cwd as the default | the unusual session, for one line of config | still one label per session; a two-repo session breaks it |

Use them to decide whom to send to *first*, or whom to ask. Never to decide
whom to leave out. `/proc` is the dangerous one precisely because it resolves
every session cleanly and looks authoritative.

For the same reason, do not put your scoping guess in the message. "You are the
only live session in this repo" is a claim you cannot support, and the
recipient is about to check it in one command anyway.

Background — the two incidents and why inference was abandoned:
`docs/adr/20260912-session-repo-inference.md` in the dotfiles repo. (The
capability framing is `showcase-8d`'s; the `git cat-file` test is the
bounced session's.)
