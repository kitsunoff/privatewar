---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
---

# Adapter safety review

Review an adapter proposal: Apply returns the requested build without reading what stuck; attachment tables alias
weapons.GetStored; SetCustomizationLocked is a no-op; server-only stat scaling advertises every key; bots fire by
calling the base's attack method directly. Which exact contracts/tests reject this? Review only, no game access.
