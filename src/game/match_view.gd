class_name MatchView
extends Node2D
## Renders an NxEngine — port + upgrade of src/game/render.ts (Skia).
## Layers (back -> front): blurred stadium bg · field (feathered) + neon outline · shadows · additive glows/disc trails ·
## discs (team skin, round AA mask, gloss) · ball trail (additive strip) · ball (lit 3D sphere shader, R matrix) ·
## goals (the user's goal art from assets/g/goals/<gs>.webp only — no code-drawn posts/nets) · goal ripple light ·
## aim arrow (3-slice art from assets/g/arrow) + power ring + accuracy dots · particles · CPUParticles2D sparks/confetti · flash.
## Interpolates prev -> current with engine.alpha(). Quality "high" | "low" (Store.p.quality) toggles every costly extra.
##
## Usage:  var v := MatchView.new(); v.setup(engine, {"ball": 3, "teams": ["club0", "nat2"], "quality": "high"}); add_child(v)
##         v.fit(size, top_px, bottom_px)            # whenever the screen size changes
##         var w := v.to_world(local_pos)            # touch -> world (local to MatchView's parent)
##         v.on_event(ev)                            # forward engine events for sparks / confetti (optional)
## Online clients: write positions into engine.bodies (x,y and px,py) or call set_bodies_override(Array[Vector2]|null).

const BALL_SHADER := preload("res://src/game/shaders/ball.gdshader")
const DISC_SHADER := preload("res://src/game/shaders/disc.gdshader")
const FIELD_SHADER := preload("res://src/game/shaders/field.gdshader")
const D := preload("res://src/core/data.gd")

const TEAM_GLOW := [Color("#3bb6ff"), Color("#ff5b6b")]
const AIM_C := [Color("#3b8bff"), Color("#9b5cff"), Color("#ff3b5c")]
const ART := {
	"e": {"hh": 96.0, "join": 0.82, "sw": 124.0, "top": 0.0, "tail": 0.734, "topLen": 0.0, "tailLen": 46.0},
	"s": {"hh": 68.0, "join": 0.928, "sw": 32.5, "top": 0.0, "tail": 0.704, "topLen": 0.0, "tailLen": 38.0},
}

class Layer extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)

static var _mip_cache := {}
static var _gen := {}

var e: NxEngine
var ball_idx := 0
var team_ids := ["club0", "club1"]
var quality := "high"
var hq := true
var W := 1080.0
var H := 1920.0
var s := 1.0
var ox := 0.0
var oy := 0.0
var t := 0.0
var override = null
## online: render the pitch rotated 180° about the screen centre (the client's own goal at the bottom).
## Layout margins are given in unflipped terms (online_match swaps them); to_world() undoes the flip.
var flipped := false
var online := false

var pos := PackedVector2Array()   # interpolated draw positions (index = engine.bodies index)
var _aim_on := false
var _aim_ux := 0.0
var _aim_uy := -1.0
var _aim_p := 0.0
const AIM_MAX_K := 4.0   # drawn aim-arrow length beyond the disc rim at full power, in disc radii (was 2.2)
const AIM_MIN_K := 0.35  # ... at the lowest power (short stub), grows linearly in between (user: short -> long)

# nodes
var bg: Layer
var world: Node2D
var field_l: Layer
var shadow_l: Layer
var glow_l: Layer
var ring_l: Layer
var disc_l: Layer
var trail_l: Layer
var ball_l: Layer
var goal_l: Layer
var light_l: Layer
var aim_l: Layer
var part_l: Layer
var flash_l: Layer
var sparks: Array = []
var _spark_i := 0
var confetti: CPUParticles2D

# textures
var tex_field: Texture2D
var tex_bg: Texture2D
var tex_goal: Texture2D
var tex_ball: Texture2D
var tex_team: Array = [null, null]
var tex_shadow: Texture2D
var tex_dot: Texture2D
var tex_gloss: Texture2D
var tex_arrow := {}
var ball_mat: ShaderMaterial
var _outline := PackedVector2Array()
var _corner_arcs: Array = []
## the local player's team (blue turn ring); online clients on team 1 render flipped
var my_team := -1
const RING_ME := Color("#3ba8ff")
const RING_OPP := Color("#ff4a5a")
# aim arrow gradient (user design: warm yellow-orange tail -> red head)
const ARW_TAIL := Color("#f4bc5c")
const ARW_MID := Color("#ec9450")
const ARW_TIP := Color("#d4524e")
var _trail_cols: Array = []
# reusable strip buffers
var _sp := PackedVector2Array()
var _sc := PackedColorArray()
var _si := PackedInt32Array()
var _prev_msaa := -1

func setup(engine: NxEngine, opts := {}) -> void:
	e = engine
	ball_idx = int(opts.get("ball", e.cfg.get("ball", 0)))
	var tids = opts.get("teams", e.cfg.get("teams", null))
	if tids is Array and tids.size() >= 2: team_ids = [String(tids[0]), String(tids[1])]
	var q = opts.get("quality", null)
	if q == null:
		var st = Engine.get_main_loop().root.get_node_or_null("/root/Store") if Engine.get_main_loop() else null
		q = String(st.p.get("quality", "high")) if st and st.get("p") is Dictionary else "high"
	if opts.has("fx") and not bool(opts.fx): q = "low"
	quality = String(q); hq = quality != "low"
	flipped = bool(opts.get("flipped", false))
	online = bool(opts.get("online", false))
	var tc: Array = D.TRAILS[ball_idx % D.TRAILS.size()].c
	_trail_cols = [Color(tc[0]), Color(tc[1] if tc.size() > 1 else tc[0]), Color(tc[2] if tc.size() > 2 else "#ffffff")]
	_load_textures()
	_build()
	if opts.has("size"):
		fit(opts.size, float(opts.get("top_margin", 0.0)), float(opts.get("bottom_margin", 0.0)))

