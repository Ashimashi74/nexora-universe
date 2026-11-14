class_name MatchHud
extends Control
## In-match HUD (offline match; reusable by the online match): code-drawn, no raster art.
## Beveled glass slab: two team wings (disc avatar, name, turn chip) around a raised metallic score plate with the
## clock pill, a glowing turn-time strip under the active wing and a beveled round pause button.
## Every string goes through tr() with keys from res://assets/i18n/game_hud.csv (fa fallback when no table is loaded).
##
##   var h := MatchHud.new(); h.setup([tex0, tex1], ["name0", "name1"], [is_human0, is_human1]); add_child(h)
##   h.size = Vector2(w, 64 * U)            # height drives every proportion
##   h.set_state(s0, s1, turn, clock_text, sudden, turn_frac, show_turn_bar, active)
##   h.pause_pressed.connect(...)

signal pause_pressed
signal loadout_pressed

const TEAM := [Color("#39d5ff"), Color("#ff4a5a")]
const TEAM2 := [Color("#3b6bff"), Color("#ff8a3a")]
const SLAB := Color("#070b1f")
const SLAB2 := Color("#111a3e")
const STEEL := Color("#c9d6ff")

var tex: Array = [null, null]
var names: Array = ["", ""]
var human: Array = [true, false]
var s0 := 0
var s1 := 0
var turn := 0
var clock := ""
var sudden := false
var frac := 1.0
var bar_on := true
var active := true          # false while goal pause / ball moving: wings dim slightly
var _t := 0.0
var _pop := 0.0             # score pop animation 0..1

var score_l: Label
var clock_l: Label
var name_l: Array = [null, null]
var chip_l: Array = [null, null]
var pause_btn: Control
var loadout_btn: Control

static func t(key: String, fa: String) -> String:
	var s := TranslationServer.translate(key)
	return fa if (s == "" or s == key) else String(s)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(textures: Array, team_names: Array, humans: Array) -> void:
	tex = textures
	names = team_names
	human = humans
	_build()

