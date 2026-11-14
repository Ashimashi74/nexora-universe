class_name NxToggle
extends Control
## Pill switch (iOS-like) with a sliding, springy knob. 56x32 dp by default (146x83 px at 1080),
## never stretched by its container; the whole switch is the touch target.

var on := false
var t := 0.0
var accent := NX.CYAN
var cb: Callable
var _tw: Tween

func _init(on_ := false, cb_ := Callable(), accent_ := NX.CYAN) -> void:
	on = on_
	t = 1.0 if on else 0.0
	cb = cb_
	accent = accent_
	custom_minimum_size = Vector2(round(56 * NX.U), round(32 * NX.U))
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _get_minimum_size() -> Vector2:
	return custom_minimum_size

func _draw() -> void:
	# draw in a fixed 56:32 track centred in whatever rect we got, so a stretched parent can't
	# turn it back into a square
	var w := minf(size.x, size.y * 1.75)
	var h := w / 1.75
	var o := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
	var r := h * 0.5
	var off := Color(0.55, 0.52, 1.0, 0.16)
	var bgc := off.lerp(NX.hdr(accent, 1.1), t)
	draw_style_box(NX.box(bgc, int(r), 2, Color(1, 1, 1, 0.18).lerp(NX.hdr(accent, 1.4), t)), Rect2(o, Vector2(w, h)))
	var kr := r - h * 0.12
	var x := o.x + lerpf(r, w - r, t)
	draw_circle(Vector2(x, o.y + r + 3), kr, Color(0, 0, 0, 0.3), true, -1.0, true)
	draw_circle(Vector2(x, o.y + r), kr, Color.WHITE, true, -1.0, true)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		UD.sfx("ui")
		UD.haptic("light")
		set_on(not on)
		if cb.is_valid():
			cb.call(on)
		accept_event()

func set_on(v: bool) -> void:
	on = v
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_method(func(x): t = x; queue_redraw(), t, 1.0 if on else 0.0, 0.4).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
