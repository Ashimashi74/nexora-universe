class_name Kit
extends RefCounted
## Static UI helpers shared by every screen (SPEC "Kit"). Sizes are viewport px (1080 base).
##
## Core API (fixed signatures, used by other workers):
##   label(text, size, color := NX.TEXT, bold := false) -> Label
##   button(text, cb, style := "primary") -> NxButton            (styles: primary|ghost|gold|danger|green|violet|dark)
##   icon_button(tex, cb) -> Control
##   panel(style := "glass") -> PanelContainer                   (glass|glass_glow|dark|flat|clear|gold|cyan|green|violet|pink)
##   chip(text, color) -> PanelContainer
##   progress(frac, color) -> NxBar (set_frac(f))
##   img(tex, size) -> TextureRect
##   avatar(url_or_key, size) -> Control
##   press_fx(ctrl) -> NxTap
##   tabs(names, cb) -> NxSegment (set_index(i))
##   scroll_list() -> [ScrollContainer, VBoxContainer]
##   spinner() -> Control

# ---------------------------------------------------------------- text
static func label(text, size: int = 36, color: Color = NX.TEXT, bold := false) -> Label:
	var l := Label.new()
	var s := I18n.f(text)  # Persian source text from const tables -> English when lang is en
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if NX.is_fa(s):
		# Persian: Vazirmatn, RTL paragraph, no letter spacing (breaks joining)
		l.add_theme_font_override("font", NX.font("faB" if bold else "fa"))
		l.add_theme_font_size_override("font_size", int(round(size * (1.2 if size < 30 else 1.03))) if bold else size)
		l.text_direction = Control.TEXT_DIRECTION_RTL
		l.horizontal_alignment = I18n.AR
	else:
		l.add_theme_font_override("font", NX.font("bold" if bold else "body"))
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Orbitron display text (falls back to Vazirmatn heavy for Persian)
static func title(text, size: int = 52, color: Color = NX.TEXT, kind := "title") -> Label:
	var s := I18n.f(text)
	if NX.is_fa(s):
		var l := label(s, int(round(size * 1.03)), color, true)
		return l
	var l2 := Label.new()
	l2.text = s
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l2.add_theme_font_override("font", NX.font(kind))
	l2.add_theme_font_size_override("font_size", size)
	l2.add_theme_color_override("font_color", color)
	return l2

## small spaced caps caption (RN "en" subtitles: Orbitron 700, letter spacing)
static func caps(text: String, size: int = 24, color: Color = NX.CYAN, spacing := 6) -> Label:
	var l := title(text, size, color, "head")
	var fv := FontVariation.new()
	fv.base_font = NX.font("head")
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	return l

## wrapping paragraph
static func para(text, size: int = 31, color: Color = NX.DIM, align := I18n.AR) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 60
	return l

static func glow_text(l: Label, c: Color, size := 14) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(c.r, c.g, c.b, 0.75))
	l.add_theme_constant_override("shadow_outline_size", size)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l

# ---------------------------------------------------------------- buttons
static func button(text: String, cb: Callable = Callable(), style := "primary") -> NxButton:
	return NxButton.new(text, cb, style, false)

static func button_small(text: String, cb: Callable = Callable(), style := "primary", icon: Texture2D = null, sub := "") -> NxButton:
	return NxButton.new(text, cb, style, true, icon, sub)

static func button_ex(text: String, cb: Callable, style: String, small: bool, icon: Texture2D, sub := "") -> NxButton:
	return NxButton.new(text, cb, style, small, icon, sub)

