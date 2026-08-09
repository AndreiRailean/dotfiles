# Automatic ADR Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make architectural decisions and rejected approaches get written to `docs/adr/` automatically, without the user invoking anything.

**Architecture:** Two Claude Code hooks (`PostToolUse` on Bash, `SubagentStop`) run a tiny POSIX shell script that emits a ~25-token probe question. The probe performs no judgment and writes no files. A model-invocable `record-decision` skill decides the answer and writes the record. The repo owns the *format* (`docs/agents/domain.md`); the machine owns the *triggering* (dotfiles-deployed skill + hooks).

**Tech Stack:** POSIX `sh`, GNU Stow, Claude Code hooks (`settings.json`), Markdown with YAML frontmatter. Tests are POSIX `sh` using `tests/lib.sh`.

**Spec:** `docs/superpowers/specs/2026-08-09-adr-capture-design.md`

## Global Constraints

- **POSIX `sh`, not bash.** `tests/run.sh` invokes `sh "$t"`. No `[[`, no arrays, no `local`.
- **No GNU-only tools.** These dotfiles run on macOS, WSL and Linux. No `find -printf`, no `sort -V`, no `readlink -f`.
- **`adr-probe.sh` must always `exit 0`.** It runs on every Bash tool call; a non-zero exit must never disrupt a session.
- **No subprocesses on the hot path.** Commit-mode matching uses shell `case` only. `sed` is permitted in subagent mode, which fires rarely.
- **Conventional Commits**, per `AGENTS.md`: `type(scope): description`, imperative, lower-case subject, why in the body.
- **Branch:** all work on `feat/adr-capture`. Do not commit to `master`.
- **Leave `claude/.claude/settings.json`'s existing uncommitted changes alone** — they are unrelated plugin churn. Stage only the `hooks` key you add.
- **ADR filenames:** `YYYYMMDD-slug.md`, no `ADR-` prefix, in `docs/adr/`.
- **ADR frontmatter required fields:** `type`, `status`, `date`, `summary`.
- **Status values:** `proposed | accepted | rejected | superseded | deprecated`.

## File Structure

| File | Responsibility |
|---|---|
| `claude/.claude/hooks/adr-probe.sh` | **Create.** Emit the probe. No judgment, no writes. |
| `claude/.claude/skills/record-decision/SKILL.md` | **Create.** Gates, statuses, procedure. Loaded on invoke. |
| `claude/.claude/settings.json` | **Modify.** Add `hooks` key registering the probe. |
| `docs/agents/domain.md` | **Modify.** Promote to the repo's ADR format contract. |
| `docs/adr/0001-no-shared-shell-library.md` | **Rename + reformat** to `20260805-no-shared-shell-library.md`. |
| `tests/test-adr-probe.sh` | **Create.** Probe behaviour + hook wiring. |
| `tests/test-adr-format.sh` | **Create.** Every `docs/adr/*.md` conforms to the contract. |

`claude` is already in `PACKAGES` (`install.sh:156`, `doctor.sh:24`), so no install wiring changes are needed.

---

### Task 1: The probe script

**Files:**
- Create: `claude/.claude/hooks/adr-probe.sh`
- Test: `tests/test-adr-probe.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `adr-probe.sh commit|subagent`, reading hook payload JSON on stdin, writing either nothing or one line of JSON `{"hookSpecificOutput":{"hookEventName":..., "additionalContext":...}}` to stdout. Always exits 0.

- [ ] **Step 1: Write the failing test**

Create `tests/test-adr-probe.sh`:

```sh
#!/bin/sh
# adr-probe.sh emits a probe question when something ADR-worthy may have
# happened, and stays silent otherwise. It runs on EVERY Bash tool call, so
# "stays silent and exits 0" is the property that matters most — a probe that
# errors or chatters would be noticed on every command the agent runs.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/adr-probe.sh"

[ -x "$PROBE" ] && pass "adr-probe.sh exists and is executable" \
  || fail "adr-probe.sh exists and is executable"

# ── commit mode ───────────────────────────────────────────────
# Fires on a successful git commit.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"[main abc1234] x\n 1 file changed"}}' | sh "$PROBE" commit)"
assert_contains "$out" 'hookSpecificOutput' "commit mode emits hookSpecificOutput"
assert_contains "$out" 'PostToolUse' "commit mode names the PostToolUse event"
assert_contains "$out" 'record-decision' "commit mode names the skill to invoke"

# Silent on any other Bash command. This is the common case by a wide margin.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"stdout":"a b c"}}' | sh "$PROBE" commit)"
assert_eq "$out" "" "commit mode is silent on a non-commit command"

# Silent when the commit did nothing. An empty commit is not a decision.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"nothing to commit, working tree clean"}}' | sh "$PROBE" commit)"
assert_eq "$out" "" "commit mode is silent when nothing was committed"

