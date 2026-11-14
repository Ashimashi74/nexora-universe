extends SceneTree
## Live smoke test for the NET layer against the real Supabase project.
##   /workspace/tools/godot --headless --script res://tests/net_smoke.gd
## Creates nothing beyond the anonymous auth user (+ its auto-created profiles row); only updates
## that row's online_at. Signs out at the end.

var supa  # untyped on purpose: typed as Node, .rpc() would resolve to Node.rpc
var fails := 0
var passes := 0

func ok(cond: bool, what: String, extra: Variant = "") -> void:
	if cond:
		passes += 1
		print("  PASS  ", what, ("  " + str(extra)) if str(extra) != "" else "")
	else:
		fails += 1
		print("  FAIL  ", what, ("  " + str(extra)) if str(extra) != "" else "")

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000):
			return false
		await process_frame
	return true

func sleep(s: float) -> void:
	await create_timer(s).timeout

func _initialize() -> void:
	# hard watchdog: never hang CI
	create_timer(90.0).timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT")
		quit(2))
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	supa = root.get_node_or_null("Supa")
	if supa == null:
		print("Supa autoload missing")
		quit(1)
		return
	await wait_until(func() -> bool: return supa.session_ready, 10.0)
	print("== errFa")
	ok(supa.err_fa("Invalid login credentials") == "ایمیل یا رمز عبور اشتباه است", "err_fa invalid login")
	ok(supa.err_fa("TypeError: Failed to fetch") == "اتصال اینترنت برقرار نیست", "err_fa network")
	ok(supa.err_fa("room is full") == "ظرفیت تکمیل است", "err_fa \\bfull\\b")
	ok(supa.err_fa("") == "خطای ناشناخته؛ دوباره امتحان کن", "err_fa empty")
	ok(supa.err_fa("weird thing") == "خطا: weird thing", "err_fa fallback")

	print("== auth: anonymous sign-in")
	if supa.signed_in():
		print("  (stale session from a previous run, signing out first)")
		await supa.sign_out()
	var r: Dictionary = await supa.sign_in_anon()
	ok(r.ok, "sign_in_anon", r.error)
	if not r.ok:
		print("anonymous sign-in failed: ", r.raw, " — continuing with anon-key-only checks")
		var lg: Dictionary = await supa.select("leagues", "select=id,min_rating&order=sort")
		ok(lg.ok, "select leagues (anon key)", lg.error)
		_finish()
		return
	var uid: String = supa.uid()
	ok(uid.length() == 36, "uid", uid)
	ok(supa.is_guest(), "is_guest")
	ok(FileAccess.file_exists("user://session.json"), "session persisted")

	print("== REST / RPC")
	var lg: Dictionary = await supa.select("leagues", "select=id,name_fa,min_rating&order=sort")
	ok(lg.ok and lg.data is Array and lg.data.size() > 0, "select leagues", str(lg.data.size()) + " rows" if lg.data is Array else lg.error)
	var me: Dictionary = await supa.select("profiles", "select=id,username,is_guest,rating&id=eq." + uid, true)
	ok(me.ok and me.data is Dictionary and me.data.id == uid, "select own profile (maybeSingle)", me.data)
	var par: Array = await supa.parallel([
		func() -> Dictionary: return await supa.rpc("level_for_xp", {"x": 2500}),
		func() -> Dictionary: return await supa.call_rpc("league_for_rating", {"r": 1300}),
	])
	ok(par[0].ok and int(par[0].data) == 6, "rpc level_for_xp(2500) == 6 (via Supa.rpc)", par[0].data)
	ok(par[1].ok and str(par[1].data) == "gold", "rpc league_for_rating(1300) == gold (parallel)", par[1].data)
	var bad: Dictionary = await supa.call_rpc("this_function_does_not_exist", {})
	ok(not bad.ok and bad.status >= 400 and bad.error != "", "missing rpc → ok=false, no crash", "%d %s" % [bad.status, bad.error])
	var emb: Dictionary = await supa.select("room_players", "select=*,profiles(username,avatar,avatar_url,level,rating,league,equipped_disc)&limit=1")
	ok(emb.ok, "embedded select room_players + profiles", emb.error)

	print("== token refresh")
	var old_tok: String = supa.access_token()
	await sleep(1.1)
	var rf: Dictionary = await supa.refresh_session()
	ok(rf.ok and supa.access_token() != "" and supa.uid() == uid, "refresh_session", "token changed" if supa.access_token() != old_tok else "same token")

	print("== realtime")
	var room := "room:test-%d" % (randi() % 1000000)
	var s2: RefCounted = supa.new_socket()
	var st1 := {"s": ""}
	var st2 := {"s": ""}
	var got1: Array = []
	var got2: Array = []
	var pres1 := {"v": {}}
	var pg := {"v": null}
	var ch1: RtChannel = supa.channel(room, {"broadcast": {"self": false, "ack": false}, "presence": {"key": "A-" + uid}})
	ch1.on_broadcast("hello", func(p: Variant) -> void: got1.append(p))
	ch1.on_presence(func(s: Dictionary) -> void: pres1.v = s)
	ch1.on_postgres("UPDATE", "public", "profiles", "id=eq." + uid, func(c: Dictionary) -> void: pg.v = c)
	ch1.subscribe(func(s: String) -> void: st1.s = s)
	var ch2: RtChannel = supa.channel(room, {"broadcast": {"self": false}, "presence": {"key": "B-" + uid}}, s2)
	ch2.on_broadcast("hello", func(p: Variant) -> void: got2.append(p))
	ch2.subscribe(func(s: String) -> void: st2.s = s)
	var sub_ok: bool = await wait_until(func() -> bool: return st1.s == "SUBSCRIBED" and st2.s == "SUBSCRIBED", 20.0)
	ok(sub_ok, "both channels SUBSCRIBED (2 sockets)", "%s / %s %s" % [st1.s, st2.s, ch1.last_error])
	ok(ch1._pg.size() == 1 and ch1._pg[0].id >= 0, "postgres_changes binding id from phx_reply", ch1._pg[0].id if ch1._pg.size() else -1)
	ch1.track({"name": "one"})
	ch2.track({"name": "two"})
	var pres_ok: bool = await wait_until(func() -> bool: return pres1.v.size() == 2, 10.0)
	ok(pres_ok, "presence sync sees both sockets", pres1.v.keys())
	if pres_ok:
		var b: Array = pres1.v.get("B-" + uid, [])
		ok(b.size() == 1 and b[0].get("name") == "two" and b[0].has("presence_ref"), "presence meta shape like presenceState()", b)
	ch2.send_broadcast("hello", {"x": 1, "from": "two"})
	var b1: bool = await wait_until(func() -> bool: return got1.size() > 0, 8.0)
	ok(b1 and got1[0].get("x") == 1, "broadcast socket2 → socket1", got1)
	ch1.send_broadcast("hello", {"x": 2})
	var b2: bool = await wait_until(func() -> bool: return got2.size() > 0, 8.0)
	ok(b2 and got2[0].get("x") == 2, "broadcast socket1 → socket2", got2)
	await sleep(0.4)
	ok(got1.size() == 1, "self:false (no echo of own broadcast)", got1.size())
	# postgres_changes: touch own profile row (online_at only)
	await sleep(1.0)
	var up: Dictionary = await supa.update("profiles", "id=eq." + uid, {"online_at": Time.get_datetime_string_from_system(true) + "Z"})
	ok(up.ok, "update own profiles.online_at", up.error)
	var pgok: bool = await wait_until(func() -> bool: return pg.v != null, 10.0)
	ok(pgok and pg.v.eventType == "UPDATE" and pg.v.new.get("id") == uid, "postgres_changes UPDATE received", pg.v.eventType if pg.v else "none")
	# access_token push on refresh keeps channels alive
	await supa.refresh_session()
	await sleep(1.0)
	ok(ch1.is_joined() and ch2.is_joined(), "channels still joined after access_token push")
	# presence leave
	ch2.untrack()
	var left: bool = await wait_until(func() -> bool: return pres1.v.size() == 1, 8.0)
	ok(left, "presence leave after untrack", pres1.v.keys())
	# reconnect: kill socket 2 and check it rejoins
	s2.ws.close()
	var re1: bool = await wait_until(func() -> bool: return st2.s == "CHANNEL_ERROR", 6.0)
	var re2: bool = await wait_until(func() -> bool: return st2.s == "SUBSCRIBED", 15.0)
	ok(re1 and re2, "socket drop → CHANNEL_ERROR → auto reconnect + rejoin → SUBSCRIBED", st2.s)
	ch2.send_broadcast("hello", {"x": 3})
	var b3: bool = await wait_until(func() -> bool: return got1.size() > 1, 8.0)
	ok(b3, "broadcast after reconnect", got1)
	supa.remove_channel(ch1)
	supa.remove_channel(ch2)
	ok(ch1.status == "CLOSED", "remove_channel → CLOSED")
	supa.close_socket(s2)

	print("== RoomLink (no room row: expects gone=true, no crash)")
	var link := RoomLink.new("00000000-0000-0000-0000-000000000000", uid, "tester")
	var lk: bool = await wait_until(func() -> bool: return link.state.loaded, 10.0)
	ok(lk and link.state.gone, "RoomLink.refresh on unknown room → loaded, gone")
	var lc: bool = await wait_until(func() -> bool: return link.state.connected, 10.0)
	ok(lc, "RoomLink channel connected")
	link.send_chat("سلام")
	ok(link.state.chat.size() == 1 and link.state.chat[0].text == "سلام", "RoomLink.send_chat local echo")
	link.destroy()
	await sleep(0.5)

	print("== sign out")
	var so: Dictionary = await supa.sign_out()
	ok(so.ok and not supa.signed_in() and not FileAccess.file_exists("user://session.json"), "sign_out clears session")
	_finish()

func _finish() -> void:
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