func _build() -> void:
	score_l = Kit.title("0  0", 30, Color.WHITE)
	score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_l.add_theme_font_override("font", NX.font("bold"))   # Exo2 digits (Orbitron's slashed zero reads as Ø)
	score_l.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.08, 0.9))
	score_l.add_theme_constant_override("outline_size", 8)
	score_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	score_l.add_theme_constant_override("shadow_offset_y", 3)
	add_child(score_l)
	clock_l = Kit.label("", 20, NX.DIM, true)
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(clock_l)
	for i in 2:
		var n := Kit.label(String(names[i]), 28, Color.WHITE, true)
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.clip_text = true
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		n.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		n.add_theme_constant_override("shadow_offset_y", 2)
		add_child(n)
		name_l[i] = n
		var c := Kit.label("", 19, Color.WHITE, true)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(c)
		chip_l[i] = c
	for l in [score_l, clock_l] + name_l + chip_l: (l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_btn = _PauseBtn.new()
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	add_child(pause_btn)
	# small loadout button (formation / ball / disc) right under the pause button
	loadout_btn = _PauseBtn.new()
	loadout_btn.icon = "sliders"
	loadout_btn.pressed.connect(func(): loadout_pressed.emit())
	add_child(loadout_btn)
	resized.connect(_layout)
	_layout()

# ------------------------------------------------------------------ state
func set_state(a: int, b: int, tn: int, clk: String, sd: bool, f: float, show_bar: bool, act := true) -> void:
	if a != s0 or b != s1: _pop = 1.0
	var redraw := a != s0 or b != s1 or tn != turn or sd != sudden or absf(f - frac) > 0.002 or show_bar != bar_on or act != active
	s0 = a; s1 = b; frac = clampf(f, 0, 1); bar_on = show_bar; active = act
	if tn != turn or chip_l[0].text == "": turn = tn; _chips()
	turn = tn
	if clk != clock or sd != sudden:
		clock = clk; sudden = sd
		clock_l.text = clk
		clock_l.add_theme_color_override("font_color", NX.GOLD if sd else Color(0.78, 0.86, 1.0))
	score_l.text = "%d   %d" % [s0, s1]
	if redraw: queue_redraw()

func _chips() -> void:
	for i in 2:
		var on: bool = i == turn
		var c: Label = chip_l[i]
		c.text = (t("hud.your_turn", "نوبت توئه") if human[i] else t("hud.opp_turn", "نوبت حریف")) if on else ""
		(name_l[i] as Label).add_theme_color_override("font_color", Color.WHITE if on else Color(0.62, 0.7, 0.88))

func _process(dt: float) -> void:
	_t += dt
	if _pop > 0:
		_pop = maxf(0.0, _pop - dt * 2.2)
		var k := 1.0 + 0.28 * sin(_pop * PI) * _pop
		score_l.pivot_offset = score_l.size * 0.5
		score_l.scale = Vector2(k, k)
	queue_redraw()   # subtle pulse on the active wing (one cheap canvas item)

# ------------------------------------------------------------------ geometry
var _pb := Rect2()        # pause button
var _wing := [Rect2(), Rect2()]
var _plate := Rect2()
var _av := [Vector2.ZERO, Vector2.ZERO]
var _avr := 0.0
var _sk := 0.0            # wing slant

func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0: return
	var pd := h * 0.66
	_pb = Rect2(0, (h * 0.86 - pd) * 0.5, pd, pd)
	pause_btn.position = _pb.position
	pause_btn.size = _pb.size
	if loadout_btn:
		var ls := pd * 0.78
		loadout_btn.size = Vector2(ls, ls)
		loadout_btn.position = Vector2(_pb.position.x + (pd - ls) * 0.5, _pb.end.y + h * 0.12)
	var x0 := pd + h * 0.14
	var bw := w - x0
	var pw := clampf(bw * 0.27, h * 1.6, h * 2.6)
	var cx := x0 + bw * 0.5
	_plate = Rect2(cx - pw * 0.5, 0, pw, h * 0.86)
	var wy := h * 0.10
	var wh := h * 0.66
	_sk = wh * 0.32
	_wing[0] = Rect2(x0, wy, _plate.position.x - x0 + _sk * 0.6, wh)
	_wing[1] = Rect2(_plate.end.x - _sk * 0.6, wy, w - (_plate.end.x - _sk * 0.6), wh)
	_avr = wh * 0.40
	_av[0] = Vector2(_wing[0].position.x + _avr + wh * 0.16, wy + wh * 0.5)
	_av[1] = Vector2(_wing[1].end.x - _avr - wh * 0.16, wy + wh * 0.5)
	var fs := int(h * 0.36)
	score_l.add_theme_font_size_override("font_size", fs)
	score_l.position = Vector2(_plate.position.x, _plate.position.y + h * 0.02)
	score_l.size = Vector2(_plate.size.x, h * 0.52)
	clock_l.add_theme_font_size_override("font_size", int(h * 0.15))
	clock_l.position = Vector2(_plate.position.x + pw * 0.2, h * 0.56)
	clock_l.size = Vector2(pw * 0.6, h * 0.22)
	for i in 2:
		var n: Label = name_l[i]
		n.add_theme_font_size_override("font_size", int(h * 0.19))
		var nx0: float
		var nw: float
		if i == 0:
			nx0 = _av[0].x + _avr + h * 0.10
			nw = _plate.position.x - nx0 - h * 0.06
		else:
			nw = (_av[1].x - _avr - h * 0.10) - (_plate.end.x + h * 0.06)
			nx0 = _plate.end.x + h * 0.06
		n.position = Vector2(nx0, wy + wh * 0.06)
		n.size = Vector2(maxf(10, nw), wh * 0.5)
		var c: Label = chip_l[i]
		c.add_theme_font_size_override("font_size", int(h * 0.13))
		var cw := minf(maxf(10, nw), h * 1.25)
		c.size = Vector2(cw, wh * 0.27)
		c.position = Vector2(nx0 if i == 0 else nx0 + nw - cw, wy + wh * 0.50)
	queue_redraw()

# ------------------------------------------------------------------ drawing
static func _shade(c: Color, k: float, a := -1.0) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a if a < 0 else a)

## vertical-gradient polygon (top colour -> bottom colour by y)
func _grad_poly(pts: PackedVector2Array, top: Color, bot: Color) -> void:
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = minf(y0, p.y); y1 = maxf(y1, p.y)
	var cols := PackedColorArray()
	for p in pts: cols.append(top.lerp(bot, (p.y - y0) / maxf(1.0, y1 - y0)))
	draw_polygon(pts, cols)

func _wing_pts(i: int, r: Rect2, inset := 0.0) -> PackedVector2Array:
	var s := _sk
	var a := r.position + Vector2(inset, inset)
	var b := r.end - Vector2(inset, inset)
	if i == 0:   # left wing: square-ish outer end, slanted inner end tucked under the plate
		return PackedVector2Array([Vector2(a.x + s * 0.25, a.y), Vector2(b.x, a.y), Vector2(b.x - s, b.y), Vector2(a.x, b.y), Vector2(a.x, a.y + s * 0.25)])
	return PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x - s * 0.25, a.y), Vector2(b.x, a.y + s * 0.25), Vector2(b.x, b.y), Vector2(a.x + s, b.y)])

func _plate_pts(r: Rect2, inset := 0.0) -> PackedVector2Array:
	var k := r.size.y * 0.30
	var a := r.position + Vector2(inset, inset)
	var b := r.end - Vector2(inset, inset)
	return PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x - k, b.y), Vector2(a.x + k, b.y)])

