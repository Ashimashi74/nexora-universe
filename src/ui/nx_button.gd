class_name NxButton
extends Container
## Gradient pill button (RN Btn): 3-stop gradient, gloss, border, outer glow, springy press.

const PAD := 26.0
var bg: NxGrad
var row: HBoxContainer
var lbl: Label
var sub_lbl: Label
var icon: TextureRect
var tap: NxTap
var small := false
var style := "primary"
var _disabled := false

func _init(text := "", cb := Callable(), style_ := "primary", small_ := false, icon_tex: Texture2D = null, sub := "") -> void:
	small = small_
	style = style_
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0, 114 if small else 150)
	var r := 36.0 if small else 46.0
	bg = NxGrad.new(NX.grad(style), r, 0.6, 0.34)
	bg.set_border(3.0, Color(1, 1, 1, 0.35))
	var gc: Color = NX.grad(style)[1]
	bg.set_glow(Color(gc.r * 1.4, gc.g * 1.4, gc.b * 1.4, 0.0 if style in ["dark", "ghost"] else 0.55), 26.0, PAD)
	add_child(bg)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	if icon_tex:
		icon = Kit.img(icon_tex, 52 if small else 62)
		row.add_child(icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var fs := 36 if small else 46
	lbl = Kit.title(text, fs, Color.WHITE) if not NX.is_fa(text) else Kit.label(text, fs, Color.WHITE, true)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0.15, 0.45))
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	if style == "gold":
		lbl.add_theme_color_override("font_color", Color("#fffaf0"))
	col.add_child(lbl)
	if sub != "":
		sub_lbl = Kit.label(sub, 25, Color(1, 1, 1, 0.85))
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub_lbl)
	tap = NxTap.attach(self, cb, 0.95)

func _get_minimum_size() -> Vector2:
	var m := row.get_combined_minimum_size() if row else Vector2.ZERO
	return Vector2(m.x + 90, max(m.y + 20, 114 if small else 150))

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		fit_child_in_rect(bg, Rect2(Vector2(-PAD, -PAD), size + Vector2(PAD * 2, PAD * 2)))
		fit_child_in_rect(row, Rect2(Vector2.ZERO, size))

func set_text(t: String) -> void:
	lbl.text = t

func set_disabled(d: bool) -> void:
	_disabled = d
	tap.disabled = d
	modulate.a = 0.45 if d else 1.0

func is_disabled() -> bool:
	return _disabled

func set_style(s: String) -> void:
	style = s
	bg.set_colors(NX.grad(s))
