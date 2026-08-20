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

## Checking pages in a browser

If `/root/bin/webcheck` exists on the machine, use it to verify a dev server or
built site instead of asking the human to look. It loads URLs in headless
Chromium and reports console messages, uncaught exceptions, failed requests and
non-2xx responses; `--shot <dir>` writes full-page PNGs, `--dark` emulates dark
mode. Exits non-zero when it finds an error, so it also works as a gate.

```bash
/root/bin/webcheck http://localhost:4321/ --shot /tmp/shots
```

It has no npm dependencies (raw CDP over node's built-in `WebSocket`), so it
works against any repo without installing anything into it, and it is safe to
run from several sessions at once — each run gets its own Chrome profile and a
kernel-assigned debugging port. See `/root/bin/README.md` for the full flag list
and caveats.

Requires `chromium` from the system package manager (`apt-get install -y
chromium`). It is a *headless* browser, so it cannot reproduce profile,
extension, or host-OS behaviour — reach for it for page errors, not for
connectivity or environment problems.
