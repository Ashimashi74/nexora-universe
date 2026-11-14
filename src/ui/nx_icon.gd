class_name NxIcon
extends Control
## Simple flat line icons drawn in code (v3 flat style): one colour, rounded strokes, no textures.
## kinds: play, globe, team, gear, chev_down, chev_fwd (points to the reading direction), dot, sliders, back

var kind := "play"
var col := Color.WHITE

func _init(k := "play", c := Color.WHITE) -> void:
	kind = k
	col = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0:
		return
	var c := size * 0.5
	var r := s * 0.5
	var w := maxf(2.0, s * 0.085)
	match kind:
		"dot":
			draw_circle(c, r, col, true, -1.0, true)
		"play":
			draw_arc(c, r - w * 0.5, 0, TAU, 40, col, w, true)
			var k := r * 0.42
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.6, -k), c + Vector2(k, 0), c + Vector2(-k * 0.6, k)]), col)
		"globe":
			var rr := r - w * 0.5
			draw_arc(c, rr, 0, TAU, 40, col, w, true)
			draw_line(c + Vector2(-rr, 0), c + Vector2(rr, 0), col, w * 0.8, true)
			var pts := PackedVector2Array()
			for i in 25:
				var a := -PI * 0.5 + PI * i / 24.0
				pts.append(c + Vector2(cos(a) * rr * 0.45, sin(a) * rr))
			draw_polyline(pts, col, w * 0.8, true)
			var pts2 := PackedVector2Array()
			for i in 25:
				var a := PI * 0.5 + PI * i / 24.0
				pts2.append(c + Vector2(cos(a) * rr * 0.45, sin(a) * rr))
			draw_polyline(pts2, col, w * 0.8, true)
		"team":
			# a disc seen from the top: ring + centre star dot
			draw_arc(c, r - w * 0.5, 0, TAU, 40, col, w, true)
			draw_arc(c, r * 0.55, 0, TAU, 32, col, w * 0.8, true)
			draw_circle(c, r * 0.18, col, true, -1.0, true)
		"gear":
			var ro := r - w * 0.2
			var ri := r * 0.72
			var pts := PackedVector2Array()
			var n := 8
			for i in n * 4 + 1:
				var a := TAU * i / (n * 4.0)
				var q := i % 4
				var rad := ro if (q == 1 or q == 2) else ri
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			draw_polyline(pts, col, w * 0.8, true)
			draw_arc(c, r * 0.3, 0, TAU, 24, col, w * 0.8, true)
		"chev_down":
			var k := r * 0.45
			draw_polyline(PackedVector2Array([c + Vector2(-k, -k * 0.45), c + Vector2(0, k * 0.5), c + Vector2(k, -k * 0.45)]), col, w, true)
		"chev_fwd", "back":
			var k := r * 0.45
			var d := 1.0 if I18n.is_en() else -1.0
			if kind == "back": d = -1.0
			draw_polyline(PackedVector2Array([c + Vector2(-k * 0.45 * d, -k), c + Vector2(k * 0.5 * d, 0), c + Vector2(-k * 0.45 * d, k)]), col, w, true)
		"sliders":
			for i in 3:
				var y := c.y + (i - 1) * r * 0.62
				draw_line(Vector2(c.x - r * 0.8, y), Vector2(c.x + r * 0.8, y), col, w * 0.8, true)
				var off: Array = [-0.35, 0.4, -0.05]
				var x: float = c.x + float(off[i]) * r
				draw_circle(Vector2(x, y), r * 0.2, col, true, -1.0, true)
