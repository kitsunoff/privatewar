---
name: deck-media-remux
description: Assemble, remux, or troubleshoot Steam Deck Game Recording DASH M4S segments into playable videos with audio. Use for stitching Steam clips, unusually short three-second exports, validating clip duration and synchronization, or when deck-media-collect collects recordings.
---

# Assemble Steam recordings

Work on local copies only. Keep source segments, manifests and previous exports unchanged, and save outputs in a new private directory. Use `nix run nixpkgs#ffmpeg --` for FFmpeg; obtain ffprobe from the same nixpkgs package, for example `nix shell nixpkgs#ffmpeg -c ffprobe`. Do not publish private media or include user identifiers in repository files.

## Workflow

1. Enumerate every selected clip and its `session.mpd`, initialization segments and numbered chunks. Read the manifest for expected duration, representation IDs and stream types. Identify and report missing segments, gaps, active recordings, or multiple periods rather than silently producing incomplete output. Audio and video chunks are separate streams and need not have equal counts.
2. Do not trust a successful FFmpeg exit or a full decode as proof of completeness. Steam's DASH manifest has previously caused FFmpeg to read only the first approximately three-second segment while exiting successfully.
3. For the observed single-period Steam layout, use FFmpeg's `concat:` protocol independently for each stream: initialization file first, then all numbered chunks in numeric order; provide the two concatenated streams as separate inputs, map video and audio, and use `-c copy -movflags +faststart`. Use absolute paths, avoid overwriting existing files (`-n`), and check that the sorted sequence has no missing or duplicate chunk numbers. Adapt stream IDs to the manifest, not filenames assumed from another recording. For other layouts stop and investigate rather than guessing. If paths contain `|` or protocol limits are reached, safely assemble temporary stream files in a private temporary directory instead.
4. Check each output using ffprobe: actual duration, video and audio streams, codecs, start times, and stream durations. Compare to the manifest and the full segment inventory. Steam's segments can include material beyond clip boundaries, so an assembled file may be a few seconds longer than the nominal saved clip. Do not describe it as an exact Steam trim unless clip boundaries have been independently validated.
5. Decode both streams with FFmpeg and inspect errors; distinguish decode failures from timestamp warnings produced by the test output. Check audio/video synchronization and beginning/end playback when feasible. A stream-copy command can lose relative source timestamp offsets, so do not assert synchronization without checking it. Report warnings and unverified playback honestly.
6. Report output paths and measured durations, the number of clips, differences from expected duration, and any omissions. Preserve individual clips rather than concatenating unrelated recordings into one timeline unless the user requests it.

## Command shape for the observed layout

For stream IDs `0` and `1`, construct each input as `concat:/absolute/path/init-stream0.m4s|/absolute/path/chunk-stream0-00001.m4s|...` and likewise for stream 1. Pass each input as one quoted argument:

```sh
nix run nixpkgs#ffmpeg -- -nostdin -hide_banner -n \
  -i "$video_input" -i "$audio_input" \
  -map 0:v:0 -map 1:a:0 -c copy -movflags +faststart "$output"
```

This is a command shape, not a substitute for checking stream IDs, continuity, output duration, or synchronization.