# ── subagent mode ─────────────────────────────────────────────
# Write-capable agents are told to record it themselves.
out="$(printf '%s' '{"agent_type":"general-purpose","agent_id":"a1"}' | sh "$PROBE" subagent)"
assert_contains "$out" 'SubagentStop' "subagent mode names the SubagentStop event"
assert_contains "$out" 'record-decision' "write-capable agent is told to invoke the skill"

# Explore and Plan are defined as all tools EXCEPT Write, so telling them to
# write a file sends them into a wall. They report back as text instead.
out="$(printf '%s' '{"agent_type":"Explore","agent_id":"a2"}' | sh "$PROBE" subagent)"
assert_contains "$out" 'final message' "write-less agent is told to report as text"
assert_not_contains "$out" 'invoke record-decision' "write-less agent is not told to write"

# ── never disruptive ──────────────────────────────────────────
# Unknown mode, empty stdin, garbage stdin: all silent, all exit 0.
printf '' | sh "$PROBE" commit >/dev/null 2>&1
assert_eq "$?" "0" "empty stdin exits 0"
printf 'not json at all' | sh "$PROBE" subagent >/dev/null 2>&1
assert_eq "$?" "0" "malformed stdin exits 0"
printf '{}' | sh "$PROBE" bogus-mode >/dev/null 2>&1
assert_eq "$?" "0" "unknown mode exits 0"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-adr-probe.sh`
Expected: FAIL — `adr-probe.sh exists and is executable`, then further failures because the script is absent.

- [ ] **Step 3: Write minimal implementation**

Create `claude/.claude/hooks/adr-probe.sh`:

```sh
#!/bin/sh
# adr-probe.sh — ask whether something ADR-worthy just happened.
#
# WHY THIS FILE EXISTS: knowledge only gets captured if the question gets
# asked. A skill that must be invoked by hand never fires — /handoff produces
# good output and still goes unused, because remembering to run it is the part
# that fails. So the question is hung off events that fire on their own.
#
# This script deliberately performs NO judgment and writes NO files. It emits a
# short probe and exits. That keeps it fast, independently testable, and unable
# to corrupt a repo. Deciding whether a record is warranted, and writing it, is
# the record-decision skill's job.
#
# It runs on EVERY Bash tool call, so the commit path uses shell `case` only —
# no sed, no grep, no subprocesses. It must always exit 0: a hook that fails is
# a hook that disrupts every command the agent runs.
#
# Usage: adr-probe.sh commit|subagent   (hook payload JSON on stdin)

set -u

mode="${1:-}"
payload="$(cat 2>/dev/null || true)"

# $1 = hookEventName, $2 = probe text
emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$2"
}

case "$mode" in
  commit)
    # Matchers match the tool NAME, not the command text, so this fires on
    # every Bash call and has to filter here.
    case "$payload" in
      *'git commit'*) ;;
      *) exit 0 ;;
    esac
    # A commit that changed nothing is not a decision.
    case "$payload" in
      *'nothing to commit'*) exit 0 ;;
    esac
    emit PostToolUse "A commit just landed. Does it encode a decision, or record an approach tried and abandoned? If yes, invoke record-decision. If no, continue silently."
    ;;
  subagent)
    # Explore and Plan are defined as all tools EXCEPT Write. Telling them to
    # write a file sends them into a wall, so they report back as text and the
    # parent records it.
    agent_type=$(printf '%s' "$payload" | sed -n 's/.*"agent_type":"\([^"]*\)".*/\1/p')
    case "$agent_type" in
      Explore|Plan)
        emit SubagentStop "Before returning: if you found a decision or a dead end worth recording, state it plainly in your final message. You do not have Write access, so the parent will record it."
        ;;
      *)
        emit SubagentStop "Before returning: does your work encode a decision, or record an approach tried and abandoned? If yes, invoke record-decision. If no, return silently."
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

exit 0
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x claude/.claude/hooks/adr-probe.sh
sh tests/test-adr-probe.sh
```

Expected: PASS (all assertions, ending `PASS`).

- [ ] **Step 5: Run the whole suite to check nothing regressed**

Run: `sh tests/run.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/hooks/adr-probe.sh tests/test-adr-probe.sh
git commit -m "feat(claude): add ADR probe hook script

The probe asks whether a commit or a returning subagent produced something
worth recording, and does nothing else. Judgment and writing belong to the
record-decision skill; keeping them apart means the script can run on every
Bash call without risk.

