# PROGRESS (branch `nxg`)

## Online foundation (M1) — done
- Supabase project `eisstodgncimypdawisy` (shared with the other NEXORA app: same `auth.users` + `profiles`).
- New schema under `nx_` prefix: `supabase/migrations/20261115000000_nx_core.sql` (+ `_100_nx_fk_profiles.sql`), RLS on every table. Applied live.
- `lib/core/online/`: `online_service.dart` (guest = anonymous auth, upgrade to email+password keeps the uid; sign in / out),
  `cloud_profile_sync.dart` (server owns XP/coins via `nx_award` / `nx_purchase` — idempotent, daily cap 3000 XP;
  inventory/achievements/stats/decor in `nx_profiles.data`; offline queue flushes on reconnect), `SupabaseBackend` implements `BackendGateway`.
- Account page: Settings → Account (`/account`). Offline builds (no dart-define) behave exactly as before.

## Online multiplayer (M2) — all 9 games wired
- Model: every phone runs the same pure-Dart core with the same seed; players exchange inputs only. The DB (`nx_push_move`, seq = last+1,
  first writer wins) is the single ordered log → identical order everywhere. Reconnect/resync = rebuild the game and replay the log instantly.
  Pre-move state hashes are verified (`NetLink.verify`).
- Physics (finger soccer, carrom, billiards): shot input relayed, identical deterministic sim, the authority (lowest connected seat) posts a full
  snapshot after every shot; non-authority waits for it (≤3.5 s) before the next aim. Physics/tuning untouched.
- Lobby (`OnlineLobbyPage`): quick match, private/public room by code, open rooms, ready/start, invite friends (`nx_invites`, real-time banner),
  presence dots, forfeit on leave, absent players auto-forfeited by the authority (40 s on their turn / 90 s otherwise).
- Results: `nx_finish_match` → `nx_match_results`, `nx_game_stats` (rating ±), XP/coins; `/leaderboard` (per game + global XP).
- Seat 1 sees finger soccer / carrom rotated 180° (own side at the bottom).
- Mafia online: 6–10 players, seeded roles on every phone, UI shows only what that player may know (roles are hidden by the client UI, not
  cryptographically — a modified client could read them).

## Social worlds (M3) — real when signed in (online build + session); device-only otherwise
Schema: `supabase/migrations/20261115000200_nx_social.sql` (applied live). Only `nx_` tables + a `nx-media` bucket with
`nx_media_*` policies on storage.objects; nothing of the other app is changed. Friends reuse the shared `follows` /
`friend_requests` RPCs (same friendships in both apps). No seeded/fake users or content is shown online.
- **Orbit Network** (`SupabaseOrbitRepository`): 1:1 (`nx_open_direct`), groups, channels (only owner/admins post — enforced
  in `nx_send_message`), members + roles, add friends, leave/delete, edit/delete/pin (RPCs), per-user stars, read receipts
  (members' `last_read_at`), unread counts (`nx_my_chats`), server search, Realtime (`nx_messages`, `nx_chat_members`,
  `nx_calls`). Offline: last server copy stays visible, sends are queued in LocalStore and flushed on the next refresh.
  Saved Orbit and chats created offline stay on the device. Contacts tab = friends with presence, requests (accept/decline/
  cancel), username search, message/call/remove. Game invites in an online chat create a real private room and the card
  joins it (`/online/<game>?code=`).
