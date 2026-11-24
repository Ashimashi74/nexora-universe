# NEXORA — ASSET MAP
_Phase 0 deliverable. 984 files, ~64 MB under `assets/`. All paths verified against `pubspec.yaml` and `lib/core/assets/app_assets.dart` (generated constants — never hardcode raw paths in code)._

## 1. Branding (`assets/branding/`)
| Path | Purpose | Status |
|---|---|---|
| `anix_logo.webp` | Stacked NX emblem + wordmark (`AnixBrand.logo`) | **Reused** — internal asset name retained; visible label normalized to NEXORA |
| `anix_mark.webp` | Mark-only emblem (`AnixBrand.mark`) | **Reused** — same as above |
| `anix_wordmark.webp` | Wordmark only | **Reused** |
| `home_logo_anix.webp` | Home-screen emblem (ANIX wordmark) | **Reused** |
| `home_logo_nexora.webp` | Same logo with NEXORA wordmark | **Available** — preferred visible variant; asset filename retained for compatibility |

## 2. Fonts (`assets/fonts/`) — bundled, no remote downloads
| File | Role |
|---|---|
| `Estedad-{Regular,Medium,Bold,Black}.ttf` | Persian UI family (default language fa) |
| `ChakraPetch-{Regular,SemiBold,Bold}.ttf` | English / futuristic labels |
| `Lalezar-Regular.ttf` | Restrained decorative display only |
| `*.OFL.txt` | Licenses |

## 3. UI kits
### `assets/ui/anix/` — owner runtime art pack (9-slice)
- `bg/` — world_hub, social, arcade scene backgrounds (1080×2400).
- `buttons/` — primary/secondary/ghost/destructive/disabled × state (normal/pressed/focused/loading/high-contrast) × size.
- `toggle/`, `modal/`, `tooltip/`, `nav/`, `card/`, `rank/`, `frames/` — control chrome.
- `avatars/` — 24 painted avatars (`01-vanguard` … `24-lumen-android`).
- `icons/` — 30 painted icons (gamepad, trophy_gold, mic, shop, …).
- `trophies/` — bronze/silver/gold/diamond/amethyst/champion.
- `bracket/` — tournament match pills, status icons, champion crest.
- `scenes/` — voice_stage, trophy_hall, hub_panorama, portals, arena podium.
**Status:** reused by `anix_kit.dart`; paths internal (`anix_` prefix retained).

### `assets/ui/nx2/` — NX2 redesign pack
`badges/`, `bg/`, `boards/`, `chests/`, `frames/`, `oracle/`, `tiles/` — chamfered gold frames, boards, Oracle art. **Reused** by `nx2_widgets.dart` / `nx2_assets.dart`.

### `assets/luxe/` — Station Luxe
`hub.webp` (station scene), `splash.webp`, `frame.webp`, `icons/` (r1c1…r5c6 destination icons used by the Hub ring and directory). **Reused** by `luxe.dart`.

## 4. Worlds (`assets/worlds/`)
- `hub/portals/` — 7 world portal arts + `arcade_gate_large.webp` (**used** by Hub ring / station directory).
- `hub/props/` + `props/set/` — station set dressing (captain chair, cargo crates, command desk, comms terminal, energy core, holo chamber, orbital globe, portal door, reactor pod…). **Available** for Personal Space / station decoration.

## 5. Characters (`assets/characters/`)
- `oracle/` — `emotes/`, `moods/`, `poses/`, `hero_orbit.webp`, `avatar_user.webp`. **Reused** by `OracleAvatar` (idle/greeting/thinking/curious/happy/error/celebration moods).

## 6. Games (`assets/games/`) — per-game art
`backgammon/`, `basketball_battle/`, `bermuda/` (Finger Soccer), `billiards/`, `bomb_arena/`, `bubble_shooter/`, `carrom/`, `chess_blitz/`, `endless_runner/`, `finger_soccer/`, `fruit_ninja/`, `game_2048/`, `geo_dash/`, `helix_jump/`, `kart_racing/`, `knife_hit/`, `ludo_battle/`, `mini_golf/`, `obstacle_race/`, `pool8/`, `shared/`, `snakes_ladders/`, `spy_mafia/`, `stack_tower/`, `stickman_arena/`, `tetris_rush/`, `traffic_racer/`.
- **Registered & used:** all 26 registry games (16 multiplayer entries + 10 solo) have art consumed by their boards/pedestals.
- **Asset-only, NOT registered (documented, not claimed playable):** `chess_blitz`, `ludo_battle`, `stickman_arena` — assets exist without a registry `GameInfo`/entry function. Listed in `docs/GAME_REGISTRY.md` as unregistered.

## 7. Arcade (`assets/arcade/`)
`pedestals/` — per-game pedestal art used by Arcade lobby + Hub game cards (`AppAssets.pedestal(gameId)`).

## 8. Avatar gear (`assets/avatar/`)
`gear/` — wearable avatar items for Wardrobe / Exchange.

## 9. Progression (`assets/progression/`)
`achievements/`, `club_badges/` — achievement art and Finger Soccer club badges (v10 crest archive: 47 clubs, 19 nations, 12 NX faction coins).

## 10. Media & audio (`assets/media/`, `assets/sfx/`)
- `intro_app.mp4` — intro cinematic (10 s, `IntroVideoPage`).
- `bgm_main.ogg` — menu music (`MusicService`).
- `sfx/ui/` — UI sound effects (`NxSfx`).

## 11. Missing / fallback policy
- No remote font downloads — all fonts bundled.
- `errorBuilder` fallbacks on every `Image.asset` (brand text fallback, empty placeholders) so a missing art file never crashes a screen.
- 3D/heavy scenes degrade via `AppSettings.quality` (star counts 60/140/240/380) and `reducedMotion`; static 2D fallbacks exist for the Hub scene and world backgrounds.
