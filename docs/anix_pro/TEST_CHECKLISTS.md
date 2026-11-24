# ANIX PRO — per-game test checklists (26 games)

Manual checklists for a tester with real Android phones. **None of these have been run on a device by the build
agent** — the agent has only the analyzer, `flutter test` (unit + widget tests) and the CI APK build. Everything a
checklist asks for is what automated tests cannot see: touch feel, sound, frame rate, two real phones on real
networks, voice.

How to use: install the `ANIX-arm64-v8a-apk` artifact of the latest green *ANIX PRO Android Build* on the
`arena/5a46ff7d-cocos-c` branch. Tick each box, note the phone model + Android version, and file anything that fails
with a screen recording.

Common to every game (do once per game, in addition to its own list):

- [ ] Opens from Arcade (tile, then mode sheet) without a blank frame or a layout overflow stripe.
- [ ] Persian and English: every label translated, RTL correct, no clipped text.
- [ ] Sound on / off in Settings is honoured in the game (effects and music).
- [ ] Back gesture / exit button asks before leaving a running match and returns to Arcade.
- [ ] Result screen: XP / coins shown, *Play again* and *Back* work; stats on the profile move by one match.
- [ ] Rotating the phone or pulling down the notification shade mid-match does not freeze or reset the game.
- [ ] Online (where supported): quick match, private room by code, a friend's invite, leaving mid-match (forfeit),
      reconnect after turning Wi-Fi off for 10 s, and the result booked on both phones (leaderboard moves).
- [ ] Online player counts stay inside the live `nx_game_bounds` (see each game). The client never offers more seats.

Player counts below are the live server bounds (`nx_game_bounds`, verified 2026-11-22); offline counts come from
`lib/games/game_registry.dart`.

---

## The nine originals

### 1. Finger Soccer (`finger_soccer`) — offline 2 (bot / pass-and-play), online 2–6 (1v1, 2v2, 3v3)
- [ ] Intro: team screen shows the three categories (Cars 24, Sport 12, NX 12); locked teams show their gem price;
      NX Core / NX Pulse / NX Inferno are free.
- [ ] Formation screen: 9 formations, the pick reaches the match.
- [ ] Only 5 pitches in the shop / setup (Silver Checker, Green Rings, Street, Neon Blue, Royal Purple; Persian names in Persian UI); 18 balls. Walls, corners, posts and nets match each art; the live score sits in each art's side displays.
- [ ] Match screen (v9, Flame): top bar has only menu + clock + formation button; no score in the top bar.
- [ ] The live score is drawn on the art's two side displays: left (blue) = bottom side, right = top side; both
      digits update on every goal, including 10+.
- [ ] Flick feel: pull back and release shoots; a short tap does nothing; two fingers do not double-shoot.
- [ ] Posts / side nets / back net rebound like rails; the ball never passes through a post or out of the frame.
- [ ] **Neon Arena bottom goal:** the drawn net is ~17 art px deeper than the collider (both goals use the shallower
      net depth so mirrored phones stay deterministic). Check the ball stopping in the bottom net looks acceptable.
- [ ] Goal: announcer, crowd, fireworks in the pitch's colours, kickoff reset.
- [ ] Last minute: "one minute left" toast once (bottom strip), clock turns red; golden goal on a draw where enabled.
- [ ] End: score table with avatars, then the host result screen.
- [ ] In-match formation change on your kickoff applies at once; otherwise from the next kickoff.
- [ ] Online: team pick 15 s then formation 15 s on one shared countdown; an idle phone still gets a default.
- [ ] Online 2v2 / 3v3: turns rotate between teammates; a leaver books a loss only for that seat.
- [ ] Online voice: mic / speaker buttons sit in the bottom strip, outside the pitch, and never cover the playfield.
      (There is no microphone in offline matches.)
- [ ] Seat 1 sees the pitch rotated 180° (own side at the bottom).
- [ ] Frame rate stays smooth on a mid-range phone with fancy effects on and off.

### 2. Carrom (`carrom`) — offline 2, online 2
- [ ] Striker placement on the baseline, aim and power feel; queen + cover rule; fouls (striker pocketed).
- [ ] Wooden men use the owner's ANIX wood sets; pockets register reliably.
- [ ] Online: shots relayed, the board ends identical on both phones after every shot.