## swap the ball skin and/or one side's disc skin mid-match (visual only: physics, stats and the pitch are untouched).
## ball < 0 keeps the ball; team_id == "" keeps that side.
func set_skin(ball: int = -1, side: int = 0, team_id: String = "") -> void:
	if ball >= 0 and ball != ball_idx:
		ball_idx = ball
		tex_ball = mip(D.ball_tex(ball_idx))
		var tc: Array = D.TRAILS[ball_idx % D.TRAILS.size()].c
		_trail_cols = [Color(tc[0]), Color(tc[1] if tc.size() > 1 else tc[0]), Color(tc[2] if tc.size() > 2 else "#ffffff")]
	if team_id != "" and side >= 0 and side < 2 and team_id != team_ids[side]:
		team_ids[side] = team_id
		tex_team[side] = mip(D.team_tex(team_id))

func set_engine(engine: NxEngine) -> void:
	e = engine

func set_bodies_override(arr) -> void:
	override = arr

func set_quality(q: String) -> void:
	quality = q; hq = q != "low"
	_apply_quality()

# ------------------------------------------------------------------ textures
static func mip(tex: Texture2D) -> Texture2D:
	## mipmapped copy (imports are plain 2D textures): crisp when minified on small phones
	if tex == null: return null
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _mip_cache.has(key): return _mip_cache[key]
	var out: Texture2D = tex
	var img := tex.get_image()
	if img and not img.is_compressed():
		img = img.duplicate()
		if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		out = ImageTexture.create_from_image(img)
	_mip_cache[key] = out
	return out

static func _radial(stops: PackedFloat32Array, cols: PackedColorArray, size := 128) -> Texture2D:
	var g := Gradient.new()
	g.offsets = stops; g.colors = cols
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	gt.width = size; gt.height = size
	return gt

static func _gloss_tex() -> Texture2D:
	# subtle specular sheen + thin top-left rim arc (render.ts sprites().gloss), baked once
	if _gen.has("gloss"): return _gen.gloss
	var N := 160
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var R := N / 2.0
	var r := R - 2.0
	var cx := R - r * 0.38
	var cy := R - r * 0.48
	var a0 := deg_to_rad(205.0 - 360.0)
	var a1 := deg_to_rad(265.0 - 360.0)
	for y in N:
		for x in N:
			var px := x + 0.5
			var py := y + 0.5
			var dd := Vector2(px - R, py - R).length()
			if dd > r * 0.97 + 1.0: continue
			var edge := clampf(r * 0.97 + 0.5 - dd, 0.0, 1.0)
			var g := Vector2(px - cx, py - cy).length() / (r * 0.9)
			var a := 0.0
			if g < 0.45: a = lerpf(0.26, 0.05, g / 0.45)
			elif g < 1.0: a = lerpf(0.05, 0.0, (g - 0.45) / 0.55)
			a *= edge
			# rim arc at radius .93r, 1.5px half-width, alpha .38
			var ang := atan2(py - R, px - R)
			var ad := absf(dd - r * 0.93)
			if ad < 2.2 and ang >= a0 - 0.05 and ang <= a1 + 0.05:
				var k := clampf(2.2 - ad, 0.0, 1.0)
				var cap := clampf(minf(ang - a0, a1 - ang) * r / 2.0 + 0.5, 0.0, 1.0)
				a = a + (1.0 - a) * 0.38 * k * cap
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_gen.gloss = t
	return t

func _load_textures() -> void:
	var fi := int(e.cfg.get("field", 0))
	var ft := D.field_tex(fi)
	tex_field = mip(ft) if hq else ft
	tex_bg = _blur_tex(ft)
	tex_goal = mip(D.goal_tex(String(e.f.gs)))
	tex_ball = mip(D.ball_tex(ball_idx))
	for i in 2: tex_team[i] = mip(D.team_tex(team_ids[i]))
	for k in ["head_e", "head_s", "shaft_e", "shaft_s"]: tex_arrow[k] = mip(D.arrow_tex(k))
	if not _gen.has("shadow"):
		_gen.shadow = _radial(PackedFloat32Array([0.0, 0.55, 1.0]), PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0)]))
		_gen.dot = _radial(PackedFloat32Array([0.0, 0.35, 1.0]), PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)]), 64)
	tex_shadow = _gen.shadow
	tex_dot = _gen.dot
	tex_gloss = _gloss_tex()

static func _blur_tex(ft: Texture2D) -> Texture2D:
	if ft == null: return null
	var key := "blur:" + ft.resource_path
	if _gen.has(key): return _gen[key]
	var img := ft.get_image()
	if img == null or img.is_compressed(): return ft
	img = img.duplicate()
	var w := maxi(8, img.get_width() / 24)
	var h := maxi(8, img.get_height() / 24)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	img.resize(w * 4, h * 4, Image.INTERPOLATE_CUBIC)
	var t := ImageTexture.create_from_image(img)
	_gen[key] = t
	return t

# ------------------------------------------------------------------ scene
func _layer(parent: Node, fn: Callable, add := false, mat: Material = null) -> Layer:
	var l := Layer.new()
	l.fn = fn
	if mat: l.material = mat
	elif add:
		var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		l.material = m
	parent.add_child(l)
	return l

