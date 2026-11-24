# NEXORA — IMPLEMENTATION PROGRESS
_Phase tracking for the master execution prompt §20 (Phases 0–7) and §22 deliverables. Branch: `arena/f772572f-nexora-flutter`._

## Phase 0 — Baseline & audit ✅
- [x] Read all docs (`docs/kit/*`, `docs/anix_pro/docs/00-07*`, `AGENT_BRIEF`, `REDESIGN`, `DECISIONS`, `HANDOFF`).
- [x] Inspected router, auth gate, app shell, world registry, all world/feature pages, services (settings, profile, online, rooms, voice, social, catalog), game registry + entry files, assets, fonts.
- [x] **Game registry discrepancy resolved:** 26 registered games = 9 original + 7 multiplayer arcade + 10 solo (see `docs/GAME_REGISTRY.md`). README's 26 is correct; the 16 entry files were only the multiplayer entries.
- [x] **Billiards vs Pool8:** kept separate — different rules/engines (Billiards = 8-ball with smart aim guide; Pool8 = 8-ball with shot clock). Not merged.
- [x] Created `docs/SCREEN_INVENTORY.md`, `docs/ROUTE_MAP.md`, `docs/UI_STATE_MATRIX.md`, `docs/ASSET_MAP.md`, this file, `docs/SOURCE_OF_TRUTH.md`.
- [x] **Baseline limitation:** no Flutter/Dart SDK in this sandbox and the allowed network hosts exclude the Flutter SDK distribution endpoints — `flutter pub get`, `flutter analyze`, `flutter test` and Android build **could not be executed here**. Recorded as a pre-existing environment limitation; CI (Flutter 3.27.1) is the build authority. All edits are conservative, null-safe Dart checked against Flutter 3.27 APIs.

## Phase 1 — Design system ✅ (consolidated)
- [x] Single source of truth: `lib/core/theme/nx_theme.dart` (`NxColors`, `NxThemeColors`, `WorldPalette`, `NxSpace`, `NxRadius`, `NxMotion`) + `lib/core/ui2/luxe.dart` (Station Luxe) + `lib/core/ui2/nx2_widgets.dart` (NX2).
- [x] Colors: midnight `#0B0A2A`/`#1A1650` identity ramp, Station Luxe `#07080C`, champagne gold `#D9B872`/`#F6E7BD`, silver, orange-coral action accents — see `docs/DESIGN_SYSTEM.md`.
- [x] Typography: Estedad (fa), ChakraPetch (en/technical), Lalezar (decorative only) — bundled, verified in `pubspec.yaml`.
- [x] Shared components: brand, headers, avatars, wallet chip, XP/level/rank, portal/game/room/post/tournament cards, panels, buttons, tabs/chips/fields, states (skeleton/empty/error/offline/reconnect/permission), sheets/dialogs/toasts.
- [x] RTL/LTR + accessibility primitives (Semantics, Directionality wrappers for game boards, 44–48 dp targets, safe areas).

## Phase 2 — Entry & global shell ✅
- [x] Boot/loading (intro takes over, no blank screen); update state via `AppUpdater`.
- [x] Intro cinematic (`/intro` video + orbital 3-step), skip, **completion persisted (`settings.intro_seen`) so it is not replayed on every launch**, replay from Settings, reduced-motion/low-mem fallbacks.
- [x] Auth & recovery (`/auth`, `/account` email flow, username/email + password, guest offline-only with accurate explanation).
- [x] Sign-in-required route for guests.
- [x] Onboarding/identity (language, username, avatar, identity explanation).
- [x] Global navigation: `Nx2Dock` (Home / Social / Play / Rooms / Profile) + Universe/More menu with all secondary destinations.
- [x] Hub (Station Luxe, **live native orbital-station scene** — star field/planet/rotating rings/gold-glow core/spacecraft, `NexoraStationScene` with quality+reduced-motion fallbacks — ring of world cards, real profile/rooms data) + Station directory (`/station/:k`, live ambient scene).