Explore and Plan hold every tool except Write, so they get a different probe
telling them to report as text rather than walk into a wall."
```

---

### Task 2: Register the hooks

**Files:**
- Modify: `claude/.claude/settings.json`
- Modify: `tests/test-adr-probe.sh` (append a wiring section)

**Interfaces:**
- Consumes: `adr-probe.sh` from Task 1, at `$HOME/.claude/hooks/adr-probe.sh` once stowed.
- Produces: a `hooks` key in `settings.json` with `PostToolUse` (matcher `Bash`) and `SubagentStop` entries.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-adr-probe.sh`, **before** the final `finish` line:

```sh
# ── hook wiring ───────────────────────────────────────────────
# The script is only useful if settings.json actually calls it. These two drift
# apart silently: a renamed script or a typo'd path produces no error anywhere,
# just a system that quietly stops capturing.
SETTINGS="$REPO/claude/.claude/settings.json"
cfg="$(cat "$SETTINGS")"
assert_contains "$cfg" '"PostToolUse"' "settings.json registers PostToolUse"
assert_contains "$cfg" '"SubagentStop"' "settings.json registers SubagentStop"
assert_contains "$cfg" 'adr-probe.sh commit' "PostToolUse calls the probe in commit mode"
assert_contains "$cfg" 'adr-probe.sh subagent' "SubagentStop calls the probe in subagent mode"
assert_contains "$cfg" '"matcher": "Bash"' "PostToolUse matches the Bash tool"

# The path in settings.json must be the one stow creates.
assert_contains "$cfg" '$HOME/.claude/hooks/adr-probe.sh' "hook path matches the stow target"

# Valid JSON, or Claude Code silently ignores the whole settings file.
if python3 -c "import json,sys; json.load(open('$SETTINGS'))" 2>/dev/null; then
  pass "settings.json is valid JSON"
else
  fail "settings.json is valid JSON"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-adr-probe.sh`
Expected: FAIL — `settings.json registers PostToolUse` and the following wiring assertions.

- [ ] **Step 3: Add the hooks block**

Edit `claude/.claude/settings.json`. Insert this `hooks` key as a top-level sibling of `permissions` (leave every other key, including the uncommitted plugin changes, untouched):

```json
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "sh $HOME/.claude/hooks/adr-probe.sh commit"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh $HOME/.claude/hooks/adr-probe.sh subagent"
          }
        ]
      }
    ]
  },
```

- [ ] **Step 4: Run the tests**

```bash
sh tests/test-adr-probe.sh
sh tests/run.sh
```

Expected: `PASS`, then `ALL TESTS PASSED`.

- [ ] **Step 5: Verify the JSON by hand**

Run: `python3 -m json.tool claude/.claude/settings.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/settings.json tests/test-adr-probe.sh
git commit -m "feat(claude): register the ADR probe on commit and subagent return

PostToolUse matchers match the tool name rather than the command text, so the
probe fires on every Bash call and filters for git commit itself.

The wiring test exists because these two drift apart silently: a renamed
script or a mistyped path raises no error anywhere, it just stops capturing."
```

> **Note:** if `git status` shows unrelated plugin changes in `settings.json`, use `git add -p` and stage only the `hooks` hunk.

---

### Task 3: The record-decision skill

**Files:**
- Create: `claude/.claude/skills/record-decision/SKILL.md`

**Interfaces:**
- Consumes: the probe text from Task 1, which names `record-decision`.
- Produces: a model-invocable skill named `record-decision`. Auto-loads next session as `record-decision@skills-dir`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-adr-skill.sh`:

```sh
#!/bin/sh
# The record-decision skill is the half of the system that exercises judgment.
# These assertions pin the properties that make it fire at all: it must be
# model-invocable, and its description must carry the triggers, because only
# the description is in context when the decision to invoke is made.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SKILL="$REPO/claude/.claude/skills/record-decision/SKILL.md"

[ -f "$SKILL" ] && pass "SKILL.md exists" || fail "SKILL.md exists"
body="$(cat "$SKILL" 2>/dev/null)"

assert_contains "$body" "name: record-decision" "skill declares its name"

# The whole point. disable-model-invocation is what makes the mattpocock
# slash-commands inert unless typed, and inert is the failure being fixed.
assert_not_contains "$body" "disable-model-invocation" "skill is model-invocable"

# Only the description is always in context, so the triggers must live there.
desc="$(sed -n 's/^description: //p' "$SKILL")"
assert_contains "$desc" "abandoned" "description names the abandoned-approach trigger"
assert_contains "$desc" "commit" "description names the commit trigger"

# Both gates must be stated or the model invents its own threshold.
assert_contains "$body" "hard to reverse" "body states the decision gate"
assert_contains "$body" "plausibly try this again" "body states the rejection gate"

# The five statuses.
for s in proposed accepted rejected superseded deprecated; do
  assert_contains "$body" "\`$s\`" "body documents the $s status"
done