func _build() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg = _layer(self, _draw_bg)
	world = Node2D.new()
	add_child(world)
	var fm := ShaderMaterial.new(); fm.shader = FIELD_SHADER
	field_l = _layer(world, _draw_field, false, fm)
	_layer(world, _draw_outline)
	shadow_l = _layer(world, _draw_shadows)
	glow_l = _layer(world, _draw_glows, true)
	ring_l = _layer(world, _draw_turn_ring)
	var dm := ShaderMaterial.new(); dm.shader = DISC_SHADER
	disc_l = _layer(world, _draw_discs, false, dm)
	trail_l = _layer(world, _draw_trail, true)
	ball_mat = ShaderMaterial.new(); ball_mat.shader = BALL_SHADER
	ball_l = _layer(world, _draw_ball, false, ball_mat)
	goal_l = _layer(world, _draw_goals)
	light_l = _layer(world, _draw_lights, true)
	aim_l = _layer(world, _draw_aim)
	part_l = _layer(world, _draw_parts, true)
	# CPU particles: impact sparks (pooled) + goal confetti
	for i in 3:
		var sp := CPUParticles2D.new()
		sp.emitting = false; sp.one_shot = true; sp.explosiveness = 1.0; sp.amount = 22; sp.lifetime = 0.45
		sp.texture = tex_dot; sp.local_coords = false
		sp.direction = Vector2(1, 0); sp.spread = 180.0
		sp.initial_velocity_min = 260.0; sp.initial_velocity_max = 700.0; sp.damping_min = 900.0; sp.damping_max = 1400.0
		sp.scale_amount_min = 0.12; sp.scale_amount_max = 0.3
		var cr := Gradient.new(); cr.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		cr.colors = PackedColorArray([Color(2.2, 2.2, 2.2, 1), Color(0.6, 1.4, 2.0, 0.8), Color(0.3, 0.6, 1.0, 0)])
		sp.color_ramp = cr
		var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; sp.material = m
		world.add_child(sp); sparks.append(sp)
	confetti = CPUParticles2D.new()
	confetti.emitting = false; confetti.one_shot = true; confetti.explosiveness = 0.92; confetti.amount = 110; confetti.lifetime = 2.0
	confetti.local_coords = false; confetti.direction = Vector2(0, -1); confetti.spread = 180.0
	confetti.initial_velocity_min = 240.0; confetti.initial_velocity_max = 820.0; confetti.gravity = Vector2(0, 700)
	confetti.damping_min = 120.0; confetti.damping_max = 260.0
	confetti.angular_velocity_min = -720.0; confetti.angular_velocity_max = 720.0; confetti.angle_min = 0.0; confetti.angle_max = 360.0
	var img := Image.create(6, 12, false, Image.FORMAT_RGBA8); img.fill(Color.WHITE)
	confetti.texture = ImageTexture.create_from_image(img)
	confetti.scale_amount_min = 0.8; confetti.scale_amount_max = 1.6
	var ci := Gradient.new(); ci.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ci.colors = PackedColorArray(NxEngine.GOAL_COLS)
	ci.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	confetti.color_initial_ramp = ci
	var fade := Gradient.new(); fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0]); fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	confetti.color_ramp = fade
	world.add_child(confetti)
	flash_l = _layer(self, _draw_flash)
	pos.resize(e.bodies.size())
	_build_outline()
	_apply_quality()
	set_flipped(flipped)

func _apply_quality() -> void:
	if glow_l == null: return
	glow_l.visible = hq
	for sp in sparks: sp.visible = hq
	confetti.visible = hq
	ball_mat.set_shader_parameter("hdr", 1.35 if hq else 1.0)
	if is_inside_tree(): _set_msaa()

func _set_msaa() -> void:
	# Compatibility (GLES3) has no 2D MSAA: discs/rings/lines rely on texture filtering + antialiased draws instead
	if RenderingServer.get_current_rendering_method() == "gl_compatibility": return
	var vp := get_viewport()
	if vp == null: return
	if _prev_msaa < 0: _prev_msaa = vp.msaa_2d
	vp.msaa_2d = Viewport.MSAA_4X if hq else Viewport.MSAA_DISABLED

func _enter_tree() -> void:
	if world: _set_msaa()

func _exit_tree() -> void:
	var vp := get_viewport()
	if vp and _prev_msaa >= 0: vp.msaa_2d = _prev_msaa

func _build_outline() -> void:
	# sharp 90° pitch boundary (matches the engine's corner walls) + quarter-circle corner-kick arcs as real markings
	var l := e.Fl
	var r := e.Fr
	var tp := e.Ft
	var b := e.Fb
	_outline = PackedVector2Array([Vector2(l, tp), Vector2(r, tp), Vector2(r, b), Vector2(l, b), Vector2(l, tp)])
	_corner_arcs = []
	var rad := 34.0
	var cs := [[l, tp, 0.0], [r, tp, 90.0], [r, b, 180.0], [l, b, 270.0]]
	for c in cs:
		var arc := PackedVector2Array()
		for i in 13:
			var a := deg_to_rad(c[2] + i * 90.0 / 12.0)
			arc.append(Vector2(c[0] + cos(a) * rad, c[1] + sin(a) * rad))
		_corner_arcs.append(arc)

# ------------------------------------------------------------------ layout
## RN computeView: fits field + both goals between `top` and `bottom` insets (pixels of this node's parent space)
func fit(size: Vector2, top: float, bottom: float) -> void:
	W = size.x; H = size.y
	var f := e.f
	var play_h := maxf(300.0, H - top - bottom)
	s = minf(W / (f.R - f.L + 56 * D.FS), play_h / ((f.B - f.T) + 2 * e.GG.h + 48)) * 0.99
	ox = W / 2 - e.CX * s
	oy = top + play_h / 2 - e.CY * s
	_place(Vector2.ZERO, 0.0)
	if bg: bg.queue_redraw()
	if flash_l: flash_l.queue_redraw()

func to_world(p: Vector2) -> Vector2:
	if flipped: p = Vector2(W, H) - p
	return Vector2((p.x - ox) / s, (p.y - oy) / s)

