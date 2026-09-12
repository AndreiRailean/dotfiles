# Project conventions

Claude Code does not read `AGENTS.md` — as of 2.1.269 the only place the CLI
mentions that filename is the `/import` path that migrates a Codex project
*into* a `CLAUDE.md`. Without this file, every Claude session in this repo
rediscovers the conventions instead of being handed them.

Keep it a pointer. The rules themselves belong in the `record-decision` skill
body and `docs/agents/domain.md`, never here — see
[docs/adr/20260809-rules-in-skill-body.md](docs/adr/20260809-rules-in-skill-body.md)
for the token accounting behind that.

@AGENTS.md
