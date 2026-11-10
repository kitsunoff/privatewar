---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

# Round-mode safety review

Review only: a proposed round mode creates teams and roles in PW_RoundStart, calls ply:Spawn directly,
emits a custom action without Dependencies, and sends all carrier positions to every client so bots can navigate.
Explain the concrete existing seams to use and the tests to preserve. Do not edit files or access the game.
