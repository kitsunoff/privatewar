# Publishing the source

The public repository is a generated artefact. It is built from `HEAD` of the private development repository by one script; nothing is copied by hand.

```bash
nix develop --command bash scripts/export/public.sh /path/to/empty-or-clean-target
```

## Rules

1. Public text is English only: code, comments, docs, commits. The script fails on any Cyrillic character in the export.
2. The local manual checklist is local only and never published. It stays tracked in the private repository because agents keep appending to it. Its path is listed in `scripts/export/local-only.txt` (one path per line, `#` starts a comment). Public docs refer to it as "the local manual checklist (not published)".
3. The script excludes every path in `scripts/export/local-only.txt` and then verifies the tree. It fails on:
   - Cyrillic in any file;
   - research-source and private terms (the pattern is in the script);
   - a `.deck.env` file or a `private/` directory.
4. The target directory must be empty, or a repository with a clean working tree. The script only writes inside the target and never deletes anything outside it. In a repository target it replaces the working tree contents and keeps its history directory.

## Self-test

`bash scripts/export/selftest.sh` plants each kind of violation in a scratch tree and asserts that the verify step rejects it. It runs as part of `make check`.

## Adding a local-only path

Append the path to `scripts/export/local-only.txt`, then export again.