func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q

func _draw() -> void:
	if size.x <= 0: return
	var h := size.y
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	# soft drop shadow under the whole slab
	for k in 3:
		var o := Vector2(0, h * (0.05 + 0.03 * k))
		for i in 2: draw_colored_polygon(_offset(_wing_pts(i, _wing[i]), o), Color(0, 0, 0, 0.16 - 0.04 * k))
		draw_colored_polygon(_offset(_plate_pts(_plate), o), Color(0, 0, 0, 0.18 - 0.05 * k))
	# wings
	for i in 2:
		var on := i == turn
		var tc: Color = TEAM[i]
		var r: Rect2 = _wing[i]
		var outer := _wing_pts(i, r)
		if on:
			# outer glow: stacked strokes, breathing
			for g in 4:
				var a := (0.16 - g * 0.035) * (0.75 + 0.25 * pulse) * (1.0 if active else 0.6)
				draw_polyline(_closed(outer), Color(tc.r, tc.g, tc.b, a), 3.0 + g * 5.0, true)
		# bevel rim (light top -> dark bottom), then the glass face inset
		_grad_poly(outer, _shade(tc, 0.9, 0.85) if on else Color(0.42, 0.5, 0.72, 0.55), _shade(tc, 0.35, 0.85) if on else Color(0.1, 0.12, 0.22, 0.75))
		var face := _wing_pts(i, r, h * 0.035)
		var top := SLAB2.lerp(tc, 0.28 if on else 0.06)
		var bot := SLAB.lerp(tc, 0.10 if on else 0.0)
		_grad_poly(face, Color(top.r, top.g, top.b, 0.96), Color(bot.r, bot.g, bot.b, 0.96))
		# glass sheen on the upper half
		var sh := PackedVector2Array()
		var cy := r.position.y + r.size.y * 0.46
		for p in face:
			sh.append(Vector2(p.x, minf(p.y, cy)))
		_grad_poly(sh, Color(1, 1, 1, 0.13 if on else 0.07), Color(1, 1, 1, 0.0))
		# top highlight / bottom shade lines (3D edge)
		draw_line(face[0] if i == 0 else face[0], face[1], Color(1, 1, 1, 0.35 if on else 0.18), 1.6, true)
		draw_line(face[2] if i == 0 else face[3], face[3] if i == 0 else face[4], Color(0, 0, 0, 0.45), 2.0, true)
		# turn-time strip along the bottom of the active wing
		if on and bar_on:
			var bh := h * 0.06
			var y := r.end.y - bh - h * 0.05
			var x0: float = (_av[0].x + _avr + h * 0.10) if i == 0 else (r.position.x + _sk + h * 0.02)
			var x1: float = (r.end.x - _sk - h * 0.02) if i == 0 else (_av[1].x - _avr - h * 0.10)
			var fullw := x1 - x0
			draw_rect(Rect2(x0, y, fullw, bh), Color(0, 0, 0, 0.45))
			var w := fullw * frac
			var fx := x0 if i == 0 else x1 - w
			var c0: Color = TEAM[i]
			var c1: Color = TEAM2[i]
			if frac < 0.33: c0 = Color("#ffd257").lerp(Color("#ff3b3b"), 1.0 - frac / 0.33); c1 = c0
			var pts := PackedVector2Array([Vector2(fx, y), Vector2(fx + w, y), Vector2(fx + w, y + bh), Vector2(fx, y + bh)])
			draw_polygon(pts, PackedColorArray([c0 if i == 0 else c1, c1 if i == 0 else c0, c1 if i == 0 else c0, c0 if i == 0 else c1]))
			draw_line(Vector2(fx, y + 0.5), Vector2(fx + w, y + 0.5), Color(1, 1, 1, 0.5), 1.0)
			var tip := Vector2(fx + w if i == 0 else fx, y + bh * 0.5)
			draw_circle(tip, bh * 1.2, Color(c0.r, c0.g, c0.b, 0.35))
		# disc avatar: recessed socket + team rim + disc + gloss
		var av: Vector2 = _av[i]
		draw_circle(av + Vector2(0, h * 0.02), _avr + h * 0.045, Color(0, 0, 0, 0.45))
		draw_circle(av, _avr + h * 0.04, _shade(tc, 1.0, 0.95) if on else Color(0.35, 0.42, 0.6, 0.9))
		draw_circle(av, _avr + h * 0.015, Color("#050816"))
		if tex[i]:
			draw_texture_rect(tex[i], Rect2(av - Vector2(_avr, _avr), Vector2(_avr, _avr) * 2), false, Color.WHITE if on else Color(0.75, 0.75, 0.8))
		draw_arc(av + Vector2(-_avr * 0.08, -_avr * 0.1), _avr * 0.82, deg_to_rad(200), deg_to_rad(265), 16, Color(1, 1, 1, 0.35), maxf(1.5, h * 0.018), true)
		if on: draw_arc(av, _avr + h * 0.04, 0, TAU, 40, Color(tc.r, tc.g, tc.b, 0.35 + 0.35 * pulse), h * 0.03, true)
		# turn chip pill behind the chip label
		if on:
			var c: Label = chip_l[i]
			var cr := Rect2(c.position, c.size)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(tc.r, tc.g, tc.b, 0.85)
			sb.set_corner_radius_all(int(cr.size.y * 0.5))
			sb.shadow_color = Color(tc.r, tc.g, tc.b, 0.35 + 0.25 * pulse)
			sb.shadow_size = int(h * 0.06)
			sb.border_color = Color(1, 1, 1, 0.45)
			sb.border_width_top = 1
			draw_style_box(sb, cr)
	# raised score plate: metallic bevel rim + deep glass face
	var pp := _plate_pts(_plate)
	_grad_poly(pp, STEEL, Color("#2a3360"))
	var pf := _plate_pts(_plate, h * 0.04)
	_grad_poly(pf, Color("#1a2558"), Color("#050816"))
	var sh2 := PackedVector2Array()
	var cy2 := _plate.position.y + _plate.size.y * 0.42
	for p in pf: sh2.append(Vector2(p.x, minf(p.y, cy2)))
	_grad_poly(sh2, Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.0))
	draw_line(pf[0], pf[1], Color(1, 1, 1, 0.5), 1.6, true)
	# accent under-glow in the active team's colour
	var ac: Color = TEAM[turn]
	draw_line(pf[3] + Vector2(h * 0.1, -1), pf[2] + Vector2(-h * 0.1, -1), Color(ac.r, ac.g, ac.b, 0.55 + 0.3 * pulse), h * 0.03, true)
	# score divider
	var mid := Vector2(_plate.position.x + _plate.size.x * 0.5, _plate.position.y + h * 0.28)
	draw_circle(mid + Vector2(0, -h * 0.05), h * 0.022, Color(1, 1, 1, 0.7))
	draw_circle(mid + Vector2(0, h * 0.05), h * 0.022, Color(1, 1, 1, 0.7))
	# clock pill
	var cr2 := Rect2(clock_l.position, clock_l.size)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.5) if not sudden else Color(0.35, 0.25, 0.0, 0.7)
	sb2.set_corner_radius_all(int(cr2.size.y * 0.5))
	sb2.border_color = Color(1, 0.82, 0.34, 0.8) if sudden else Color(1, 1, 1, 0.14)
	sb2.set_border_width_all(1)
	draw_style_box(sb2, cr2)