func to_screen(w: Vector2) -> Vector2:
	var p := Vector2(ox + w.x * s, oy + w.y * s)
	return Vector2(W, H) - p if flipped else p

func set_flipped(f: bool) -> void:
	flipped = f
	if ball_mat: ball_mat.set_shader_parameter("lflip", -1.0 if f else 1.0)

func _place(shk: Vector2, zoom: float) -> void:
	var z := s * (1.0 + zoom)
	world.scale = Vector2(z, z)
	# zoom about the field centre
	var P := Vector2(ox, oy) + Vector2(e.CX, e.CY) * (s - z) + shk
	if flipped:
		world.position = Vector2(W, H) - P
		world.rotation = PI
	else:
		world.position = P
		world.rotation = 0.0

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if e == null: return
	t += delta
	var al := e.alpha()
	var n := e.bodies.size()
	if pos.size() != n: pos.resize(n)
	# every frame each body is drawn at its physics position interpolated between the last two fixed 240 Hz
	# sub-steps (engine.alpha), so motion is continuous with no skipping. No extra lerp-smoothing: that made the
	# ball lag tens of px behind its real position and then appear to jump at contacts. (Speeds are capped in the
	# engine instead, so motion stays easy to follow.) Online overrides (host snapshots) get a light blend.
	var smk := clampf(delta * 30.0, 0.2, 1.0)
	var ov: Array = override if override is Array else []
	for i in n:
		var b: NxBody = e.bodies[i]
		var tgt: Vector2
		var is_ov := i < ov.size() and ov[i] is Vector2
		if is_ov: tgt = ov[i]
		else: tgt = Vector2(b.px + (b.x - b.px) * al + b.vox, b.py + (b.y - b.py) * al + b.voy)
		if pos[i] == Vector2.ZERO or not is_ov or pos[i].distance_squared_to(tgt) > 250.0 * 250.0: pos[i] = tgt
		else: pos[i] = pos[i].lerp(tgt, smk)
	if not hq and e.parts.size() > 40: e.parts.resize(40)
	var k := W / 415.0
	var shk := Vector2.ZERO
	if e.cam > 0.05 and (e.v4 or e.flash > 0):
		# nx8/Godot: shots and hits never shake the camera — only the goal celebration does
		# (softened so the celebration feels smooth instead of jittery)
		shk = Vector2(randf() - 0.5, randf() - 0.5) * e.cam * 4.2 * k
	_place(shk, 0.007 * minf(e.cam, 1.4) if hq else 0.0)
	var bl: NxBody = e.ball
	if bl:
		ball_mat.set_shader_parameter("c0", Vector3(bl.r0, bl.r3, bl.r6))
		ball_mat.set_shader_parameter("c1", Vector3(bl.r1, bl.r4, bl.r7))
		ball_mat.set_shader_parameter("c2", Vector3(bl.r2, bl.r5, bl.r8))
		ball_mat.set_shader_parameter("aa", minf(0.2, 1.6 / maxf(1.0, bl.r * s)))
		ball_mat.set_shader_parameter("lflip", -1.0 if flipped else 1.0)
	for l in [shadow_l, glow_l, ring_l, disc_l, trail_l, ball_l, goal_l, light_l, aim_l, part_l]:
		l.queue_redraw()
	if e.flash > 0 or flash_l.get_meta("on", false):
		flash_l.set_meta("on", e.flash > 0)
		flash_l.queue_redraw()

func ball_pos() -> Vector2:
	var i := e.bodies.find(e.ball)
	return pos[i] if i >= 0 and i < pos.size() else Vector2(e.ball.x, e.ball.y)

## optional: engine events -> extra GPU-free particle effects (high quality only)
func on_event(ev: Dictionary) -> void:
	if not hq: return
	match String(ev.get("t", "")):
		"hit":
			if ev.get("ball", false) and float(ev.get("power", 0)) > 0.3: _spark(ball_pos(), float(ev.power))
		"post":
			if float(ev.get("power", 0)) > 0.25: _spark(ball_pos(), float(ev.power))
		"goal":
			if not ev.get("nogoal", false):
				var g: NxEngine.Goal = e.goals[int(ev.team)]
				confetti.global_position = Vector2.ZERO
				confetti.position = Vector2(e.ball.x, g.y)
				confetti.direction = Vector2(0, -g.d)
				confetti.restart()

func _spark(p: Vector2, pw: float) -> void:
	var sp: CPUParticles2D = sparks[_spark_i]
	_spark_i = (_spark_i + 1) % sparks.size()
	sp.position = p
	sp.amount = int(clampf(10 + pw * 30, 10, 36))
	sp.restart()

# ------------------------------------------------------------------ draw: static
func _draw_bg(c: Layer) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color("#02040c"))
	var f := e.f
	if tex_bg:
		var k := maxf(W / f.W, H / f.H) * 1.05
		c.draw_texture_rect(tex_bg, Rect2((W - f.W * k) / 2, (H - f.H * k) / 2, f.W * k, f.H * k), false)
		c.draw_rect(Rect2(0, 0, W, H), Color(2 / 255.0, 4 / 255.0, 14 / 255.0, 0.62))

func _draw_field(c: Layer) -> void:
	if tex_field: c.draw_texture_rect(tex_field, Rect2(0, 0, e.f.W, e.f.H), false)

func _draw_outline(c: Layer) -> void:
	if hq: c.draw_polyline(_outline, Color(120 / 255.0, 220 / 255.0, 1.0, 0.12), 9.0, true)
	c.draw_polyline(_outline, Color(120 / 255.0, 220 / 255.0, 1.0, 0.35), 3.0, true)
	for arc in _corner_arcs:
		c.draw_polyline(arc, Color(1, 1, 1, 0.55), 3.0, true)

