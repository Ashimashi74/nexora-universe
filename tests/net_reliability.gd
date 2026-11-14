extends SceneTree
## Offline reliability test of the NET layer (src/net/realtime.gd + src/net/room_link.gd) — no network.
##   godot --headless --script res://tests/net_reliability.gd
##
## An in-process fake Supabase Realtime server (Phoenix vsn 1.0.0 semantics that matter here: join replies,
## heartbeats, broadcast fan-out with self=false, presence track/diff, duplicate join → phx_close to the old
## join_ref, phx_leave by topic regardless of join_ref) talks to real RtChannel.Socket instances through the
## Socket.transport test hook. A fake "Supa" autoload replaces the real one for RoomLink (REST/RPC stubs).
##
## Checks: subscribe + presence for two clients, ordered/duplicate-free game stream (server duplicates
## frames), half-open connection detected by heartbeat timeout after wake(), automatic reconnect + rejoin +
## presence re-track, ephemeral messages (snapshots) are not queued while offline but reliable ones
## (result) are, same-topic double subscription neither flip-flops nor gets killed by the stale leave,
## RoomLink re-enters a waiting room after the server sweep dropped it during a long background,
## channel/socket cleanup (no leaks) after destroy.

var fails := 0
var passes := 0

func ok(c: bool, what: String, extra: Variant = "") -> void:
	if c: passes += 1
	else: fails += 1
	print("  %s  %s  %s" % ["PASS" if c else "FAIL", what, str(extra) if str(extra) != "" else ""])

# ============================================================================ fake server
class FakeServer extends RefCounted:
	var socks: Array = []
	var presences := {}        # topic -> {ws_id: {key, meta}}
	var joins := 0
	var leaves := 0
	var dup_rate := 0.0        # probability a broadcast frame is delivered twice
	var refuse := false        # new connections fail (offline)
	var ref_n := 0
	var log_dup_closes := 0

	func open(_endpoint: String) -> FakeWS:
		var w := FakeWS.new(self)
		w.state = WebSocketPeer.STATE_CLOSED if refuse else WebSocketPeer.STATE_CONNECTING
		socks.append(w)
		return w

	func _send(w: FakeWS, topic: String, event: String, payload: Variant, ref: Variant = null, join_ref: Variant = null) -> void:
		if w.state != WebSocketPeer.STATE_OPEN or w.blackhole:
			return
		w.inbox.append(JSON.stringify({"topic": topic, "event": event, "payload": payload, "ref": ref, "join_ref": join_ref}))

	func recv(w: FakeWS, text: String) -> void:
		if w.blackhole:
			return
		var m: Dictionary = JSON.parse_string(text)
		var topic := str(m.topic)
		var ev := str(m.event)
		var ref = m.get("ref")
		var jref = m.get("join_ref")
		if topic == "phoenix" and ev == "heartbeat":
			_send(w, "phoenix", "phx_reply", {"status": "ok", "response": {}}, ref, null)
			return
		match ev:
			"phx_join":
				if w.chans.has(topic):
					# Phoenix: duplicate join closes the existing channel (phx_close with ITS join_ref)
					log_dup_closes += 1
					_send(w, topic, "phx_close", {}, w.chans[topic], w.chans[topic])
					_presence_leave(w, topic)
				w.chans[topic] = str(jref)
				joins += 1
				var pg: Array = []
				var cfg: Dictionary = m.payload.get("config", {})
				for i in (cfg.get("postgres_changes", []) as Array).size():
					pg.append({"id": 1000 + i})
				_send(w, topic, "phx_reply", {"status": "ok", "response": {"postgres_changes": pg}}, ref, jref)
				_send(w, topic, "presence_state", _pres_state(topic), null, jref)
			"phx_leave":
				# Phoenix routes phx_leave by topic: a stale join_ref still kills the current channel
				if w.chans.has(topic):
					leaves += 1
					w.chans.erase(topic)
					_presence_leave(w, topic)
				_send(w, topic, "phx_reply", {"status": "ok", "response": {}}, ref, jref)
			"broadcast":
				if not w.chans.has(topic):
					return
				for o in socks:
					if o != w and o.chans.has(topic):
						_send(o, topic, "broadcast", m.payload, null, null)
						if dup_rate > 0.0 and randf() < dup_rate:
							_send(o, topic, "broadcast", m.payload, null, null)
			"presence":
				if not w.chans.has(topic):
					return
				var pl: Dictionary = m.payload
				if str(pl.get("event")) == "track":
					_presence_leave(w, topic)
					ref_n += 1
					var meta: Dictionary = (pl.get("payload", {}) as Dictionary).duplicate()
					meta["phx_ref"] = "p%d" % ref_n
					var key := str(w.key_for.get(topic, "anon"))
					if not presences.has(topic): presences[topic] = {}
					presences[topic][w.id] = {"key": key, "meta": meta}
					_fan(topic, "presence_diff", {"joins": {key: {"metas": [meta]}}, "leaves": {}})
				else:
					_presence_leave(w, topic)
			"access_token":
				pass

	func _presence_leave(w: FakeWS, topic: String) -> void:
		if presences.has(topic) and presences[topic].has(w.id):
			var e: Dictionary = presences[topic][w.id]
			presences[topic].erase(w.id)
			_fan(topic, "presence_diff", {"joins": {}, "leaves": {e.key: {"metas": [e.meta]}}})

	func _pres_state(topic: String) -> Dictionary:
		var out := {}
		for wid in presences.get(topic, {}):
			var e: Dictionary = presences[topic][wid]
			if not out.has(e.key): out[e.key] = {"metas": []}
			out[e.key].metas.append(e.meta)
		return out

	func _fan(topic: String, ev: String, payload: Dictionary) -> void:
		for o in socks:
			if o.chans.has(topic):
				_send(o, topic, ev, payload, null, null)

	func drop(w: FakeWS) -> void:
		# server side cleanup of a dead connection
		for t in w.chans.keys():
			_presence_leave(w, t)
		w.chans.clear()
		socks.erase(w)