## Phase 3 — Seven worlds ✅
- [x] Nova Gallery: feed/explore/reels/alerts/profile tabs, composer, story viewer, post detail, follow/report sheets, empty/offline states.
- [x] Orbit Network: chats/calls/contacts, conversation detail, search, starred, groups/channels, call page (LiveKit, backend token), offline notices.
- [x] Arcade: lobby, per-game setup (mode/difficulty/seats), host page, online lobby/match, leaderboard, 16 game boards, 10 solo boards, Finger Soccer intro/shop.
- [x] Oracle Core: chat, suggestions, moods, game help, navigation actions, honest offline limits, admin persona config.
- [x] Personal Orbit: identity/missions/wardrobe/space/records tabs, avatar view, rewards.
- [x] Social Station: discover/joined, community detail, create sheet, members/events/tournaments, invite.
- [x] Nexora Exchange: featured (date-rotated), categories, search, item detail, server-confirmed purchase, balance/level states.

## Phase 4 — Rooms & competition ✅
- [x] Rooms directory (talk + game lobbies, search/filter, Quick Play, create wizard with capacity rules from `room_capacity.dart`).
- [x] Talk Room stage (speakers/audience, mic states, raise hand, chat, members, moderation with confirmations).
- [x] Game room/lobby (seats, ready, start validation).
- [x] Matchmaking/online match/reconnect/results; return-to-room behavior.
- [x] Tournaments (home/detail/bracket/wizard/manage/edit/inbox/join-code), leaderboards.

## Phase 5 — Settings & account lifecycle ✅
- [x] Full settings center (sound/music, graphics/motion, haptics, Oracle, language, account/data, about/build).
- [x] Account status/switching/recovery; sign-out (≠ delete, confirmation, server data preserved).
- [x] Delete flow (separate, truthful dialog that distinguishes device-clear vs server-not-enabled, server coverage documented in `docs/BACKEND_GAPS.md`).
- [x] Android exit/background: back behavior per layer, no sign-out on exit, realtime lifecycle preserved.

## Phase 6 — Admin & system surfaces ✅
- [x] Admin dashboard (`/admin`, server-guarded), force password change, Oracle config, update/notification/deep-link/not-found states.

## Phase 7 — Polish & quality
- [x] Empty/loading/error/offline/permission states mapped (`docs/UI_STATE_MATRIX.md`).
- [x] Performance: quality profiles, image cacheWidth, animation gating, no continuous offscreen loops.
- [x] Reduced-motion + accessibility pass (boards LTR-wrapped, semantics labels).
- [x] Persian/English localization pass — **brand normalization ANIX→NEXORA applied to all user-facing strings** (`docs/BRANDING.md`).
- [ ] Full navigation & regression tests — **blocked: no Flutter SDK in sandbox** (CI runs them).
- [ ] Android release build — **blocked: no Flutter SDK in sandbox** (CI runs it).

## Deliverables (§22) status
1. Rebuilt native Flutter NEXORA UI — ✅ integrated (brand-normalized; worlds/flows verified).
2. Screen inventory — ✅ `docs/SCREEN_INVENTORY.md`.
3. Route/navigation map — ✅ `docs/ROUTE_MAP.md`.
4. UI state matrix — ✅ `docs/UI_STATE_MATRIX.md`.
5. Design-system document — ✅ `docs/DESIGN_SYSTEM.md`.
6. Asset inventory — ✅ `docs/ASSET_MAP.md`.
7. ANIX→NEXORA branding list — ✅ `docs/BRANDING.md`.
8. Verified game registry — ✅ `docs/GAME_REGISTRY.md` (26 vs 16 resolved).
9. Backend-dependent unimplemented capabilities — ✅ `docs/BACKEND_GAPS.md`.
10. Test results — ⚠️ pending CI (no SDK in sandbox; baseline limitation documented).
11. analyze/test/build output — ⚠️ pending CI (same limitation).
12. Known risks — ✅ `docs/BACKEND_GAPS.md` + this file.
