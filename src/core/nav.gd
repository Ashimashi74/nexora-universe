extends Node
## Nav autoload — screen router + overlays (SPEC "UI shell").
##   Nav.go(name, params := {})      swap screen (veil fade) / open sheet / open modal
##   Nav.back()                       Android back: modal > sheet > screen.on_back() > history > home > exit confirm
##   Nav.sheet(control, opts := {})   bottom sheet ({title, en, accent, height})  /  Nav.close_sheet()
##   Nav.modal(control, accent)       centred card                                  /  Nav.close_modal()
##   Nav.toast(text, kind := "info")  kind: info|ok|err
##   Nav.confirm(text, cb, ok := "تأیید", cancel := "انصراف")
##   Nav.chrome(visible)              show/hide HUD + tab bar for the current screen
##   Nav.backdrop(theme, dim := -1)   switch the space backdrop (base|win|lose|system|hub|stadium|holo)
##   Nav.insets() -> {top, bottom}    content padding below HUD / above tab bar for this screen
## Screens: `extends Control`, `func setup(params: Dictionary)` (before add_child), optional
## `func leave()`, optional `func on_back() -> bool` (true = handled), optional `sheet_opts() -> Dictionary`.

signal screen_changed(name: String)
signal sheet_closed

const TABS := ["home", "team", "play", "shop", "profile"]
## name -> [script path, kind]  kind: tab | screen (no chrome) | sheet | modal | fs (full-screen, no chrome, no backdrop)
const REG := {
	"intro": ["res://src/screens/intro.gd", "fs"],
	# v3: ONLINE is the default first screen — "home" is the online rooms screen (room list, create, join by
	# code) with the collapsible category drawers for everything else; "hub" is an alias of it.
	"home": ["res://src/online/hub.gd", "tab"],
	"menu_v2": ["res://src/screens/home.gd", "tab"],
	"team": ["res://src/screens/team.gd", "tab"],
	"play": ["res://src/screens/play.gd", "tab"],
	"shop": ["res://src/screens/shop.gd", "tab"],
	"profile": ["res://src/screens/profile.gd", "tab"],
	"settings": ["res://src/screens/settings.gd", "sheet"],
	"setup": ["res://src/screens/setup.gd", "sheet"],
	"daily": ["res://src/screens/daily.gd", "modal"],
	"chest": ["res://src/screens/chest.gd", "modal"],
	"match": ["res://src/screens/match.gd", "fs"],
	"result": ["res://src/screens/result.gd", "screen"],
	"account": ["res://src/screens/account.gd", "screen"],
	"hub": ["res://src/online/hub.gd", "screen"],
	"lobby": ["res://src/online/lobby.gd", "screen"],
	"ranks": ["res://src/online/ranks.gd", "screen"],
	"tournaments": ["res://src/online/tournaments.gd", "screen"],
	"challenges": ["res://src/online/challenges.gd", "screen"],
	"online_result": ["res://src/online/online_result.gd", "screen"],
	"arena": ["res://src/online/arena.gd", "screen"],
	"online_match": ["res://src/online/online_match.gd", "fs"],
	"social": ["res://src/social/social.gd", "screen"],
	"chat": ["res://src/social/chat.gd", "screen"],
	"club": ["res://src/social/club.gd", "screen"],
	"public_profile": ["res://src/social/public_profile.gd", "screen"],
	"oracle": ["res://src/oracle/oracle.gd", "screen"],
}
## backdrop theme per screen (RN Space theme per tab)
const BACKDROP := {"home": ["m_home", 0.0], "play": ["m_mode", 0.0], "team": ["m_team", 0.05], "shop": ["m_shop", 0.05], "profile": ["m_settings", 0.08], "account": ["m_settings", 0.1], "result": ["system", 0.0],
	"ranks": ["m_rank", 0.1], "tournaments": ["m_rank", 0.1], "challenges": ["m_rank", 0.1], "arena": ["m_rank", 0.1],
	"social": ["m_social", 0.1], "chat": ["m_social", 0.18], "club": ["m_social", 0.1], "public_profile": ["m_social", 0.1],
	"oracle": ["m_oracle", 0.1], "hub": ["m_stadium", 0.05], "lobby": ["m_stadium", 0.05], "online_result": ["m_stadium", 0.1]}
const NO_MUSIC := ["match", "online_match", "intro"]
## alternative script locations tried when the registry path is missing
const ALT_DIRS := ["res://src/screens/", "res://src/online/", "res://src/social/", "res://src/oracle/"]

