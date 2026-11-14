extends SceneTree
## Offline loopback test of the online-match netcode (no network):
##   one HOST instance + one CLIENT (spectator) instance of src/online/online_match.gd, connected by an
##   in-process fake RoomLink with latency, jitter, reordering and duplicates. Both teams' players are
##   "offline" so the host's bot plays both sides (AI takeover path). Checks: snapshots stream, client
##   interpolates, duplicate/out-of-order snapshots are dropped, scores agree, both sides finish.
##   /workspace/tools/godot --headless --script res://tests/net_match.gd

const HOST := "11111111-1111-1111-1111-111111111111"
const CLI := "22222222-2222-2222-2222-222222222222"
const P0 := "33333333-3333-3333-3333-333333333333"
const P1 := "44444444-4444-4444-4444-444444444444"

class FakeLink extends Node:
	signal changed
	var id := "room-test"
	var me := ""
	var chat_open := false
	var dead := false
	var peers: Array = []
	var cbs: Array = []
	var sent := 0
	var state := {}
	func _init(me_: String, st: Dictionary) -> void:
		me = me_
		state = st
	func on_game(f: Callable) -> Callable:
		cbs.append(f)
		return func() -> void: cbs.erase(f)
	func send_game(m: Dictionary) -> void:
		sent += 1
		var p := m.duplicate(true)
		p["from"] = me
		# JSON round trip like the real wire (ints become floats etc.)
		var wire: Variant = JSON.parse_string(JSON.stringify(p))
		for peer in peers:
			var delay := 0.04 + randf() * 0.06       # 40–100 ms, jittered → reorders
			get_tree().create_timer(delay).timeout.connect(peer._deliver.bind(wire))
			if randf() < 0.05:                       # 5 % duplicates
				get_tree().create_timer(delay + 0.03).timeout.connect(peer._deliver.bind(wire))
	func _deliver(m: Variant) -> void:
		for f in cbs.duplicate():
			if f.is_valid():
				f.call(m, str(m.get("from", "")))
	func ping() -> void: pass
	func refresh() -> void: pass
	func mark_read() -> void: pass
	func send_chat(_t: String) -> void: pass
	func voice_join() -> void: pass

func _initialize() -> void:
	create_timer(115.0, true, false, true).timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT")
		quit(2))
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var OM: Script = load("res://src/online/online_match.gd")
	if OM == null or not OM.can_instantiate():
		print("FAIL: online_match.gd does not compile")
		quit(1)
		return
	var f1: int = await _case(OM, false)
	var f2: int = await _case(OM, true)
	print("RESULT: %s" % ("OK" if f1 + f2 == 0 else "%d FAILED" % (f1 + f2)))
	quit(0 if f1 + f2 == 0 else 1)