## round glowing art button (ICON_ART 40dp inside a 44dp target), optional badge dot / count
static func icon_button(tex, cb: Callable = Callable(), art := 104.0, badge = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(art + 10, art + 10)
	var i := img(tex, art)
	i.position = Vector2(5, 5)
	i.size = Vector2(art, art)
	c.add_child(i)
	if badge:
		c.add_child(badge_dot(badge))
	NxTap.attach(c, cb, 0.88)
	return c

## round glass close button (sheet / modal X): 96px touch target, drawn X so it is crisp at any scale
static func close_button(cb: Callable, d := 96.0) -> Control:
	var c := CloseX.new()
	c.custom_minimum_size = Vector2(d, d)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	NxTap.attach(c, cb, 0.88)
	return c

## round back button (screens): same size, look and corner (top-left) as the popup close button
static func back_button(cb: Callable, d := 96.0) -> Control:
	var c := CloseX.new()
	c.arrow = true
	c.custom_minimum_size = Vector2(d, d)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	NxTap.attach(c, cb, 0.88)
	return c

class CloseX extends Control:
	var arrow := false   # true: back chevron (screens), false: X (popups)
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2
		draw_circle(c, r, NX.SURF2, true, -1.0, true)
		draw_arc(c, r - 1, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
		var k := r * 0.32
		var w := maxf(3.0, r * 0.09)
		if arrow:
			# always points left: the button lives top-left in both languages
			draw_polyline(PackedVector2Array([c + Vector2(k * 0.45, -k), c + Vector2(-k * 0.55, 0), c + Vector2(k * 0.45, k)]), NX.TEXT, w, true)
		else:
			draw_line(c + Vector2(-k, -k), c + Vector2(k, k), NX.TEXT, w, true)
			draw_line(c + Vector2(k, -k), c + Vector2(-k, k), NX.TEXT, w, true)

static func badge_dot(v = true) -> Control:
	var hold := Control.new()
	hold.name = "Badge"
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hold.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hold.custom_minimum_size = Vector2(30, 30)
	hold.add_child(_badge_pill(v))
	return hold

static func _badge_pill(v) -> Control:
	var b := PanelContainer.new()
	b.name = "Badge"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("panel", NX.box(NX.hdr(NX.RED, 1.2), 20, 4, Color("#0b1236")))
	b.custom_minimum_size = Vector2(26, 26)
	b.position = Vector2(2, 2)
	b.size = Vector2(26, 26)
	if not (v is int and v > 0):  # plain dot: no padding, so it stays a 26px circle
		var dsb := NX.box(NX.RED, 13, 3, Color("#0b1236"))
		dsb.content_margin_left = 0; dsb.content_margin_right = 0; dsb.content_margin_top = 0; dsb.content_margin_bottom = 0
		b.add_theme_stylebox_override("panel", dsb)
	if v is int and v > 0:
		var l := label("9+" if v > 9 else str(v), 22, Color.WHITE, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
	return b

## make any control tappable with springy feedback; returns the NxTap helper
static func tap(ctrl: Control, cb: Callable, scale_to := 0.94) -> NxTap:
	return NxTap.attach(ctrl, cb, scale_to)

static func press_fx(ctrl: Control) -> NxTap:
	return NxTap.attach(ctrl, Callable(), 0.96)

# ---------------------------------------------------------------- panels
static func panel(style := "glass") -> PanelContainer:
	match style:
		"glass": return NxGlass.new()
		"glass_glow": return NxGlass.new(NX.CYAN, true)
		"gold": return NxGlass.new(NX.GOLD, true)
		"cyan": return NxGlass.new(NX.CYAN, false)
		"green": return NxGlass.new(NX.GREEN, true)
		"violet": return NxGlass.new(NX.VIOLET, true)
		"pink": return NxGlass.new(NX.ROSE, true)
		"plain", "clear":
			var pc := NxGlass.new()
			return pc
		"dark", "flat":
			var p := PanelContainer.new()
			var sb := NX.box(Color(0.04, 0.055, 0.157, 0.82), 40, 3, NX.LINE)
			sb.content_margin_left = 30; sb.content_margin_right = 30
			sb.content_margin_top = 24; sb.content_margin_bottom = 24
			p.add_theme_stylebox_override("panel", sb)
			p.mouse_filter = Control.MOUSE_FILTER_PASS
			return p
	return NxGlass.new()

static func glass(accent := Color.TRANSPARENT, glow := false, pad := -1.0) -> NxGlass:
	return NxGlass.new(accent, glow, pad)

static func chip(text: String, color: Color = NX.CYAN, on := true) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := NX.box(Color(color.r, color.g, color.b, 0.16) if on else Color(0.03, 0.047, 0.133, 0.7), 47, 3, NX.hdr(color, 1.2) if on else NX.LINE)
	if on:
		sb.shadow_color = Color(color.r, color.g, color.b, 0.35)
		sb.shadow_size = 10
	sb.content_margin_left = 36; sb.content_margin_right = 36
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, 31, Color.WHITE if on else NX.DIM, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.custom_minimum_size.y = 94
	return p

## small rounded tag (e.g. rarity, -30%)
static func tag(text: String, bg: Color, fg: Color = NX.DARK_TXT, size := 25) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := NX.box(bg, 30)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, size, fg, true) if NX.is_fa(text) else caps(text, size, fg, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p

# ---------------------------------------------------------------- progress / misc widgets
static func progress(frac: float, color: Color = NX.CYAN, color2: Color = NX.INDIGO, h := 21.0) -> NxBar:
	return NxBar.new(frac, color, color2, h)

static func tabs(names: Array, cb: Callable = Callable(), index := 0, accent: Color = NX.CYAN) -> NxSegment:
	return NxSegment.new(names, cb, index, accent)

static func toggle(on: bool, cb: Callable, accent: Color = NX.CYAN) -> NxToggle:
	return NxToggle.new(on, cb, accent)

static func scroll_list(sep := 24) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.scroll_deadzone = 12
	sc.follow_focus = false
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", sep)
	sc.add_child(v)
	OUI.fill_width(sc)
	return [sc, v]

## horizontal scroller: [ScrollContainer, HBoxContainer] (RTL: starts at the right)
static func hscroll(sep := 20, rtl := true) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	if rtl:
		h.layout_direction = I18n.LD
		sc.layout_direction = I18n.LD
	sc.add_child(h)
	return [sc, h]

static func spinner(size := 96.0, color: Color = NX.CYAN) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _Spinner.new()
	s.color = color
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(s)
	return c

class _Spinner extends Control:
	var color := NX.CYAN
	var a := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		a = fmod(a + dt * 5.5, TAU)
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.08), 8, true)
		draw_arc(c, r, a, a + 1.9, 24, NX.hdr(color, 1.5), 8, true)

## ring with the win-rate style sweep
static func ring(value: float, size := 240.0) -> NxRing:
	return NxRing.new(value, size)

# ---------------------------------------------------------------- images
static func img(tex, size = 96.0, fit := "contain") -> TextureRect:
	var t := TextureRect.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture = tex if tex is Texture2D else (UD.tex(str(tex)) if tex is String else null)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if fit == "cover" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sz: Vector2 = size if size is Vector2 else Vector2(float(size), float(size))
	t.custom_minimum_size = sz
	t.size = sz
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if fit == "cover":
		t.clip_contents = true
	return t

## TextureRect clipped to a circle
static func round_img(tex, size := 96.0) -> TextureRect:
	var t := img(tex, size, "cover")
	t.clip_contents = false
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/shaders/circle.gdshader")
	t.material = m
	return t

static var _url_cache := {}

## avatar: http(s) url (downloaded + cached), a team id ("club3") / team key ("club03"), or a texture
static func avatar(url_or_key, size := 104.0, ring_color: Color = NX.CYAN) -> Control:
	var holder := Panel.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(size, size)
	holder.size = Vector2(size, size)
	holder.add_theme_stylebox_override("panel", NX.box(Color("#050816"), int(size / 2), 5, NX.hdr(ring_color, 1.2)))
	var inner := size - 12
	var key := str(url_or_key) if url_or_key != null else ""
	var t: TextureRect
	if url_or_key is Texture2D:
		t = round_img(url_or_key, inner)
	elif key.begins_with("http"):
		t = round_img(_url_cache.get(key), inner)
		if not _url_cache.has(key):
			_fetch_avatar(holder, key, t)
	else:
		t = img(_team_tex_from_key(key), inner)
	t.position = Vector2(6, 6)
	holder.add_child(t)
	return holder

static func _team_tex_from_key(key: String) -> Texture2D:
	if key == "":
		return UD.team_tex(str(UD.pv("team", "club0")))
	var re := RegEx.create_from_string("^([a-z]+)(\\d+)$")
	var m := re.search(key)
	if m:
		var cat := UD.data_cat("TEAM_IMG")
		var k2 := "%s%02d" % [m.get_string(1), int(m.get_string(2))]
		if cat.has(k2):
			return UD.tex(str(cat[k2]))
	return UD.team_tex(key)

static func _fetch_avatar(holder: Control, url: String, t: TextureRect) -> void:
	var req := HTTPRequest.new()
	holder.add_child(req)
	req.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 300 or body.is_empty():
			return
		var im := Image.new()
		var err := im.load_png_from_buffer(body)
		if err != OK: err = im.load_jpg_from_buffer(body)
		if err != OK: err = im.load_webp_from_buffer(body)
		if err != OK:
			return
		var tx := ImageTexture.create_from_image(im)
		_url_cache[url] = tx
		if is_instance_valid(t):
			t.texture = tx)
	if req.request(url) != OK:
		req.queue_free()

