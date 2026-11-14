class_name NxChrome
extends Control
## App chrome, v2 (home mockup): top HUD (avatar ring + level badge + name + XP bar, gems, coins,
## gift, settings) + floating glass tab bar (Home, Rank, centre round Play, Team, Social) with a
## sliding pink highlight on the active tab.

const TABS := [
	["home", "v2.tab_home", "n_home"],
	["rank", "v2.tab_rank", "n_rank"],
	["play", "v2.tab_play", ""],
	["team", "v2.tab_team", "n_team"],
	["social", "v2.tab_social", "n_social"],
]
const PINK := Color("#ff4f8b")
const PEACH := Color("#ff9a66")

var hud: Control
var hud_bg: TextureRect
var tabbar: Control
var bar_bg: Panel
var hl: Panel
var play_orb: PlayOrb
var tab_btns: Array[Control] = []
var tab_icons: Array[TextureRect] = []
var tab_labels: Array[Label] = []
var tab_badges: Array[Control] = []
var cur := 0
var _hl_x := 0.0
var _hl_tw: Tween

# hud widgets
var name_l: Label
var xp_bar: NxBar
var lvl_l: Label
var av_holder: Control
var gem_l: Label
var coin_l: Label
var gift: Control
var gift_art: TextureRect
var gift_badge: Control
var _gift_tw: Tween
var _last_sig := ""
var back_btn: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_build_tabbar()
	resized.connect(_layout)
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", refresh)
	var sp := UD.node("Supa")
	if sp and sp.has_signal("profile_changed"):
		sp.connect("profile_changed", func(_p): refresh())
	var tm := Timer.new()
	tm.wait_time = 20.0
	tm.autostart = true
	tm.timeout.connect(refresh)
	add_child(tm)
	_layout()
	refresh()

static func glass_sb(r: int, _border := Color(0.56, 0.5, 1.0, 0.34), _bg := Color(0.06, 0.05, 0.18, 0.86)) -> StyleBoxFlat:
	return NX.box(NX.SURF2, r, 2, NX.LINE)  # flat v3

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	hud_bg = TextureRect.new()
	hud_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_bg.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(NX.BG, 0.96), Color(NX.BG, 0.85), Color(NX.BG, 0)])
	g.offsets = PackedFloat32Array([0, 0.55, 1])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	hud_bg.texture = gt
	hud.add_child(hud_bg)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(row)

	# v3: back button, top-left — chrome only shows on inner screens now (the online home has its own header)
	back_btn = Kit.back_button(func(): Nav.back(), 96)
	row.add_child(back_btn)
	# profile: avatar ring (level badge) + name/XP pill (hidden in v3: lives in the home drawers)
	var me := Control.new()
	me.visible = false
	me.custom_minimum_size = Vector2(330, 120)
	me.mouse_filter = Control.MOUSE_FILTER_PASS
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", glass_sb(40))
	pill.position = Vector2(56, 22)
	pill.size = Vector2(274, 80)
	me.add_child(pill)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.position = Vector2(128, 22)
	col.size = Vector2(186, 80)
	name_l = Kit.label("Pilot", 32, NX.TEXT, true)
	name_l.custom_minimum_size.x = 186
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.horizontal_alignment = I18n.AR
	col.add_child(name_l)
	xp_bar = NxBar.new(0.0, PINK, PEACH, 12)
	xp_bar.custom_minimum_size = Vector2(186, 12)
	xp_bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	col.add_child(xp_bar)
	me.add_child(col)
	var ring := AvatarRing.new()
	ring.position = Vector2(0, 2)
	ring.size = Vector2(116, 116)
	me.add_child(ring)
	av_holder = Control.new()
	av_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_holder.position = Vector2(14, 16)
	ring.add_child(av_holder)
	var lv := PanelContainer.new()
	var lsb := NX.box(Color(0.07, 0.06, 0.2, 0.98), 14, 3, Color(0.62, 0.55, 1.0, 0.9))
	lsb.content_margin_left = 6; lsb.content_margin_right = 6
	lv.add_theme_stylebox_override("panel", lsb)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvl_l = Kit.title("1", 22, NX.TEXT)
	lvl_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.add_child(lvl_l)
	lv.position = Vector2(78, 78)
	lv.custom_minimum_size = Vector2(44, 42)
	me.add_child(lv)
	Kit.tap(me, func(): Nav.go("profile"), 0.95)
	row.add_child(me)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)

	var gp := _pill(UD.art("h_gem"))
	gem_l = gp.get_meta("label")
	row.add_child(gp)
	var cp := _pill(UD.art("h_coin"))
	coin_l = cp.get_meta("label")
	row.add_child(cp)

	gift = _round(UD.art("h_gift"), func(): Nav.go("daily"))
	gift_art = gift.get_meta("art")
	gift_badge = NxNeon.dot(Vector2(62, -2))
	gift.add_child(gift_badge)
	row.add_child(gift)
	gift.visible = false   # v3: daily reward + settings live in the home drawers
	var gear := _round(UD.art("h_gear"), func(): Nav.go("settings"))
	gear.visible = false
	row.add_child(gear)