### 3. Billiards (`billiards`) — offline 2, online 2
- [ ] Cue aim line, spin, power; groups assigned on the first legal pot; ball-in-hand after a foul.
- [ ] Cue skins from the shop apply.
- [ ] Online: identical table on both phones after each shot.

### 4. Backgammon / تخته‌نرد (`backgammon`) — offline 2, online 2
- [ ] Dice, legal moves only, bar entry, bearing off, gammon / backgammon scoring.
- [ ] Undo inside a turn (if offered); turn passes when no move is possible.
- [ ] Online: moves logged in order, rejoin replays the log.

### 5. Ludo (`ludo`) — offline 2–4, online 2–4
- [ ] Six to leave base, captures send home, safe squares, exact roll to finish.
- [ ] Bots move on their own turns without long pauses.

### 6. Snakes & Ladders (`snakes_ladders`) — offline 2–4, online 2–4
- [ ] Dice animation, ladders up, snakes down, exact finish.

### 7. NX Cards (UNO-style) (`uno`) — offline 2–4, online 2–4
- [ ] Draw / skip / reverse / wild rules; "last card" call; hands hidden from other players online.

### 8. Quiz (`quiz`) — offline 2, online 2
- [ ] Questions in the selected language; timer; correct / wrong feedback; no repeated question in one match.

### 9. Mafia (`mafia`) — offline 6–12 (pass-and-play), online 6–12
- [ ] Roles dealt; night / day phases; voting; each phone shows only what that player may know.
- [ ] Online with 6+ phones: night actions resolve once; dead players can no longer vote.

## Arcade multiplayer (7) — online 2–4 except where noted

### 10. Kart Racing (`kart_racing`)
- [ ] Steering / drift feel, lap counter, bots, finish order.
### 11. Obstacle Race (`obstacle_race`)
- [ ] Jumps / hazards register fairly; respawn; finish order.
### 12. Bomb Arena (`bomb_arena`)
- [ ] Bombs, crates, power-ups, chain blasts; last player standing.
### 13. 8-Ball Pool (`pool8`) — online 2
- [ ] Break, groups, 8-ball rules (early 8 loses), ball-in-hand.
### 14. Mini Golf (`mini_golf`)
- [ ] Aim / power, walls, hole-in, stroke count per hole and total.
### 15. Basketball Battle (`basketball_battle`)
- [ ] Shot arc, score, timer, winner.
### 16. Spy & Mafia (`spy_mafia`) — online 4–8
- [ ] Roles hidden per phone, clue / vote rounds, win conditions.

For every group game (10–12, 14, 15): online rooms offer **at most 4 players**. The server's `nx_game_bounds`
allows 2–4 for them and there is no server migration for larger groups; the client stays inside those bounds.

## Arcade solo (10) — offline only, global score board

For each: controls respond on the first touch, score / personal best / medal (bronze / silver / gold) shown, the
daily challenge uses today's seed, the score reaches the board when signed in.

### 17. Endless Runner (`endless_runner`) — [ ] lane swipes, jump / slide, speed ramps
### 18. Tetris Rush (`tetris_rush`) — [ ] rotate, soft / hard drop, line clears, level speed
### 19. Helix Jump (`helix_jump`) — [ ] tower rotates with the finger, platforms break, game over on red
### 20. Fruit Ninja (`fruit_ninja`) — [ ] slice trails, combos, bombs end the run
### 21. Geo Dash (`geo_dash`) — [ ] tap-to-jump timing, spikes, progress bar
### 22. Traffic Racer (`traffic_racer`) — [ ] tilt / touch steering, near-miss bonus, crash
### 23. Stack Tower (`stack_tower`) — [ ] tap timing, overhang trimmed, perfect bonus
### 24. Bubble Shooter (`bubble_shooter`) — [ ] wall bounce aim, clusters of 3 pop, ceiling drop
### 25. Knife Hit (`knife_hit`) — [ ] knives stick, hitting a knife ends the run, boss logs
### 26. 2048 (`game_2048`) — [ ] swipes merge correctly, undo (if offered), 2048 tile win
