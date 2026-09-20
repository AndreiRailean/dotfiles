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

## After a PR merges

When you merge a PR, **or are told that one of yours has been merged**,
fast-forward the main checkout so the next session starts from the latest code:

```
git -C <main checkout> fetch origin --prune
git -C <main checkout> merge --ff-only origin/main
```

- Use `git -C`, never `cd` — you are usually in a worktree, and the main
  checkout is somewhere else.
- `--ff-only` so this can never create a merge commit or rewrite anything. If
  it refuses, say so rather than forcing it.
- If the main checkout is dirty, leave it alone and report that.

`ff-probe.sh` asks this question after a `gh pr merge` runs, but it cannot see a
merge done in the web UI or one you are simply told about. That is why the rule
is here as well as in the hook.
