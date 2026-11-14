class_name NxRing
extends Control
## Win-rate ring: sweep-gradient arc that animates in (RN Profile Ring).

var v := 0.0
var _shown := 0.0
var c0 := NX.CYAN
var c1 := NX.GREEN
var width := 21.0

func _init(value := 0.0, sz := 240.0) -> void:
	v = value
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready.connect(func():
		var tw := create_tween()
		tw.tween_method(func(x): _shown = x; queue_redraw(), 0.0, v, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - width * 0.5 - 2
	draw_arc(c, r, 0, TAU, 72, Color(1, 1, 1, 0.08), width, true)
	var frac := clampf(_shown / 100.0, 0.0, 1.0)
	if frac <= 0.002:
		return
	var segs := int(max(2, 72 * frac))
	var a0 := -PI / 2
	for i in segs:
		var f0 := float(i) / segs * frac
		var f1 := float(i + 1) / segs * frac
		var k := absf(sin(f0 * PI))
		var col := c0.lerp(c1, k)
		draw_arc(c, r, a0 + f0 * TAU, a0 + f1 * TAU + 0.01, 4, NX.hdr(col, 1.3), width, true)
	var e := a0 + frac * TAU
	draw_circle(c + Vector2(cos(e), sin(e)) * r, width * 0.5, NX.hdr(c1.lerp(c0, 0.3), 1.3), true, -1.0, true)
	draw_circle(c + Vector2(cos(a0), sin(a0)) * r, width * 0.5, NX.hdr(c0, 1.3), true, -1.0, true)
