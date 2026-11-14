# NET API (owner: NET worker)

All calls are coroutines (`await`). Every network call returns `{ok: bool, data: Variant, error: String (fa), status: int (HTTP, 0 = network), raw: String (original message)}` and never throws.

## IMPORTANT: Supa.rpc
`Node.rpc()` is a native method. `Supa.rpc(fn, args)` works through the **autoload name** (`await Supa.rpc("heartbeat", {"p_room": id})`), because it is declared variadic so it can shadow `Node.rpc`.
If you hold Supa in a variable **typed `Node`**, `.rpc()` resolves to the native `Node.rpc` → returns an `Error` int. Then use `Supa.call_rpc(fn, args) -> Dictionary` (same thing, typed) or keep the variable untyped.

## Supa (autoload, res://src/net/supa.gd)
- state: `session` (Dictionary|null), `profile` (own profiles row, live), `session_ready`, `recovery`, `discs` (NxDiscs node), `socket` (shared RtChannel.Socket)
- signals: `auth_changed(event: String, session)` events INITIAL_SESSION | SIGNED_IN | SIGNED_OUT | TOKEN_REFRESHED | USER_UPDATED | PASSWORD_RECOVERY; `profile_changed(profile)`; `app_resumed(away_seconds)` (after sockets were woken)
- `uid() -> String`, `signed_in() -> bool`, `email() -> String`, `is_guest() -> bool`, `access_token() -> String`
- auth: `ensure() -> String uid` (anonymous on demand, deduped), `sign_in_anon()`, `sign_up_email(email, pass, username := "")` (data.info == "confirm" when e-mail confirmation is required), `sign_in_email(email, pass)`, `upgrade(email, pass)` (guest → e-mail, same uid), `set_new_password(pass)`, `update_user(attrs)`, `reset_password(email)`, `resend(email)`, `set_session_tokens(access, refresh, type := "")`, `handle_auth_url(url)` (nexora://auth#access_token=…), `sign_out()` (calls leave_all_rooms first), `set_username(name)` (RN validation), `refresh_profile()`, `refresh_session()`
  - session persisted in user://session.json; expiry kept on the LOCAL clock (expires_in), refresh 60 s before expiry, on APPLICATION_RESUMED/FOCUS_IN, and before any request when < 15 s left; a 401 "JWT expired" from REST/functions refreshes once and retries; only a dead refresh token (GoTrue invalid_grant / refresh_token_not_found …) signs out — 408/429/5xx/network keep the session and retry with backoff. Account switch / sign-out destroys every live RoomLink.
- REST: `rest(method, path, body := null, prefer := "", extra_headers := [])`, `select(table, query := "select=*", single := false)` (single → first row or null), `insert(table, rows, returning := true)`, `upsert(table, rows, on_conflict := "", ignore_duplicates := false, returning := true)`, `update(table, filter, patch, returning := false)`, `delete(table, filter, returning := false)`, `count(table, filter := "") -> data:int`
  - query strings are raw PostgREST: `"select=*,profiles(username,avatar)&room_id=eq.%s&order=joined_at" % id`
- `rpc(fn, args := {})` / `call_rpc(fn, args := {})`
- `fn_invoke(name, body := {})` (Bearer user token + apikey; on HTTP error `status` and `data` (parsed body) are still set)
- `upload(bucket, path, bytes, mime := "image/jpeg", upsert := false) -> data: public url`, `public_url(bucket, path)`
- `parallel([callable, ...]) -> Array` run coroutine callables concurrently
- realtime: `channel(name, opts := {}, socket := null) -> RtChannel`, `remove_channel(ch)`, `new_socket()`, `close_socket(s)`
- `err_fa(msg_or_result) -> String` (exact port of errFa)
- `link_for(room_id) -> RoomLink|null` (registry of live RoomLinks)

## RtChannel (res://src/net/realtime.gd)
`ch = Supa.channel("room:<id>", {broadcast = {self = false, ack = false}, presence = {key = uid}})`
- `on_broadcast(event, cb(payload))` ("*" = all), `on_postgres(event, schema, table, filter, cb(change))` with change = `{eventType, schema, table, commit_timestamp, new, old, errors}`, `on_presence(cb(state))` state = `{key: [{presence_ref, ...meta}]}`, `on_presence_join(cb(key, current, new))`, `on_presence_leave(cb(key, current, left))`, `on_system(cb(payload))`
- `subscribe(cb(status))` status: SUBSCRIBED | CHANNEL_ERROR | TIMED_OUT | CLOSED (repeats: drop → CHANNEL_ERROR → auto rejoin → SUBSCRIBED)
- `send_broadcast(event, payload) -> bool` (queued ≤5 s while not joined), `send_now(event, payload) -> bool` (only if joined; never queued — for high-rate data), `track(meta)` (re-tracked automatically after every rejoin), `untrack()`, `presence_state()`, `is_joined()`, `unsubscribe()`
- socket: heartbeat 20 s, unanswered heartbeat → reconnect after 8 s (4 s right after app resume), jittered backoff 0.5/1/2/5/10 s. Two channels with the same topic on one socket are safe: the newest owns the server join, older ones are "shadowed" (still receive everything, send through the owner, never send phx_leave).
- signals: status_changed, broadcast(event, payload), presence_sync(state), postgres_change(change), system_message(payload)

## RoomLink (res://src/net/room_link.gd, extends Node)
`RoomLink.new(room_id, my_uid, my_name)`; parents itself under Supa if nobody adds it to the tree.
- `state = {room, players, online {uid:{name}}, chat [{id,uid,name,text,ts}], connected, loaded, gone, unread, rtt}`; `signal changed`; `signal game(msg, from)`
- `refresh()`, `soon()`, `ping()` (broadcast "sync"), `send_chat(text)`, `mark_read()`, `chat_open`, `on_game(cb(msg, from)) -> unsubscribe Callable`, `send_game(dict) -> bool` (k "s"/"aim" only while connected, others queued; every message gets a per-sender `gi`, duplicates are dropped before listeners), `voice()`, `voice_join()`, `voice_leave()`, `destroy()` (frees itself)
- state also has `offline_since` (msec, 0 while connected) and `rejoined` (true after an automatic re-entry: app resumed after ≥40 s and the server sweep had dropped us from a waiting room)
- match end: `await host_quit(match_id, [sa, sb])` (host quits: rpc host_forfeit — forfeit when opponents are present, else abandon; falls back to abandon_match), `await claim_host_lost(match_id, [sa, sb])` (host silent ≥30 s server-side: caller becomes host, host team forfeits or match is abandoned; data.outcome = "forfeit" | "abandoned"; error "host still online" → retry later)

## NxDiscs (Supa.discs, res://src/net/discs.gd)
`stats(id) -> {power, accuracy}`, `price(id)`, `is_free(id)`, `has(id)`, `equipped()`, `catalog`, `owned`, `loaded`, `signal changed`, `buy(id)`, `equip(id)`, `buy_and_equip(id, name) -> bool`, `load_catalog()`, `load_owned()`

## online_match (res://src/online/online_match.gd, screen "online_match")
Nav params `{room_id, match_id, link?, before?}`. Exits: `Nav.go("online_result", {o, outcome, room_id, before, link})`, `Nav.go("lobby", {room_id, skip_match, why: "quit"|"hostLost"|"aborted", link})`.
Outcome dict: `{match_id, score [a,b], winner -1|0|1, rating_delta int|null, my_team 0|1|null, teams [team dict, team dict], team_ids, names, reported, ranked}`.
Static helpers: `cfg_from_room(room)`, `rule_label(settings)`, `disc_of(player)`, `team_of(players, t)`, `team_of_avatar(key)`, `enc_ev(e)`, `dec_ev(a)`.

## Sfx (src/core/sfx.gd, NET-owned since 2026-11-13)
- `Sfx.play_goal()` — goal horn (PCM) + crowd roar 120 ms later, crowd loop ducked 2.2 s. `Sfx.play("goal")` routes to it (a following `play("roar")` within 150 ms is skipped).
- Music: plays only in the main-menu shell; fully stopped (not ducked) in every online screen, matches, the intro, and while voice is connecting/on, the mic is on or anyone is speaking. Follows `Nav.screen_changed` by itself; `music(on)`/`menu_music(on)` only gate it (music(true) never starts it outside the menu). `Sfx.music_playing()`, `Sfx.audio_state()`.

## Server (supabase/migrations)
- 20261113170000_online_fixes.sql (applied): `claim_host_lost(p_match, p_score_a, p_score_b)`, `host_forfeit(p_match, p_score_a, p_score_b)` → jsonb (report_match fields + outcome).
- 20261113170100_online_fixes_abandon_forfeit_PENDING.sql (NOT applied): abandon_match forfeits instead of wiping when opponents are still connected.
