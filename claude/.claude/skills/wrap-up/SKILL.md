---
name: wrap-up
description: Wrap up a session — stop its background work and servers, return the branches, worktrees and files it made, name what exists only in the conversation, and report what is not yours to touch. Use when the user asks for a wrap-up or says the session is over, when the work is handed off, before saying a task is finished, and before a /clear.
---

# Wrap-up

A wrap-up returns everything this session took, then says what it could not
return and what nobody has written down yet. Most of what a session leaves
behind it does not remember starting: a script that left a preview server up
by design, a branch `git branch -d` refused because its upstream ref was stale.
Recalling what the session did finds neither; the ledger and the checks below
do.

## 0. The repo's own wrap-up comes first

```sh
sh ${CLAUDE_SKILL_DIR}/ledger.sh project-skill
```

If it prints a path, this repo wrote its own wrap-up. **Read that file and
follow it instead of this one, from its first line; stop reading here.** It
knows the repo's servers, build output and shared resources. Where it writes
`${CLAUDE_SKILL_DIR}`, read the directory that file is in. Wherever it says
the ledger is, also run `sh ${CLAUDE_SKILL_DIR}/ledger.sh open`: a
session-start note may have had this session record there instead, and
every open item it lists is this session's too. Each `before /clear:` line it
prints names an earlier session ID of this session: the repo's ledger under
that ID is this session's as well, and the transcript beside it is read in its
step for what the conversation holds.

If it prints nothing, carry on.

## The one rule

**Return what is yours. Report everything else.**

Branches, worktrees, the stash, servers and `/tmp` are shared with sessions
you cannot see. A server or branch you did not start is evidence of another
session's work, not of a leak; two sessions have each mistaken the other's for
one. Reporting more and removing less is always the right trade.

## The ledger

Yours means **named in the ledger**: a session-start note asked for one line
each time this session made something that outlives a command. Read it:

```sh
sh ${CLAUDE_SKILL_DIR}/ledger.sh open
```

It lists every `taken:` line with no matching `returned:` line. As you return
each item below, append its line, so a later wrap-up in this session starts
where this one ends:

```sh
sh ${CLAUDE_SKILL_DIR}/ledger.sh returned 'branch feat/x (deleted after #12)'
```

An item matches on the text before its trailing note, so copy it exactly. The
ledger is append-only; never edit or delete it.

**A `/clear` starts a new session ID.** A hook carries the open items across
into the new ledger, and `ledger.sh open` then prints a `before /clear:` line
with the earlier ID and the transcript of the conversation before it. The
items survive a `/clear`; the conversation does not, which is why a `/clear`
is safe only after a wrap-up.

**No ledger, or a gap in it:** say so in the report, and return only what you
can tie to this session with certainty, such as a background task this
conversation started or a branch whose PR you opened in it. A glob or a name
pattern is never that certainty: `feat/*` once swept up another session's two
branches.

**This is the weaker half.** Most sessions end abruptly and never reach a
wrap-up. Run it as the best effort; build nothing that depends on it having
run.

## 1. Background work

Stop this session's background work first, so nothing restarts a server or
rewrites a file after you return it: each background task and Monitor still
running (TaskStop), and each loop or cron this session scheduled (CronList,
then CronDelete).

Then look for what outlived the command that started it:

```sh
sh ${CLAUDE_SKILL_DIR}/ledger.sh procs
```

It lists **candidates**: every process whose working directory is inside this
worktree, leaving out your own shell, Claude and nested worktrees. Another
session in the same checkout, a terminal pane opened here and an MCP server
show too, and a process started elsewhere (a server run with `-C`) does not,
so the ledger still decides. Kill by pid, and only a pid you can tie to this
session; report the rest with their age. `pkill -f` and
`pgrep -f` match the Bash tool's own wrapper, so `pkill` kills your shell
(exit 144) and a `pgrep` wait loop never ends.

**Done when:** no task, Monitor or schedule of this session is running, and
every other long-running process is reported or known to be someone else's.

## 2. Servers

For each server in the ledger, find its pid by port and stop it:

```sh
ss -ltnp 'sport = :<port>'
```

A server the user was reviewing on is the one judgement here. **If they asked
for the wrap-up, the review is over: stop it without asking.** If you are
wrapping up on your own initiative, a review may still be going: leave it, and
say so. A listener that is not in the ledger is reported with its port.

**Done when:** nothing in the ledger is listening, or what is left up is named
with the review it serves.

## 3. Files outside git's view

`git status` never shows ignored files or anything outside the worktree, so
look for them:

```sh
git status --porcelain --ignored | grep '^!!'
```

Remove each file the ledger names, by its exact path as `ledger.sh open`
prints it, and the output of each build this conversation ran in the worktree. **Remove by exact path only.**
`/tmp` and every scratchpad beside yours hold files you cannot tell from your
own; `rm /tmp/name.*` reached for them once. `git clean -X` takes every ignored
file, including the machine's own local config, and is never part of a
wrap-up.

