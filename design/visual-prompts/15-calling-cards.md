# 15 — Calling cards

Art prompts for the ten calling cards of `changes/done/calling-card-kill-banner.md`. Generate one image per prompt;
paste the shared block first, then the card block. Final in-game asset: 512×128 (4:1) PNG under
`addons/privatewar/materials/privatewar/cards/`.

Art direction (user decision 2026-11-22, option B): the cards look like in-engine screenshots of a mid-2000s
sandbox game, so players recognise the Garry's Mod feel, but every character and object is original. No Valve
characters or other third-party designs, and no recognisable faces: the art stays original project work under the
project licence.

## Shared block

```text
You are generating calling card art for an original modern military first-person shooter mod for a mid-2000s style
sandbox game (a fictional game with no real branding). A calling card is a wide horizontal banner shown in the HUD
when a player is eliminated; the player's nickname is drawn over it by the game.

Format: wide banner, 4:1 aspect ratio. If you cannot output 4:1, output 1536x1024 and keep every important element
inside the central horizontal band (full width, 384 px tall) so the image can be cropped to 4:1 without losing anything.

Composition rules for every card:
- The left 40 % of the banner is calm and darker (low detail, gradient or soft shadow) so white text stays readable there.
- The main subject sits in the right 60 %.
- Must read clearly when shown small (512x128 px): bold shapes, strong silhouette, high contrast, no tiny details.

Style for the whole set (all ten cards must look like one collection):
- Looks like an in-engine screenshot from a mid-2000s Source-engine-era sandbox game: slightly low-poly characters,
  simple materials and textures, hard-edged dynamic lighting, strong bloom and HDR glow, light film grain.
- Characters are original, generic modern soldiers and civilians in simple tactical gear; faces are always hidden by
  masks, helmets, balaclavas, goggles or deep shadow.
- Environments: generic industrial yards, concrete buildings, warehouses, rooftops, rural fields; boxy level
  geometry typical of that era.
- Base palette: near-black and dark grey-green (#0B0F0C, #1F2A22), off-white highlights (#E8EDE9), plus the one accent
  colour given in the card block, used for the key light or glow.

Hard restrictions:
- No text, letters, numbers, logos, watermarks or signatures anywhere in the image.
- No existing video game characters, creatures or factions (for example no characters from any Valve game), no real
  game logos, brand names or trademarks, no real military insignia, unit patches or national flags.
- No real weapon brand markings; weapons are generic fictional designs.
- No real or recognisable people; faces always hidden.
- No gore, no blood.
```

## Cards

### Level cards (player level): serious tone

```text
Card "Recruit" (id: default, unlocked at level 1, rarity common, accent #8A958D muted grey-green).
Subject: a lone masked soldier seen from behind, standing at the edge of a boxy industrial yard at dusk, looking toward
distant floodlights with a bloom glow. Quiet, humble, the beginning of a journey. Mostly dark, low saturation.
```

```text
Card "Veteran" (id: level_20, unlocked at level 20, rarity rare, accent #4FC3F7 cool cyan).
Subject: a helmeted soldier kneeling behind a concrete barrier in rain, rifle ready, cyan rim light from a nearby lamp,
glossy wet floor reflections typical of that engine era. Calm, experienced, focused.
```

```text
Card "Elite" (id: level_40, unlocked at level 40, rarity epic, accent #B47CFF violet).
Subject: a masked operator in a gas mask walking out of thick particle smoke toward the viewer, violet backlight with
strong bloom cutting through the smoke, sparks floating. Confident, intimidating, powerful.
```

```text
Card "Legend" (id: level_55, unlocked at max level 55, rarity legendary, accent #FFB547 amber gold).
Subject: a heroic operator silhouette standing on a flat concrete rooftop above a low-poly city skyline at night, a
huge golden HDR glow behind them, thin gold geometric accent lines framing the subject. Epic, prestigious, highest rank.
```

### Weekly challenge cards (one per challenge type): a little playful sandbox energy

```text
Card "Headhunter" (id: challenge_headshots, reward of the weekly headshot challenge, rarity epic, accent #FF4D4D red).
Subject: a view through a simple sniper scope with a red glowing reticle centred on a distant helmet perched on a
wooden crate (no person), red laser beam, shallow depth of field. Tense, precise, slightly tongue-in-cheek.
```

```text
Card "Marksman" (id: challenge_longshots, reward of the weekly long-range kills challenge, rarity rare, accent #5BE37D green).
Subject: a prone masked sniper on a grassy hill at dawn, long fictional suppressed rifle, flat low-poly terrain
stretching to a tiny distant farmhouse, a faint green tracer line across the valley. Patience and distance.
```

```text
Card "Flag Runner" (id: challenge_captures, reward of the weekly objective capture challenge, rarity rare, accent #4FC3F7 cyan).
Subject: a masked soldier sprinting past a capture-point flag pole with a plain cyan cloth (no symbols), a glowing cyan
ring on the ground around the pole, a stray traffic cone and an oil barrel flying in the air behind them. Momentum.
```

```text
Card "Air Support" (id: challenge_streak_kills, reward of the weekly killstreak kills challenge, rarity epic, accent #FFB547 amber).
Subject: a low-angle view of a boxy street with a few blocky fictional jet silhouettes streaking overhead, big amber
explosions with bright bloom, physics props (barrels, crates, a car door) flung into the air. Overwhelming firepower.
```

```text
Card "Untouchable" (id: challenge_life_kills, reward of the weekly kills-without-dying challenge, rarity epic, accent #5BE37D green).
Subject: a masked operator standing calmly in the middle of a concrete corridor while spent shell casings hang
frozen in the air around them, green rim light, bullet decals all over the walls, the operator unharmed. Composure.
```

```text
Card "Champion" (id: challenge_wins, reward of the weekly wins challenge, rarity legendary, accent #FFB547 amber gold).
Subject: a squad of four masked soldiers in slightly stiff, exaggerated victory poses on a hill of stacked shipping
containers at sunset, a plain amber banner on a pole (no symbols), warm god rays with heavy bloom. Victory and pride.
```

## Mapping (for the code)

| Card id | Unlock | Source |
| --- | --- | --- |
| `default` | level 1 (free, default choice) | level |
| `level_20` | level 20 | level |
| `level_40` | level 40 | level |
| `level_55` | level 55 | level |
| `challenge_headshots` | grant only | weekly challenge `headshots` (C2) |
| `challenge_longshots` | grant only | weekly challenge `longshots` (C8) |
| `challenge_captures` | grant only | weekly challenge `captures` (C10) |
| `challenge_streak_kills` | grant only | weekly challenge `streak_kills` (C15) |
| `challenge_life_kills` | grant only | weekly challenge `life_kills` (C20) |
| `challenge_wins` | grant only | weekly challenge `wins` (C17) |
