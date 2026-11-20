# HANDOFF
- Contract for games: `lib/games/core/game_contract.dart`; registry `lib/games/game_registry.dart`.
- Worlds registry: `lib/worlds/world_registry.dart`; routes in `lib/app/router.dart` (`/world/<id>`, `/arcade/<gameId>`, `/oracle?q=`).
- Progress events: `ProfileService.award(event, xp, coins)`, counters `nova.posts`, `orbit.sent`, `social.joined`, `oracle.asked`, `worlds.visited`, `shop.bought`, `games.played`, `games.won`.
- Going online: see `docs/ONLINE_SETUP.md`.
- Finger soccer: engine `lib/games/finger_soccer/core/bm_engine.dart` (physics constants carry their calibration notes;
  retune only from new measurements), view `ui/bm_view.dart`, pre-match intro `intro/` (offline matches), in-match formation
  change = `BmEngine.changeForm` + `'form'` net move (DECISIONS D11). v3 tuning (straight ball, rail .9, light struck disc, 5% slower scene, count-up clock, intro picks) in PROGRESS + D13. Branch `work/fs-ref-physics`; CI "ANIX Quick Check"
  renders `test_render/finger_soccer_render_test.dart` + `finger_soccer_intro_render_test.dart`.
  v4: disc felt PF1 0 / PF2 3.25 (fit in PROGRESS); online matches open with `intro/fs_online_pick.dart` (own side only, logged 'setup', fallback 'for' after 75 s, D14).
