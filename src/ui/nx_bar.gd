class_name NxBar
extends Control
## Animated progress bar (RN Bar): rounded track, gradient fill with gloss; set_frac() tweens.

var frac := 0.0
var _shown := 0.0
var fill: NxGrad
var _tw: Tween

func _init(f := 0.0, color := NX.CYAN, color2 := NX.INDIGO, h := 21.0) -> void:
	custom_minimum_size = Vector2(40, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill = NxGrad.new([color2, color2.lerp(color, 0.5), NX.hdr(color, 1.25)], h * 0.5, 0.0, 0.32)
	add_child(fill)
	frac = clampf(f, 0.0, 1.0)
	resized.connect(_layout)
	ready.connect(func(): set_frac(frac))

func _draw() -> void:
	var sb := NX.box(Color(1, 1, 1, 0.08), int(size.y * 0.5), 1.5, Color(1, 1, 1, 0.1))
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

func _layout() -> void:
	fill.position = Vector2.ZERO
	fill.size = Vector2(max(size.y, size.x * _shown), size.y)
	fill.visible = _shown > 0.001
	queue_redraw()

func _set_shown(v: float) -> void:
	_shown = v
	_layout()

func set_frac(f: float, animate := true) -> void:
	frac = clampf(f, 0.0, 1.0)
	var target := maxf(0.02, frac)
	if _tw:
		_tw.kill()
	if not animate or not is_inside_tree():
		_set_shown(target)
		return
	_tw = create_tween()
	_tw.tween_method(_set_shown, _shown, target, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_colors(color: Color, color2: Color) -> void:
	fill.set_colors([color2, color2.lerp(color, 0.5), NX.hdr(color, 1.25)])
