# Project conventions

Cross-platform dotfiles (macOS, WSL, Linux) managed with GNU Stow. See
`README.md` for layout, bootstrap, and architecture.

## Commits

Always use [Conventional Commits](https://www.conventionalcommits.org):
`type(scope): description`.

- Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`.
- Scope is optional but preferred — use the package/area name, e.g.
  `feat(shell):`, `fix(tmux):`, `feat(install):`, `docs:`.
- Keep the subject imperative and lower-case; put the "why" in the body.
- Group related changes into separate, logical commits rather than one large one.

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues on `AndreiRailean/dotfiles` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
