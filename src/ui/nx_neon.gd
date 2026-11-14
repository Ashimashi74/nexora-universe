class_name NxNeon
extends PanelContainer
## v2 neon glass tile (home mockup): deep indigo glass, violet edge, cyan -> pink glow along the
## bottom edge and a soft top sheen. Used for the home tiles, level card, shop categories, mode cards.

var c1 := Color("#39d5ff")
var c2 := Color("#ff4f8b")
var radius := 40
var strength := 1.0

func _init(r := 40, pad := 20.0, c1_ := Color("#39d5ff"), c2_ := Color("#ff4f8b")) -> void:
	# flat v3: a plain rounded card (no glow wash, sheen or neon edge)
	radius = mini(r, 36)
	c1 = c1_
	c2 = c2_
	var sb := NX.box(NX.SURF, radius, 2, NX.LINE)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS


## small red notification dot (28px) for tiles / round buttons; never stretched by a container
static func dot(pos := Vector2(12, 10)) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := _Dot.new()
	d.position = pos
	d.size = Vector2(28, 28)
	holder.add_child(d)
	return holder

class _Dot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_circle(size * 0.5, 14, NX.BG, true, -1.0, true)
		draw_circle(size * 0.5, 10.5, NX.hdr(NX.RED, 1.3), true, -1.0, true)