# Redaction: rejection records quote error output, which quotes credentials.
assert_contains "$body" "Redact" "body requires redaction"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-adr-skill.sh`
Expected: FAIL — `SKILL.md exists`, and every assertion after it.

- [ ] **Step 3: Write the skill**

Create `claude/.claude/skills/record-decision/SKILL.md`:

````markdown
---
name: record-decision
description: Write an architectural decision or a rejected approach to docs/adr/ as an ADR. Use when a decision is made that would be hard to reverse, when an approach has been tried and abandoned, when a commit lands that encodes either, or when a delegated agent returns having discovered either.
---

# Record a decision

Write the record now, while the reasoning is present. Do not ask permission
first — the record lands in the working tree and is reviewed in the diff like
any other file. Over-capture is recoverable; silent under-capture is not.

## Should this be recorded at all?

Two gates. Answer one of them, not both.

**A decision** — all three must hold:

1. Hard to reverse — the cost of changing your mind later is meaningful.
2. Surprising without context — a future reader will wonder why it was done
   this way.
3. The result of a real trade-off — there were genuine alternatives.

**A rejection** — one test:

> Would a competent person plausibly try this again?

Both also require repo-specificity. "Postgres has advisory locks" is a general
fact. "Advisory locks deadlock under our access pattern" is a record.

If neither gate passes, stop and say nothing.

An alternative dismissed **on paper** is not a rejection record — it is a
`Considered Options` section in the deciding ADR. A rejection record is for an
approach someone actually spent effort on.

## Where records go

Read `docs/agents/domain.md` first — it is the repo's format contract and
overrides anything here if the two disagree. It also says whether the repo is
single- or multi-context, and therefore which `docs/adr/` applies.

If `docs/agents/domain.md` has no ADR section, create `docs/adr/` and seed the
section using the format below, so the repo becomes self-describing to agents
that do not have this skill.

If the repo already uses sequential numbering (`0001-…`), leave those files
alone and write new records date-stemmed. Do not migrate.

## Status

| Status | Means |
|---|---|
| `proposed` | We are going to try this; outcome unknown |
| `accepted` | This is how it works |
| `rejected` | We tried it; it did not work |
| `superseded` | Was true, now replaced — set `superseded_by` |
| `deprecated` | No longer applies, nothing replaced it |

Records are append-only. Never delete one. A `rejected` record is the highest
value file in the directory: it is the only artifact that can stop a path being
re-tried, because the code contains no trace of it.

`rejected` may be entered directly, with no prior `proposed`. Most dead ends
are not deliberate choices made in advance.

## Format

Filename `docs/adr/YYYYMMDD-slug.md` — date-stem, no `ADR-` prefix.

```markdown
---
type: ADR
status: rejected
date: 2026-08-09
summary: One sentence, so the directory can be skimmed without opening files.
superseded_by: 20260815-other-record
---

# Short title, no ID

## Context
Why this came up.

## What was tried
Specific enough that someone about to re-attempt it recognises themselves.

## How it failed
The observable symptom, with numbers where they exist.

## What would make it viable
Or an explicit "nothing; this is structural".
```

For a decision, use **Context / Decision / Consequences** instead, the last
only if there are non-obvious downstream effects. Add `Considered Options` only
when the rejected alternatives are worth remembering.

Sections differ by status on purpose. Fixed headings across both would force
empty sections, and an empty section is worse than an absent one.

`superseded_by` and `supersedes` hold the filename **stem** exactly.

Length is whatever the reasoning requires. No template padding, no section
written because it exists. The minimum is a title, frontmatter, and a
paragraph.

## Procedure

1. **Check for a duplicate.** List `docs/adr/` for today's date-stem. Several
   triggers can fire on one decision. If a record already covers it, edit that
   record instead of adding another.
2. **Redact.** Rejection records quote error output, which quotes connection
   strings, tokens and hostnames. Remove them before writing.
3. **Write the file.**
4. **Commit separately.** The probe fires *after* a commit, so the record
   cannot join it. Use a follow-up commit — this matches the repo's "group
   related changes into separate, logical commits" convention:

   ```
   docs(adr): record why per-request pooling was rejected
   ```

   Reference the triggering commit by SHA in the body.
5. **Say one line** about what you recorded. Do not summarise the record back.
````

- [ ] **Step 4: Run the tests**

```bash
sh tests/test-adr-skill.sh
sh tests/run.sh
```

Expected: `PASS`, then `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/skills/record-decision/SKILL.md tests/test-adr-skill.sh
git commit -m "feat(claude): add the record-decision skill

Carries the two gates, the status lifecycle and the write procedure. Model
invocable by design: disable-model-invocation is exactly what leaves the
mattpocock slash-commands inert unless typed, and inert is the problem.

