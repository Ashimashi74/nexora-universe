extends SceneTree
## OUI walk: opens every online / social / oracle / account screen with sample params against the
## live Supabase project (anonymous session), checks back-button contracts and a few behaviours.
##   /workspace/tools/godot --headless --script res://tests/oui_walk.gd
## Junk writes: the anonymous user (session reused across runs), one casual room created + left.
## Script errors are printed by the engine on stderr: grep the output for "SCRIPT ERROR".

var fails := 0
var passes := 0
var nav: Node
var supa
var OUI  # loaded at runtime (class names need the autoloads first)
var OracleScreen

func ok(cond: bool, what: String, extra: Variant = "") -> void:
	if cond:
		passes += 1
		print("  PASS  ", what, ("  " + str(extra)) if str(extra) != "" else "")
	else:
		fails += 1
		print("  FAIL  ", what, ("  " + str(extra)) if str(extra) != "" else "")

func sleep(s: float) -> void:
	await create_timer(s).timeout

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000):
			return false
		await process_frame
	return true

func _initialize() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT")
		quit(2))
	_run.call_deferred()

func open(name: String, params := {}, settle := 2.5) -> Control:
	nav.go(name, params)
	await wait_until(func() -> bool: return nav.current == name, 4.0)
	await sleep(settle)
	ok(nav.current == name and is_instance_valid(nav.screen), "open " + name, str(params.keys()))
	return nav.screen