var main: Node  # set by main.gd (has: host, backdrop, chrome_node, sheet_layer, toast_layer, veil)
var current := ""
var current_params := {}
var screen: Control
var history: Array = []  # [[name, params], ...]
var _busy := false
var _sheet: Control
var _sheet_panel: Control
var _sheet_dim: ColorRect
var _sheet_h := 0.0
var _modal: Control
var _modal_stack: Array = []
var _toast_node: Control
var _toast_tw: Tween
var _music_on = null
var _chrome_vis := true
## screen-owned popups (OUI.modal etc.): [[node, on_close], ...] — Android back closes the top one first
var _overlays: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", func(): _update_music(current))

func attach(m: Node) -> void:
	main = m
	# a fresh main (first boot or a language-switch scene reload): forget the old tree's nodes
	current = ""
	current_params = {}
	screen = null
	history.clear()
	_busy = false
	_sheet = null
	_sheet_panel = null
	_sheet_dim = null
	_modal = null
	_modal_stack.clear()
	_toast_node = null

func is_registered(name: String) -> bool:
	return REG.has(name)

func script_path(name: String) -> String:
	if not REG.has(name):
		for d in ALT_DIRS:
			if ResourceLoader.exists(d + name + ".gd"):
				return d + name + ".gd"
		return ""
	var p: String = REG[name][0]
	if ResourceLoader.exists(p):
		return p
	for d in ALT_DIRS:
		if ResourceLoader.exists(d + name + ".gd"):
			return d + name + ".gd"
	return ""

func kind_of(name: String) -> String:
	return REG[name][1] if REG.has(name) else "screen"

## Create a screen instance (setup called) or null (with a "به‌زودی" toast) if missing/broken.
func _instance(name: String, params: Dictionary) -> Control:
	var path := script_path(name)
	if path == "":
		toast(I18n.t("nav.coming_soon"))
		return null
	var s = load(path)
	if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
		toast(I18n.t("nav.coming_soon"))
		return null
	var o = (s as GDScript).new()
	if not o is Control:
		if o is Node:
			o.queue_free()
		toast(I18n.t("nav.coming_soon"))
		return null
	var c := o as Control
	c.name = name.capitalize().replace(" ", "")
	if c.has_method("setup"):
		c.setup(params)
	return c

# ------------------------------------------------------------------ go / back
func go(name: String, params := {}, _push := true) -> void:
	if name == "hub":
		name = "home"
	if main == null:
		push_warning("Nav.go before main attached: " + name)
		return
	var kind := kind_of(name)
	if kind == "sheet":
		var c := _instance(name, params)
		if c:
			var opts: Dictionary = c.sheet_opts() if c.has_method("sheet_opts") else {}
			sheet(c, opts)
		return
	if kind == "modal":
		var c2 := _instance(name, params)
		if c2:
			modal(c2, c2.modal_accent() if c2.has_method("modal_accent") else NX.GOLD)
		return
	if _busy:
		# queue the latest request right after the running transition
		get_tree().create_timer(0.2).timeout.connect(func(): go(name, params, _push))
		return
	if name == current and kind == "tab":
		close_sheet()
		_close_all_modals()
		if screen and screen.has_method("on_reselect"):
			screen.on_reselect(params)
		return
	var c3 := _instance(name, params)
	if c3 == null:
		return
	close_sheet(true)
	_close_all_modals()
	if kind == "tab":
		history.clear()
	elif _push and current != "" and current != "intro" and current != name:
		history.append([current, current_params])
		if history.size() > 12:
			history.pop_front()
	var prev_kind := kind_of(current) if current != "" else ""
	var quick := kind == "tab" and prev_kind == "tab"
	_swap(name, params, c3, quick)

