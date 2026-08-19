---
type: ADR
status: rejected
date: 2026-08-11
summary: A SubagentStop hook probe is delivered to the subagent, which answers
  it instead of returning its work, silently destroying the return value.
---

# Probing for ADRs on SubagentStop

## Context

Delegated agents discover things the parent never sees. A subagent that tries
an approach and abandons it returns a conclusion, not the dead end — so the
delegation boundary looked like the right place to capture knowledge that would
otherwise be discarded. `SubagentStop` fires there and accepts
`additionalContext`, so the mechanism appeared to exist.

## What was tried

A `SubagentStop` hook running `adr-probe.sh subagent`, emitting:

> Before returning: does your work encode a decision, or record an approach
> tried and abandoned? If yes, invoke record-decision. If no, return silently.

with a separate branch for `Explore` and `Plan`, which hold every tool except
`Write` and so cannot record anything themselves.

## How it failed

The probe replaced the subagent's return value instead of accompanying it.

A code reviewer dispatched during this project's own build completed a full
review — 44k tokens, seven tool calls — and then returned exactly
`No decision to record.` It had answered the probe. The review was gone.

`additionalContext` on `SubagentStop` is documented as *"non-error feedback
delivered to the subagent"*. Its purpose is to tell an agent to keep working.
There is no channel there for a question the agent should act on without
altering what it returns, and "return silently" reads as an instruction about
the final message.

The failure is silent. It was caught only because that reply was visibly not a
code review. A subtler task would have returned something plausible and the
loss would never have been noticed.

## What would make it viable

Nothing available today. Rewording was considered — telling the agent its final
message must be preserved — but that relies on model compliance for a failure
mode that is undetectable when it recurs, and the cost of a miss is the primary
work product.

It would become viable if the harness gained a channel that delivers to the
**parent** on subagent completion, the way `PostToolUse` delivers to the caller.
`PostToolUse` works precisely because the probe sits beside the tool result
rather than in place of it.

Nothing was lost by removing it: the parent already receives the subagent's
findings in the return value and can record them, and commit-time capture still
fires in the parent when that work lands.

## Consequences

`adr-probe.sh` keeps only `commit` mode. The `agent_type` inspection and the
`Explore`/`Plan` branch went with it — the sole remaining caller passes a fixed
mode, so the argument survives only as a guard against a future second caller.
