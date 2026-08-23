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