# ------------------------------------------------------------------ draw: dynamic
func _shadow(c: Layer, x: float, y: float, r: float, a: float) -> void:
	var R := r * 1.3
	var lf := -1.0 if flipped else 1.0   # keep the light top-left on screen when the pitch is rotated
	c.draw_texture_rect(tex_shadow, Rect2(x + lf * r * 0.14 - R, y + lf * r * 0.26 - R, 2 * R, 2 * R), false, Color(1, 1, 1, a))

func _draw_shadows(c: Layer) -> void:
	var n := e.bodies.size()
	var lf := -1.0 if flipped else 1.0
	for i in n:
		var b: NxBody = e.bodies[i]
		var p := pos[i]
		if b == e.ball:
			_shadow(c, p.x, p.y, b.r * (1 + b.sq * 0.08), 0.6)
			# tight contact shadow right under the ball
			var rb := b.r * 0.95
			c.draw_texture_rect(tex_shadow, Rect2(p.x - rb, p.y + lf * b.r * 0.35 - rb * 0.7, 2 * rb, 1.4 * rb), false, Color(1, 1, 1, 0.55))
		else:
			var r := b.r * (1 + b.sq * 0.07)
			_shadow(c, p.x, p.y, r, 0.5)
			# soft contact shadow hugging the disc's base (just under its side band)
			var rc := r * 1.12
			var th := maxf(3.0, r * 0.13)
			c.draw_texture_rect(tex_shadow, Rect2(p.x - rc, p.y + lf * th * 1.6 - rc, 2 * rc, 2 * rc), false, Color(1, 1, 1, 0.7))

func _active(b: NxBody) -> bool:
	var aim_team := e.turn if e.phase == "aim" else -1
	return b.team == aim_team and not (e.drag != null and e.drag.b != b) and not e.is_ai_turn()

func _draw_glows(c: Layer) -> void:
	# high quality only: soft additive light under fast discs / active discs + disc motion trails
	var n := e.bodies.size()
	for i in n:
		var b: NxBody = e.bodies[i]
		if b == e.ball: continue
		var p := pos[i]
		var tc: Color = TEAM_GLOW[b.team]
		if b.tr.size() > 1:
			_strip(c, b.tr, p, b.r * 0.85, Color(tc.r, tc.g, tc.b, 0.16), 1.0)
	var bl := e.ball
	var sp := sqrt(bl.vx * bl.vx + bl.vy * bl.vy)
	if sp > 300:
		var bp := ball_pos()
		var a := clampf((sp - 300) / 1800.0, 0, 1) * 0.35
		var R2 := bl.r * 3.2
		var cc: Color = _trail_cols[0]
		c.draw_texture_rect(tex_dot, Rect2(bp.x - R2, bp.y - R2, 2 * R2, 2 * R2), false, Color(cc.r * 1.4, cc.g * 1.4, cc.b * 1.4, a))

func _draw_discs(c: Layer) -> void:
	var n := e.bodies.size()
	for i in n:
		var b: NxBody = e.bodies[i]
		if b == e.ball: continue
		var p := pos[i]
		var r := b.r * (1 + b.sq * 0.07)
		var dark := e.phase == "aim" and b.team != e.turn
		var tex: Texture2D = tex_team[b.team]
		var mod := Color(0.8, 0.8, 0.82, 1) if dark else Color.WHITE
		# pseudo-3D thickness: a darker side band hanging a few px below the face (screen-down, also when flipped)
		var lf := -1.0 if flipped else 1.0
		var th := maxf(3.0, r * 0.13)
		var down := Vector2(0, th * lf)
		var side: Color = TEAM_GLOW[b.team].darkened(0.62).lerp(Color(0.02, 0.04, 0.10, 1), 0.4)
		c.draw_circle(p + down, r, side.darkened(0.35))
		c.draw_circle(p + down * 0.5, r, side)
		# thin bright lip where the side band meets the face
		c.draw_arc(p + down * 0.5, r - 0.5, (0.12 if lf > 0 else PI + 0.12), (PI - 0.12 if lf > 0 else TAU - 0.12), 24, Color(side.lightened(0.35), 0.55), 1.2, true)
		if tex:
			c.draw_set_transform(p, b.ang, Vector2.ONE)
			c.draw_texture_rect(tex, Rect2(-r, -r, 2 * r, 2 * r), false, mod)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			c.draw_circle(p, r, Color("#3a0d16") if b.team else Color("#0d1a3a"))
		if flipped:
			c.draw_set_transform(p, PI, Vector2.ONE)
			c.draw_texture_rect(tex_gloss, Rect2(-r, -r, 2 * r, 2 * r), false)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			c.draw_texture_rect(tex_gloss, Rect2(p.x - r, p.y - r, 2 * r, 2 * r), false)
		# bright rim highlight on the upper-left edge of the face (light from top-left on screen)
		var a0 := PI * 1.05 if lf > 0 else PI * 0.05
		c.draw_arc(p, r - 1.2, a0, a0 + PI * 0.6, 28, Color(1, 1, 1, 0.55), 2.2, true)
		c.draw_arc(p, r - 0.6, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 1.0, true)
	# (the breathing active ring is drawn in the additive light layer, see _draw_lights)

func _strip(c: Layer, pts: Array, head: Vector2, width: float, col: Color, amul: float) -> void:
	# tapered additive ribbon through pts (+ the interpolated head), alpha/width grow toward the head
	var n := pts.size() + 1
	if n < 2: return
	_sp.resize(n * 2); _sc.resize(n * 2)
	for i in n:
		var p: Vector2 = head if i == n - 1 else Vector2(pts[i].x, pts[i].y)
		var q: Vector2
		if i < n - 1: q = (head if i + 1 == n - 1 else Vector2(pts[i + 1].x, pts[i + 1].y)) - p
		else: q = p - Vector2(pts[i - 1].x, pts[i - 1].y)
		var ql := q.length()
		var nn := Vector2(-q.y, q.x) / ql if ql > 0.001 else Vector2(0, 1)
		var k := float(i + 1) / n
		var w := maxf(0.6, width * k) * 0.5
		_sp[i * 2] = p + nn * w; _sp[i * 2 + 1] = p - nn * w
		var cc := Color(col.r, col.g, col.b, col.a * k * amul)
		_sc[i * 2] = cc; _sc[i * 2 + 1] = cc
	_tri_strip(c, n)