static func _offset(p: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var q := PackedVector2Array()
	q.resize(p.size())
	for i in p.size(): q[i] = p[i] + o
	return q

# ------------------------------------------------------------------ pause button
class _PauseBtn extends Control:
	signal pressed
	var _down := false
	var icon := "pause"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = ""
	func _gui_input(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT) or ev is InputEventScreenTouch:
			if ev.pressed:
				_down = true; queue_redraw()
			elif _down:
				_down = false; queue_redraw()
				if Rect2(Vector2.ZERO, size).has_point(ev.position): pressed.emit()
			accept_event()
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5 + (Vector2(0, r * 0.06) if _down else Vector2.ZERO)
		draw_circle(c + Vector2(0, r * 0.12), r, Color(0, 0, 0, 0.4))
		# bevel ring: light top-left -> dark bottom-right
		var n := 40
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in n:
			var a := TAU * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
			var k := 0.5 - 0.5 * sin(a + PI * 0.25)
			cols.append(Color("#9fb4ff").lerp(Color("#1a2250"), 1.0 - k))
		draw_polygon(pts, cols)
		draw_circle(c, r * 0.86, Color("#0b1233"))
		draw_arc(c, r * 0.86, PI * 1.05, PI * 1.75, 20, Color(1, 1, 1, 0.22), r * 0.08, true)
		if icon == "sliders":
			var col := Color(0.92, 0.96, 1.0) if not _down else NX.CYAN
			for i in 3:
				var y := c.y + (i - 1) * r * 0.36
				draw_line(Vector2(c.x - r * 0.46, y), Vector2(c.x + r * 0.46, y), col, maxf(2.0, r * 0.08), true)
				draw_circle(Vector2(c.x + [-0.2, 0.22, -0.02][i] * r, y), r * 0.11, col, true, -1.0, true)
			return
		var bw := r * 0.17
		var bh := r * 0.78
		for sx in [-1.0, 1.0]:
			var rr := Rect2(c.x + sx * r * 0.2 - bw * 0.5, c.y - bh * 0.5, bw, bh)
			draw_rect(rr, Color(0.92, 0.96, 1.0) if not _down else NX.CYAN)