func _swap(name: String, params: Dictionary, c: Control, quick: bool) -> void:
	_busy = true
	var old := screen
	if quick:
		# tab → tab: cross-fade with a small rise (RN FadeIn 240 / FadeOut 120)
		if old:
			_leave(old)
			var to := old.create_tween()
			to.tween_property(old, "modulate:a", 0.0, 0.12)
			to.tween_callback(old.queue_free)
		_mount(name, params, c)
		_screen_pop_in(c)
		c.modulate.a = 0.0
		c.position.y = 36
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.24)
		tw.tween_property(c, "position:y", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func(): _busy = false)
		return
	var veil: ColorRect = main.veil
	var tw2 := veil.create_tween()
	veil.visible = true
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	tw2.tween_property(veil, "color:a", 1.0, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_callback(func():
		if old:
			_leave(old)
			old.queue_free()
		_mount(name, params, c)
		_screen_pop_in(c))
	tw2.tween_property(veil, "color:a", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_callback(func():
		veil.visible = false
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy = false)

func _leave(s: Control) -> void:
	if is_instance_valid(s) and s.has_method("leave"):
		s.leave()

## subtle zoom-in on freshly mounted screens (menu quality): scale 0.965 → 1 with a soft cubic ease
func _screen_pop_in(c: Control) -> void:
	var tw := c.create_tween()
	tw.tween_interval(0.02)
	tw.tween_callback(func():
		if not is_instance_valid(c):
			return
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(0.965, 0.965)
		var tw2 := c.create_tween()
		tw2.tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

func _mount(name: String, params: Dictionary, c: Control) -> void:
	current = name
	current_params = params
	screen = c
	var kind := kind_of(name)
	_chrome_vis = kind == "tab"
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.host.add_child(c)
	_apply_chrome()
	if main.chrome_node:
		main.chrome_node.set_tab(name)
	if main.backdrop:
		main.backdrop.visible = kind != "fs" or name == "intro"
		if BACKDROP.has(name):
			main.backdrop.set_theme_name(BACKDROP[name][0], BACKDROP[name][1])
		elif kind == "screen":
			main.backdrop.set_theme_name("base", 0.15)
	_update_music(name)
	screen_changed.emit(name)

## register a popup a screen built itself so Android back closes it (topmost first)
func push_overlay(node: Control, on_close: Callable = Callable()) -> void:
	_overlays.append([node, on_close])

func _close_top_overlay() -> bool:
	while _overlays.size():
		var o: Array = _overlays.pop_back()
		var n = o[0]
		if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree() or (n as Node).is_queued_for_deletion():
			continue
		var cb: Callable = o[1]
		if cb.is_valid():
			cb.call()
		else:
			(n as Node).queue_free()
		return true
	return false

func back() -> void:
	if _modal:
		close_modal()
		return
	if _sheet:
		close_sheet()
		return
	if _close_top_overlay():
		return
	if screen and screen.has_method("on_back") and screen.on_back() == true:
		return
	if current == "intro" or current == "match" or current == "online_match":
		return  # those screens own their back behaviour via on_back()
	if history.size():
		var h = history.pop_back()
		go(h[0], h[1], false)
		return
	if current != "home":
		go("home")
		return
	if _busy:
		return
	confirm(I18n.t("nav.quit_nexora"), func(): get_tree().quit(), I18n.t("nav.quit"), I18n.t("nav.stay"))

# ------------------------------------------------------------------ chrome / backdrop / music
func chrome(visible: bool) -> void:
	_chrome_vis = visible
	_apply_chrome()

func _apply_chrome() -> void:
	if main == null or main.chrome_node == null:
		return
	var ch: Control = main.chrome_node
	if _chrome_vis and not ch.visible:
		ch.visible = true
		ch.modulate.a = 0.0
		ch.create_tween().tween_property(ch, "modulate:a", 1.0, 0.25)
	elif not _chrome_vis:
		ch.visible = false
	if _chrome_vis:
		ch.refresh()

func backdrop(theme: String, dim := -1.0) -> void:
	if main and main.backdrop:
		main.backdrop.visible = true
		main.backdrop.set_theme_name(theme, dim)

func insets() -> Dictionary:
	var top := NX.safe_top + (NX.HUD_H + 10 if _chrome_vis else 24.0)
	var bottom := maxf(26.0, NX.safe_bottom) + 24.0  # v3: no bottom tab bar
	return {"top": top, "bottom": bottom}

func refresh_chrome() -> void:
	if main and main.chrome_node and main.chrome_node.visible:
		main.chrome_node.refresh()

## menu track (Sfx "menu"): on in the shell, off in intro / match / online_match; resumes on return.
func _update_music(name: String) -> void:
	if name in ["match", "online_match"]:
		UD.set_scene("match")
	elif kind_of(name) == "tab":
		UD.set_scene("menu")
	var want: bool = bool(UD.pv("music", true)) and not (name in NO_MUSIC) and name != ""
	if _music_on == null or _music_on != want:
		_music_on = want
		UD.menu_music(want)

# ------------------------------------------------------------------ sheets
func sheet(content: Control, opts := {}) -> Control:
	close_sheet(true)
	var layer: Control = main.sheet_layer
	var accent: Color = opts.get("accent", NX.CYAN)
	var H: float = layer.size.y
	var h: float = minf(H * float(opts.get("height", 0.84)), H - NX.safe_top - 52)
	_sheet_h = h
	var root := Control.new()
	root.name = "Sheet"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.012, 0.047, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and not ev.pressed: close_sheet())
	root.add_child(dim)
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size = Vector2(layer.size.x, h + 100)
	panel.position = Vector2(0, H)
	root.add_child(panel)
	var bg := NxGrad.new([NX.BG2, NX.BG2, NX.BG2], 56.0, 1.57, 0.0)
	bg.set_border(3.0, Color(accent.r, accent.g, accent.b, 0.4))
	bg.set_glow(Color(accent.r * 1.3, accent.g * 1.3, accent.b * 1.3, 0.4), 50.0, 60.0)
	bg.position = Vector2(-60, -60)
	bg.size = panel.size + Vector2(120, 120)
	# opaque backing: the gradient shader leaves the sheet see-through, so the screen behind
	# bled into headers and rows
	var back := Panel.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := NX.box(NX.BG2, 0)
	bsb.corner_radius_top_left = 56; bsb.corner_radius_top_right = 56
	back.add_theme_stylebox_override("panel", bsb)
	back.size = panel.size
	panel.add_child(back)
	panel.add_child(bg)
	var scan := TextureRect.new()
	scan.texture = UD.tex("res://assets/g/ui/scan.png")
	scan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scan.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scan.modulate.a = 0.35
	scan.visible = false  # flat v3: no scanline texture
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.position = Vector2(20, 20)
	scan.size = panel.size - Vector2(40, 40)
	panel.add_child(scan)
	# header (drag handle)
	var head := Control.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.size = Vector2(panel.size.x, 210 if opts.has("title") else 140)
	panel.add_child(head)
	var grip := ColorRect.new()
	grip.color = Color(1, 1, 1, 0.22)
	grip.size = Vector2(120, 13)
	grip.position = Vector2(panel.size.x * 0.5 - 60, 22)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(grip)
	if not opts.has("title"):
		# every popup gets the same close button in the same (top-left) corner
		var cx := Kit.close_button(func(): close_sheet(), 88)
		cx.position = Vector2(40, 40)
		cx.size = Vector2(88, 88)
		head.add_child(cx)
	if opts.has("title"):
		var row := Kit.hbox(20)
		row.layout_direction = Control.LAYOUT_DIRECTION_LTR
		row.position = Vector2(40, 58)
		row.size = Vector2(panel.size.x - 80, 130)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(Kit.close_button(func(): close_sheet()))
		var col := Kit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		if false and opts.get("en", "") != "":  # v3: no English caps sub-title (clutter)
			var e := Kit.caps(str(opts["en"]), 23, NX.hdr(accent, 1.3), 8)
			e.horizontal_alignment = I18n.AR
			col.add_child(e)
		var t := Kit.title(str(opts["title"]), 52)
		t.horizontal_alignment = I18n.AR
		col.add_child(t)
		row.add_child(col)
		head.add_child(row)
	var drag := {"on": false, "y0": 0.0, "py": 0.0, "t": 0}
	head.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				drag["on"] = true; drag["y0"] = ev.global_position.y; drag["py"] = panel.position.y; drag["t"] = Time.get_ticks_msec()
			elif drag["on"]:
				drag["on"] = false
				var dy: float = panel.position.y - (H - h)
				var dt: float = maxf(1.0, Time.get_ticks_msec() - drag["t"])
				if dy > h * 0.22 or (dy > 40 and dy / dt > 1.0):
					close_sheet()
				else:
					panel.create_tween().tween_property(panel, "position:y", H - h, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif ev is InputEventMouseMotion and drag["on"]:
			panel.position.y = maxf(H - h, drag["py"] + ev.global_position.y - drag["y0"]))
	# body
	var body := MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.position = Vector2(0, head.size.y)
	body.size = Vector2(panel.size.x, h - head.size.y - NX.safe_bottom)
	body.clip_contents = true
	panel.add_child(body)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(content)
	_sheet = root
	_sheet_panel = panel
	_sheet_dim = dim
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "position:y", H - h, 0.55).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "color:a", 0.72, 0.25)
	UD.haptic("light")
	return root