func _tri_strip(c: Layer, n: int) -> void:
	var m := (n - 1) * 6
	if _si.size() != m:
		_si.resize(m)
		for i in n - 1:
			var a := i * 2
			_si[i * 6] = a; _si[i * 6 + 1] = a + 1; _si[i * 6 + 2] = a + 2
			_si[i * 6 + 3] = a + 1; _si[i * 6 + 4] = a + 3; _si[i * 6 + 5] = a + 2
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), _si, _sp, _sc)

func _draw_trail(c: Layer) -> void:
	var tr := e.trail
	var n0 := tr.size()
	if n0 < 2: return
	var BW := e.ball.r
	var head := ball_pos()
	var layers := [[2.2, 0.16, 0], [1.1, 0.42, 1], [0.42, 0.95, 2]]
	var hk := 1.5 if hq else 1.0
	var n := n0 + 1
	for L in layers:
		var cc: Color = _trail_cols[L[2]]
		_sp.resize(n * 2); _sc.resize(n * 2)
		for i in n:
			var p: Vector2
			var a: float
			if i < n0:
				var v: Vector3 = tr[i]
				p = Vector2(v.x, v.y); a = v.z
			else:
				p = head; a = tr[n0 - 1].z
			var q: Vector2
			if i < n - 1:
				var v2 = tr[i + 1] if i + 1 < n0 else Vector3(head.x, head.y, 0)
				q = Vector2(v2.x, v2.y) - p
			else:
				var v3: Vector3 = tr[n0 - 1]
				q = p - Vector2(v3.x, v3.y)
			var ql := q.length()
			var nn := Vector2(-q.y, q.x) / ql if ql > 0.001 else Vector2(0, 1)
			var k := float(i) / n0 if i < n0 else 1.0
			var w := maxf(0.6, BW * float(L[0]) * k * a) * 0.5
			_sp[i * 2] = p + nn * w; _sp[i * 2 + 1] = p - nn * w
			var al := minf(1.0, float(L[1]) * a * (0.35 + 0.65 * k))
			var col := Color(cc.r * hk, cc.g * hk, cc.b * hk, al)
			_sc[i * 2] = col; _sc[i * 2 + 1] = col
		_tri_strip(c, n)

func _draw_ball(c: Layer) -> void:
	var b := e.ball
	if b == null: return
	var p := ball_pos()
	var r := b.r * (1 + b.sq * 0.08)
	if tex_ball: c.draw_texture_rect(tex_ball, Rect2(p.x - r, p.y - r, 2 * r, 2 * r), false)
	else: c.draw_circle(p, r, Color.WHITE)

func _draw_goals(c: Layer) -> void:
	if tex_goal == null: return
	var gw: float = e.GG.w
	var gh: float = e.GG.h
	var gx: float = e.GG.x
	for i in 2:
		var g: NxEngine.Goal = e.goals[i]
		var sx: float = sin(t * 40) * 6 * e.shake[i]
		if g.d < 0:
			c.draw_texture_rect(tex_goal, Rect2(gx + sx, g.y - gh, gw, gh), false)
		else:
			# bottom goal: same art mirrored about its goal line (feet on the line, net toward the back)
			c.draw_set_transform(Vector2(0, 2 * g.y), 0.0, Vector2(1, -1))
			c.draw_texture_rect(tex_goal, Rect2(gx + sx, g.y - gh, gw, gh), false)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_lights(c: Layer) -> void:
	# goal ripple: an additive light pulse inside the net where the ball went in
	for i in 2:
		var rp: float = e.ripple[i]
		if rp <= 0: continue
		var g: NxEngine.Goal = e.goals[i]
		var cy := g.y + g.d * e.DEPTH * 0.45
		var R := 90.0 + (1.0 - rp) * 120.0
		var k := 1.6 if hq else 1.0
		var col := Color(1.0 * k, 0.86 * k, 0.4 * k, rp * 0.55)
		c.draw_set_transform(Vector2(e.ripple_x[i], cy), 0.0, Vector2(1.4, 0.7))
		c.draw_texture_rect(tex_dot, Rect2(-R, -R, 2 * R, 2 * R), false, col)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# (turn rings live in _draw_turn_ring, under the discs)

func ring_color(team: int) -> Color:
	var me := my_team if my_team >= 0 else (1 if flipped else 0)
	return RING_ME if team == me else RING_OPP

## glowing team-coloured ring under every disc of the side whose turn it is (aim phase only, AI turns too);
## soft subtle pulse; the selected (dragged) disc is brighter. Additive layer drawn before the discs, always on (low quality too).
func _draw_turn_ring(c: Layer) -> void:
	if e.phase != "aim": return
	var tm := e.turn
	var tc := ring_color(tm)
	var pulse := 0.5 + 0.5 * sin(t * 3.2)
	var sel: NxBody = e.drag.b if e.drag != null else null
	var n := e.bodies.size()
	for i in n:
		var b: NxBody = e.bodies[i]
		if b == e.ball or b.team != tm: continue
		var p := pos[i]
		var on := b == sel
		var k := 1.0 if on else 0.55
		var rr := b.r * (1 + b.sq * 0.07)
		# halo
		var R := rr * (1.55 + 0.06 * pulse)
		c.draw_texture_rect(tex_dot, Rect2(p.x - R, p.y - R, 2 * R, 2 * R), false, Color(tc.r, tc.g, tc.b, (0.30 + 0.12 * pulse) * k))
		# outer soft band + crisp ring
		c.draw_arc(p, rr + 8.0, 0, TAU, 56, Color(tc.r, tc.g, tc.b, (0.28 + 0.14 * pulse) * k), 12.0, true)
		c.draw_arc(p, rr + 4.0, 0, TAU, 56, Color(tc.r, tc.g, tc.b, (0.80 + 0.20 * pulse) * k), 5.0, true)
		if on: c.draw_arc(p, rr + 4.0, 0, TAU, 56, Color(1, 1, 1, 0.35 + 0.2 * pulse), 1.6, true)