Only a skill's description sits in context permanently, so the triggers live
there and everything else in the body, which costs nothing until invoked. The
test pins both properties because losing either turns the skill off without
any visible failure."
```

---

### Task 4: Promote domain.md to the format contract

**Files:**
- Modify: `docs/agents/domain.md`
- Test: `tests/test-adr-format.sh`

**Interfaces:**
- Consumes: the format defined in Task 3.
- Produces: a `## Writing ADRs` section in `domain.md` that any agent can follow without this skill installed.

- [ ] **Step 1: Write the failing test**

Create `tests/test-adr-format.sh`:

```sh
#!/bin/sh
# docs/agents/domain.md is the repo's ADR format contract. It has to be
# complete on its own: a collaborator, a CI agent, or a session on a machine
# without these dotfiles has no record-decision skill, and the only thing
# telling them what a record looks like is this file.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
DOMAIN="$REPO/docs/agents/domain.md"

d="$(cat "$DOMAIN")"
assert_contains "$d" "## Writing ADRs" "domain.md has a production section"
assert_contains "$d" "YYYYMMDD-slug.md" "domain.md documents date-stem naming"
for s in proposed accepted rejected superseded deprecated; do
  assert_contains "$d" "\`$s\`" "domain.md documents the $s status"
done
for f in "type:" "status:" "date:" "summary:"; do
  assert_contains "$d" "$f" "domain.md documents the $f field"
done
assert_contains "$d" "overrides" "domain.md states it overrides bundled templates"

# The old sequential convention must be gone, or agents keep reading it.
assert_not_contains "$d" "0001-event-sourced-orders.md" "old sequential example removed"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-adr-format.sh`
Expected: FAIL — `domain.md has a production section`, plus the naming, status and field assertions.

- [ ] **Step 3: Update the two file-structure examples**

In `docs/agents/domain.md`, replace both occurrences of the sequential filenames in the tree diagrams:

```
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
```

with:

```
│   ├── 20260805-event-sourced-orders.md
│   └── 20260812-postgres-for-write-model.md
```

- [ ] **Step 4: Append the production section**

Add to the end of `docs/agents/domain.md`:

````markdown
## Writing ADRs

This section is the repo's format contract and **overrides any template
bundled with a skill or plugin**. `/domain-modeling` ships its own
`ADR-FORMAT.md` using sequential numbering and a bold status line; where the
two disagree, this file wins.

It is stated here, in the repo, rather than only in a skill, so that an agent
without this machine's dotfiles — a collaborator, a CI run, another harness —
can still produce a conforming record.

### When to write one

**A decision** needs all three: hard to reverse, surprising without context,
the result of a real trade-off.

**A rejection** needs one test: would a competent person plausibly try this
again? An approach dismissed on paper is a `Considered Options` section in the
deciding ADR, not a record of its own — a rejection record is for something
someone actually spent effort on.

### Naming

`docs/adr/YYYYMMDD-slug.md`. Date-stem, no `ADR-` prefix. Date-stems are minted
locally, so parallel agents and worktrees cannot collide the way sequential
numbering does.

Repos already using `0001-` style keep those files. New records are
date-stemmed; do not migrate.

### Frontmatter

`type`, `status`, `date` and `summary` are required. `supersedes` and
`superseded_by` hold a filename **stem** exactly.

```yaml
---
type: ADR
status: rejected
date: 2026-08-09
summary: One sentence, so the directory can be skimmed without opening files.
superseded_by: 20260815-other-record
---
```

### Status

| Status | Means |
|---|---|
| `proposed` | We are going to try this; outcome unknown |
| `accepted` | This is how it works |
| `rejected` | We tried it; it did not work |
| `superseded` | Was true, now replaced |
| `deprecated` | No longer applies, nothing replaced it |

Records are append-only — never delete one. `rejected` may be entered directly
without a prior `proposed`.

### Sections

Decisions use **Context / Decision / Consequences** (the last optional).
Rejections use **Context / What was tried / How it failed / What would make it
viable**.

They differ on purpose. Fixed headings across both would force empty sections,
and an empty section is worse than an absent one.

A rejection is only useful if it answers all three of: what was tried,
specifically enough to recognise a re-attempt; how it failed, with numbers
where they exist; and what would make it viable — or an explicit "nothing,
this is structural". The last distinguishes *don't do this* from *don't do
this yet*.

Length is whatever the reasoning requires. The minimum is a title,
frontmatter, and a paragraph.
````

- [ ] **Step 5: Run the tests**

```bash
sh tests/test-adr-format.sh
sh tests/run.sh
```

Expected: `PASS`, then `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add docs/agents/domain.md tests/test-adr-format.sh
git commit -m "docs(agents): promote domain.md to the ADR format contract

domain.md governed consumption only — read ADRs, use the glossary, flag
conflicts — and nothing said what writing one looks like. That left the format
living solely in a dotfiles-deployed skill, so a collaborator, a CI agent or
another harness had no way to produce a conforming record.

The repo now owns what a record IS and the machine owns when one gets written.
Also states that this file overrides any skill-bundled template, since
domain-modeling ships a conflicting one and auto-updates."
```