- **Calls (M4)**: Edge Function `nx-call-token` (source `supabase/functions/nx-call-token`, verify_jwt) — only members of the
  chat get a 15-min LiveKit token for room `nxg-call-<chat id>` (channel listeners can't publish). `OrbitCallPage` (livekit_client):
  voice/video/group, mute/camera/speaker, speaking glow. `nx_start_call` logs the call + a call message; `CallWatcher` rings
  anywhere in the app (snackbar → `/call/:chatId`). Calls tab = real history.
- **Nova Gallery** (`SupabaseNovaRepository`): posts, 24 h stories (+ views), likes, comments, saves, notifications (likes/comments
  by others, via triggers), hashtags (derived server-side), `#tag` / `@user` / text search, trending, photo posts uploaded to
  `nx-media/<uid>/…` (RLS: write only your own folder; public read), follow / followers on `follows`. My uid is shown to the UI
  as the explorer id so ownership checks keep working.
- **Social Station** (`SupabaseSocialRepository`): `nx_communities` (document + version) + `nx_community_members` (real roles).
  `nx_community_save` refuses stale versions (client re-applies the change, ≤3 tries) and keeps only what the caller's role may
  change (member: posts + events/RSVP; moderator: + tournaments/local players; admin/owner: all). Role change / kick / delete /
  join-by-code / join-public / leave are role-checked RPCs. Discover sheet lists public communities.
  Known limit: within the parts a role may edit, a modified client could rewrite others' posts (no per-post server check).
- **Orbit chat media**: photos, audio/music and documents upload to the private `nx-chat-media/<uid>/chat/<chat_uuid>/` bucket with an 8 MiB/MIME allow-list. Read/write/delete policies require the correct owner and chat membership; messages store the canonical path plus a seven-day signed URL. Nova's public `nx-media` bucket remains separate for public posts. The server RPC and Storage policies are in `20261119000100_nx_chat_media.sql`.

## ORACLE remote (M5)
- `RemoteOracleEngine` → existing `oracle-chat` Edge Function (unchanged). Contract: POST `{messages, ctx}` with the user JWT →
  `{message:{content, tool_calls?}}`. Its tools belong to the other app: the client answers them with
  `not_available_in_this_app` once and asks again. App-aware intents (navigation, settings, rules, stats…) stay on the offline
  brain; open conversation goes online; any error → offline reply.
- As of 2026-11-15 the function's LLM provider (apinex.bond) answers 402 "insufficient balance / daily check-in", so ORACLE
  currently always falls back to the offline brain. Topping up that provider (or setting another key in its config) turns it on
  with no app change.

## Remaining / next
- Voice recording (microphone capture) is still a separate follow-up; selected audio/music files are supported in Orbit chats now.
- Push notifications for messages/calls when the app is closed (calls ring only while the app is open).
- ORACLE voice (the notice stays; `oracle-chat` supports audio but needs the provider balance first).
- No device testing possible from the build agent: SQL/RPC/RLS/Storage/Edge Functions verified live with guest accounts
  (test data removed); UI verified by analyzer + CI build.

## Tournaments (M6) — `lib/features/tournaments` + `supabase/migrations/20261116000*_nx_tournaments*.sql`
No extra server: everything runs in the existing Supabase project (Postgres RPCs + RLS + pg_cron + Realtime).
- **Roles (RBAC in Postgres)**: admin (`nx_staff.role='admin'` or the shared `is_admin()`), organizer (`nx_staff.role='organizer'`),
  per-tournament runner (`nx_t_staff`), player. Tables are read-only for clients (RLS); every write is a role-checked
  SECURITY DEFINER RPC (`nx_t_save`, `nx_t_admin`, `nx_t_register`, `nx_t_join_code`, `nx_t_withdraw`, `nx_t_decide`,
  `nx_t_remove_entry`, `nx_t_set_seed`, `nx_t_code_create/revoke`, `nx_t_ready`, `nx_t_report`, `nx_t_dispute`,
  `nx_t_admin_match`, `nx_t_set_staff`, `nx_t_set_runner`, `nx_t_standings`, `nx_t_logs`). Engine functions `_nx_t_*` and
  `nx_t_tick` are not executable by clients. Only admins can set fixed (minted) prizes.
- **Formats** (2–64 players, automatic byes): single elimination (+3rd place), double elimination (grand final + reset),
  two legs (aggregate, optional single-leg final), round robin (single/double), groups → knockout (snake groups, configurable
  groups/advancers, A1-vs-other-group seeding), swiss (N rounds, no rematches while avoidable, rotating bye), custom (organizer adds
  matches). Best-of per round kind (early / semis / final: Bo1/2/3/5). Knockout draws: finger soccer (BERMUDA port) already ends ties
  with its own golden goal; if any game still reports a draw, the server opens a decider game (`settings.golden_goal`) and after
  4 extra games the better seed advances. Leagues award draw points.
- **Registration**: open / approval / code / code+approval; 8-char codes (no 0/O/1/I) with max uses, expiry, revoke,
  requires-approval; deep link `nexora://t/<code>`; 5 wrong codes per 15 min per account. Min level / XP / rating, entry fee in
  coins and gems (escrowed in the tournament row + immutable `nx_t_ledger`), waitlist with automatic promotion, withdraw with
  refund before registration closes, one registration per account.
- **Scheduler**: pg_cron job `nx_t_tick` every minute: idempotent `nx_t_jobs` (open/close registration, draw, start, 10-minute
  reminders), ready checks (default 5 min) → both ready creates the private room + online match through the same
  `nx_rooms`/`nx_matches` the lobby uses (settings.tmatch), no-shows → walkover (double no-show: better seed in knockouts, void in
  leagues), 60 s reconnect grace (`settings.grace_sec` in `SupabaseMatchLink`), result acceptance, finish + payout.
- **Results**: only server-side. Forfeits are server facts; normal ends need both players' `nx_t_report` to agree (one report +
  90 s silence, or the server row alone after 3 min, is accepted); disagreement → dispute; organizer fixes or replays with an
  audit trail (`nx_t_audit`, append-only). Corrections re-seat downstream players if the next match has not started.