func _run() -> void:
	await process_frame
	nav = root.get_node_or_null("Nav")
	supa = root.get_node_or_null("Supa")
	OUI = load("res://src/online/oui.gd")
	OracleScreen = load("res://src/oracle/oracle.gd")
	OS.set_environment("NX_START", "home")
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await wait_until(func() -> bool: return nav.main != null and nav.current == "home", 6.0)
	await wait_until(func() -> bool: return supa.session_ready, 10.0)
	print("== auth")
	var u: String = await supa.ensure()
	ok(u != "", "anonymous session", u.substr(0, 8))
	if u == "":
		quit(1)
		return
	OUI.boot()
	await wait_until(func() -> bool: return not OUI.profile.is_empty(), 8.0)
	ok(not OUI.profile.is_empty() and OUI.s(OUI.profile.get("id")) == u, "OUI.profile synced from Supa.profile")
	ok(OUI.ebus() != null, "OUI.ebus() not null")

	print("== sample data")
	var t: Dictionary = await supa.select("tournaments", "select=id&order=created_at.desc&limit=1", true)
	var tid: String = OUI.s(OUI.d(t.get("data")).get("id")) if t.ok and t.data is Dictionary else ""
	var c: Dictionary = await supa.select("club_list", "select=id&limit=1", true)
	var cid: String = OUI.s(OUI.d(c.get("data")).get("id")) if c.ok and c.data is Dictionary else ""
	var pc: Dictionary = await supa.select("public_conversations", "select=id&limit=1", true)
	var conv: String = OUI.s(OUI.d(pc.get("data")).get("id")) if pc.ok and pc.data is Dictionary else ""
	var lb: Dictionary = await supa.select("leaderboard", "select=id&limit=1", true)
	var other: String = OUI.s(OUI.d(lb.get("data")).get("id")) if lb.ok and lb.data is Dictionary else u
	print("  tournament=", tid, " club=", cid, " conv=", conv, " player=", other)

	print("== screens")
	var s: Control = await open("hub", {"entry": "hub"})
	ok(s.on_back() == false, "hub.on_back -> false")
	s = await open("ranks", {"entry": "leagues"})
	ok(str(s.get("tab")) == "leagues", "ranks entry=leagues opens leagues tab")
	ok(s.on_back() == false, "ranks.on_back -> false")
	s = await open("ranks", {"tab": "top"}, 2.0)
	s = await open("tournaments", {})
	ok(s.on_back() == false, "tournaments.on_back -> false")
	if tid != "":
		await open("tournaments", {"id": tid})
	s = await open("challenges", {})
	ok(s.on_back() == false, "challenges.on_back -> false")
	s = await open("arena", {})
	ok(s.on_back() == false, "arena.on_back -> false")
	for tb in ["msg", "club", "friends"]:
		s = await open("social", {"tab": tb}, 2.0)
	if cid != "":
		s = await open("club", {"id": cid})
		ok(s.on_back() == false, "club.on_back -> false")
	s = await open("public_profile", {"id": other})
	ok(s.on_back() == false, "public_profile.on_back -> false")
	if conv != "":
		s = await open("chat", {"id": conv})
		ok(s.on_back() == false, "chat.on_back (no overlay) -> false")
	s = await open("account", {})
	ok(s.on_back() == false, "account.on_back -> false")
	s = await open("oracle", {"ask": "الماس"})
	ok(s.on_back() == false, "oracle.on_back -> false")
	var r: Dictionary = await OracleScreen.run_action("stats")
	ok(OUI.s(r.get("text")) != "", "oracle action stats")
	r = await OracleScreen.run_action("disc")
	ok(OUI.s(r.get("text")) != "", "oracle action disc")
	r = await OracleScreen.run_action("challenges")
	ok(OUI.s(r.get("text")) != "", "oracle action challenges", OUI.s(r.get("text")).substr(0, 40))
	await sleep(1.0)
	ok(nav.current == "oracle", "oracle data actions stay on oracle")

	print("== sheet / toast")
	OUI.open_sheet("آزمایش", "TEST", OUI.lbl("x"), OUI.CYAN, 0.5)
	await sleep(0.6)
	ok(nav.has_sheet(), "OUI.open_sheet -> Nav.sheet")
	nav.close_sheet(true)
	OUI.toast_err("خطای آزمایشی")

	print("== room: create -> lobby -> online_result -> lobby -> leave")
	var cr: Dictionary = await supa.call_rpc("create_room", {"p_mode": "1v1", "p_name": "oui-walk", "p_private": true, "p_ranked": false, "p_voice": false, "p_settings": {"goals": 3, "time": 0, "turn": 15, "field": 0, "ball": 0}})
	ok(cr.ok, "create_room", cr.error)
	if cr.ok:
		OUI.enter_room(cr.data)
		await wait_until(func() -> bool: return nav.current == "lobby", 5.0)
		await sleep(3.0)
		ok(nav.current == "lobby" and OUI.link != null, "lobby opened with link")
		var l: Variant = OUI.link
		ok(l != null and is_instance_valid(l) and (l as Node).get_parent() != null, "RoomLink parented itself")
		s = nav.screen
		ok(s.on_back() == true, "lobby.on_back -> true (leave dialog)")
		await sleep(0.4)
		ok(nav.current == "lobby", "lobby stays while dialog open")
		s.call("_close_confirm")
		var outcome := {"match_id": "00000000-0000-0000-0000-000000000000", "score": [2, 1], "winner": 0, "rating_delta": null, "my_team": 0, "teams": ["club0", "nat15"], "names": ["A", "B"], "reported": true, "ranked": false}
		s = await open("online_result", {"o": outcome, "before": OUI.profile, "room_id": OUI.s(l.id), "link": l})
		ok(s.on_back() == true, "online_result.on_back -> true")
		await wait_until(func() -> bool: return nav.current == "lobby", 4.0)
		await sleep(1.5)
		ok(nav.current == "lobby", "online_result back -> lobby")
		OUI.leave_room(true)
		await wait_until(func() -> bool: return nav.current == "hub", 4.0)
		await sleep(1.0)
		ok(nav.current == "hub" and OUI.link == null, "leave_room -> hub, link dropped")
		ok(not is_instance_valid(l), "RoomLink freed after destroy()")

	print("== back from hub (Nav.back, no recursion)")
	nav.back()
	await sleep(1.2)
	ok(nav.current != "hub" and nav.current != "lobby", "Nav.back from hub navigates away", nav.current)
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(1 if fails else 0)
