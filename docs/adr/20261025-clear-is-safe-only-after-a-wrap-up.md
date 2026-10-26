---
type: ADR
status: accepted
date: 2026-10-25
summary: A /clear detaches a session from its ledger and its conversation; a
  SessionEnd/SessionStart handoff through the shared claude PID carries the
  ledger across, and the wrap-up report says when a /clear is safe.
---

# A /clear is safe only after a wrap-up

## Context

Andrei found that a `/clear` mid-session breaks `/wrap-up`. Read in the 2.1.310
binary: `/clear` fires `SessionEnd` with `reason: "clear"` under the old session
ID, then `SessionStart` with `source: "clear"` under a new one, and keeps the
old conversation on disk as a resumable transcript. The ledger is keyed by
session ID (20261024-global-wrap-up-shadows-and-hands-over), so everything
recorded so far landed under a name nothing read, and step 5 of the wrap-up,
which reads back over the conversation, lost what it reads.

A hook cannot stop a `/clear`, and no hook payload names the previous session
ID; it appears only in telemetry (`tengu_session_start.previous_session_id`).

## Decision

Carry what can be carried, and say when clearing is safe.

- `ledger-probe.sh` also runs at `SessionEnd`. On `reason: clear` it calls
  `ledger.sh clear-out`, which writes `cleared.<claude pid>` holding the old ID
  and its `transcript_path`. The `SessionStart(clear)` right after runs in the
  same claude process, so `clear-in` finds that file by the same PID, appends
  the old ledger's open items, review boundary and earlier `/clear`s to the new
  ledger under a `cleared-from:` line, and deletes the handoff. The PID comes
  from `CLAUDE_PID`, which Claude sets for the commands it runs, or the nearest
  ancestor whose command is `claude`.
- The probe then names the old ID and the transcript, even in a repo that
  keeps its own ledger, since telik's is keyed by session ID as well.
- The skill reads those transcripts in step 5, and its report ends with
  `/clear: safe | not yet`: safe only when the ledger shows 0 open and step 5
  is done. The description triggers on "before a /clear", so saying so is
  enough to start a wrap-up.

## Consequences

The ledger survives a `/clear`; the conversation only survives as a file to be
read, which costs a wrap-up more than reading its own context. That is why the
rule stays: clear after a wrap-up, not instead of one.

The handoff file lives only between two hooks fired back to back. One left by a
crash between them is keyed to a PID that will not be reused soon, and the next
`clear-out` from that PID overwrites it.
