---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

# Perk safety review

Review only: a speed perk multiplies owner:GetRunSpeed on each refresh and restores health to maximum;
another sends SetStatMods({reload_time=0.8}) directly, and Stockpile replaces PW_EquipmentCount's existing answer.
All use global PERK in timer callbacks. Explain concrete fixes and tests for two owners and Infection role composition.
Do not edit files or access the Deck.