func has_sheet() -> bool:
	return _sheet != null

func close_sheet(instant := false) -> void:
	if _sheet == null:
		return
	var s := _sheet
	var p := _sheet_panel
	var d := _sheet_dim
	_sheet = null
	_sheet_panel = null
	_sheet_dim = null
	for c in _find_screens(s):
		_leave(c)
	if instant:
		s.queue_free()
		sheet_closed.emit()
		return
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UD.haptic("light")
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(p, "position:y", s.size.y, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(d, "color:a", 0.0, 0.22)
	tw.chain().tween_callback(func():
		s.queue_free()
		sheet_closed.emit())

func _find_screens(n: Node) -> Array:
	var o := []
	for c in n.get_children():
		if c.has_method("setup"):
			o.append(c)
		o.append_array(_find_screens(c))
	return o

# ------------------------------------------------------------------ modals
func modal(content: Control, accent := NX.GOLD, width := 0.88) -> Control:
	var layer: Control = main.sheet_layer
	var root := Control.new()
	root.name = "Modal"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.0
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and not ev.pressed: close_modal())
	root.add_child(dim)
	var w: float = minf(layer.size.x * width, 1100)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := NX.box(Color(0, 0, 0, 0), 48)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(w, 0)
	var g := NxGrad.new([NX.SURF, NX.SURF, NX.SURF], 48, 1.57, 0.0)
	g.set_border(3.0, Color(accent.r * 1.2, accent.g * 1.2, accent.b * 1.2, 0.6))
	card.add_child(g)
	card.add_child(content)
	root.add_child(card)
	# same close button, same corner as sheets and screen headers (top-left of the card)
	var cx := Kit.close_button(func(): close_modal(), 84)
	cx.size = Vector2(84, 84)
	root.add_child(cx)
	var place := func():
		card.reset_size()
		card.position = (layer.size - card.size) * 0.5
		card.pivot_offset = card.size * 0.5
		cx.position = card.position + Vector2(22, 22)
	content.resized.connect(place)
	card.resized.connect(place)
	place.call()
	card.scale = Vector2(0.6, 0.6)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_property(dim, "modulate:a", 1.0, 0.2)
	cx.modulate.a = 0.0
	cx.create_tween().tween_property(cx, "modulate:a", 1.0, 0.25).set_delay(0.12)
	if _modal:
		_modal_stack.append(_modal)
	_modal = root
	return root

