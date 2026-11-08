---
name: deck-media-collect
description: Collect existing Steam Deck screenshots, game recordings, saved clips, or recent footage for this project. Use when asked to fetch, refresh, inventory, or copy Deck media, including requests in Russian for скриншоты, видосы, записи or футажи. For local M4S conversion also load deck-media-remux.
---

# Collect Steam Deck media

Follow `AGENTS.md` and the Deck rules before accessing the device. Collection is read-only: do not launch the game, capture new screenshots, delete or modify Deck files, or publish anything unless explicitly requested. Media, account paths and nicknames are private; keep them in a git-ignored private directory such as `ignoredprivate/workshop-media/`, never in a published tree. Do not put hosts, account IDs or credentials in repository files.

## Deck access

- Access the Deck only through a locked `scripts/deck/*.sh` entrypoint using `scripts/deck/common.sh` and `deck_lock`. Do not run raw SSH, rsync, arbitrary shell commands, or scripts in `ignoredprivate` as a workaround. Never disable the lock or touch its file. Wait for another owner to finish; report a timeout rather than interfering.
- At the time this skill was written there is no dedicated media-collection entrypoint in `scripts/deck/`. Check for one before proceeding. If none exists, explain the blocker and obtain approval for implementing a locked, read-only entrypoint; do not claim the existing private collector is an approved entrypoint. Respect project TDD and review rules when implementing it.
- Use `nix develop --command` for project tools when necessary; macOS built-ins may not support GNU options used by Deck scripts. Never run `cp1.sh` for media collection.

## Inventory and copy

1. Clarify scope only if needed. “Latest” normally means files new since the previous verified collection; compare full source paths and metadata, and explain if there is no reliable baseline. Do not silently cap results at 30 screenshots or three clips.
2. Inventory Steam screenshots for the requested app and saved recordings, including the complete clip folders, DASH manifests, initialization segments, audio and video chunks, and clip metadata. For this project the GMod Steam app ID is 4000. Inspect other recording locations too where available; distinguish saved clips, active or incomplete recordings, and unavailable sources. Never claim an inventory is exhaustive when a location was excluded.
3. Create a unique private output directory; do not overwrite earlier inventories, files, or user work. Report counts and size before exceptionally large transfers. Copy only selected existing files without deleting anything. If a recording is changing, skip it or clearly label it incomplete.
4. Verify every copied file against the inventory (count and size), check source size and modification time after transfer when possible, and record local SHA-256 hashes. Local hashes alone do not prove a byte-for-byte match with the Deck; report precisely which checks succeeded. Use streamed or batched verification, not a giant command-line argument.
5. If video is requested, use `deck-media-remux` for each recording. Report actual locations, counts, any omissions or failures, and whether source stability and audio/video playback were verified. Do not invent durations.
