# Global conventions

Personal defaults that apply to **all projects on this machine**. Deployed via
dotfiles, so they're the same on every machine. A project's own `CLAUDE.md`
(read after this one) takes precedence where they differ.

## Commits

Always use [Conventional Commits](https://www.conventionalcommits.org):
`type(scope): description`.

- Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`.
- Scope is optional but preferred — use the package/area name, e.g.
  `feat(auth):`, `fix(api):`, `docs:`.
- Keep the subject imperative and lower-case; put the "why" in the body.
- Group related changes into separate, logical commits rather than one large one.
