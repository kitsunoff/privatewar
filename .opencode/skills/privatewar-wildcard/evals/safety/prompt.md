---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

# Wildcard safety review

Review only: a wildcard adds primary2 to effective slots and its pure Validate case passes, so the author claims
the second gun is equipped, editable and networked. ModifySlots also raises wildcard.count to 9, writes the
global slot store and throws after a partial edit expecting PW.Call to disable it. What actually happens today,
which checks are missing, and where must ownership be agreed? Do not edit or use the Deck.