**Done when:** every file in the ledger is returned, and no output of this
session's is left among the ignored files, other than what the report names.

## 4. Git

```sh
git fetch origin --prune
git worktree list
git stash list
```

**`--prune` first.** `git branch -d` checks against the branch's upstream
ref, and until a prune GitHub's deletion on merge is invisible, so the refusal
reads "not fully merged" and is not true.

- **Branches and the main checkout:** the global `CLAUDE.md`, "After a PR
  merges", has the rules, applied to branches in the ledger.
- **Worktrees:** the one you are in belongs to whoever created it for you (a
  herdr worktree is herdr's). Remove a worktree the ledger names:
  `git worktree remove <path>`.
- **The stash:** read, never pop. Apply an entry of yours by SHA and drop it by
  its tag; every other entry stays, and is counted in the report.
- **PRs:** for each PR in the ledger, `gh pr view <n> --json state` and
  `gh pr checks <n>`, and report both. Merging is not a wrap-up step: merge
  only one the user already asked you to merge. Every other open PR on the
  repo, yours by author or not, belongs to whichever session opened it.

**Done when:** `git status --porcelain` prints nothing, **read unfiltered**; no
branch, worktree or stash entry from the ledger remains unless the report says
why; and every PR in the ledger is merged or reported with its checks.

## 5. What would be forgotten

The next session cannot read this one. Read back over the conversation for
anything that exists only in it, starting with the **signals**: places where
how the session worked cost something, which nobody checking whether the work
got done will see.

- a **correction** from the user, quoted;
- a **claim retracted** after it was made;
- **work done twice**: a revert, a redo, a fix-up commit;
- a **check that passed, or failed, for the wrong reason**;
- a **rule obeyed in letter and missed in spirit**.

The scope is the session since the `last reviewed:` line `ledger.sh open`
printed, or the whole session if there is none. A session that began with
`/clear` started before it: read each transcript a `before /clear:` line names,
back to that boundary, as part of the session. It is JSONL; the user's side,
where corrections are, reads out with:

```sh
jq -r 'select(.type == "user") | .message.content | if type == "string" then . else (map(.text? // empty) | join(" ")) end' <transcript>
```

Count signals against what you
examined, so the count is checkable. Several with one cause are one
**finding**: what happened, its evidence, and the cause in the method rather
than the code. No signals is a valid result, and then this is one line.

| Found in the session | Capture |
|---|---|
| A finding a rule or memory already covered, and was missed | sharpen that rule: it did not fire, so its wording is the defect |
| Any other finding | a check if one can hold it; else the repo's agent docs; else a memory |
| A decision agreed in chat, or an approach tried and dropped | an ADR, via `/record-decision` |
| A defect or gap noticed and not fixed | an issue in the repo's tracker |
| A promise ("I'll do that next") or work in flight | an issue, or the PR it belongs to |
| A standing instruction or correction from the user | a memory |

Issues are part of finishing and need no agreement. Name an ADR, a memory or a
rule change, and make it once the user agrees. A capture made in the repo is a
change like any other, so step 4's **Done when** is checked again after it.
Then record where the review ran to:

```sh
sh ${CLAUDE_SKILL_DIR}/ledger.sh reviewed '<HEAD sha, or the last request covered>'
```

**Done when:** the signals are counted, and every finding and item is captured
or named in the report with its suggested capture.

## The report

Numbers, because they are checkable and a claim is not:

```
tree: 0 changes (git status --porcelain | wc -l, unfiltered) · HEAD: <branch> @ <sha>
ledger: <n> taken, <n> returned, <n> open (each named, with why) | not kept
background: 0 · servers: stopped | left for review of <what> · others reported: <n>
branches deleted: <names> · worktrees: <n> · stash: <n>, <n> mine
PRs in the ledger: <number: state, checks> · main checkout: <sha> | untouched, why
signals: <n> (<what was examined>) · findings: <n>
not captured: <each finding and item, with its suggested capture>
left running on purpose: <what, and why>
/clear: safe | not yet: <what is still open or uncaptured>
```

The last line answers the user's next move. **`/clear` is safe only when the
ledger shows 0 open and step 5 is done**: a `/clear` carries the ledger but
drops the conversation, and step 5 is the one step that reads it. Anything
open is named, so the user can choose to clear anyway.

**Ready to close means every line is zero or names a reason**, and the tree
line takes no general reason. `git status --porcelain` prints nothing, or every
path it prints is listed by name in the report as there before this session or
another session's, and left alone: never "nothing of mine", never "nothing but
build output", never a filter. A `grep -v` on that check once reported "0
changes" over sixteen untracked files, and the session called itself ready to
close.