func _pill(icon: Texture2D) -> Control:
	var p := PanelContainer.new()
	var sb := glass_sb(40)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = 80
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := Kit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	p.add_child(h)
	h.add_child(Kit.img(icon, 50))
	var l := Kit.title("0", 28, NX.TEXT, "head")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 54
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)
	var pl := PanelContainer.new()
	pl.add_theme_stylebox_override("panel", NX.box(Color(1, 1, 1, 0.04), 22, 2, Color(0.75, 0.75, 1.0, 0.55)))
	pl.custom_minimum_size = Vector2(44, 44)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Kit.title("+", 28, Color(0.85, 0.85, 1.0))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.add_child(t)
	h.add_child(pl)
	p.set_meta("label", l)
	Kit.tap(p, func(): Nav.go("shop"), 0.92)
	return p

## round glass button (gift / settings): 88px touch target, 52px glyph
func _round(icon: Texture2D, cb: Callable) -> Control:
	var c := Panel.new()
	c.add_theme_stylebox_override("panel", glass_sb(44))
	c.custom_minimum_size = Vector2(88, 88)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var a := Kit.img(icon, 52)
	a.position = Vector2(18, 18)
	a.size = Vector2(52, 52)
	a.pivot_offset = Vector2(26, 26)
	c.add_child(a)
	c.set_meta("art", a)
	Kit.tap(c, cb, 0.88)
	return c

