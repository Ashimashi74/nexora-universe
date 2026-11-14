extends Node
## UI walk test: navigates through every UI screen / sheet / modal via Nav, scrolls them, and
## (when rendering, i.e. not --headless) saves screenshots to $NX_SHOTS (default res://../shots).
## Run:  NX_WALK=1 godot --headless --path . res://src/main.tscn
##       NX_WALK=1 NX_SHOTS=/workspace/work/nexgodot/shots DISPLAY=:99 godot --rendering-driver opengl3 --resolution 1080x1920 --path . res://src/main.tscn

var shots := ""
var tag := ""
var render := false
var steps := 0

func _ready() -> void:
	render = DisplayServer.get_name() != "headless"
	shots = OS.get_environment("NX_SHOTS")
	var vs := get_viewport().get_visible_rect().size
	tag = "%dx%d" % [int(vs.x), int(vs.y)]
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	steps += 1
	if not render or shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [shots, tag, name]
	img.save_png(path)
	print("[walk] shot ", path)

func _scroll_to(frac: float) -> void:
	var s = Nav.screen
	if s and s.get("scroll") is ScrollContainer:
		var sc: ScrollContainer = s.scroll
		var mx: float = sc.get_v_scroll_bar().max_value - sc.size.y
		sc.scroll_vertical = int(maxf(0.0, mx) * frac)

func _run() -> void:
	print("[walk] start ", tag, " render=", render)
	await _wait(1.6)
	await _shot("00_intro_warp")
	await _wait(3.6)
	await _shot("01_intro_logo")
	var intro = Nav.screen
	if intro and intro.has_method("enter"):
		intro.enter()
	await _wait(1.6)
	print("[walk] current=", Nav.current)
	for tab in ["home", "team", "play", "shop", "profile"]:
		Nav.go(tab)
		await _wait(1.3)
		print("[walk] tab ", tab, " -> ", Nav.current)
		await _shot("10_%s_a" % tab)
		for f in [0.33, 0.66, 1.0]:
			_scroll_to(f)
			await _wait(0.5)
			await _shot("10_%s_%d" % [tab, int(f * 100)])
		_scroll_to(0.0)
	# team sub tabs
	Nav.go("team")
	await _wait(1.0)
	for i in [1, 2, 3]:
		var t = Nav.screen
		if t and t.has_method("_on_sub"):
			t.seg.set_index(i)
			t._on_sub(i)
		await _wait(0.9)
		await _shot("11_team_sub%d" % i)
		_scroll_to(1.0)
		await _wait(0.4)
		await _shot("11_team_sub%d_end" % i)
	# shop catalogue kinds
	Nav.go("shop")
	await _wait(1.0)
	for k in [1, 2]:
		var s = Nav.screen
		s.kind = k
		s.on_store_changed()
		await _wait(0.6)
		_scroll_to(1.0)
		await _wait(0.4)
		await _shot("12_shop_kind%d" % k)
	# play carousel swipe
	Nav.go("play")
	await _wait(1.2)
	var pl = Nav.screen
	if pl and pl.carousel:
		pl.carousel._snap(2)
		await _wait(0.8)
		await _shot("13_play_card2")
	# sheets
	Nav.go("settings")
	await _wait(1.0)
	await _shot("20_settings")
	Nav.back()
	await _wait(0.6)
	print("[walk] after back sheet: has_sheet=", Nav.has_sheet())
	for m in ["quick", "cup", "galaxy", "local", "train"]:
		Nav.go("setup", {"mode": m})
		await _wait(0.9)
		if m in ["quick", "cup"]:
			await _shot("21_setup_%s" % m)
		Nav.close_sheet()
		await _wait(0.4)
	# modals
	Nav.go("home")
	await _wait(0.8)
	Nav.go("daily")
	await _wait(1.0)
	await _shot("30_daily")
	Nav.claim_daily()
	await _wait(0.8)
	Nav.close_modal()
	UD.set_p({"coins": 5000})
	Nav.open_chest(true)
	await _wait(0.6)
	await _shot("31_chest_shake")
	await _wait(1.4)
	await _shot("32_chest_open")
	Nav.close_modal()
	await _wait(0.4)
	Nav.toast("پیشرفت پاک شد", "ok")
	await _wait(0.3)
	await _shot("33_toast")
	Nav.confirm("از نکسورا خارج می‌شی؟", func(): print("[walk] confirm ok"), "خروج", "ماندن")
	await _wait(0.7)
	await _shot("34_confirm")
	Nav.close_modal()
	await _wait(0.4)
	# start a match the way Setup does (GAME's match screen, or the "به‌زودی" toast if absent)
	var launch := Launch.build("quick", UD.p(), {"lvl": 1, "rule": "g3", "tt": 15, "opp": Launch.pick_opp(), "stage": 0})
	print("[walk] launch cfg=", launch["cfg"])
	Nav.go("match", launch)
	await _wait(1.6)
	print("[walk] match -> ", Nav.current)
	await _shot("40_match")
	Nav.go("home")
	await _wait(1.0)
	# online + other workers' screens: must not crash (missing => toast)
	for n in ["hub", "ranks", "tournaments", "challenges", "arena", "social", "account", "oracle", "public_profile", "nonexistent_screen"]:
		Nav.go(n, {})
		await _wait(1.0)
		print("[walk] go ", n, " -> ", Nav.current)
		if n in ["hub", "account"]:
			await _shot("50_%s" % n)
	Nav.go("home")
	await _wait(0.8)
	# back handling: history
	Nav.go("team")
	await _wait(0.6)
	Nav.back()
	await _wait(0.8)
	print("[walk] back from team -> ", Nav.current)
	print("[walk] DONE steps=", steps)
	get_tree().quit()