---

### Task 5: Migrate ADR-0001 and validate every record

**Files:**
- Rename: `docs/adr/0001-no-shared-shell-library.md` → `docs/adr/20260805-no-shared-shell-library.md`
- Modify: the renamed file's header
- Modify: `tests/test-adr-format.sh` (append a validator)

**Interfaces:**
- Consumes: the contract from Task 4.
- Produces: a validator that every `docs/adr/*.md` must pass, used by Task 6.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-adr-format.sh`, **before** the final `finish` line:

```sh
# ── every record conforms ─────────────────────────────────────
# Applies to the whole directory rather than a list, so records added later are
# covered without anyone remembering to extend this test.
for f in "$REPO"/docs/adr/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  c="$(cat "$f")"

  # Date-stem naming: 8 digits, a dash, a slug.
  echo "$n" | grep -q '^[0-9]\{8\}-.*\.md$' \
    && pass "$n uses a date-stem filename" \
    || fail "$n uses a date-stem filename"

  # Frontmatter must open on line 1 or the YAML is not parsed at all.
  assert_eq "$(head -1 "$f")" "---" "$n opens with frontmatter"

  for k in "type:" "status:" "date:" "summary:"; do
    assert_contains "$c" "$k" "$n has $k"
  done

  # Status must be one of the five.
  st="$(sed -n 's/^status: *//p' "$f" | head -1)"
  case "$st" in
    proposed|accepted|rejected|superseded|deprecated)
      pass "$n has a valid status ($st)" ;;
    *)
      fail "$n has a valid status (got '$st')" ;;
  esac

  # The old bold status line must not survive the migration.
  assert_not_contains "$c" "**Status:**" "$n does not use the old bold status line"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh tests/test-adr-format.sh`
Expected: FAIL — `0001-no-shared-shell-library.md uses a date-stem filename`, `opens with frontmatter`, the four field assertions, and `does not use the old bold status line`.

- [ ] **Step 3: Rename the file**

```bash
git mv docs/adr/0001-no-shared-shell-library.md docs/adr/20260805-no-shared-shell-library.md
```

- [ ] **Step 4: Convert the header**

In `docs/adr/20260805-no-shared-shell-library.md`, replace the first three lines:

```markdown
# ADR-0001 — No shared shell library (yet) between install.sh and doctor.sh

**Status:** accepted · **Date:** 2026-08-05
```

with:

```markdown
---
type: ADR
status: accepted
date: 2026-08-05
summary: install.sh and doctor.sh duplicate logic deliberately, enforced by a
  sync test rather than by comments, because a third consumer (drift.sh) is
  POSIX sh and cannot source a bash library.
---

# No shared shell library (yet) between install.sh and doctor.sh
```

Leave the rest of the file exactly as it is. The content is not being revised.

- [ ] **Step 5: Fix the inbound reference**

`tests/test-shared-logic-sync.sh` cites the ADR by its old number. Update the comment on line 12:

```
# whenever ~/dotfiles was itself a symlink (see docs/adr/0001).
```

to:

```
# whenever ~/dotfiles was itself a symlink (see docs/adr/20260805-no-shared-shell-library.md).
```

- [ ] **Step 6: Run the tests**

```bash
sh tests/test-adr-format.sh
sh tests/run.sh
```

Expected: `PASS`, then `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add -A docs/adr tests/test-adr-format.sh tests/test-shared-logic-sync.sh
git commit -m "docs(adr): migrate ADR-0001 to date-stem and frontmatter

Content unchanged; only the filename and header move to the new contract.
git mv preserves history.

