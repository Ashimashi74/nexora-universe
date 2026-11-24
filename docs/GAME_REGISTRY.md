# NEXORA — VERIFIED GAME REGISTRY
_Deliverable §8. Source of truth: `lib/games/game_registry.dart` (`kGames`), `lib/games/arcade_registry.dart` (`kArcadeGames`), `lib/games/solo/solo_registry.dart` (`kSoloDefs` / `buildSoloGameInfos`). Executable registry + entry functions only — an asset existing does not make a game playable._

## The 26-vs-16 discrepancy — RESOLVED
The README's **26 games** is correct. The static audit found **16 `*_entry.dart` files** because those are only the **multiplayer** entries. The full registered catalogue is:

**26 = 9 original games + 7 multiplayer arcade games + 10 solo arcade games.**

`kGames` = 9 original + `...kArcadeGames` (7) + `...buildSoloGameInfos()` (10) = **26**.

## A. The nine original games (`game_registry.dart`)
| # | ID | Name (en) | Name (fa) | Players | Online | Local | Modes |
|---|----|-----------|-----------|---------|--------|-------|-------|
| 1 | `finger_soccer` | Finger Soccer | فوتبال انگشتی | 2 (online up to 6: 1v1/2v2/3v3) | ✅ | ✅ (duel) | Bot / Local / Online; team·formation·field·ball·kit selection |
| 2 | `carrom` | Carrom | کارم | 2 | ✅ | ✅ | Bot / Local / Online |
| 3 | `billiards` | Billiards (8-ball, smart aim guide) | بیلیارد | 2 | ✅ | ✅ | Bot / Local / Online |
| 4 | `backgammon` | Backgammon | تخته‌نرد | 2 | ✅ | ✅ | Bot / Local / Online |
| 5 | `ludo` | Ludo | لودو (منچ) | 2–4 (default 4) | ✅ | ✅ | Bot / Local / Online |
| 6 | `snakes_ladders` | Snakes & Ladders | مار و پله | 2–4 (default 2) | ✅ | ✅ | Bot / Local / Online |
| 7 | `uno` | NX Cards (UNO-style) | کارت‌های NX | 2–4 (default 4) | ✅ | ✅ | Bot / Local / Online |
| 8 | `quiz` | NEXORA Quiz | کوییز نیکسورا | 2 | ✅ | ✅ | Bot / Local / Online |
| 9 | `mafia` | Mafia | مافیا | 6–12 (default 8) | ✅ | ✅ (narrator) | Bot / Narrator / Online |

## B. The seven multiplayer arcade games (`arcade_registry.dart`)
| # | ID | Name | Players | Online | Local | Group |
|---|----|------|---------|--------|-------|-------|
| 10 | `kart_racing` | Kart Racing | 2–4 (default 4) | ✅ | — | Sports/Action (4) |
| 11 | `obstacle_race` | Obstacle Race | 2–4 (default 4) | ✅ | — | Action (4) |
| 12 | `bomb_arena` | Bomb Arena | 2–4 (default 4) | ✅ | — | Action (4) |
| 13 | `pool8` | 8 Ball Pool (shot clock) | 2 | ✅ | — | Table (1) |
| 14 | `mini_golf` | Mini Golf | 2–4 (default 2) | ✅ | — | Sports (1) |
| 15 | `basketball_battle` | Basketball Battle | 2–4 (default 2) | ✅ | — | Sports (1) |
| 16 | `spy_mafia` | Spy & Mafia | 4–8 (default 5) | ✅ | — | Party (3) |

## C. The ten solo arcade games (`solo_registry.dart`)
| # | ID | Name | Control | Online |
|---|----|------|---------|--------|
| 17 | `endless_runner` | Endless Runner | dpad | daily challenge + global board |
| 18 | `geo_dash` | Geo Dash | tap | ✅ |
| 19 | `traffic_racer` | Traffic Racer | dpad | ✅ |
| 20 | `fruit_ninja` | Fruit Ninja | drag | ✅ |
| 21 | `knife_hit` | Knife Hit | tap | ✅ |
| 22 | `helix_jump` | Helix Jump | drag | ✅ |
| 23 | `bubble_shooter` | Bubble Shooter | drag | ✅ |
| 24 | `stack_tower` | Stack Tower | tap | ✅ |
| 25 | `tetris_rush` | Tetris Rush | dpad | ✅ |
| 26 | `game_2048` | NX 2048 | dpad | ✅ |

Solo games: `minPlayers/maxPlayers = 1`, `supportsOnline = false` for live play; they share medals, daily challenge and the server-validated global score board like every other arcade game.

## Billiards vs Pool8 — kept separate (evidence)
- `billiards`: 8-ball with a **smart aim guide**, offline bot + pass-and-play, group 1.
- `pool8`: 8-ball with a **shot clock** (20 s per shot), bot offline, turn-by-turn online, `supportsLocal: false`, group 1, `isNew: true`.
Different rules/engines/UX — not merged.

## Unregistered assets (documented, NOT claimed playable)
`assets/games/` contains art for `chess_blitz`, `ludo_battle`, `stickman_arena` with **no** `GameInfo` entry and **no** `buildXxxGame` entry function. These are documented as unregistered and are not shown as playable anywhere. No game implementation was deleted.

## Launch status
All 26 have an entry function (`buildXxxGame(GameLaunch)` / `buildSoloGame(d, launch)`) consumed by `GameSetupPage` → `GameHostPage`, with real boards in `lib/games/<id>/ui/` (multiplayer) and `lib/games/solo/ui/` (solo). Offline: bots + pass-and-play. Online: rooms/quick-match/invites/tournaments on the games Supabase project with host-authoritative settlement.