func close_modal() -> void:
	if _modal == null:
		return
	var m := _modal
	_modal = _modal_stack.pop_back() if _modal_stack.size() else null
	for c in _find_screens(m):
		_leave(c)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := m.create_tween()
	tw.tween_property(m, "modulate:a", 0.0, 0.16)
	tw.tween_callback(m.queue_free)

func _close_all_modals() -> void:
	while _modal:
		var m := _modal
		_modal = _modal_stack.pop_back() if _modal_stack.size() else null
		m.queue_free()

func has_modal() -> bool:
	return _modal != null

func confirm(text: String, cb: Callable, ok := "", cancel := "") -> void:
	if ok == "": ok = I18n.t("nav.ok")
	if cancel == "": cancel = I18n.t("nav.cancel")
	var v := Kit.vbox(30)
	var m := Kit.margin(v, 56, 60, 56, 56)
	v.add_child(Kit.center(Kit.img(UD.ui2("c_bell"), 170)))
	var l := Kit.para(text, 42, NX.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(l)
	var row := Kit.hbox(24, true)
	var b1 := Kit.button_small(ok, func():
		close_modal()
		if cb.is_valid(): cb.call(), "primary")
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := Kit.button_small(cancel, func(): close_modal(), "dark")
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b1)
	row.add_child(b2)
	v.add_child(Kit.gap(6))
	v.add_child(row)
	modal(m, NX.CYAN, 0.84)

