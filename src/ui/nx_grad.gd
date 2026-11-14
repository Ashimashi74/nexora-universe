class_name NxGrad
extends ColorRect
## Gradient rounded rect (shader). `pad` > 0 expands the rect for an outer glow
## (only when the parent is not a Container, e.g. inside NxButton).
## Flat v3: every instance renders as ONE flat colour (the middle stop), no gloss, no glow, no shine.

const SHADER := preload("res://src/ui/shaders/grad_rect.gdshader")
var mat: ShaderMaterial
var pad := 0.0

func _init(colors: Array = [], radius := 44.0, angle := 0.6, gloss := 0.3) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	if colors.size() >= 3:
		set_colors(colors)
	elif colors.size() == 2:
		set_colors([colors[0], colors[0].lerp(colors[1], 0.5), colors[1]])
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("angle", angle)
	mat.set_shader_parameter("gloss", 0.0 * gloss)
	resized.connect(_sz)

func _sz() -> void:
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("pad", pad)

func set_colors(c: Array) -> NxGrad:
	var m: Color = c[1]
	mat.set_shader_parameter("c0", m)
	mat.set_shader_parameter("c1", m)
	mat.set_shader_parameter("c2", m)
	return self

func set_border(w: float, col: Color) -> NxGrad:
	mat.set_shader_parameter("border", minf(w, 2.0))
	mat.set_shader_parameter("border_col", Color(1, 1, 1, minf(col.a, 0.10)))
	return self

func set_glow(col: Color, sz := 24.0, p := 30.0) -> NxGrad:
	pad = p
	mat.set_shader_parameter("glow_col", Color(col.r, col.g, col.b, 0.0))
	mat.set_shader_parameter("glow_size", sz)
	_sz()
	return self

func set_param(k: String, v) -> NxGrad:
	mat.set_shader_parameter(k, v)
	return self

var shine: float = -1.0:
	set(v):
		shine = v
		mat.set_shader_parameter("shine", -1.0)
