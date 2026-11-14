class_name RoomLink
extends Node
## RoomLink: one realtime connection per joined room, shared by the lobby and the online match
## (exact port of src/online/link.ts).
##  - postgres_changes on rooms / room_players  → refetch room state (debounced 150 ms)
##  - broadcast 'chat'                           → text chat (max 80 kept)
##  - broadcast 'g'                              → match netcode (online_match.gd)
##  - broadcast 'sync'                           → "please refetch" pings (covers DELETEs, kicks)
##  - broadcast 'pi'/'po'                        → RTT probe every 3 s (never touches the DB)
##  - presence (key = user id)                   → who is connected right now
## Also: 12 s poll, 15 s heartbeat rpc (server sweeps players silent for 45 s), voice via Voice autoload.
##
## Usage: var l := RoomLink.new(room_id, my_uid, my_name); add it anywhere in the tree (if nobody does,
## it parents itself under Supa next frame). l.destroy() when leaving (it frees itself).
##
## Reliability:
##  - every 'g' message carries a per-sender counter "gi": duplicates are dropped before on_game listeners;
##  - send_game(): snapshots ("s") and aim streaming ("aim") are sent only while the channel is joined
##    (never queued -> no stale burst after a reconnect); everything else is queued <=5 s and flushed;
##  - app resume (Supa.app_resumed): heartbeat + refetch + "sync" ping at once; if we were away long
##    enough for the server sweep (45 s) to drop us from a waiting room, we re-enter it (join_room) once;
##  - state.offline_since = msec when the realtime link dropped (0 while connected).

signal changed
## (msg: Dictionary, from: String) — every 'g' broadcast
signal game(msg: Dictionary, from: String)

var id: String
var me: String
var my_name: String
## state: {room, players, online {uid:{name}}, chat [{id,uid,name,text,ts}], connected, loaded, gone, unread, rtt (int or null)}
var state := {"room": null, "players": [], "online": {}, "chat": [], "connected": false, "loaded": false, "gone": false, "unread": 0, "rtt": null, "offline_since": 0, "rejoined": false}
## game message kinds that are worthless when stale (sent only while joined, never queued)
const EPHEMERAL := ["s", "aim"]
const SWEEP_AFTER := 40.0
var chat_open := false
var dead := false
var ch: RtChannel = null

var _soon_t := -1.0
var _poll_t := 12.0
var _beat_t := 15.0
var _ping_t := 3.0
var _seen_online := {}
var _gl: Array[Callable] = []
var _refreshing := false
var _refresh_again := false
var _voice_joined := false
var _gi := 0                     # my outgoing game message counter
var _seen_gi := {}               # from -> {gi: true} (bounded)
var _seen_order := {}            # from -> Array of gi (FIFO)
var _chat_ids := {}
var _last_beat_ok := 0.0         # unix s of the last successful heartbeat rpc
var _maybe_swept := false
var _rejoining := false

func _init(room_id: String = "", my_uid: String = "", name_: String = "") -> void:
	id = room_id
	me = my_uid
	my_name = name_
	name = "RoomLink_" + room_id.substr(0, 8)
	if id == "":
		return
	_S().register_link(id, self)
	_connect()
	refresh()
	_beat()
	if _S().has_signal("app_resumed"):
		_S().app_resumed.connect(_on_resumed)
	_ensure_parent.call_deferred()

## Supa autoload, looked up at runtime (keeps this class compilable before autoloads exist, e.g. in -s tests)
static func _S():
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Supa") if ml else null