- **Prizes**: fixed + pool % of entry fees − house fee %, split by place percentages (shared places split, remainder to the champion),
  paid once in one transaction with idempotency keys (`payout:<t>:<user>:<currency>`). Cancel = full refund.
- **Notifications**: `nx_t_notifications` (in-app inbox + Realtime banner) for approved/rejected/waitlist/promoted, drawn, starting
  soon, match soon, match ready, result, advanced/eliminated, walkover, dispute, prize, time changed, cancelled, refund. No FCM in
  this app → device notifications via flutter_local_notifications (shown when a notification arrives in the background, and the
  10-minute reminders are scheduled on the device so they fire with the app closed).
- **UI**: Tournaments (tabs registering/upcoming/live/finished/mine, filters, countdowns), detail (overview, prize pool, rules,
  schedule local + UTC, register/code/withdraw, my next match with READY, live bracket with pan/zoom, league tables, matches,
  players), inbox, organizer wizard (info → format → times → match rules → prizes → registration/codes → review/publish) and
  manage panel (controls, approvals, players/seeds, codes, match tools, logs/jobs/ledger, staff). Entry points: Hub quick row
  (Cups), Arcade, and the game setup page of every 1-vs-1 online game (incl. finger soccer).
- Verified live against the project with guest accounts (SE/DE/two legs/RR/groups/swiss/custom paths, byes, golden-goal cap,
  codes + rate limit, approvals, waitlist, refunds, cancel, payout maths, disputes, admin correction, forfeits, cron-driven run,
  RLS from the REST API). Pure-Dart mirror + tests: `test/features/tournaments/bracket_test.dart`.

## ORACLE personality (redesign, 2026-11-17) — `lib/worlds/oracle_core/persona/`
- `oracle_persona_data.dart`: default JSON config (39 players + aliases, verbatim lines, login greetings, spontaneous lines,
  result reactions, funny tutorials per game mechanic, guided-tour texts, `{jan}` replies, frequencies/cooldowns, category switches).
  `{jan}` renders the stretched signature «جاااااااااان» (8–13 ا, 10 by default); any short signature «جان» in admin text is upgraded.
- `oracle_persona.dart` (pure Dart): name NLU (normalisation, ZWNJ, ی/ي ک/ك, letter squeeze, Persian suffixes, Latin aliases,
  Levenshtein for long names, ambiguity for shared first names), cooldown manager, no-repeat shuffle bag, login greetings
  (never claims another player logged in), spontaneous lines, reactions from real results, tutorials, tour steps, AI context.
- Wired into: offline brain (`respond` → players / wake / jan replies / unknown names), corner buddy (login greeting,
  spontaneous lines, guided tour overlay on route changes), game result screens (offline + online), tutorial banner at game start,
  in-game ORACLE sheet ("آموزش ORACLE" replay + persona context), `nx-oracle` (persona rules + verified profiles from the server config).
- Guided tour: `oracle_tour.dart` — spotlight coach marks (`OracleTourTarget` on dock items), once per section per account
  (LocalStore + `nx_profiles.tour_seen` via `nx_tour_seen_set`), replay from Settings.
- Server: `supabase/migrations/20261117200000_nx_oracle_persona.sql` (applied live): `nx_oracle_persona` (public read, seeded with
  the defaults), `nx_oracle_persona_save` (owner or `oracle` permission via `nx_has_perm`, audited in `nx_owner_audit`),
  `nx_admin_perms` (per-permission admins, used by the admin panel milestone), `nx_tour_seen_set`.
- Admin editor: Settings → «تنظیمات شخصیت اوراکل (مدیر)» (`/admin/oracle`, JSON editor; visible only when `nx_has_perm('oracle')`).
- Tests: `test/worlds/oracle_persona_test.dart` (names incl. typos/Latin, Pedro/Denny/Mahyar separation, verbatim lines,
  stretched signature everywhere, cooldowns, no-repeat, reactions, greetings, tutorials, tour, brain integration).