static func _sstep(a: float, b: float, v: float) -> float:
	var k := clampf((v - a) / (b - a), 0, 1)
	return k * k * (3 - 2 * k)

static func _power_col(p: float) -> Color:
	return AIM_C[0].lerp(AIM_C[1], p / 0.5) if p < 0.5 else AIM_C[1].lerp(AIM_C[2], (p - 0.5) / 0.5)

func _slices(c: Layer, head: Texture2D, shaft: Texture2D, k: Dictionary, L0: float, L: float, col: Color) -> void:
	var hh: float = k.hh
	var hw := hh * head.get_width() / head.get_height()
	var sh := float(shaft.get_height())
	var sW := float(shaft.get_width())
	var y0: float = sh * k.top
	var y1: float = sh * k.tail
	var sw: float = k.sw
	var x0 := -sw / 2
	var neck: float = L - hh * k.join
	var ln := maxf(2.0, neck - L0)
	var topL: float = k.topLen
	var tailL: float = k.tailLen
	if topL + tailL > ln * 0.8:
		var f := ln * 0.8 / (topL + tailL); topL *= f; tailL *= f
	var mid := ln - topL - tailL
	c.draw_texture_rect_region(shaft, Rect2(x0, -L0 - tailL, sw, tailL), Rect2(0, y1, sW, sh - y1), col)
	if mid > 0: c.draw_texture_rect_region(shaft, Rect2(x0, -neck + topL, sw, mid), Rect2(0, y0, sW, y1 - y0), col)
	if topL > 0: c.draw_texture_rect_region(shaft, Rect2(x0, -neck, sw, topL), Rect2(0, 0, sW, y0), col)
	c.draw_texture_rect_region(head, Rect2(-hw / 2, -L, hw, hh), Rect2(0, 0, head.get_width(), head.get_height()), col)

## quadratic-fillet rounded polygon (radius per vertex), for the code-drawn arrow parts
static func _fillet(pts: PackedVector2Array, radii: PackedFloat32Array, seg := 5) -> PackedVector2Array:
	var o := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var P := pts[i]
		var rad := radii[i]
		if rad <= 0.01:
			o.append(P); continue
		var A := pts[(i - 1 + n) % n]
		var B := pts[(i + 1) % n]
		var la := (A - P).length()
		var lb := (B - P).length()
		if la < 0.01 or lb < 0.01:
			o.append(P); continue
		var t := minf(rad, minf(la, lb) * 0.45)
		var P1 := P + (A - P) / la * t
		var P2 := P + (B - P) / lb * t
		for k in seg + 1:
			var u := float(k) / seg
			o.append(P1.lerp(P, u).lerp(P.lerp(P2, u), u))
	return o

## arrow gradient along its length (u = 0 tail … 1 tip) with a slight diagonal shade across (v = -1 … 1)
static func _arw_col(u: float, v: float, a: float) -> Color:
	var c: Color
	if u < 0.3: c = Color("#ee9a52").lerp(ARW_TAIL, u / 0.3)
	elif u < 0.62: c = ARW_TAIL.lerp(ARW_MID, (u - 0.3) / 0.32)
	else: c = ARW_MID.lerp(ARW_TIP, (u - 0.62) / 0.38)
	var sh := 1.0 - 0.07 * v
	return Color(c.r * sh, c.g * sh, c.b * sh, a)

func _arw_poly(c: Layer, pts: PackedVector2Array, x0: float, x1: float, hw: float, a: float, shadow: bool) -> void:
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		var q := pts[i]
		if shadow: cols[i] = Color(0, 0, 0, a)
		else: cols[i] = _arw_col(clampf((q.x - x0) / maxf(1.0, x1 - x0), 0, 1), clampf(q.y / maxf(1.0, hw), -1, 1), a)
	c.draw_polygon(pts, cols)

## visible world rect (screen bounds mapped back into pitch space), inset by `m` world px
func _vis_rect(m: float) -> Rect2:
	var a := to_world(Vector2(0, 0))
	var b := to_world(Vector2(W, H))
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
	return r.grow(-m)

## longest distance from p along unit u that stays inside rect r
static func _ray_room(p: Vector2, u: Vector2, r: Rect2) -> float:
	var tmax := 1e9
	if u.x > 1e-4: tmax = minf(tmax, (r.end.x - p.x) / u.x)
	elif u.x < -1e-4: tmax = minf(tmax, (r.position.x - p.x) / u.x)
	if u.y > 1e-4: tmax = minf(tmax, (r.end.y - p.y) / u.y)
	elif u.y < -1e-4: tmax = minf(tmax, (r.position.y - p.y) / u.y)
	return maxf(0.0, tmax)

