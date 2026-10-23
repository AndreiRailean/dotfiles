# Project conventions

Since 2.1.277 Claude Code loads `AGENTS.md` itself, but only as a fallback for
a project with no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`. Any one
of those, including a gitignored `CLAUDE.local.md` on one machine, switches the
fallback off and drops `AGENTS.md`. This file imports it explicitly so every
session in this repo is handed the conventions whatever else is lying around.

Keep it a pointer. The rules themselves belong in the `record-decision` skill
body and `docs/agents/domain.md`, never here — see
[docs/adr/20260809-rules-in-skill-body.md](docs/adr/20260809-rules-in-skill-body.md)
for the token accounting behind that.

@AGENTS.md