## Backend split — infrastructure (2026-11-17, applied live; app not switched yet)
- Auth project: custom access token hook `nx_access_token_hook` enabled (claim `nx_perms`: `owner` | per-permission admins from
  `nx_admin_perms` | `tournaments` for nx_staff | `unlimited_gems`; never fails a sign-in). Verified: sign-up still works, claim present.
- Games project trusts auth JWTs (Third-Party Auth, ES256 JWKS) — verified `auth.uid()` = same user id there.
- Wallet bridge (both directions, verified end-to-end with a temporary guest, then deleted): games `profiles` mirror + `nx_wallet_tx`
  outbox → auth `nx_bridge_apply_batch` (idempotent by tx id, `nx_bridge_applied`) → snapshot back via `nx_mirror_put`;
  auth-side profile changes of NEXORA players push snapshots (`nx_profiles_to_games` trigger). Service keys in Vault on both sides.
  Files: `supabase/games/migrations/20261117100000_g_mirror_bridge.sql`, `supabase/migrations/20261117210000_nx_access_token_hook.sql`,
  `supabase/migrations/20261117220000_nx_games_bridge.sql`.
- Remaining for the split: port rooms/matches/matchmaking + the tournaments engine (~100 SQL functions) to the games project with
  shims (`nx_perm` instead of nx_staff/is_admin), then switch the app's rooms/matches/tournaments calls to a second Supabase client
  (`accessToken` = auth session) in one release.