# ------------------------------------------------------------------ tab bar
func _build_tabbar() -> void:
	tabbar = Control.new()
	tabbar.visible = false   # v3: no bottom tab bar (duplicate entry points); categories live in home drawers
	tabbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tabbar)
	bar_bg = Panel.new()
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := NX.box(Color(0.07, 0.055, 0.2, 0.94), 56, 3, Color(0.56, 0.5, 1.0, 0.38), 34, Color(0.45, 0.2, 0.9, 0.35))
	bar_bg.add_theme_stylebox_override("panel", bsb)
	tabbar.add_child(bar_bg)
	hl = Panel.new()
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := NX.box(Color(1.0, 0.42, 0.45, 0.30), 40, 3, NX.hdr(Color(1.0, 0.5, 0.55, 0.75), 1.2), 22, Color(1.0, 0.3, 0.5, 0.35))
	hl.add_theme_stylebox_override("panel", hsb)
	tabbar.add_child(hl)
	for i in TABS.size():
		var b := Control.new()
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic: TextureRect
		var l: Label
		if TABS[i][0] == "play":
			play_orb = PlayOrb.new()
			play_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(play_orb)
			ic = TextureRect.new()
			l = Label.new()
			l.visible = false
		else:
			ic = Kit.img(UD.art(TABS[i][2]), 66)
			ic.pivot_offset = Vector2(33, 33)
			b.add_child(ic)
			l = Kit.label(I18n.t(TABS[i][1]), 27, NX.DIM, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_child(l)
		var bd := Kit.badge_dot(true)
		bd.visible = false
		b.add_child(bd)
		var idx := i
		b.gui_input.connect(func(ev): _tab_input(ev, idx))
		tabbar.add_child(b)
		tab_btns.append(b)
		tab_icons.append(ic)
		tab_labels.append(l)
		tab_badges.append(bd)

func _tab_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		if i != cur:
			UD.sfx("ui")
			UD.haptic("light")
		match TABS[i][0]:
			"rank": Nav.online("ranks")
			"social": Nav.go("social")
			_: Nav.go(TABS[i][0])

func _bar_w() -> float:
	return minf(size.x - 52, 1352)

func _cell_x(i: int) -> float:
	# RTL (fa): home is the right-most cell; LTR (en): left-most
	var cw := _bar_w() / TABS.size()
	if I18n.is_en():
		return cw * i
	return _bar_w() - cw * (i + 1)

func _layout() -> void:
	var W := size.x
	var top := NX.safe_top
	hud.position = Vector2.ZERO
	hud.size = Vector2(W, top + NX.HUD_H + 40)
	hud_bg.size = hud.size
	var row := hud.get_node("Row") as Control
	row.position = Vector2(22 + NX.safe_left, top + 14)
	row.size = Vector2(W - 44 - NX.safe_left - NX.safe_right, 120)
	var bw := _bar_w()
	var bh := NX.TAB_H - 30
	var bottom := maxf(26, NX.safe_bottom)
	tabbar.size = Vector2(bw, bh)
	tabbar.position = Vector2((W - bw) * 0.5, size.y - bottom - bh)
	bar_bg.position = Vector2.ZERO
	bar_bg.size = tabbar.size
	var cw := bw / TABS.size()
	for i in tab_btns.size():
		var b := tab_btns[i]
		b.position = Vector2(_cell_x(i), 0)
		b.size = Vector2(cw, bh)
		if TABS[i][0] == "play":
			var d := 172.0
			play_orb.size = Vector2(d, d)
			play_orb.position = Vector2(cw * 0.5 - d * 0.5, bh * 0.5 - d * 0.5 - 26)
		else:
			tab_icons[i].position = Vector2(cw * 0.5 - 33, bh * 0.5 - 56)
			tab_labels[i].position = Vector2(0, bh * 0.5 + 14)
			tab_labels[i].size = Vector2(cw, 40)
		tab_badges[i].position = Vector2(cw * 0.66, 14)
	hl.size = Vector2(cw - 20, bh - 20)
	if _hl_tw == null or not _hl_tw.is_running():
		_hl_x = _cell_x(cur) + 10
	hl.position = Vector2(_hl_x, 10)
	hl.visible = TABS[cur][0] != "play"
	_style_tabs(false)

## highlight a tab by screen name ("" = none, e.g. online screens)
func set_tab(name: String) -> void:
	var idx := -1
	var key: String = "rank" if name == "ranks" else name
	for i in TABS.size():
		if TABS[i][0] == key:
			idx = i
	if idx < 0:
		return
	if idx == cur and _hl_x != 0.0:
		return
	cur = idx
	if _hl_tw:
		_hl_tw.kill()
	hl.visible = TABS[cur][0] != "play"
	_hl_tw = create_tween()
	_hl_tw.tween_method(func(v): _hl_x = v; hl.position.x = v, hl.position.x, _cell_x(cur) + 10, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_style_tabs(true)

func _style_tabs(animate: bool) -> void:
	for i in tab_btns.size():
		var on := i == cur
		if TABS[i][0] == "play":
			play_orb.active = on
			play_orb.queue_redraw()
			continue
		tab_labels[i].add_theme_color_override("font_color", Color("#ffd6e2") if on else Color(0.72, 0.74, 0.95))
		var ic := tab_icons[i]
		var target_y := (tabbar.size.y * 0.5 - 56) - (4 if on else 0)
		# active glyphs take the mockup's peach -> pink tint, idle ones stay lavender
		var mod := Color(1.25, 0.82, 0.8, 1) if on else Color(0.9, 0.92, 1.05, 0.75)
		if TABS[i][0] == "home" and not on:
			mod = Color(0.62, 0.7, 1.15, 0.75)
		if animate:
			var tw := ic.create_tween().set_parallel(true)
			tw.tween_property(ic, "position:y", target_y, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(ic, "modulate", mod, 0.25)
			if on:
				var pop := ic.create_tween()
				pop.tween_property(ic, "scale", Vector2(1.16, 1.16), 0.1)
				pop.tween_property(ic, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		else:
			ic.position.y = target_y
			ic.modulate = mod

func show_hud(v: bool) -> void:
	hud.visible = v

func show_tabs(_v: bool) -> void:
	tabbar.visible = false

# ------------------------------------------------------------------ data refresh
func refresh() -> void:
	var p := UD.p()
	var op := UD.online_profile()
	var xp := int(op.get("xp", p.get("xp", 0))) if not op.is_empty() else int(p.get("xp", 0))
	var lv := UD.level(xp)
	var nm := str(op.get("username", "")) if not op.is_empty() else ""
	if nm == "":
		nm = str(p.get("name", "Pilot"))
	var gems := int(op.get("gems", p.get("gems", 0))) if not op.is_empty() else int(p.get("gems", 0))
	var av_key = op.get("avatar_url", null) if not op.is_empty() else null
	if av_key == null or str(av_key) == "":
		av_key = op.get("equipped_disc", null) if not op.is_empty() else null
	if av_key == null or str(av_key) == "":
		av_key = str(p.get("team", "club0"))
	var sig := "%s|%s" % [av_key, nm]
	name_l.text = nm
	name_l.text_direction = Control.TEXT_DIRECTION_RTL if NX.is_fa(nm) else Control.TEXT_DIRECTION_AUTO
	name_l.add_theme_font_override("font", NX.font("faB" if NX.is_fa(nm) else "bold"))
	lvl_l.text = str(lv["level"])
	xp_bar.set_frac(maxf(0.04, float(lv["cur"]) / maxf(1.0, float(lv["need"]))))
	_count(gem_l, gems)
	_count(coin_l, int(p.get("coins", 0)))
	if sig != _last_sig:
		_last_sig = sig
		for c in av_holder.get_children():
			c.queue_free()
		av_holder.add_child(Kit.avatar(av_key, 88))
	var dr := UD.daily_ready()
	gift_badge.visible = dr
	if dr and _gift_tw == null:
		_gift_tw = gift_art.create_tween().set_loops()
		_gift_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_gift_tw.tween_property(gift_art, "rotation", deg_to_rad(8), 0.9)
		_gift_tw.parallel().tween_property(gift_art, "scale", Vector2(1.08, 1.08), 0.9)
		_gift_tw.tween_property(gift_art, "rotation", deg_to_rad(-8), 0.9)
		_gift_tw.parallel().tween_property(gift_art, "scale", Vector2.ONE, 0.9)
	elif not dr and _gift_tw:
		_gift_tw.kill()
		_gift_tw = null
		gift_art.rotation = 0
		gift_art.scale = Vector2.ONE

## animated count-up for currency changes
func _count(l: Label, v: int) -> void:
	var old := int(l.get_meta("v", -1))
	l.set_meta("v", v)
	if old < 0 or old == v or not is_inside_tree():
		l.text = NX.en_num(v)
		return
	var tw := l.create_tween()
	tw.tween_method(func(x: float): l.text = NX.en_num(int(x)), float(old), float(v), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var pop := l.create_tween()
	l.pivot_offset = l.size * 0.5
	pop.tween_property(l, "scale", Vector2(1.2, 1.2), 0.1)
	pop.tween_property(l, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## avatar socket: dark disc with a peach -> pink progress-style ring (mockup)
class AvatarRing extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.05, 0.04, 0.16, 0.96), true, -1.0, true)
		draw_arc(c, r - 3, 0, TAU, 64, Color(0.56, 0.5, 1.0, 0.35), 3.0, true)
		var n := 40
		for i in n:
			var a0 := -PI * 0.5 + PI * 1.2 * float(i) / n
			var a1 := -PI * 0.5 + PI * 1.2 * float(i + 1) / n
			var col := Color("#ff9a66").lerp(Color("#ff4f8b"), float(i) / n)
			draw_arc(c, r - 3, a0, a1 + 0.01, 3, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4), 6.0, true)


## centre Play button: dark orb, neon ring, orbit, gradient triangle; brighter when active
class PlayOrb extends Control:
	var active := false
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6
		var pulse := 0.5 + 0.5 * sin(t * 2.2)
		draw_circle(c, r + 4, Color(1.0, 0.3, 0.55, 0.16 + 0.1 * pulse + (0.1 if active else 0.0)), true, -1.0, true)
		draw_circle(c, r, Color(0.06, 0.04, 0.17, 0.98), true, -1.0, true)
		var n := 48
		for i in n:
			var a0 := TAU * float(i) / n
			var k := 0.5 + 0.5 * sin(a0 + t * 0.8)
			var col := Color("#ff9a66").lerp(Color("#8a3fe0"), k)
			draw_arc(c, r - 3, a0, a0 + TAU / n + 0.01, 3, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5), 5.0, true)
		draw_arc(c, r - 18, 0, TAU, 48, Color(1, 1, 1, 0.08), 2.0, true)
		# orbit
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * float(i) / 48
			var p := Vector2(cos(a) * (r + 10), sin(a) * (r * 0.32)).rotated(-0.45)
			pts.append(c + p)
		draw_polyline(pts, Color(1.0, 0.55, 0.6, 0.45), 2.0, true)
		# play triangle
		var s := r * 0.42
		var tri := PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.8), c + Vector2(s * 0.9, 0), c + Vector2(-s * 0.55, s * 0.8)])
		var k2 := 1.6 if active else 1.3
		draw_polygon(tri, PackedColorArray([Color(1.0 * k2, 0.62 * k2, 0.45 * k2), Color(1.0 * k2, 0.31 * k2, 0.55 * k2), Color(0.85 * k2, 0.3 * k2, 0.7 * k2)]))
