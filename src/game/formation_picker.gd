class_name FormationPicker
extends VBoxContainer
## Formation picker (sheet content): 9 formations from Data.FORMS as code-drawn pitch thumbnails
## (own half, own goal at the bottom, the player's disc art on each slot), each with «انتخاب» / «انتخاب شده».
## Picking saves Store.p.form; the engine places that side with it at kickoff (the other side mirrored).
##   Nav.sheet(FormationPicker.new())

const D := preload("res://src/core/data.gd")

## v3 options (set before add_child): value (-1 = Store.p.form), disc art, on_select(fi) callback,
## save (write Store.p.form on pick), title / subtitle overrides, read_only (captain-only online picks)
var value := -1
var disc_tex: Texture2D = null
var on_select: Callable = Callable()
var save := true
var title_text := ""
var sub_text := ""
var read_only := false
var _cards: Array = []
var _btns: Array = []
var _thumbs: Array = []

static func t(key: String, fa: String) -> String:
	var s := TranslationServer.translate(key)
	return fa if (s == "" or s == key) else String(s)

func _ready() -> void:
	add_theme_constant_override("separation", 24)
	if value < 0: value = int(UD.p().get("form", D.FORM_DEFAULT))
	var title := Kit.title(title_text if title_text != "" else t("form.title", "ترکیب"), 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := Kit.label(sub_text if sub_text != "" else t("form.subtitle", "چیدمان تیمت را انتخاب کن"), 30, NX.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	sc.add_child(grid)
	var p := UD.p()
	var tex: Texture2D = disc_tex if disc_tex else UD.team_tex(UD.team_by_id(str(p.get("team", "club0"))))
	for i in D.FORMS.size():
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		card.add_child(v)
		var th := _Thumb.new()
		th.pts = D.FORMS[i][2]
		th.tex = tex
		th.custom_minimum_size = Vector2(280, 300)
		th.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(th)
		var nm := Kit.label(t("form.n%d" % i, String(D.FORMS[i][0])), 32, Color.WHITE, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 76)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", NX.font("fa_b"))
		b.add_theme_font_size_override("font_size", 28)
		var ii := i
		b.pressed.connect(func(): _pick(ii))
		v.add_child(b)
		Kit.tap(th, func(): _pick(ii), 0.96)
		grid.add_child(card)
		_cards.append(card); _btns.append(b); _thumbs.append(th)
	_refresh()

func _pick(i: int) -> void:
	if read_only or i == value: return
	value = i
	if save: UD.set_p({"form": i})
	UD.sfx("ui")
	_refresh()
	if on_select.is_valid(): on_select.call(i)

## external update (online: the host's state changed)
func set_value(i: int) -> void:
	if i == value: return
	value = i
	_refresh()

func _refresh() -> void:
	var cur := clampi(value, 0, D.FORMS.size() - 1)
	for i in _cards.size():
		var on := i == cur
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.84, 1.0, 0.14) if on else Color(0.03, 0.047, 0.133, 0.85)
		sb.set_corner_radius_all(30)
		sb.set_border_width_all(4 if on else 2)
		sb.border_color = Color(0.4, 0.92, 1.0, 1.0) if on else Color(1, 1, 1, 0.12)
		sb.shadow_color = Color(0.22, 0.84, 1.0, 0.45) if on else Color(0, 0, 0, 0.35)
		sb.shadow_size = 18 if on else 8
		sb.set_content_margin_all(16)
		(_cards[i] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var b: Button = _btns[i]
		b.text = t("form.selected", "انتخاب شده") if on else t("form.select", "انتخاب")
		b.disabled = on
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var bs := StyleBoxFlat.new()
			bs.set_corner_radius_all(38)
			if on:
				bs.bg_color = Color("#1fb85a")
				bs.border_color = Color("#7dffb0")
			else:
				bs.bg_color = Color("#2a6cff") if st != "pressed" else Color("#1d4fc4")
				bs.border_color = Color(1, 1, 1, 0.35)
			bs.border_width_top = 2
			bs.shadow_color = Color(0, 0, 0, 0.4); bs.shadow_size = 6; bs.shadow_offset = Vector2(0, 4)
			b.add_theme_stylebox_override(st, bs)
		for k in ["font_color", "font_disabled_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color.WHITE)
		(_thumbs[i] as _Thumb).on = on
		(_thumbs[i] as _Thumb).queue_redraw()

## code-drawn mini pitch: own half (own goal at the bottom, halfway line at the top), stripes, markings, discs
class _Thumb extends Control:
	var pts: Array = []
	var tex: Texture2D
	var on := false
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1f7a34")
		sb.set_corner_radius_all(18)
		draw_style_box(sb, r)
		var n := 6
		for k in n:
			if k % 2 == 0: continue
			draw_rect(Rect2(6, h * k / n, w - 12, h / n), Color(1, 1, 1, 0.06))
		var lc := Color(1, 1, 1, 0.75)
		var m := 10.0
		draw_rect(Rect2(m, m, w - 2 * m, h - 2 * m), lc, false, 2.0, true)
		# halfway line + centre circle at the top
		draw_arc(Vector2(w * 0.5, m), w * 0.16, 0, PI, 24, lc, 2.0, true)
		# penalty box + goal at the bottom
		var bw := w * 0.56
		var bh := h * 0.2
		draw_rect(Rect2((w - bw) * 0.5, h - m - bh, bw, bh), lc, false, 2.0, true)
		draw_rect(Rect2((w - w * 0.28) * 0.5, h - m - bh * 0.42, w * 0.28, bh * 0.42), lc, false, 2.0, true)
		draw_rect(Rect2((w - w * 0.3) * 0.5, h - m + 1, w * 0.3, m - 2), Color(1, 1, 1, 0.9))
		# discs (RN v6 FormationMini mapping, own goal at the bottom): nx = across, ny = depth from the own goal line
		# (0.03 .. 0.47 of the full pitch fills the half shown here)
		var dr := w * 0.085
		for pt in pts:
			var x := m + dr + float(pt[0]) * (w - 2 * (m + dr))
			var y := (h - m) - ((float(pt[1]) - 0.03) / 0.44) * (h - 2 * m)
			y = clampf(y, m + dr, h - m - dr)
			draw_circle(Vector2(x, y + 3), dr, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(x, y), dr + 3, Color(0.4, 0.92, 1.0) if on else Color(0.85, 0.9, 1.0, 0.9))
			if tex: draw_texture_rect(tex, Rect2(x - dr, y - dr, 2 * dr, 2 * dr), false)
			else: draw_circle(Vector2(x, y), dr, Color("#0d1a3a"))