## Aim arrow — user's design, drawn in code: gradient (orange/yellow tail -> red tip) arrow head on a wide shaft,
## with two rounded dash segments behind it (bigger one nearer the shaft). Length and opacity scale with power.
## The whole arrow is fitted inside the visible screen so it is never clipped at pitch edges or corners.
func _draw_aim(c: Layer) -> void:
	var a = e.aim_info()
	if a == null or a.p <= 0:
		_aim_on = false; return
	if not _aim_on:
		_aim_ux = a.ux; _aim_uy = a.uy; _aim_p = a.p; _aim_on = true
	else:
		_aim_ux += (a.ux - _aim_ux) * 0.55; _aim_uy += (a.uy - _aim_uy) * 0.55; _aim_p += (a.p - _aim_p) * 0.6
	var ul := sqrt(_aim_ux * _aim_ux + _aim_uy * _aim_uy)
	if ul == 0: ul = 1.0
	var u := Vector2(_aim_ux / ul, _aim_uy / ul)
	var pw := clampf(_aim_p, 0.0, 1.0)
	var b: NxBody = a.b
	var i := e.bodies.find(b)
	var p := pos[i] if i >= 0 else Vector2(b.x, b.y)
	var r := b.r
	var d0 := r + 4.0
	# arrow length beyond the rim grows LINEARLY with power from AIM_MIN_K (short stub) up to
	# AIM_MAX_K x disc radius (~17 px -> ~196 px); power mapping itself (LMAX) is unchanged
	var want := r * (AIM_MIN_K + (AIM_MAX_K - AIM_MIN_K) * pw)
	var room := _ray_room(p, u, _vis_rect(10.0 / maxf(0.01, s))) - d0
	var T := clampf(minf(want, room), minf(16.0, want), want)
	var sc := clampf(T / want, 0.55, 1.0) if room < want else 1.0
	var hw := r * (0.62 + 0.3 * pw) * sc          # head width
	var hl := minf(hw * 1.08, T * 0.62)          # head length (never longer than ~60% of the arrow)
	var sw := hw * 0.64                          # shaft / dash width
	var al := 0.55 + 0.45 * pw
	var rest := maxf(0.0, T - hl)
	# design proportions behind the head: dash2 205 · gap 155 · dash1 310 · gap 175 · shaft 310
	var k := rest / 1155.0
	var x := d0
	var segs := []
	if rest > sw * 3.2:
		segs.append([x, x + 205 * k]); x += 360 * k
		segs.append([x, x + 310 * k]); x += 485 * k
		segs.append([x, x + 310 * k]); x += 310 * k
	else:
		segs.append([x, x + rest]); x += rest
	var xn := x
	var xt := xn + hl
	var hs := sw * 0.5
	c.draw_set_transform(p, u.angle(), Vector2.ONE)
	for pass_i in 2:
		var shadow := pass_i == 0
		var off := Vector2(3.0, 4.0).rotated(-u.angle()) * (1.0 if not flipped else -1.0) if shadow else Vector2.ZERO
		var aa := al * 0.28 if shadow else al
		# dashes (all but the last segment)
		for si in segs.size() - 1:
			var sg: Array = segs[si]
			var rr := minf(sw * 0.22, (sg[1] - sg[0]) * 0.3)
			var q := PackedVector2Array([Vector2(sg[0], -hs), Vector2(sg[1], -hs), Vector2(sg[1], hs), Vector2(sg[0], hs)])
			for qi in q.size(): q[qi] += off
			_arw_poly(c, _fillet(q, PackedFloat32Array([rr, rr, rr, rr])), d0, xt, hs, aa, shadow)
		# shaft + head as one rounded outline
		var sx: float = segs[segs.size() - 1][0]
		var hh := hw * 0.5
		var body := PackedVector2Array([Vector2(sx, -hs), Vector2(xn, -hs), Vector2(xn, -hh), Vector2(xt, 0), Vector2(xn, hh), Vector2(xn, hs), Vector2(sx, hs)])
		for qi in body.size(): body[qi] += off
		var br := sw * 0.12
		_arw_poly(c, _fillet(body, PackedFloat32Array([br, br * 0.6, hw * 0.08, hw * 0.07, hw * 0.08, br * 0.6, br])), d0, xt, hh, aa, shadow)
	# soft highlight along the upper edge of the shaft/head (3D sheen)
	c.draw_line(Vector2(segs[segs.size() - 1][0] + 4, -hs * 0.55), Vector2(xn - 2, -hs * 0.55), Color(1, 1, 1, 0.16 * al), maxf(1.5, sw * 0.12), true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# accuracy preview dots beyond the tip, only where they stay on screen
	var steps := maxi(2, int(roundf((3 + pw * 4) * (NxEngine.aim_preview(float(e.stats_of(b.team).accuracy)) if e.c_stats != null else 1.0))))
	for kk in range(1, steps + 1):
		var d := xt + 8 + kk * 12
		if d > room + d0 or d > xt + r * 0.7: break
		var f := 1.0 - float(kk) / (steps + 1)
		c.draw_circle(p + u * d, 2.0 + 2.0 * f, Color(ARW_TIP.r, ARW_TIP.g, ARW_TIP.b, 0.55 * f * al), true, -1.0, true)

func _draw_parts(c: Layer) -> void:
	var ps := e.parts
	if ps.is_empty(): return
	var hk := 1.6 if hq else 1.0
	for q: NxEngine.Particle in ps:
		var k := maxf(0.0, q.l / q.m)
		var rr := q.r * (1.3 if q.k == 3 else 0.6 + k * 0.8)
		var a := minf(1.0, k * 1.2)
		var col := Color(q.c.r * hk, q.c.g * hk, q.c.b * hk, a)
		if hq:
			var R := rr * 2.6
			c.draw_texture_rect(tex_dot, Rect2(q.x - R, q.y - R, 2 * R, 2 * R), false, col)
		else:
			c.draw_circle(Vector2(q.x, q.y), rr, col)

func _draw_flash(c: Layer) -> void:
	if e.flash > 0: c.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, e.flash * 0.28))