The validator walks docs/adr/*.md rather than a list, so records added later
are covered without anyone remembering to extend the test."
```

---

### Task 6: Record this design's own decisions

**Files:**
- Create: `docs/adr/20260809-one-record-type-status-lifecycle.md`
- Create: `docs/adr/20260809-editing-plugin-cache-skills.md`
- Create: `docs/adr/20260809-rules-in-skill-body.md`

**Interfaces:**
- Consumes: the contract from Task 4 and the validator from Task 5.
- Produces: nothing consumed by later tasks. This is the system's first real output, written by hand because the machinery is not yet loaded.

> **Why this task exists:** the design produced three decisions that would
> otherwise be lost. The rejection in particular leaves no trace in any diff —
> it is exactly the class of knowledge the system is being built to catch, and
> catching it by hand once proves the format works before anything depends on it.

- [ ] **Step 1: Write the first record**

Create `docs/adr/20260809-one-record-type-status-lifecycle.md`:

```markdown
---
type: ADR
status: accepted
date: 2026-08-09
summary: Negative results are ADRs with status rejected rather than a separate
  document type, so the supersession link between a failure and its
  replacement survives.
---

# One record type, status carries the lifecycle

## Context

Capturing failed approaches needs somewhere to put them. `domain-modeling`'s
gate requires a decision to be hard to reverse, which excludes most dead ends —
they are abandoned precisely because they were cheap to abandon.

The first design used two document types: `type: decision` and
`type: negative-result`, each with its own admission gate.

## Decision

One type. Negative results are ADRs with `status: rejected`.

`rejected` may be entered directly, without a prior `proposed`, because most
dead ends are not deliberate choices made in advance — requiring an upfront
record for everything tried would drown the directory and would miss the
incidental discoveries worth keeping.

The two gates survive, selecting *status* rather than *type*: a decision needs
hard-to-reverse plus surprising plus a real trade-off; a rejection needs only
"would a competent person plausibly try this again?".

## Considered Options

**Two document types.** Keeps the differing gates visible in the filename, but
severs the link between a failure and what replaced it. Two disconnected facts
are worth less than the chain.

**Widening the decision gate** so dead ends qualify as ordinary ADRs. Simplest,
but dilutes the gate that keeps ADRs scarce, and forks further from upstream.

## Consequences

`rejected` is not upstream's `deprecated`. Deprecated means *was true, no
longer applies*; rejected means *never adopted*. Both are kept.
```

- [ ] **Step 2: Write the second record**

Create `docs/adr/20260809-editing-plugin-cache-skills.md`:

```markdown
---
type: ADR
status: rejected
date: 2026-08-09
summary: Editing domain-modeling in ~/.claude/plugins/cache to add proactive
  ADR writing is silently reverted by plugin auto-update.
---

# Editing skills in the plugin cache

## Context

`domain-modeling` almost does what is wanted: it has the gates, the format and
the ADR directory convention. It only declines to *write* — it is told to
"offer ADRs sparingly", and offering is what leaves the repo at one ADR in 88
commits. Changing "offer" to "write" is a two-word edit.

## What was tried

Editing `SKILL.md` and `ADR-FORMAT.md` in place under
`~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/`.

## How it failed

The marketplace entry in `settings.json` carries `"autoUpdate": true`. The next
plugin update overwrites the cache directory, reverting the edit with no
warning and no error. The system appears to work until it silently stops.

Two versions were already present on disk (`1.2.0` and `1.2.3`), so updates
were demonstrably happening.

## What would make it viable

Nothing while the plugin auto-updates. Setting `autoUpdate: false` would hold
the edit but freezes every other skill in the plugin, which is a worse trade.

The workable route is what was built instead: a separate `record-decision`
skill in the dotfiles-managed `~/.claude/skills/`, which nothing else writes
to. It duplicates the gates rather than sharing them, and that duplication is
the price of not being overwritten.
```

- [ ] **Step 3: Write the third record**

Create `docs/adr/20260809-rules-in-skill-body.md`:

```markdown
---
type: ADR
status: accepted
date: 2026-08-09
summary: ADR rules live in the skill body and in the repo's domain.md, never in
  AGENTS.md or CLAUDE.md, because those load in full on every request forever.
---

# ADR rules live in the skill body, not in always-loaded files

## Context

The rules — two gates, five statuses, the record format — have to be somewhere
an agent can reach. The obvious place is `AGENTS.md` or `CLAUDE.md`, which are
already read every session.

## Decision

Rules go in the `record-decision` skill body and in `docs/agents/domain.md`.
Neither `AGENTS.md` nor `CLAUDE.md` carries more than a pointer.

Skills load in two stages: frontmatter `name` and `description` sit in context
permanently, the body only on invocation. Measured on this machine, 46 skills
cost 4k tokens standing — roughly 87 each. So triggers go in the description,
where they must always be visible, and everything else in the body, where it
costs nothing until used.

The same reasoning governs the hook. Injecting the ruleset on every commit
would cost doc-size times commits-per-session — around 30k tokens a session —
to answer a question that is almost always "no". The probe is therefore a
pointer of about 25 tokens, never the rules.

## Consequences

A realistic session of 20 commits and 2 records costs roughly 3.6k tokens:
~85 standing, ~500 in probes, ~3k for the two skill-body loads.

The failure mode to watch for is someone "helpfully" moving the rules into
`CLAUDE.md` to make them more reliable. That would add their full size to every
request in every project, permanently, and this record exists to explain why
it was not done.
```

- [ ] **Step 4: Validate all three against the contract**

```bash
sh tests/test-adr-format.sh
sh tests/run.sh
```

Expected: `PASS` including the new files, then `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add docs/adr/20260809-*.md
git commit -m "docs(adr): record the decisions behind ADR capture

Three records the design produced. The rejection is the one that matters: it
leaves no trace in any diff, so without a record it exists only in a session
transcript that retention will eventually delete.

Written by hand because the machinery that would have caught them only loads
next session — which is itself the first useful test of the format."
```

---

### Task 7: End-to-end verification

**Files:**
- None created. This task is verification only.

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: confirmation the system is live, or a specific failure to fix.

- [ ] **Step 1: Stow the package**

```bash
cd ~/.dotfiles && ./install.sh
```

Expected: `Stowing claude...` with no conflict errors.

- [ ] **Step 2: Verify the symlinks landed**

```bash
ls -l ~/.claude/hooks/adr-probe.sh ~/.claude/skills/record-decision/SKILL.md
```

Expected: both exist as symlinks into `~/.dotfiles/claude/.claude/`.

- [ ] **Step 3: Verify doctor.sh reports no drift**

Run: `./doctor.sh`
Expected: no drift reported for the `claude` package.

- [ ] **Step 4: Exercise the probe through the real stowed path**

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"[main abc] x\n 1 file changed"}}' \
  | sh ~/.claude/hooks/adr-probe.sh commit
```

Expected: one line of JSON containing `record-decision`.

- [ ] **Step 5: Confirm the skill loads in a new session**

Start a fresh Claude Code session and run `/context`. Under **Skills**, expect
`record-decision` listed as `@skills-dir`.

This is the step that cannot be shortcut: `.claude/skills/` auto-loads *next*
session, never the one that installed it.

- [ ] **Step 6: Record the baseline**

```bash
echo "ADRs: $(ls docs/adr/*.md | wc -l)  Commits: $(git rev-list --count HEAD)"
```

Note the numbers in the PR description. The pre-change baseline was 1 / 88. The
meaningful signal over the following weeks is not a target count but whether
any `status: rejected` record appears without being asked for — under the
previous setup that rate was structurally zero.

- [ ] **Step 7: Open the PR**

```bash
git push -u origin feat/adr-capture
gh pr create --title "feat(claude): automatic ADR capture with negative results" --body-file - <<'EOF'
Implements `docs/superpowers/specs/2026-08-09-adr-capture-design.md`.

Baseline was 1 ADR across 88 commits. The cause was structural: nothing in the
toolchain produced ADRs. `docs/agents/domain.md` governed how agents *consume*
them, and production was delegated to `/domain-modeling`, which is user-invoked
and told to "offer" rather than write.

Two hooks now ask the question on their own — `PostToolUse` on `git commit` and
`SubagentStop` — and a model-invocable `record-decision` skill answers it.
The probe stays a ~25 token pointer, so a 20-commit session costs about 3.6k
tokens in total.

Negative results are captured as `status: rejected` rather than a separate
document type, keeping the link between a failure and its replacement.

`docs/agents/domain.md` is promoted to the repo's format contract so the
convention travels with the repo rather than with one machine's dotfiles.

## Verification
- `sh tests/run.sh` passes
- Probe exercised through the stowed path
- `record-decision` confirmed loading in a fresh session
EOF
```

---

## Self-Review

**Spec coverage.** Every section maps to a task: architecture → 1–3; status
lifecycle and record format → 3, 4; gates → 3, 4; commit sequencing → 3 step 3
procedure; token budget → 3 (description/body split), 1 (pointer-only probe);
degradation → 3 (`domain.md` seeding, sequential coexistence); dependencies and
portability → 4; failure modes → 1 (write-less agents, always-exit-0, empty
commits), 2 (wiring drift), 3 (redaction, dedup); migrations → 5; coexistence →
3, 4; verification → 7.

**Deliberately not implemented, and why.** The spec's *Known risk: two writers*
has no task — it is a documented hazard with a convention-level mitigation
(Task 4's "overrides" statement), not something code can enforce. The
out-of-scope items — session trailers, transcript archiving, CI enforcement,
`tags:`, a generated index — remain out of scope.

**Placeholder scan.** No TBD/TODO. Every code step carries the literal content.
Task 5's edits quote the exact lines being replaced.

**Type consistency.** `adr-probe.sh` takes `commit|subagent` in Tasks 1, 2 and
7. The probe text names `record-decision`, matching the skill's `name:` in Task
3 and the assertions in Tasks 1 and 3. The five statuses are identical across
Tasks 3, 4, 5 and 6. Required frontmatter — `type`, `status`, `date`,
`summary` — is identical in Tasks 3, 4, 5 and used by all three records in Task
6. `superseded_by` holds a filename stem in Tasks 3, 4 and 6.

**One known ordering constraint.** Task 5's validator walks `docs/adr/*.md`, so
it must run after Task 4 defines the contract and will police Task 6's records.
Running Task 6 before Task 5 leaves the new records unvalidated.
