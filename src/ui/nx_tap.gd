class_name NxTap
extends Node
## Springy press feedback + tap detection for any Control (child helper node).
## Uses MOUSE_FILTER_PASS so a parent ScrollContainer still receives the drag; a move beyond
## SLOP cancels the tap.

signal tapped
signal long_pressed

const SLOP := 26.0
var target: Control
var cb: Callable
var scale_to := 0.94
var sound := true
var haptic := true
var disabled := false
var _down := false
var _start := Vector2.ZERO
var _t0 := 0
var _tw: Tween
var _lp_timer: SceneTreeTimer

static func attach(c: Control, callback := Callable(), scale := 0.94) -> NxTap:
	var t := NxTap.new()
	t.target = c
	t.cb = callback
	t.scale_to = scale
	t.name = "Tap"
	c.add_child(t)
	return t

func _ready() -> void:
	if target == null:
		target = get_parent() as Control
	if target.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		target.mouse_filter = Control.MOUSE_FILTER_PASS
	target.gui_input.connect(_on_input)
	target.resized.connect(_pivot)
	target.mouse_exited.connect(func(): if _down: _cancel())
	_pivot()

func _pivot() -> void:
	target.pivot_offset = target.size * 0.5

func _on_input(ev: InputEvent) -> void:
	if disabled:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_down = true
			_start = ev.global_position
			_t0 = Time.get_ticks_msec()
			_anim(true)
		elif _down:
			_down = false
			_anim(false)
			if target.get_global_rect().grow(SLOP).has_point(ev.global_position):
				_fire()
	elif ev is InputEventMouseMotion and _down:
		if ev.global_position.distance_to(_start) > SLOP:
			_cancel()

func _cancel() -> void:
	_down = false
	_anim(false)

func _fire() -> void:
	if sound:
		UD.sfx("ui")
	if haptic:
		UD.haptic("light")
	tapped.emit()
	if cb.is_valid():
		cb.call()

func _anim(down: bool) -> void:
	if not is_instance_valid(target):
		return
	if _tw:
		_tw.kill()
	_tw = target.create_tween()
	if down:
		_tw.set_parallel(true)
		_tw.tween_property(target, "scale", Vector2(scale_to, scale_to), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tw.tween_property(target, "modulate", Color(1.18, 1.18, 1.22, target.modulate.a), 0.09)
	else:
		_tw.set_parallel(true)
		_tw.tween_property(target, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_tw.tween_property(target, "modulate", Color(1, 1, 1, target.modulate.a), 0.2)
