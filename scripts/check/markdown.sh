#!/usr/bin/env bash
# Markdown gate: markdownlint-cli2 over the project documents (globs in .markdownlint-cli2.yaml).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool markdownlint-cli2
markdownlint-cli2
echo "[markdown] ok"
