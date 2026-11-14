class_name NxChangeForm
extends PanelContainer
## In-match «تغییر ترکیب» button (RN v6 ChangeFormation): bottom-left pill with the current formation's mini
## thumbnail; opens the 9-formation grid. The pick is reported through on_select(fi) and APPLIES AT THE NEXT
## KICKOFF (match start / after every goal) — offline the match calls NxEngine.set_form, online the host does.
##   var cf := NxChangeForm.new(); cf.value = 8; cf.disc_tex = tex; cf.on_select = func(fi): ...; add_child(cf)

var value := 8
var disc_tex: Texture2D
var on_select: Callable = Callable()
var on_open: Callable = Callable()     # e.g. pause the offline match while the grid is open
var on_close: Callable = Callable()
var _thumb: Control

func _ready() -> void:
	add_theme_stylebox_override("panel", NX.box(Color(0.03, 0.05, 0.13, 0.9), 36, 3, Color(NX.GREEN, 0.67)))
	var h := HBoxContainer.new()
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Kit.label("تغییر ترکیب", 32, NX.TEXT, true)
	h.add_child(Kit.margin(l, 26, 0, 0, 0))
	_thumb = _Mini.new()
	_thumb.custom_minimum_size = Vector2(114, 76)
	(_thumb as _Mini).fi = value
	h.add_child(_thumb)
	add_child(Kit.margin(h, 6, 10, 10, 10))
	Kit.tap(self, _open, 0.95)

func set_value(fi: int) -> void:
	value = fi
	if _thumb:
		(_thumb as _Mini).fi = fi
		_thumb.queue_redraw()

func _open() -> void:
	if on_open.is_valid(): on_open.call()
	var v := Kit.vbox(12)
	var note := Kit.label("از کیک‌آف بعدی (بعد از گل) اعمال می‌شود", 28, NX.DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	var fp := FormationPicker.new()
	fp.value = value
	fp.disc_tex = disc_tex
	fp.save = true
	fp.title_text = "تغییر ترکیب"
	fp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fp.on_select = func(fi: int):
		set_value(fi)
		if on_select.is_valid(): on_select.call(fi)
		Nav.toast("ترکیب از کیک‌آف بعدی اعمال می‌شود", "info")
		Nav.close_sheet()
	v.add_child(fp)
	v.custom_minimum_size.y = 1300
	Nav.sheet(v, {"title": "تغییر ترکیب", "en": "FORMATION", "height": 0.86})
	if on_close.is_valid() and Nav.has_signal("sheet_closed"):
		Nav.sheet_closed.connect(on_close, CONNECT_ONE_SHOT)

## RN FormationMini: half pitch with the own goal on the LEFT, half-way line on the right
class _Mini extends Control:
	var fi := 8
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color("#1d7a3a"))
		var lc := Color(1, 1, 1, 0.75)
		draw_rect(Rect2(1, h * 0.2, w * 0.17, h * 0.6), lc, false, 1.5)
		draw_line(Vector2(w - 1, 0), Vector2(w - 1, h), lc, 1.5)
		draw_arc(Vector2(w, h * 0.5), h * 0.28, PI * 0.5, PI * 1.5, 16, lc, 1.5)
		var r := maxf(4.0, w * 0.065)
		var D := preload("res://src/core/data.gd")
		for pt in D.FORMS[D.form_idx(fi)][2]:
			var x := ((float(pt[1]) - 0.03) / 0.44) * w
			var y := float(pt[0]) * h
			draw_circle(Vector2(x, y), r, NX.CYAN)
			draw_arc(Vector2(x, y), r, 0, TAU, 12, Color.WHITE, 1.2, true)
