# Publishing the source

## Canonical development workflow

This repository (`kitsunoff/privatewar`) is the canonical development repository. Develop directly here; the former research checkout is historical only, not a development source to export from.

1. Create a feature branch from the current `main`; use isolated worktrees for parallel tasks. Never commit or merge locally on `main`.
2. Run the required checks and review the branch. Push only with the user's authorization.
3. Show the PR title and complete body to the user and obtain approval before creating the PR. Use `gh pr create --draft` by default.
4. Changes reach `main` only through a reviewed PR with green merge gates. A skipped gate leaves the merge gate incomplete. Merging needs separate explicit user approval; once the PR is ready, use `gh pr merge --squash --delete-branch`.

## Public-content rules

1. Public text is English only: code, comments, docs, commits.
2. Private content, credentials, `.deck.env` and the local manual checklist must stay outside the public repository and any published tree. The checklist may be written in the maintainer's language. Public docs refer to it as "the local manual checklist (not published)".
3. Review staged changes and publication content for private terms and local-only paths before any authorized push or publication. An export exclusion does not protect a direct push; keep local configuration git-ignored and never commit private content.

## Optional filtered export

`scripts/export/public.sh` remains available to build a filtered snapshot of `HEAD`; it is not required for normal development or PRs. It does not authorize a push or publication.

```bash
nix develop --command bash scripts/export/public.sh /path/to/empty-or-clean-target
```

1. The script excludes every path in `scripts/export/local-only.txt` (one path per line, `#` starts a comment), including the local manual checklist, and then verifies the tree. It fails on:
   - Cyrillic in any file;
   - research-source and private terms (the pattern is in the script);
   - a `.deck.env` file or a `private/` directory.
2. The target directory must be empty, or a repository with a clean working tree. The script only writes inside the target and never deletes anything outside it. In a repository target it replaces the working tree contents and keeps its history directory.

## Self-test

`bash scripts/export/selftest.sh` plants each kind of violation in a scratch tree and asserts that the verify step rejects it. It runs as part of `make check`.

## Adding a local-only path

Append the path to `scripts/export/local-only.txt`, then export again.