class FakeWS extends RefCounted:
	static var _n := 0
	var id := 0
	var srv: FakeServer
	var state := WebSocketPeer.STATE_CONNECTING
	var inbox: Array = []
	var chans := {}            # topic -> join_ref (server side)
	var key_for := {}          # topic -> presence key (from join config)
	var blackhole := false     # half-open: nothing gets through either way
	func _init(s: FakeServer) -> void:
		_n += 1
		id = _n
		srv = s
	func poll() -> void:
		if state == WebSocketPeer.STATE_CONNECTING:
			state = WebSocketPeer.STATE_OPEN
	func get_ready_state() -> int: return state
	func get_available_packet_count() -> int: return inbox.size() if not blackhole else 0
	func get_packet() -> PackedByteArray: return str(inbox.pop_front()).to_utf8_buffer()
	func send_text(t: String) -> int:
		if state != WebSocketPeer.STATE_OPEN: return ERR_UNAVAILABLE
		var m: Variant = JSON.parse_string(t)
		if m is Dictionary and str(m.get("event")) == "phx_join":
			var cfg: Dictionary = m.payload.get("config", {})
			key_for[str(m.topic)] = str(cfg.get("presence", {}).get("key", ""))
		srv.recv(self, t)
		return OK
	func close(_code: int = 1000, _reason: String = "") -> void:
		if state == WebSocketPeer.STATE_CLOSED: return
		state = WebSocketPeer.STATE_CLOSED
		srv.drop(self)
	func get_close_code() -> int: return 1000
	func get_close_reason() -> String: return ""

class Transport extends RefCounted:
	var srv: FakeServer
	func _init(s: FakeServer) -> void: srv = s
	func open(endpoint: String) -> Object: return srv.open(endpoint)

# ============================================================================ fake Supa (for RoomLink)
class FakeSupa extends Node:
	signal app_resumed(away: float)
	var sock: RtChannel.Socket
	var room := {"id": "R", "host": "A", "status": "waiting", "settings": {}}
	var players: Array = []
	var rpcs: Array = []
	var links := {}
	func channel(n: String, o: Dictionary = {}, _s = null) -> RtChannel: return sock.channel(n, o)
	func remove_channel(c: RtChannel) -> void: if c: c.unsubscribe()
	func register_link(r: String, l: Object) -> void: links[r] = l
	func unregister_link(r: String, l: Object) -> void: if links.get(r) == l: links.erase(r)
	func call_rpc(fn: String, args: Dictionary = {}) -> Dictionary:
		await get_tree().process_frame
		rpcs.append(fn)
		if fn == "join_room":
			var me := str(get_meta("me", ""))
			players.append({"user_id": me, "role": "player", "team": 1, "slot": 0})
		return {"ok": true, "data": null, "error": "", "status": 200, "raw": ""}
	func select(t: String, _q: String = "", single := false) -> Dictionary:
		await get_tree().process_frame
		if t == "rooms": return {"ok": true, "data": room if single else [room], "status": 200}
		return {"ok": true, "data": players.duplicate(true), "status": 200}
	func parallel(calls: Array) -> Array:
		var out: Array = []
		for c in calls: out.append(await c.call())
		return out