func _ensure_parent() -> void:
	if not dead and get_parent() == null and is_instance_valid(_S()):
		_S().add_child(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(dt: float) -> void:
	if dead:
		return
	if _soon_t >= 0.0:
		_soon_t -= dt
		if _soon_t < 0.0:
			refresh()
	_poll_t -= dt
	if _poll_t <= 0.0:
		_poll_t = 12.0
		refresh()
	_beat_t -= dt
	if _beat_t <= 0.0:
		_beat_t = 15.0
		_beat()
	_ping_t -= dt
	if _ping_t <= 0.0:
		_ping_t = 3.0
		_probe()

func get_state() -> Dictionary:
	return state

## heartbeat rpc (server sweeps silent players after 45 s); a failure retries after 4 s
func _beat() -> void:
	var r: Dictionary = await _S().call_rpc("heartbeat", {"p_room": id})
	if dead:
		return
	if r.ok:
		_last_beat_ok = Time.get_unix_time_from_system()
	else:
		_beat_t = minf(_beat_t, 4.0)

## back from the background: resync everything right away
func _on_resumed(away: float) -> void:
	if dead:
		return
	if away >= SWEEP_AFTER or (_last_beat_ok > 0.0 and Time.get_unix_time_from_system() - _last_beat_ok >= SWEEP_AFTER):
		_maybe_swept = true
	_beat_t = 15.0
	_beat()
	_poll_t = 12.0
	refresh()
	ping()
	_ping_t = 1.0

func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _patch(p: Dictionary) -> void:
	state.merge(p, true)
	changed.emit()

func _sfx(k: String) -> void:
	var s := get_node_or_null("/root/Sfx") if is_inside_tree() else (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")
	if s:
		s.play(k)

func _probe() -> void:
	if ch == null or not state.connected:
		return
	var room: Variant = state.room
	var host := str(room.get("host", "")) if room is Dictionary else ""
	var to := ""
	if host != "" and host != me and state.online.has(host):
		to = host
	else:
		for k in state.online:
			if k != me:
				to = k
				break
	if to == "":
		if state.rtt != null:
			_patch({"rtt": null})
		return
	ch.send_now("pi", {"t": _now_ms(), "f": me, "to": to})

func _connect() -> void:
	ch = _S().channel("room:" + id, {"broadcast": {"self": false, "ack": false}, "presence": {"key": me}})
	ch.on_postgres("*", "public", "rooms", "id=eq." + id, func(_c: Dictionary) -> void: soon())
	ch.on_postgres("*", "public", "room_players", "room_id=eq." + id, func(_c: Dictionary) -> void: soon())
	ch.on_broadcast("sync", func(_p: Variant) -> void: soon())
	ch.on_broadcast("chat", func(p: Variant) -> void: _add_chat(p))
	ch.on_broadcast("pi", func(p: Variant) -> void:
		if p is Dictionary and str(p.get("to", "")) == me:
			ch.send_now("po", {"t": p.get("t"), "to": p.get("f")}))
	ch.on_broadcast("po", func(p: Variant) -> void:
		if not (p is Dictionary) or str(p.get("to", "")) != me or not (p.get("t") is float or p.get("t") is int):
			return
		var r: int = max(1, _now_ms() - int(p.t))
		if r > 10000:
			return
		var prev: Variant = state.rtt
		_patch({"rtt": int(round(r if prev == null else float(prev) * 0.6 + r * 0.4))}))
	ch.on_broadcast("g", func(p: Variant) -> void:
		if not (p is Dictionary):
			return
		var from := str(p.get("from", ""))
		if from == me or _dup(from, p.get("gi")):
			return
		game.emit(p, from)
		for f in _gl.duplicate():
			if f.is_valid():
				f.call(p, from))
	ch.on_presence(func(ps: Dictionary) -> void:
		var online := {}
		for k in ps:
			var arr: Array = ps[k]
			online[k] = {"name": str(arr[0].get("name", "")) if arr.size() > 0 and arr[0] is Dictionary else ""}
		for k in online:
			if not _seen_online.has(k):
				_seen_online[k] = true
				if k != me and state.connected:
					_sfx("join")
		for k in _seen_online.keys():
			if not online.has(k):
				_seen_online.erase(k)
				if k != me:
					_sfx("leave")
		_patch({"online": online})
		soon())
	ch.subscribe(func(st: String) -> void:
		if dead:
			return
		if st == "SUBSCRIBED":
			_patch({"connected": true, "offline_since": 0})
			ch.track({"name": my_name})
			refresh()
			ping()   # others refetch: covers changes we missed while offline
		elif st == "CHANNEL_ERROR" or st == "TIMED_OUT" or st == "CLOSED":
			_patch({"connected": false, "offline_since": state.offline_since if int(state.offline_since) > 0 else _now_ms()}))

## debounced refetch (150 ms)
func soon() -> void:
	_soon_t = 0.15

func refresh() -> void:
	if dead:
		return
	if _refreshing:
		_refresh_again = true
		return
	_refreshing = true
	var res: Array = await _S().parallel([
		func() -> Dictionary: return await _S().select("rooms", "select=*&id=eq." + id, true),
		func() -> Dictionary: return await _S().select("room_players", "select=*,profiles(username,avatar,avatar_url,level,rating,league,equipped_disc)&room_id=eq." + id + "&order=joined_at"),
	])
	_refreshing = false
	if dead:
		return
	var r: Dictionary = res[0]
	var p: Dictionary = res[1]
	if r.ok and p.ok:
		var players: Array = p.data if p.data is Array else []
		var mine := false
		for x in players:
			if x is Dictionary and str(x.get("user_id", "")) == me:
				mine = true
				break
		var gone: bool = r.data == null or not mine
		if gone and r.data != null and _maybe_swept and not _rejoining:
			# dropped by the server sweep while backgrounded -> re-enter the room once
			_maybe_swept = false
			_rejoining = true
			var j: Dictionary = await _S().call_rpc("join_room", {"p_room": id})
			_rejoining = false
			if dead:
				return
			if j.ok:
				_patch({"rejoined": true})
				ping()
				_refresh_again = false
				refresh()
				return
		if mine:
			_maybe_swept = false
		_patch({"room": r.data if r.data != null else state.room, "players": players, "loaded": true, "gone": gone})
	if _refresh_again:
		_refresh_again = false
		refresh()

## ask everyone in the room to refetch
func ping() -> void:
	if ch:
		ch.send_broadcast("sync", {})

func _add_chat(c: Variant) -> void:
	if not (c is Dictionary) or not (c.get("text") is String):
		return
	var cid := str(c.get("id", ""))
	if cid != "":
		if _chat_ids.has(cid):
			return
		_chat_ids[cid] = true
		if _chat_ids.size() > 200:
			_chat_ids.erase(_chat_ids.keys()[0])
	var m: Dictionary = c.duplicate()
	m.text = str(m.text).substr(0, 200)
	var chat: Array = state.chat.duplicate()
	chat.append(m)
	if chat.size() > 80:
		chat = chat.slice(chat.size() - 80)
	var mine := str(m.get("uid", "")) == me
	if not mine:
		_sfx("chat")
	_patch({"chat": chat, "unread": 0 if (chat_open or mine) else int(state.unread) + 1})

func send_chat(text: String) -> void:
	var t := text.strip_edges().substr(0, 200)
	if t == "":
		return
	var c := {"id": "%d-%s" % [_now_ms(), _rand36(5)], "uid": me, "name": my_name, "text": t, "ts": _now_ms()}
	_add_chat(c)
	if ch:
		ch.send_broadcast("chat", c)

func mark_read() -> void:
	if int(state.unread) != 0:
		_patch({"unread": 0})

## subscribe to 'g' messages; returns a Callable that unsubscribes
func on_game(f: Callable) -> Callable:
	_gl.append(f)
	return func() -> void: _gl.erase(f)

## Returns false when the message could not be sent (ephemeral kinds while disconnected).
func send_game(m: Dictionary) -> bool:
	if ch == null:
		return false
	var p := m.duplicate()
	p["from"] = me
	_gi += 1
	p["gi"] = _gi
	if str(p.get("k", "")) in EPHEMERAL:
		return ch.send_now("g", p)
	return ch.send_broadcast("g", p)

## true when (from, gi) was seen already (messages without gi are never treated as duplicates)
func _dup(from: String, gi: Variant) -> bool:
	if not (gi is int or gi is float):
		return false
	var g := int(gi)
	if not _seen_gi.has(from):
		_seen_gi[from] = {}
		_seen_order[from] = []
	var seen: Dictionary = _seen_gi[from]
	if seen.has(g):
		return true
	seen[g] = true
	var order: Array = _seen_order[from]
	order.append(g)
	if order.size() > 256:
		seen.erase(order.pop_front())
	return false

# ---------------------------------------------------------------- match end helpers (server: supabase/migrations/20261113170000_online_fixes.sql)
## Host quits a running match: forfeit when opponents are still here (a losing host can no longer wipe the
## match), plain abandon otherwise. Falls back to abandon_match on servers without host_forfeit.
## score = [a, b] as last simulated. Returns the rpc result (data.outcome = "forfeit" | "abandoned" | "none").
func host_quit(match_id: String, score: Array = [0, 0]) -> Dictionary:
	var r: Dictionary = await _S().call_rpc("host_forfeit", {"p_match": match_id, "p_score_a": int(score[0]) if score.size() > 0 else 0, "p_score_b": int(score[1]) if score.size() > 1 else 0})
	if not r.ok and (int(r.get("status", 0)) == 404 or str(r.get("raw", "")).contains("PGRST202")):
		r = await _S().call_rpc("abandon_match", {"p_match": match_id})
	if not dead:
		ping()
	return r

## The host vanished mid-match (≥30 s silent server-side): take over the room and settle the match
## (host's team forfeits if its opponents are here, else abandoned). score = last snapshot seen.
## Errors: "host still online" (retry later) / "match not live" (already settled).
func claim_host_lost(match_id: String, score: Array = [0, 0]) -> Dictionary:
	var r: Dictionary = await _S().call_rpc("claim_host_lost", {"p_match": match_id, "p_score_a": int(score[0]) if score.size() > 0 else 0, "p_score_b": int(score[1]) if score.size() > 1 else 0})
	if not dead:
		ping()
		refresh()
	return r

# ---------------------------------------------------------------- voice (Voice autoload, one room at a time)
func voice() -> Node:
	return _S().get_node_or_null("/root/Voice")

func voice_join() -> void:
	var v := voice()
	if v and v.has_method("join"):
		_voice_joined = true
		v.join(id)

func voice_leave() -> void:
	var v := voice()
	if v and _voice_joined and v.has_method("leave"):
		v.leave()
	_voice_joined = false

func destroy() -> void:
	if dead:
		return
	dead = true
	_S().unregister_link(id, self)
	if _S().has_signal("app_resumed") and _S().app_resumed.is_connected(_on_resumed):
		_S().app_resumed.disconnect(_on_resumed)
	# leave voice if it is (or may be) this room's session
	var v := voice()
	if v and v.has_method("leave"):
		var vr: Variant = v.get("room_id")
		if _voice_joined or (vr != null and str(vr) == id):
			v.leave()
	if ch:
		var c := ch
		ch = null
		c.untrack()
		# give the untrack push a moment to go out, then leave the channel
		_S().get_tree().create_timer(0.2).timeout.connect(func() -> void: _S().remove_channel(c))
	_gl.clear()
	for con in changed.get_connections():
		changed.disconnect(con.callable)
	if is_inside_tree():
		queue_free()
	else:
		call_deferred("free")  # not in a tree: free next idle frame (lambda + bare free() fails to parse on export)

func _rand36(n: int) -> String:
	const A := "0123456789abcdefghijklmnopqrstuvwxyz"
	var s := ""
	for i in n:
		s += A[randi() % 36]
	return s