# ------------------------------------------------------------------ toast
func toast(text: String, kind := "info") -> void:
	if main == null:
		print("[toast] ", text)
		return
	var layer: Control = main.toast_layer
	if _toast_node and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	var col: Color = NX.RED if kind == "err" else (NX.GREEN if kind == "ok" else NX.CYAN)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := NX.box(Color(NX.SURF2, 0.98), 40, 2, Color(col, 0.6))
	sb.content_margin_left = 42; sb.content_margin_right = 42; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", sb)
	var h := Kit.hbox(16, true)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE   # toast never swallows taps
	h.add_child(Kit.img(UD.ui2("c_bell") if kind == "err" else (UD.ui2("x_star") if kind == "ok" else UD.ui2("c_mega")), 68))
	var l := Kit.label(text, 36, NX.TEXT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var maxw := layer.size.x * 0.9
	# an autowrap Label has ~0 minimum width: give it its natural one-line width capped by the
	# space left next to the icon BEFORE it is laid out, or it wraps one letter per line and the
	# toast becomes a screen-tall column
	l.custom_minimum_size.x = minf(UD.text_w(l) + 6.0, maxw - 84 - 68 - 16)
	l.size.x = l.custom_minimum_size.x
	h.add_child(l)
	p.add_child(h)
	layer.add_child(p)
	_toast_node = p
	var fit := func():
		p.size = Vector2.ZERO
		p.reset_size()
		p.size.x = minf(p.size.x, maxw)
		p.position = Vector2((layer.size.x - p.size.x) * 0.5, NX.safe_top + 170)
		p.pivot_offset = p.size * 0.5
	fit.call()
	# second pass once the wrapped label has its real width (its min height depends on it)
	(func():
		if is_instance_valid(p):
			p.size = Vector2.ZERO
			p.reset_size()
			p.position.x = (layer.size.x - p.size.x) * 0.5
			p.pivot_offset = p.size * 0.5).call_deferred()
	p.modulate.a = 0.0
	p.scale = Vector2(0.9, 0.9)
	var y0 := p.position.y
	p.position.y = y0 - 50
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = p.create_tween()
	_toast_tw.set_parallel(true)
	_toast_tw.tween_property(p, "modulate:a", 1.0, 0.3)
	_toast_tw.tween_property(p, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_property(p, "position:y", y0, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_toast_tw.chain().tween_interval(1.7)
	_toast_tw.chain().tween_property(p, "modulate:a", 0.0, 0.25)
	_toast_tw.chain().tween_callback(p.queue_free)

# ------------------------------------------------------------------ app-level actions (RN App.tsx)
## open the free (premium=false) or royal chest; applies the prize and shows the opening modal
func open_chest(premium: bool) -> void:
	var p := UD.p()
	if not premium and not UD.chest_ready():
		toast(I18n.t("nav.the_free_chest_isn_t"), "info")
		return
	if premium and int(p.get("coins", 0)) < 600:
		toast(I18n.t("nav.you_need_600_coins"), "err")
		return
	var prize := UD.roll_chest(p, premium)
	var patch := {}
	if prize.has("item") and prize["item"] is Dictionary:
		patch = UD.grant(prize["item"], p)
	patch["coins"] = int(p.get("coins", 0)) + int(prize.get("coins", 0)) - (600 if premium else 0)
	if int(prize.get("gems", 0)) > 0:
		patch["gems"] = int(p.get("gems", 0)) + int(prize["gems"])
	if not premium:
		patch["lastChest"] = UD.now_ms()
	patch["chests"] = int(p.get("chests", 0)) + 1
	UD.set_p(patch)
	refresh_chrome()
	go("chest", {"prize": prize, "premium": premium})

func claim_daily() -> void:
	if not UD.daily_ready():
		return
	var p := UD.p()
	var last := int(p.get("lastDaily", 0))
	var streak := (int(p.get("streak", 0)) % 7) + 1 if UD.now_ms() - last < 2 * UD.DAY else 1
	var rw: Dictionary = UD.dget("DAILY", UD.DAILY)[streak - 1]
	UD.set_p({"lastDaily": UD.now_ms(), "streak": streak, "coins": int(p.get("coins", 0)) + int(rw["coins"]), "gems": int(p.get("gems", 0)) + int(rw.get("gems", 0))})
	UD.sfx("ui")
	UD.haptic("heavy")
	var msg := I18n.t("nav.x_coins") % NX.fa(rw["coins"])
	if int(rw.get("gems", 0)) > 0:
		msg += I18n.t("nav.x_gems") % NX.fa(rw["gems"])
	toast(msg, "ok")
	close_modal()
	refresh_chrome()

## online entry points (Home/Play) — entry: hub|tours|ranks|arena|challenges|leagues
func online(entry := "hub", quick := "") -> void:
	var m := {"hub": "hub", "tours": "tournaments", "tournaments": "tournaments", "ranks": "ranks", "leagues": "ranks", "arena": "arena", "challenges": "challenges", "social": "social"}
	var target: String = m.get(entry, "hub")
	var params := {"entry": entry}
	if quick != "":
		params["quick"] = quick
	if script_path(target) == "" and script_path("hub") != "":
		target = "hub"
	go(target, params)