## players=false: host + client are spectators, bots play both teams.
## players=true : host plays team 0, client plays team 1 (client shots go through shot requests/seq).
func _case(OM: Script, players_mode: bool) -> int:
	var room := {"id": "room-test", "host": HOST, "ranked": true, "voice": false, "settings": {"goals": 1, "time": 0, "field": 0, "turn": 6}}
	var prof := func(n: String) -> Dictionary: return {"username": n, "avatar": "club00", "equipped_disc": "club1"}
	var players: Array
	if players_mode:
		players = [
			{"user_id": HOST, "role": "player", "team": 0, "slot": 0, "profiles": prof.call("host")},
			{"user_id": CLI, "role": "player", "team": 1, "slot": 0, "profiles": prof.call("guest")},
		]
	else:
		players = [
			{"user_id": HOST, "role": "spectator", "team": null, "slot": null, "profiles": prof.call("host")},
			{"user_id": CLI, "role": "spectator", "team": null, "slot": null, "profiles": prof.call("viewer")},
			{"user_id": P0, "role": "player", "team": 0, "slot": 0, "profiles": prof.call("blue")},
			{"user_id": P1, "role": "player", "team": 1, "slot": 0, "profiles": prof.call("red")},
		]
	var online := {HOST: {"name": "host"}, CLI: {"name": "viewer"}}
	var mk := func(me: String) -> FakeLink:
		return FakeLink.new(me, {"room": room.duplicate(true), "players": players.duplicate(true), "online": online.duplicate(true), "chat": [], "connected": true, "loaded": true, "gone": false, "unread": 0, "rtt": 50})
	var lh: FakeLink = mk.call(HOST)
	var lc: FakeLink = mk.call(CLI)
	lh.peers = [lc]
	lc.peers = [lh]
	root.add_child(lh)
	root.add_child(lc)
	var mid := "m-%d" % int(players_mode)
	var host: Control = OM.new()
	host.setup({"room_id": "room-test", "match_id": mid, "link": lh})
	var cli: Control = OM.new()
	cli.setup({"room_id": "room-test", "match_id": mid, "link": lc})
	root.add_child(host)
	root.add_child(cli)
	Engine.time_scale = 3.0
	var t0 := Time.get_ticks_msec()
	var max_buf := 0
	var moved := false
	var last_cli_ball := Vector2.ZERO
	var cli_shots := 0
	var host_shots := 0
	var t1_shots := {"n": 0}
	while Time.get_ticks_msec() - t0 < 45000:
		await process_frame
		max_buf = max(max_buf, cli.cs.buf.size())
		var bp := Vector2(cli.eng.ball.x, cli.eng.ball.y)
		if cli.cs.got and bp.distance_to(last_cli_ball) > 0.5 and last_cli_ball != Vector2.ZERO:
			moved = true
		last_cli_ball = bp
		if players_mode:
			# count shots of team 1 seen by the host
			if host.eng.phase == "move" and host.eng.last_who == 1 and not t1_shots.has("m%d" % host.eng.shots):
				t1_shots["m%d" % host.eng.shots] = true
				t1_shots.n += 1
			# host human: flick its nearest disc at the ball via the engine (like a touch release)
			if host._can_act() and randf() < 0.05:
				var b: NxBody = _nearest(host.eng, 0)
				host.eng.fire(b, host.eng.ball.x - b.x, host.eng.ball.y - b.y, 200.0, true)
				host_shots += 1
			# client human: real input path (_grant/_move/_release with world→screen bypassed)
			if cli._can_act() and cli._local == null and randf() < 0.05:
				var b: NxBody = _nearest(cli.eng, 1)
				cli._local = {"b": b, "sx": b.x, "sy": b.y}
				var d := Vector2(cli.eng.ball.x - b.x, cli.eng.ball.y - b.y).normalized() * 190.0
				cli.eng.drag = {"b": b, "sx": b.x, "sy": b.y, "cx": b.x - d.x, "cy": b.y - d.y, "ai": false}
				cli._send_aim(true)
				cli._release()
				cli_shots += 1
		if host.done == "finished" and cli.done == "finished":
			break
	Engine.time_scale = 1.0
	var fails := [0]
	var chk := func(c: bool, what: String, extra: Variant = "") -> void:
		print("  ", "PASS  " if c else "FAIL  ", what, "  ", extra)
		if not c:
			fails[0] += 1
	print("== online match loopback (%s)" % ("host vs client players" if players_mode else "spectators, bots play"))
	chk.call(host.is_host and not cli.is_host, "roles")
	chk.call(lh.sent > 20, "host sent snapshots", lh.sent)
	chk.call(cli.cs.got, "client received + applied snapshots", "applied q=%d" % cli.cs.applied)
	chk.call(moved, "client bodies move (interpolation)")
	chk.call(max_buf <= 60, "client buffer bounded", max_buf)
	if players_mode:
		chk.call(cli_shots > 0 and t1_shots.n > 0, "client shot requests accepted by host", "%d sent, %d fired" % [cli_shots, t1_shots.n])
		chk.call(host_shots > 0, "host shots", host_shots)
	chk.call(host.done == "finished", "host finished", host.done)
	chk.call(cli.done == "finished", "client finished", cli.done)
	chk.call(int(cli.eng.score[0]) == int(host.eng.score[0]) and int(cli.eng.score[1]) == int(host.eng.score[1]), "scores agree", "%s vs %s" % [host.eng.score, cli.eng.score])
	chk.call(cli.cs.res != null, "client got result message", cli.cs.res)
	var before: int = cli.cs.buf.size()
	cli._on_msg({"k": "s", "mid": "other", "s": {"q": 99999, "ts": 0, "p": []}}, HOST)
	chk.call(cli.cs.buf.size() == before, "stale-match snapshot dropped")
	print("  (%.1f s wall)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	host.queue_free()
	cli.queue_free()
	lh.queue_free()
	lc.queue_free()
	await process_frame
	return fails[0]

func _nearest(eng: Variant, team: int) -> NxBody:
	var best: NxBody = null
	var bd := 1e9
	for b in eng.bodies:
		if b.team == team:
			var d := Vector2(b.x - eng.ball.x, b.y - eng.ball.y).length()
			if d < bd:
				bd = d
				best = b
	return best
