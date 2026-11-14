extends Node
## Text/layout audit walk. Opens every UI screen + key sheets, then for each visible Label reports
##   NARROW  an autowrap label narrower than ~3 glyphs (one-letter-per-line column bug)
##   CUT     an ellipsis/clip label whose text does not fit (truncated "…")
##   SQUEEZE a scroller whose content is narrower than 80% of the scroller (collapsed page)
## and saves screenshots when rendering (Xvfb). Run:
##   NX_TEXTWALK=1 NX_SHOTS=/tmp/shots DISPLAY=:99 godot --rendering-driver opengl3 --resolution 1080x1920 --path . res://src/main.tscn
##   NX_TEXTWALK=1 godot --headless --path . res://src/main.tscn      (audit only)

var shots := ""
var render := false
var issues := 0
var only := ""

func _ready() -> void:
	render = DisplayServer.get_name() != "headless"
	shots = OS.get_environment("NX_SHOTS")
	only = OS.get_environment("NX_ONLY")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	_audit(name)
	if not render or shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(540, int(540.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_png("%s/%s.png" % [shots, name])
	print("[tw] shot ", name)

func _audit(tag: String) -> void:
	var root := get_tree().root
	_walk(root, tag)

func _walk(n: Node, tag: String) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is ScrollContainer:
		var sc := n as ScrollContainer
		for c in sc.get_children():
			if c is Control and not (c is ScrollBar) and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				if sc.size.x > 200 and (c as Control).size.x < sc.size.x * 0.8:
					issues += 1
					print("[tw] %s SQUEEZE %s content %d/%d" % [tag, sc.get_path(), int((c as Control).size.x), int(sc.size.x)])
	if n is Label or n is PanelContainer or n is BaseButton:
		var r := (n as Control).get_global_rect()
		var vw := get_viewport().get_visible_rect().size.x
		if r.size.x > 0 and (r.end.x > vw + 6 or r.position.x < -6) and not _in_hscroll(n):
			issues += 1
			print("[tw] %s OVER x=%d..%d %s" % [tag, int(r.position.x), int(r.end.x), n.get_path()])
	if n is Label:
		var l := n as Label
		var t := l.text.strip_edges()
		if t.length() > 2 and l.get_global_rect().size.x > 0:
			var fs := l.get_theme_font_size("font_size")
			var tw := UD.text_w(l)
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.size.x < fs * 2.2 and tw > l.size.x + 2:
				issues += 1
				print("[tw] %s NARROW w=%d fs=%d '%s' %s" % [tag, int(l.size.x), fs, t.left(30), l.get_path()])
			elif l.autowrap_mode == TextServer.AUTOWRAP_OFF and (l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and tw > l.size.x + 3:
				issues += 1
				print("[tw] %s CUT w=%d need=%d '%s' %s" % [tag, int(l.size.x), int(tw), t.left(30), l.get_path()])
	for c in n.get_children():
		_walk(c, tag)

func _go(n: String, params := {}, wait := 1.4) -> void:
	Nav.go(n, params)
	await _wait(wait)

func _want(n: String) -> bool:
	return only == "" or n in only.split(",")

func _compile_all(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var s = load(dir + "/" + f)
			if s == null or not (s as GDScript).can_instantiate():
				issues += 1
				print("[tw] COMPILE FAIL ", dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_compile_all(dir + "/" + d)

func _run() -> void:
	_compile_all("res://src")
	print("[tw] lang=", I18n.lang)
	await _wait(1.5)
	var intro = Nav.screen
	if intro and intro.has_method("enter"):
		intro.enter()
	await _wait(1.5)
	if _want("home"):
		await _go("home")
		var h = Nav.screen
		if h and h.has_method("_mascot_say"):
			h._mascot_say("سلام کاپیتان! آماده‌ی بازی هستی؟")
		await _wait(0.6)
		await _shot("home_mascot")
		Nav.toast("صندوقچه‌ی رایگان هنوز آماده نیست")
		await _wait(0.7)
		await _shot("home_toast")
	for n in ["team", "play", "shop", "profile"]:
		if _want(n):
			await _go(n)
			await _shot(n)
	if _want("settings"):
		await _go("settings")
		await _shot("settings")
		Nav.close_sheet(true)
		await _wait(0.4)
	if _want("setup"):
		await _go("setup", {"mode": "quick"})
		await _shot("setup")
		Nav.close_sheet(true)
		await _wait(0.4)
	if _want("ranks"):
		await _go("ranks", {"tab": "leagues"}, 3.5)
		await _shot("ranks_leagues")
		await _go("ranks", {"tab": "top"}, 3.0)
		await _shot("ranks_top")
	if _want("hub"):
		await _go("hub", {}, 3.0)
		await _shot("hub")
		var hb = Nav.screen
		if hb and hb.has_method("_open_create"):
			hb._open_create()
			await _wait(1.2)
			await _shot("hub_create")
			if OS.has_environment("NX_ROOM"):
				# press the sheet's create button -> real lobby
				var go := _find_button(Nav.main.sheet_layer, I18n.t("hub.create_room"))
				if go:
					go.emit_signal("pressed")
					await _wait(5.0)
					await _shot("lobby_room")
					var lb = Nav.screen
					if lb and lb.has_method("_open_settings"):
						lb._open_settings()
						await _wait(1.2)
						await _shot("lobby_settings")
						Nav.close_sheet(true)
					OUI.leave_room(true)
					await _wait(1.5)
			Nav.close_sheet(true)
			await _wait(0.4)
	for n in ["account", "challenges", "tournaments", "arena", "social", "oracle", "lobby", "club", "public_profile"]:
		if _want(n):
			await _go(n, {}, 3.0)
			await _shot(n)
	print("[tw] DONE issues=", issues)
	get_tree().quit()

func _in_hscroll(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is ScrollContainer and (p as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return true
		if p is CanvasItem and (p as CanvasItem).top_level:
			return false
		p = p.get_parent()
	return false

func _find_button(n: Node, txt: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text == txt and (c as Button).is_visible_in_tree():
			return c
		var r := _find_button(c, txt)
		if r:
			return r
	return null
