extends Control
## "Flight to Nexora" (RN Intro.tsx): hyperspace warp (240 streaks, closed-form travel curve),
## ringed planet growing out of the warp, NX logo slams in with a flash, tagline, pulse
## "tap to enter", skip button. Drawn with _draw() into preallocated arrays (no per-frame allocs).

const N := 240
var stars := PackedFloat32Array()
var far_pts := PackedVector2Array()
var near_pts := PackedVector2Array()
var t := 0.0
var cx := 0.0
var cy := 0.0
var f := 0.0
var glow_rect: ColorRect
var planet: TextureRect
var space: TextureRect
var mascot: TextureRect
var logo: TextureRect
var tagline: Label
var flash: ColorRect
var tap_btn: Control
var skip: Control
var ready_tap := false
var done := false
var _logo_shown := false
var _canvas: Control

func setup(_params: Dictionary) -> void:
	pass

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	stars.resize(N * 3)
	for i in N:
		stars[i * 3] = (randf() - 0.5) * 2.0
		stars[i * 3 + 1] = (randf() - 0.5) * 2.0
		stars[i * 3 + 2] = randf()
	far_pts.resize(N * 2)
	near_pts.resize(N * 2)
	var bg := ColorRect.new()
	bg.color = NX.VEIL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# v2: the NEXORA space backdrop fades in under the warp
	space = TextureRect.new()
	space.texture = UD.art("bg/home")
	space.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	space.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	space.set_anchors_preset(Control.PRESET_FULL_RECT)
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.modulate.a = 0.0
	add_child(space)
	glow_rect = ColorRect.new()
	glow_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://src/ui/shaders/warp.gdshader")
	glow_rect.material = gm
	add_child(glow_rect)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_warp)
	add_child(_canvas)
	planet = TextureRect.new()
	planet.texture = UD.art("planet")
	planet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	planet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet.modulate.a = 0.0
	add_child(planet)
	logo = TextureRect.new()
	logo.texture = UD.art("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.modulate.a = 0.0
	add_child(logo)
	mascot = TextureRect.new()
	mascot.texture = UD.art("mascot")
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mascot.modulate.a = 0.0
	add_child(mascot)
	tagline = Kit.caps("NEXORA · FINGER SOCCER", 31, NX.hdr(Color("#ff9ab8"), 1.4), 14)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.modulate.a = 0.0
	add_child(tagline)
	flash = ColorRect.new()
	flash.color = Color("#dff6ff")
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	add_child(flash)
	# tap to enter
	tap_btn = PanelContainer.new()
	var sb := NX.box(Color(0.09, 0.05, 0.2, 0.85), 78, 3, NX.hdr(Color("#ff6f9a"), 1.3), 40, Color(1.0, 0.3, 0.55, 0.5))
	sb.content_margin_left = 68; sb.content_margin_right = 68; sb.content_margin_top = 30; sb.content_margin_bottom = 30
	tap_btn.add_theme_stylebox_override("panel", sb)
	tap_btn.add_child(Kit.label(I18n.t("intro.tap_to_enter"), 39, NX.TEXT, true))
	tap_btn.visible = false
	add_child(tap_btn)
	# skip
	skip = PanelContainer.new()
	var ssb := NX.box(Color(0.07, 0.055, 0.2, 0.9), 57, 3, Color(0.56, 0.5, 1.0, 0.45))
	ssb.content_margin_left = 42; ssb.content_margin_right = 42; ssb.content_margin_top = 22; ssb.content_margin_bottom = 22
	skip.add_theme_stylebox_override("panel", ssb)
	skip.add_child(Kit.label(I18n.t("intro.skip"), 34))
	add_child(skip)
	Kit.tap(skip, enter, 0.92)
	resized.connect(_layout)
	_layout()
	var tm := get_tree().create_timer(3.6)
	tm.timeout.connect(_show_logo)
	get_tree().create_timer(4.6).timeout.connect(_show_tap)

func _layout() -> void:
	var W := size.x
	var H := size.y
	cx = W * 0.5
	cy = H * 0.38
	f = maxf(W, H) * 0.3
	(glow_rect.material as ShaderMaterial).set_shader_parameter("aspect", Vector2(1.0, H / maxf(1.0, W)))
	var ls := minf(W * 0.86, 940)
	logo.size = Vector2(ls, ls)
	logo.pivot_offset = logo.size * 0.5
	logo.position = Vector2(cx - ls * 0.5, cy - ls * 0.5)
	tagline.position = Vector2(0, cy + ls * 0.33)
	var ms := minf(W * 0.36, 400)
	mascot.size = Vector2(ms, ms * 1.25)
	mascot.position = Vector2(cx - ms * 0.5, H * 0.56)
	tagline.size = Vector2(W, 60)
	skip.position = Vector2(42 + NX.safe_left, NX.safe_top + 120)
	tap_btn.reset_size()
	tap_btn.position = Vector2((W - tap_btn.size.x) * 0.5, H * 0.87 - tap_btn.size.y)
	tap_btn.pivot_offset = tap_btn.size * 0.5

## distance travelled by the stars after t seconds (closed-form integral of the speed curve)
static func travel(x: float) -> float:
	if x < 0.5:
		return 0.12 * x + 2.38 * x * x * x / 0.75
	var s05 := 0.12 * 0.5 + 2.38 * 0.125 / 0.75
	if x < 2.2:
		return s05 + 2.5 * (x - 0.5)
	var s22 := s05 + 2.5 * 1.7
	var u := minf(1.0, (x - 2.2) / 1.4)
	return s22 + 0.09 * (x - 2.2) + 2.41 * 1.4 * (1.0 - pow(1.0 - u, 4)) / 4.0

static func speed(x: float) -> float:
	if x < 0.5:
		return 0.12 + 2.38 * (x / 0.5) * (x / 0.5)
	if x < 2.2:
		return 2.5
	var u := minf(1.0, (x - 2.2) / 1.4)
	return 0.09 + 2.41 * pow(1.0 - u, 3)

func _process(dt: float) -> void:
	t += dt
	var S := travel(t)
	var v := speed(t)
	var nf := 0
	var nn := 0
	for i in N:
		var z := stars[i * 3 + 2] - S * 0.55
		z = z - floorf(z)
		z = 0.02 + z * 0.98
		var pz := z + v * 0.07
		var sx := stars[i * 3]
		var sy := stars[i * 3 + 1]
		var a := Vector2(cx + sx / pz * f, cy + sy / pz * f)
		var b := Vector2(cx + sx / z * f + 0.6, cy + sy / z * f)
		if z < 0.45:
			near_pts[nn] = a; near_pts[nn + 1] = b; nn += 2
		else:
			far_pts[nf] = a; far_pts[nf + 1] = b; nf += 2
	# park unused segment slots off-screen (keeps arrays fixed-size: no allocations)
	for k in range(nf, N * 2):
		far_pts[k] = Vector2(-50, -50)
	for k in range(nn, N * 2):
		near_pts[k] = Vector2(-50, -50)
	(glow_rect.material as ShaderMaterial).set_shader_parameter("strength", 0.14 + minf(0.3, v * 0.1))
	# planet grows out of the warp
	var pp := clampf((t - 1.8) / 2.4, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - pp, 3)
	var sz := minf(size.x, size.y) * 0.8 * e
	space.modulate.a = clampf((t - 1.4) / 1.6, 0.0, 0.9)
	planet.size = Vector2(sz, sz)
	planet.pivot_offset = planet.size * 0.5
	planet.position = Vector2(cx - sz * 0.5, cy - sz * 0.5)
	planet.rotation = (t - 4.0) * 0.02
	planet.modulate.a = clampf((t - 1.8) * 0.6, 0.0, 1.0) * (0.35 if _logo_shown else 0.8)
	_canvas.queue_redraw()

func _draw_warp() -> void:
	_canvas.draw_multiline(far_pts, Color(0.59 * 1.2, 0.78 * 1.2, 1.2, 0.55), 2.8, true)
	_canvas.draw_multiline(near_pts, Color(0.78 * 1.6, 0.7 * 1.6, 1.6, 0.95), 6.0, true)

func _show_logo() -> void:
	if done or _logo_shown:
		return
	_logo_shown = true
	UD.sfx("whistle")
	UD.haptic("medium")
	logo.scale = Vector2(0.4, 0.4)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(logo, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(logo, "modulate:a", 1.0, 0.25)
	tw.tween_property(flash, "modulate:a", 0.6, 0.06)
	tw.chain().tween_property(flash, "modulate:a", 0.0, 0.35)
	var mt := create_tween()
	mt.tween_interval(0.35)
	mt.tween_property(mascot, "modulate:a", 1.0, 0.4)
	Kit.bob(mascot, 16, 2.4, 0.6)
	var tg := create_tween()
	tg.tween_interval(0.5)
	tg.tween_property(tagline, "modulate:a", 0.9, 0.8)

func _show_tap() -> void:
	if done:
		return
	ready_tap = true
	tap_btn.visible = true
	_layout()
	tap_btn.modulate.a = 0.55
	var tw := tap_btn.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(tap_btn, "modulate:a", 1.0, 0.9)
	tw.parallel().tween_property(tap_btn, "scale", Vector2(1.04, 1.04), 0.9)
	tw.tween_property(tap_btn, "modulate:a", 0.55, 0.9)
	tw.parallel().tween_property(tap_btn, "scale", Vector2.ONE, 0.9)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and ready_tap:
		enter()

func on_back() -> bool:
	enter()
	return true

func enter() -> void:
	if done:
		return
	done = true
	UD.haptic("medium")
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): Nav.go("home"))
