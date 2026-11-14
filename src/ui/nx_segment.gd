class_name NxSegment
extends Control
## Segmented control with a spring-sliding highlight (RN Segment). Items laid out RTL
## (first item on the right) like the RN row-reverse. cb(index) on change.

signal changed(index: int)
var items: Array = []
var index := 0
var accent := NX.CYAN
var cb: Callable
var hl: NxGrad
var labels: Array[Label] = []
var _tw: Tween
var _hl_x := 0.0

func _init(items_: Array = [], cb_ := Callable(), index_ := 0, accent_ := NX.CYAN) -> void:
	items = items_
	cb = cb_
	index = index_
	accent = accent_
	custom_minimum_size = Vector2(200, 114)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hl = NxGrad.new([NX.a(accent, 0.38), NX.a(accent, 0.24), NX.a(accent, 0.12)], 50.0, 1.57, 0.12)
	hl.set_border(3.0, NX.hdr(NX.a(accent, 0.9), 1.3))
	add_child(hl)
	for i in items.size():
		var l := Kit.label(str(items[i]), 31, NX.DIM, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		labels.append(l)
	resized.connect(_layout)

func _cell_w() -> float:
	return (size.x - 16.0) / max(1, items.size())

func _cell_x(i: int) -> float:
	# item 0 sits at the reading start: right edge in Persian (RTL), left edge in English
	if I18n.is_en():
		return 8.0 + _cell_w() * i
	return size.x - 8.0 - _cell_w() * (i + 1)

func _layout() -> void:
	var cw := _cell_w()
	for i in labels.size():
		labels[i].position = Vector2(_cell_x(i), 8)
		labels[i].size = Vector2(cw, size.y - 16)
		labels[i].add_theme_color_override("font_color", Color.WHITE if i == index else NX.DIM)
	if _tw == null or not _tw.is_running():
		_hl_x = _cell_x(index)
	hl.position = Vector2(_hl_x, 8)
	hl.size = Vector2(cw, size.y - 16)
	queue_redraw()

func _draw() -> void:
	draw_style_box(NX.box(NX.SURF, int(size.y * 0.5), 2, NX.LINE), Rect2(Vector2.ZERO, size))

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		var cw := _cell_w()
		for i in items.size():
			var x := _cell_x(i)
			if ev.position.x >= x and ev.position.x < x + cw:
				if i != index:
					UD.sfx("ui")
					UD.haptic("light")
					set_index(i)
					changed.emit(i)
					if cb.is_valid():
						cb.call(i)
				break

func set_index(i: int, animate := true) -> void:
	index = clampi(i, 0, max(0, items.size() - 1))
	for k in labels.size():
		labels[k].add_theme_color_override("font_color", Color.WHITE if k == index else NX.DIM)
	if _tw:
		_tw.kill()
	if not animate or not is_inside_tree():
		_hl_x = _cell_x(index)
		_layout()
		return
	_tw = create_tween()
	_tw.tween_method(func(v): _hl_x = v; hl.position.x = v, _hl_x, _cell_x(index), 0.45).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