# ============================================================================ helpers
var srv := FakeServer.new()
var sockets: Array = []

func mk_socket() -> RtChannel.Socket:
	var s := RtChannel.Socket.new("https://fake.local", "anon")
	s.transport = Transport.new(srv)
	sockets.append(s)
	return s

func pump() -> void:
	for s in sockets: s.poll()

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000):
			return false
		pump()
		await process_frame
	return true

func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000):
		pump()
		await process_frame

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void: print("WATCHDOG TIMEOUT"); quit(2))
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var t_start := Time.get_ticks_msec()
	# ------------------------------------------------------------ 1. channels, presence, ordered stream
	print("== RtChannel: subscribe, presence, ordering, duplicates")
	var sa := mk_socket()
	var sb := mk_socket()
	var ca := sa.channel("room:X", {"broadcast": {"self": false}, "presence": {"key": "A"}})
	var cb := sb.channel("room:X", {"broadcast": {"self": false}, "presence": {"key": "B"}})
	var got: Array = []
	var a_status: Array = []
	cb.on_broadcast("g", func(p: Variant) -> void: got.append(p))
	ca.subscribe(func(s: String) -> void:
		a_status.append(s)
		if s == "SUBSCRIBED": ca.track({"name": "a"}))
	cb.subscribe(func(s: String) -> void:
		if s == "SUBSCRIBED": cb.track({"name": "b"}))
	ok(await wait_until(func() -> bool: return ca.is_joined() and cb.is_joined(), 3.0), "both channels SUBSCRIBED")
	ok(await wait_until(func() -> bool: return ca.presence_state().has("B") and cb.presence_state().has("A"), 3.0), "presence sees each other")
	for i in 200:
		ca.send_broadcast("g", {"q": i})
	await wait_until(func() -> bool: return got.size() >= 200, 3.0)
	var ordered := true
	for i in got.size():
		if int(got[i].q) != i: ordered = false
	ok(got.size() == 200 and ordered, "200 messages delivered in order, none lost", got.size())

	# ------------------------------------------------------------ 2. half-open connection
	print("== half-open socket: heartbeat timeout after wake(), reconnect, rejoin, re-track")
	var ws_a: FakeWS = sa.ws
	ws_a.blackhole = true                       # NAT rebinding / network switch: nothing gets through
	var t0 := Time.get_ticks_msec()
	sa.wake()                                   # what Supa does on APPLICATION_RESUMED
	ok(await wait_until(func() -> bool: return not sa.connected or sa.ws != ws_a, 8.0), "dead socket detected", "%d ms" % (Time.get_ticks_msec() - t0))
	srv.drop(ws_a)                              # server times the old connection out too
	ok(await wait_until(func() -> bool: return ca.is_joined(), 6.0), "reconnected + rejoined", "%d ms total" % (Time.get_ticks_msec() - t0))
	ok("CHANNEL_ERROR" in a_status and a_status[a_status.size() - 1] == "SUBSCRIBED", "status CHANNEL_ERROR → SUBSCRIBED", a_status)
	ok(await wait_until(func() -> bool: return cb.presence_state().has("A"), 3.0), "presence re-tracked after rejoin")

	# ------------------------------------------------------------ 3. RoomLink: dedupe, ephemeral vs reliable while offline
	print("== RoomLink over the fake server")
	var real_supa := root.get_node_or_null("Supa")
	if real_supa:
		root.remove_child(real_supa)
	var fs := FakeSupa.new()
	fs.name = "Supa"
	fs.sock = mk_socket()
	fs.players = [{"user_id": "A", "role": "player", "team": 0, "slot": 0}, {"user_id": "B", "role": "player", "team": 1, "slot": 0}]
	root.add_child(fs)
	var fs_b_sock := mk_socket()
	var la := RoomLink.new("R", "A", "Ann")
	root.add_child(la)
	# B on its own socket: swap the fake's socket while constructing
	var keep := fs.sock
	fs.sock = fs_b_sock
	var lb := RoomLink.new("R", "B", "Bob")
	root.add_child(lb)
	fs.sock = keep
	ok(await wait_until(func() -> bool: return la.state.connected and lb.state.connected and la.state.online.has("B") and lb.state.online.has("A"), 4.0), "two RoomLinks connected, presence both ways")
	var recv: Array = []
	lb.on_game(func(m: Dictionary, _f: String) -> void: recv.append(m))
	srv.dup_rate = 0.3                           # server/network duplicates 30 % of frames
	for i in 100:
		la.send_game({"k": "s", "s": {"q": i}})
	await wait_until(func() -> bool: return recv.size() >= 100, 3.0)
	await settle(0.2)
	srv.dup_rate = 0.0
	var qs := {}
	var dups := 0
	for m in recv:
		var q := int(m.s.q)
		if qs.has(q): dups += 1
		qs[q] = true
	ok(recv.size() == 100 and dups == 0, "duplicated frames dropped by gi (100 unique of %d frames)" % recv.size(), "dups=%d" % dups)
	# A goes offline (refuse reconnect for a moment)
	recv.clear()
	srv.refuse = true
	fs.sock.ws.close()                           # connection lost
	await settle(0.1)
	ok(not la.state.connected and int(la.state.offline_since) > 0, "RoomLink reports offline + offline_since")
	var sent_s: bool = la.send_game({"k": "s", "s": {"q": 999}})
	var sent_res: bool = la.send_game({"k": "res", "winner": 0})
	ok(not sent_s, "snapshot NOT queued while offline")
	ok(sent_res, "result queued while offline")
	srv.refuse = false
	ok(await wait_until(func() -> bool: return la.state.connected, 6.0), "RoomLink reconnected")
	await wait_until(func() -> bool: return recv.size() >= 1, 2.0)
	var kinds: Array = []
	for m in recv: kinds.append(str(m.k))
	ok(kinds.has("res") and not kinds.has("s"), "after reconnect: queued result delivered, stale snapshot not", kinds)

	# ------------------------------------------------------------ 4. same topic subscribed twice on one socket
	print("== same topic twice on one socket (screen re-entered before the old one left)")
	var j0 := srv.joins
	var c1 := fs.sock.channel("hub:rooms", {})
	var c2 := fs.sock.channel("hub:rooms", {})
	var other := fs_b_sock.channel("hub:rooms", {})
	var c2_got: Array = []
	c2.on_broadcast("x", func(p: Variant) -> void: c2_got.append(p))
	c1.subscribe()
	other.subscribe()
	await wait_until(func() -> bool: return c1.is_joined() and other.is_joined(), 3.0)
	c2.subscribe()
	await settle(1.5)
	ok(srv.joins - j0 <= 4, "no rejoin flip-flop", "%d joins" % (srv.joins - j0))
	c1.unsubscribe()                             # old screen leaves AFTER the new one joined
	await settle(0.5)
	other.send_broadcast("x", {"n": 1})
	await settle(0.3)
	ok(c2.is_joined() and c2_got.size() == 1, "newer channel survives the old one's unsubscribe", c2_got.size())
	c2.unsubscribe()
	other.unsubscribe()

	# ------------------------------------------------------------ 5. sweep → auto rejoin after long background
	print("== RoomLink re-enters a waiting room after the 45 s server sweep")
	fs.set_meta("me", "B")
	var before := fs.players.size()
	fs.players = fs.players.filter(func(p: Dictionary) -> bool: return p.user_id != "B")   # swept
	fs.app_resumed.emit(120.0)                   # B's app was 2 min in the background
	ok(await wait_until(func() -> bool: return bool(lb.state.rejoined) and not bool(lb.state.gone), 3.0), "join_room called, B back in the room", fs.rpcs.count("join_room"))
	ok(fs.players.size() == before, "B seated again")
	# a kick while active must NOT be undone
	var jr := fs.rpcs.count("join_room")
	fs.players = fs.players.filter(func(p: Dictionary) -> bool: return p.user_id != "B")
	lb.refresh()
	await settle(0.4)
	ok(bool(lb.state.gone) and fs.rpcs.count("join_room") == jr, "kicked while active stays out (no auto rejoin)")

	# ------------------------------------------------------------ 6. cleanup / leaks
	print("== cleanup")
	la.destroy()
	lb.destroy()
	await settle(0.5)
	ok(fs.sock.channels.is_empty() and fs_b_sock.channels.is_empty(), "channels removed after destroy", "%d/%d" % [fs.sock.channels.size(), fs_b_sock.channels.size()])
	ok(fs.sock.ws == null and fs_b_sock.ws == null, "idle sockets closed")
	ca.unsubscribe()
	cb.unsubscribe()
	ok(sa.channels.is_empty() and sa.ws == null, "plain channel unsubscribe closes the socket")
	if real_supa:
		fs.queue_free()
		root.add_child(real_supa)
	print("  (%.1f s wall)" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	print("RESULT: ", "OK" if fails == 0 else "FAIL (%d of %d)" % [fails, fails + passes])
	quit(0 if fails == 0 else 1)
