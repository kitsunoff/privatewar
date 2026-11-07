# 00 — Shared style

Paste this block before every screen prompt.

## Prompt

```text
Visual style for the UI of an original modern military first-person shooter (fictional game, no real branding).
Overall look: dark, clean, premium, minimal. Large uppercase condensed sans-serif headings (similar to Barlow Condensed),
regular sans-serif body text (similar to Barlow). Generous spacing, strict alignment grid, 16:9 layout.
Background: a blurred, desaturated, slightly darkened 3D game scene (industrial yard at dusk) with soft vignette.
Panels: semi-transparent near-black panels (#0B0F0C at about 70 % opacity) with background blur, thin 1 px borders in
dark grey-green (#1F2A22), square corners or very small radius (2 px).
Single accent colour: bright tactical green (#5BE37D) used for selection highlights, active tabs, progress bars,
primary buttons and key numbers. Everything else is neutral: primary text off-white (#E8EDE9), secondary text muted
grey-green (#8A958D). Secondary colours only for meaning: enemy red (#FF4D4D), friendly cyan (#4FC3F7),
warning amber (#FFB547), rarity colours for store items.
Selected item: green left edge bar plus a subtle green glow; hover: lighter panel. Buttons: flat, uppercase labels,
primary button filled green with dark text, secondary buttons outlined.
Icons: simple monochrome line icons. No skeuomorphism, no chrome, no heavy gradients, no clutter.
```

## Colour tokens (for the code, `10-frontend.md`)

| Token | Value | Use |
| --- | --- | --- |
| `bg` | `#0B0F0C` | Panels (about 70 % opacity) |
| `border` | `#1F2A22` | Panel borders, separators |
| `accent` | `#5BE37D` | Selection, primary buttons, progress, key numbers |
| `text` | `#E8EDE9` | Primary text |
| `text_muted` | `#8A958D` | Secondary text |
| `enemy` | `#FF4D4D` | Enemies, defeat |
| `friendly` | `#4FC3F7` | Teammates |
| `warning` | `#FFB547` | Warnings |