## Finger soccer — reference physics v2, intro merge, in-match formation change (2026-11-20, branch `work/fs-ref-physics`)
- Merged `work/fs-intro` (splash, team select, formation select, shop, game bar) into `work/fs-ref-physics`. Conflict in
  `ui/bm_view.dart` (offline config) resolved to the intro's pick; `intro/fs_intro_data.dart` adapted to the
  `BmFormation` list (9 shapes, slots [x, depth of half] -> the intro's [x, 0..0.5]). The match render test now drives
  the intro (team -> formation Nish -> match) and also opens the in-match picker; the intro render test is unchanged.
- Physics calibration v2 (`core/bm_engine.dart`, constants commented in place; test: `test/games/finger_soccer_test.dart`):
  frame-by-frame template tracking of the reference recordings (15 fps, 1 px = 2.88 world) — 3 clean shot glides
  (Japan, power 2) and 4 discs struck by another body, positions fitted with the engine's own friction law.
  Before -> after: PF1 280 -> 45 (123 -> 20 px/s^2), PF2 5.0 -> 3.5 /s, launch glide .22 s -> 0, kBmLaunch 1.87 -> 2.04
  (distance-matched so a shot disc still stops where the reference shots stop), kBmDiscVMax 4200 -> 4400 (above the
  strongest launch), ball striking a disc: disc impulse 1/HV -> full (kBmBallHitDiscK = 1) and no PCAP cap on a disc
  the ball hits, disc<->disc struck-disc impulse .85 -> 1 (kBmStruckDiscK). Ball rolling friction unchanged
  (kBmBallF0 23, kBmBallDrag 1.08: the ball could not be tracked reliably next to the white Japan discs).
  Team power: measured speeds are divided by each side's reference power (`kBmRefPower`, `BmEngine.refStrikeOf`);
  ANIX team stats unchanged. Contract row: `supabase/games/migrations/20261120030000_physics_reference_v4.sql`
  (not applied live).
- In-match "تغییر ترکیب" button (bottom left, above the game bar handle) opens the 3 x 3 picker (`BmFormationPicker`);
  rule in DECISIONS D11; engine API `canReformNow(side)` / `changeForm(side, fi)`; online move `'form'` (live + replay).

## Finger soccer v3 — owner feedback on the reference-physics build (2026-11-20, branch `work/fs-ref-physics`)
- Ball travels straight: ball curl per unit spin `kBmBallCurve` .034 -> 0 (spin is still kept and drawn, so the ball
  still turns round in the corners; no bends after a wall or a glancing hit).
- Bank shots keep their power: one rail restitution `kBmRailE` = .9 for ball AND discs on side rails, end lines and the
  round corners, no tangential loss (before: ball .62-.72 speed dependent, disc .48). Goal posts / inside of the goal
  unchanged.
- Lighter pieces: a disc the ball strikes reacts with mass `kBmDiscLightM` 5.5 (before DISC_M 8) -> knocked back ~30%
  further. Disc->ball strikes and disc<->disc hits keep DISC_M 8, so shot power is unchanged (D13).
- Whole scene 5% slower: `kBmSimRate` .95 scales only the real time fed to the fixed-step accumulator; same steps,
  same paths and outcomes (online phones still run identical steps).
- Match clock: runs on real elapsed time (was clamped to 50 ms per frame like physics, so it lagged on slow frames)
  and the HUD counts the played time up (0:00 -> 5:00), red over the last 30 s.
- Intro team select: the arrows pick the team shown when it can be fielded (owned, or any team for the opponent side);
  tapping the big disc selects / buys it. Before, only the small "انتخاب" button picked, so the browsed team was not
  the one that played.
- Intro formation select: the whole card (mini pitch, name, button) picks; before, only the small button did, and
  the auto-advance timer then started the match with the first / saved formation ("stuck on 0").
- Tests: `test/games/finger_soccer_test.dart` (v3 group), `test/games/finger_soccer_intro_pick_test.dart`; the match
  render test asserts the intro formation reaches the match.

## Finger soccer v4 — disc friction refit, online team / formation picks (2026-11-20, branch `work/fs-ref-physics`)
- Disc felt refit "exactly like the video": the v2 tracks (3 Japan shot glides + 4 struck discs) plus 3 fast glides
  (v1 frames 580 PSG, 1779, 1460 Adidas; up to ~1700 px/s) fitted jointly with the engine's own law, free launch speed
  per track, no glide (`/workspace/work/fsref/fit4.py`). Best fit: no constant part, 3.25/s drag, rms 6.05 px per
  position over 10 tracks; v2 (20 px/s^2 + 3.5/s) rms 6.41 px; v1 (123 + 5.1) rms 10.3 px. Engine: PF1 45 -> 0,
  PF2 3.5 -> 3.25 (a disc glides ~9% further, ~10% longer at the same launch); kBmLaunch, team power, rails, masses,
  sim rate unchanged. Ball rolling friction not refitted (ball tracking next to the white Japan discs still unreliable).
- Online matches now open with the same team select and formation select screens (`intro/fs_online_pick.dart`):
  each phone picks only its own side (the other side's toggle shows "حریف تیمش را خودش انتخاب می‌کند"), owned-team
  rule and shop as offline, and both screens auto-advance (45 s + 15 s). The pick goes out as the logged `'setup'`
  move; the match starts when seats 0 and 1 both have a setup in the log (both phones, log order). If the other
  side's setup is missing 75 s after sending ours, the phone logs a default setup FOR that side (`'for': seat`;
  room prefs if any, else club0/club1); the first setup per side in the log wins, so phones stay identical.
  Room matches: the room's pre-game choice is the starting pick. Seats 2..5 (team games) wait for seats 0/1.
  Legacy room matches (play moves logged, no setups) still start from room prefs as before.
- Re-check of the v3 asks in code: ball curl 0 (sim), rail .9 for ball + discs (walls), struck disc mass 5.5
  (collide), sim rate .95 (tick accumulator), real-time count-up clock, intro picks, in-match formation button
  — all wired in the running paths; unchanged.
- Tests: `test/games/finger_soccer_online_pick_test.dart` (pick -> setup -> match, idle timeouts + absent-side
  fallback, replay restart, legacy room prefs, room pick as start); constants test updated to v4.
- Match soundtrack off (owner request 2026-11-20): the finger soccer menu music never plays during a match. Fixed a
  race in `BmAudio.music`: a music(true) still creating its player when the match's music(false) arrived (the one
  setup frame before an auto-started offline match) started the soundtrack under the match; now the last call
  wins (checked after every await). The auto-start setup frame no longer requests music; the app soundtrack is
  already faded out by `MusicService.enterGame` while a game page is open and fades back on leaving. Crowd
  ambience and every sound effect (hits, goals, whistle) unchanged.

## Finger soccer v5 — shared pick clock, 85% speed, visible spin, side swap, team results (2026-11-20, branch `work/fs-v5`)
- Online picks finished (`intro/fs_online_pick.dart`, `ui/bm_view.dart`): team 15 s then formation 15 s on one shared
  countdown. The team pick is logged (`{'a': 'tpick'}`); a side that picks early waits on its team screen (banner +
  seconds left) until the other side's team pick (or setup) is in the log, or the team time + 3 s grace is over, so
  both phones open the formation screen on the same logged event. After the formation pick the screen waits
  ("منتظر بقیه‌ی بازیکن‌ها…") until both setups are in and everyone enters the match together. Absent-side fallback
  75 s -> 25 s. `tpick` is not a play move (legacy room-prefs start untouched).
