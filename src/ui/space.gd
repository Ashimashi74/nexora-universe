class_name NxSpace
extends Control
## Deep-space backdrop (RN Space): baked nebula per theme with a slow breathing zoom/drift,
## two parallax star layers scrolled in a shader (no per-frame script), a bobbing planet,
## and a vertical darkening gradient. Theme changes cross-fade.

const NEB := {
	"base": "res://assets/g/ui/neb_base.jpg",
	"win": "res://assets/g/ui/neb_win.jpg",
	"lose": "res://assets/g/ui/neb_lose.jpg",
	"system": "res://assets/g/ui/neb_system.jpg",
	"hub": "res://assets/g/ui2/home_bg.jpg",
	"stadium": "res://assets/g/menu/bg_stadium.webp",
	"holo": "res://assets/g/menu/bg_holo.webp",
	# NEXORA v2 menu art (assets/ui/bg): one space backdrop per screen family
	"m_home": "res://assets/ui/bg/home.webp",
	"m_mode": "res://assets/ui/bg/mode.webp",
	"m_shop": "res://assets/ui/bg/shop.webp",
	"m_social": "res://assets/ui/bg/social.webp",
	"m_rank": "res://assets/ui/bg/rank.webp",
	"m_team": "res://assets/ui/bg/team.webp",
	"m_settings": "res://assets/ui/bg/settings.webp",
	"m_oracle": "res://assets/ui/bg/oracle.webp",
	"m_stadium": "res://assets/ui/bg/stadium.webp",
}
const STAR_SHADER := preload("res://src/ui/shaders/stars.gdshader")

var theme_name := ""
var dim := 0.0
var neb_holder: Control
var neb: TextureRect
var stars: Array[TextureRect] = []
var planet: TextureRect
var shade: TextureRect
var _shade_grad: Gradient
var _stars_on := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = NX.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	neb_holder = Control.new()
	neb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(neb_holder)
	# planet (behind stars, in front of nebula)
	planet = TextureRect.new()
	planet.texture = UD.ui("planet")
	planet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	planet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet.modulate = Color(1, 1, 1, 0.0)
	add_child(planet)
	for cfg in [["stars1", 110.0, 0.7, 1024.0], ["stars2", 60.0, 0.75, 760.0]]:
		var s := TextureRect.new()
		s.texture = UD.tex("res://assets/g/ui/%s.png" % cfg[0])
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var m := ShaderMaterial.new()
		m.shader = STAR_SHADER
		m.set_shader_parameter("period", cfg[1])
		m.set_shader_parameter("opacity", cfg[2])
		m.set_shader_parameter("tile", cfg[3])
		s.material = m
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(s)
		stars.append(s)
	shade = TextureRect.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade_grad = Gradient.new()
	var gt := GradientTexture2D.new()
	gt.gradient = _shade_grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	shade.texture = gt
	add_child(shade)
	resized.connect(_layout)
	if theme_name == "":
		set_theme_name("base")
	_layout()

func _layout() -> void:
	for s in stars:
		(s.material as ShaderMaterial).set_shader_parameter("rect_size", size)
	var pw := size.x * 0.62
	planet.size = Vector2(pw, pw)
	planet.pivot_offset = planet.size * 0.5
	planet.position = Vector2(size.x - pw * 0.62, size.y * 0.06)
	if neb:
		_fit(neb)

func _fit(t: TextureRect) -> void:
	t.size = size
	t.position = Vector2.ZERO
	t.pivot_offset = size * 0.5

## theme: base|win|lose|system|hub|stadium|holo; dim: extra darkening (RN dim prop)
func set_theme_name(t: String, dim_ := -1.0) -> void:
	# flat v3: one plain dark surface for every screen (no nebula art, stars or planet)
	theme_name = t
	dim = maxf(0.0, dim_)
	for s in stars:
		s.visible = false
	planet.visible = false
	if shade:
		shade.visible = false

## v2 nebula art per theme (kept for reference / a future "rich backdrop" option; unused in flat v3)
func _theme_art_v2(t: String, dim_ := -1.0) -> void:
	if dim_ < 0:
		dim_ = 0.0 if t in ["stadium", "holo", "hub"] or t.begins_with("m_") else 0.15 if t == "base" else 0.0
	_set_shade(t, dim_)
	if t == theme_name:
		return
	theme_name = t
	var nt := TextureRect.new()
	nt.texture = UD.tex(NEB.get(t, NEB["base"]))
	nt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nt.modulate.a = 0.0
	neb_holder.add_child(nt)
	_fit(nt)
	var old := neb
	neb = nt
	var tw := nt.create_tween()
	tw.tween_property(nt, "modulate:a", 1.0, 0.6)
	if old:
		tw.tween_callback(old.queue_free)
	# slow breathing zoom + drift (RN: scale 1.05→1.10, y ±6dp over 16 s)
	var br := nt.create_tween().set_loops()
	br.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	br.tween_property(nt, "scale", Vector2(1.10, 1.10), 16.0).from(Vector2(1.05, 1.05))
	br.parallel().tween_property(nt, "position:y", 16.0, 16.0).from(-16.0)
	br.tween_property(nt, "scale", Vector2(1.05, 1.05), 16.0)
	br.parallel().tween_property(nt, "position:y", -16.0, 16.0)
	# planet only over the plain nebula themes
	var show_planet := t in ["base", "system", "win", "lose"]
	var pt := planet.create_tween()
	pt.tween_property(planet, "modulate:a", 0.55 if show_planet else 0.0, 0.8)
	if show_planet and not planet.has_meta("bob"):
		planet.set_meta("bob", true)
		var pb := planet.create_tween().set_loops()
		pb.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pb.tween_property(planet, "position:y", 30.0, 7.0).as_relative()
		pb.parallel().tween_property(planet, "rotation", 0.04, 7.0)
		pb.tween_property(planet, "position:y", -30.0, 7.0).as_relative()
		pb.parallel().tween_property(planet, "rotation", -0.02, 7.0)

func _set_shade(t: String, d: float) -> void:
	dim = d
	var c := Color(0.02, 0.016, 0.055)
	var stops: Array
	if t in ["stadium", "holo"]:
		stops = [.55 + d, .45 + d, .82 + d]
	elif t.begins_with("m_"):
		# keep the new art vivid; just enough shade under the HUD and the tab bar
		stops = [.30 + d, .12 + d, .55 + d]
	else:
		stops = [.35 + d, d, .55 + d]
	_shade_grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_shade_grad.colors = PackedColorArray([Color(c, minf(1, stops[0])), Color(c, minf(1, stops[1])), Color(c, minf(1, stops[2]))])

func set_stars(on: bool) -> void:
	_stars_on = on
	for s in stars:
		s.visible = false  # flat v3

## small parallax offset for star layers (e.g. from a scroll position)
func set_drift(y: float) -> void:
	if stars.size() == 2:
		(stars[0].material as ShaderMaterial).set_shader_parameter("drift", Vector2(0, y * 0.08))
		(stars[1].material as ShaderMaterial).set_shader_parameter("drift", Vector2(0, y * 0.18))