# ---------------------------------------------------------------- layout helpers
static func hbox(sep := 20, rtl := false) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	if rtl:
		h.layout_direction = I18n.LD
	return h

static func vbox(sep := 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	return v

static func margin(c: Control, l: float, t: float = -1, r: float = -1, b: float = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_theme_constant_override("margin_left", int(l))
	m.add_theme_constant_override("margin_top", int(t if t >= 0 else l))
	m.add_theme_constant_override("margin_right", int(r if r >= 0 else l))
	m.add_theme_constant_override("margin_bottom", int(b if b >= 0 else (t if t >= 0 else l)))
	if c:
		m.add_child(c)
	return m

static func gap(h := 24.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	cc.add_child(c)
	return cc

## absolute-layout box of a fixed size (for hero art composed by hand)
static func stage(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c

## place `child` centered at (x, y) inside an absolute stage
static func put(parent: Control, child: Control, x: float, y: float) -> Control:
	parent.add_child(child)
	var s := child.custom_minimum_size
	child.position = Vector2(x - s.x * 0.5, y - s.y * 0.5)
	child.size = s
	child.pivot_offset = s * 0.5
	return child

## section header (RN Section/Title): right aligned title + optional en caption + action link
static func section(title_fa: String, en := "", accent: Color = NX.CYAN, action := "", on_action: Callable = Callable()) -> Control:
	var row := hbox(16)
	row.custom_minimum_size.y = 80
	if action != "":
		var a := label(action, 31, NX.CYAN, true)
		a.mouse_filter = Control.MOUSE_FILTER_PASS
		a.custom_minimum_size = Vector2(0, 100)
		a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tap(a, on_action)
		row.add_child(a)
	var line := ColorRect.new()
	line.color = Color(0.47, 0.7, 1.0, 0.18)
	line.custom_minimum_size = Vector2(0, 3)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var col := vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := label(title_fa, 42, NX.TEXT, true)
	col.add_child(t)
	if en != "":
		var e := caps(en, 21, NX.hdr(accent, 1.25), 7)
		e.horizontal_alignment = I18n.AR
		col.add_child(e)
	row.add_child(col)
	var bar := ColorRect.new()
	bar.color = NX.hdr(accent, 1.5)
	bar.custom_minimum_size = Vector2(8, 46)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	return margin(row, NX.PAD, 46, NX.PAD, 6)

## list row (RN ListRow) — icon on the right, title/sub, right-hand widget on the left
static func list_row(icon, title_fa: String, sub := "", right: Control = null, cb: Callable = Callable()) -> Control:
	var p := glass(Color.TRANSPARENT, false)
	p.set_pad(30, 22)
	var h := hbox(26, true)
	p.add_child(h)
	if icon != null:
		h.add_child(img(icon, 110))
	var col := vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(label(title_fa, 39, NX.TEXT, true))
	if sub != "":
		col.add_child(label(sub, 29, NX.DIM))
	h.add_child(col)
	if right:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(right)
	if cb.is_valid():
		tap(p, cb, 0.98)
	return p

# ---------------------------------------------------------------- animation helpers (Tween based)
## slow breathing glow disc used behind hero art (RN Pulse)
static var _glow_tex: GradientTexture2D

static func glow_tex() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 256
		_glow_tex.height = 256
	return _glow_tex

static func pulse(size: float, color: Color, dur := 2.2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = glow_tex()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = Vector2(size, size) * 1.6
	t.size = t.custom_minimum_size
	t.pivot_offset = t.size * 0.5
	t.modulate = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, color.a)
	t.ready.connect(func():
		var tw := t.create_tween().set_loops()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(t, "scale", Vector2(1.02, 1.02), dur).from(Vector2(0.9, 0.9))
		tw.parallel().tween_property(t, "self_modulate:a", 1.0, dur).from(0.5)
		tw.tween_property(t, "scale", Vector2(0.9, 0.9), dur)
		tw.parallel().tween_property(t, "self_modulate:a", 0.5, dur))
	return t

## bob a control up/down forever (it must not be inside a Container that re-sorts it)
static func bob(c: Control, amp := 16.0, dur := 2.6, delay := 0.0) -> void:
	var run := func():
		var y0 := c.position.y
		var tw := c.create_tween().set_loops()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if delay > 0:
			tw.tween_interval(delay)
		tw.tween_property(c, "position:y", y0 - amp, dur)
		tw.tween_property(c, "position:y", y0 + amp * 0.2, dur)
	if c.is_inside_tree():
		run.call()
	else:
		c.ready.connect(run, CONNECT_ONE_SHOT)

static func spin(c: Control, period := 12.0, dir := 1.0) -> void:
	var run := func():
		c.pivot_offset = c.size * 0.5
		var tw := c.create_tween().set_loops()
		tw.tween_property(c, "rotation", c.rotation + TAU * dir, period).as_relative().from(0.0)
	if c.is_inside_tree():
		run.call()
	else:
		c.ready.connect(run, CONNECT_ONE_SHOT)

## staggered entrance: fade + slide up (RN Enter / FadeInDown springify)
static func enter(c: Control, i := 0, dist := 40.0) -> Control:
	c.modulate.a = 0.0
	var run := func():
		var tw := c.create_tween()
		tw.tween_interval(min(i, 10) * 0.045)
		tw.tween_property(c, "modulate:a", 1.0, 0.32)
	var wrap := func():
		# translate via a child-level offset is not possible inside containers; animate the
		# position after the container sorted it
		run.call()
		await c.get_tree().process_frame
		if not is_instance_valid(c):
			return
		var y := c.position.y
		c.position.y = y + dist
		var tw2 := c.create_tween()
		tw2.tween_interval(min(i, 10) * 0.045)
		tw2.tween_property(c, "position:y", y, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c.is_inside_tree():
		wrap.call()
	else:
		c.ready.connect(wrap, CONNECT_ONE_SHOT)
	return c

## horizontal shake loop (chests)
static func wiggle(c: Control, deg := 6.0, pause := 1.8) -> Tween:
	var tw := c.create_tween().set_loops()
	var r := deg_to_rad(deg)
	tw.tween_property(c, "rotation", r, 0.08)
	tw.tween_property(c, "rotation", -r, 0.08)
	tw.tween_property(c, "rotation", r, 0.08)
	tw.tween_property(c, "rotation", 0.0, 0.08)
	tw.tween_interval(pause)
	return tw

## price tag pill (coin/gem)
static func price_tag(v: int, gem := false) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := NX.box(Color(1, 0.82, 0.34, 0.14), 30, 2, Color(1, 0.82, 0.34, 0.3))
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(8)
	h.add_child(img(UD.ui2("x_gem") if gem else UD.ui2("c_coin"), 42))
	var l := title(NX.en_num(v), 26, Color("#9fd8ff") if gem else NX.GOLD, "head")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	p.add_child(h)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p

## two-row stat bars (power / accuracy, 10 pips) — RN StatBars
static func stat_bars(power: int, accuracy: int, compact := false) -> Control:
	var v := vbox(6 if compact else 12)
	for row in [[I18n.t("oui.power"), power, NX.ORANGE], [I18n.t("oui.accuracy"), accuracy, NX.CYAN]]:
		var h := hbox(4, true)
		var l := label(row[0], 23 if compact else 27, NX.DIM)
		l.custom_minimum_size.x = 68 if compact else 90
		h.add_child(l)
		var pips := HBoxContainer.new()
		pips.layout_direction = I18n.LD
		pips.add_theme_constant_override("separation", 4)
		pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in 10:
			var r := Panel.new()
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.custom_minimum_size = Vector2(0, 10 if compact else 16)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_theme_stylebox_override("panel", NX.box(NX.hdr(row[2], 1.2) if i < int(row[1]) else Color(1, 1, 1, 0.1), 5))
			pips.add_child(r)
		h.add_child(pips)
		if not compact:
			var n := label(NX.fa_num(row[1]), 27, row[2], true)
			n.custom_minimum_size.x = 40
			h.add_child(n)
		v.add_child(h)
	return v

## Persian speech bubble (mascot / oracle): wide, auto height, word-wrapped. The label gets its
## natural one-line width capped at `max_w` so it never collapses into a one-letter column.
static func speech(text: String, max_w := 756.0, size := 36, accent: Color = NX.CYAN) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := NX.box(Color(0.04, 0.07, 0.2, 0.97), 40, 3, NX.hdr(accent, 1.2), 18, Color(accent.r, accent.g, accent.b, 0.35))
	sb.content_margin_left = 38; sb.content_margin_right = 38
	sb.content_margin_top = 24; sb.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, size, NX.TEXT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = I18n.AR
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = clampf(UD.text_w(l) + 6.0, 120.0, max_w - 76.0)
	p.add_child(l)
	p.set_meta("label", l)
	return p