- Scene speed `kBmSimRate` .95 -> .85 (same fixed steps, outcomes unchanged).
- Spin: discs pick up render-only spin from glancing contacts (`kBmDiscSpinK` .16, cap 22 rad/s; never feeds motion
  or the sync hash); the painter turns each disc by its angle and draws a small white rim notch; the ball sprite also
  turns by its spin angle on top of the roll direction.
- Goal mouth 3.5% narrower: `kBmGoalMouthScale` .965 narrows the goal sprite's width only (height / net depth kept);
  posts, mouth and side nets are still built from the drawn sprite, so colliders match the art.
- Room: the manager has "جابه‌جایی تیم ۱ و تیم ۲" (talk room games panel, finger soccer, 2+ picked): seat pairs
  0<->1, 2<->3, 4<->5 are swapped through `nx_room_select_players` (`fsSwapSides`), synced to every member. Note: that
  RPC re-inserts the picked players, so their room pre-game prefs reset (the in-match pick screens cover it).
- Team results (2v2 / 3v3): the reported `scores` are per seat (seat i = its side's goals) — the server books
  `scores[i]` per seat, so seats 2+ were booked 0. Seats that left (forfeited) are never in `winnerSeats` (they book a
  loss); their turns are played by the next teammate still in (`BmEngine.controllerSeat`, rotation counters
  unchanged); leaving from the game bar in a team game logs a forfeit for that seat only and shows the loss without
  ending the match (`GameResult.endsMatch` false); when a whole side has left, the other side wins at once.
- Tests: `test/games/finger_soccer_v5_test.dart` (shared clock, early-pick wait, idle timeouts + fallback, tpick
  replay, controller seat, 2v2 / 3v3 results per seat, draw, leaver), `test/worlds/fs_swap_sides_test.dart`.

## Finger soccer v7 — rail-like goals, formation button by the bar, 6 pitches removed, NX GIF balls (2026-11-20, branch `work/fs-v7`)
- Goal posts and the inside of the goal (side nets, back net) rebound exactly like the rails for the ball and every
  disc: normal restitution `kBmRailE` (.9), no tangential loss (`BmEngine.walls` / `BmEngine.post`). Before: ball
  nets .62-.72 / post impulse 1.54-1.7 (speed dependent), disc .48. Only the ball settling in the net after a goal
  (phase 'goal', play stopped) keeps its soft .2 / .3 damping. Contract row: `supabase/games/migrations/20261120040000_physics_fs_v7_rebound.sql`
  (documentation only, not applied).
- In-match "تغییر ترکیب" button moved down onto the game bar's row, right beside the bar handle (`kBmFormButtonLeft`,
  vertically centred on `kFsBarHandleHeight`); same button, same picker, same D11 rule. The "one minute left" toast
  moved one row up (where the button was). The button is still hidden only under the end-of-match score table.
- Pitches: Neon Cup, Street Cage, Sockerbox, Gold Leather, Neon Grass, Royal Gold removed (catalog entries, field +
  thumb art, `tool/fs_goal_cleanup.py` which only served them). They were the last six entries, so saved indices
  0..29 are unchanged; any saved / synced / room index that no longer exists becomes pitch 0 (`bmFieldIndex`, used by
  prefs, shop, room panel, online setup, room prefs and `BmEngine.startMatch`). No backend seed referenced them.
- Balls: NX Spin (index 5, the owner's "NX ball fixed center spin", 24 frames) and NX Star (index 6, the owner's
  "NX football", 16 frames), both 90 ms per frame, built by `tool/build_fs_nx_balls.py` from `tool/ball_src/`: GIF
  order kept, each frame re-centred on its silhouette (the source drifted ~3 px; output centre within 0.1 px),
  one scale per ball, anti-aliased circular trim, 160 px cells (ball radius 76 = kBmBallArtFill). Played with
  `BmAnimBall.gifTimed`: exactly frameMs per frame while the ball moves, held on the current frame at rest, no extra
  sprite rotation (only the GIF's own spin). NX Spin is the default (`kBmDefaultBall`); new preference key
  `bm.ball.v7` so every player starts on it once (the v6 key was also written automatically at each match start, so
  explicit picks could not be told apart); a pick in the shop / setup is kept under the new key.
- Tests: `test/games/finger_soccer_v7_test.dart` (rail / back net / side net / post parity for ball and disc on two
  pitches, speed-independent post, removed pitches + fallback incl. a saved removed pitch, default ball + GIF frame
  timing, formation button beside the bar and still opening the picker).
