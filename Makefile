.PHONY: lint types markdown rules agent-guides check test test-selftest package package-selftest export-selftest

# Quality gates (same scripts as nix flake check and the git hooks).
lint:
	bash scripts/check/lint.sh

types:
	bash scripts/check/types.sh

markdown:
	bash scripts/check/markdown.sh

# File and function size limits, no net.WriteTable (DESIGN.md global rules 3 and 4).
rules:
	bash scripts/check/rules.sh

agent-guides:
	bash scripts/check/agent-guides.sh
	bash scripts/check/agent-guides-selftest.sh

check: lint types markdown rules agent-guides
	bash scripts/check/selftest.sh
	bash scripts/package/selftest.sh
	bash scripts/deck/publish-selftest.sh
	bash scripts/export/selftest.sh

# GLuaTest in the real game on the Steam Deck (scripts/deck/test.sh).
test:
	bash scripts/deck/test.sh

# Proves that a failing case makes the test run fail.
test-selftest:
	bash scripts/deck/test.sh --expect-failure

# Local Workshop build into dist/ (T-10.2); never uploads. See docs/packaging.md.
package:
	bash scripts/package/build.sh

# Builds into a temp dir and asserts the exclusions hold.
package-selftest:
	bash scripts/package/selftest.sh

# Proves that the public export verify step rejects Cyrillic, scrub terms, local-only paths and private files.
export-selftest:
	bash scripts/export/selftest.sh
