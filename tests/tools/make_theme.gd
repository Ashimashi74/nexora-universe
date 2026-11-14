extends SceneTree
## Generates res://src/ui/theme.tres (run: godot --headless --script res://tests/tools/make_theme.gd)

func _init() -> void:
	var th := Theme.new()
	var body := FontVariation.new()
	body.base_font = load("res://assets/fonts/Exo2_700Bold.ttf")
	body.fallbacks = [load("res://assets/fonts/Vazirmatn_500Medium.ttf")]
	th.default_font = body
	th.default_font_size = 36
	var text := Color("#eaf4ff")
	var dim := Color("#8ea3d6")
	var cyan := Color("#39d5ff")
	for t in ["Label", "Button", "LineEdit", "TextEdit", "RichTextLabel", "CheckBox", "OptionButton", "ItemList", "PopupMenu"]:
		th.set_color("font_color", t, text)
	th.set_color("default_color", "RichTextLabel", text)
	# buttons (plain Godot Buttons used by other workers get the glass look)
	var mk := func(bg: Color, border: Color, r := 36) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(r)
		sb.set_border_width_all(3)
		sb.border_color = border
		sb.content_margin_left = 36; sb.content_margin_right = 36
		sb.content_margin_top = 20; sb.content_margin_bottom = 20
		sb.anti_aliasing = true
		return sb
	th.set_stylebox("normal", "Button", mk.call(Color(0.06, 0.1, 0.27, 0.9), Color(0.43, 0.67, 1.0, 0.35)))
	th.set_stylebox("hover", "Button", mk.call(Color(0.08, 0.14, 0.36, 0.95), Color(0.31, 0.89, 1.0, 0.6)))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.12, 0.2, 0.46, 1.0), Color(0.31, 0.89, 1.0, 0.9)))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.06, 0.08, 0.18, 0.6), Color(0.43, 0.67, 1.0, 0.15)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", cyan)
	th.set_color("font_disabled_color", "Button", dim)
	# line edit
	var le: StyleBoxFlat = mk.call(Color(0.03, 0.05, 0.15, 0.85), Color(0.43, 0.67, 1.0, 0.3), 30)
	th.set_stylebox("normal", "LineEdit", le)
	var lef: StyleBoxFlat = mk.call(Color(0.04, 0.07, 0.2, 0.95), cyan, 30)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_color("caret_color", "LineEdit", cyan)
	th.set_color("selection_color", "LineEdit", Color(0.22, 0.84, 1.0, 0.35))
	th.set_color("font_placeholder_color", "LineEdit", Color(0.56, 0.64, 0.84, 0.6))
	th.set_stylebox("normal", "TextEdit", le)
	th.set_stylebox("focus", "TextEdit", lef)
	# panels
	var pn: StyleBoxFlat = mk.call(Color(0.043, 0.071, 0.188, 0.78), Color(0.43, 0.67, 1.0, 0.24), 44)
	pn.shadow_size = 14
	pn.shadow_color = Color(0, 0, 0, 0.45)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PopupMenu", pn)
	# thin, nearly invisible scrollbars
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.5, 0.75, 1.0, 0.25)
	grab.set_corner_radius_all(4)
	grab.content_margin_left = 3; grab.content_margin_right = 3
	var emp := StyleBoxEmpty.new()
	for sb_name in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", sb_name, emp)
		th.set_stylebox("scroll_focus", sb_name, emp)
		th.set_stylebox("grabber", sb_name, grab)
		th.set_stylebox("grabber_highlight", sb_name, grab)
		th.set_stylebox("grabber_pressed", sb_name, grab)
	th.set_stylebox("panel", "ScrollContainer", emp)
	th.set_stylebox("focus", "ScrollContainer", emp)
	th.set_constant("separation", "VBoxContainer", 16)
	th.set_constant("separation", "HBoxContainer", 16)
	var err := ResourceSaver.save(th, "res://src/ui/theme.tres")
	print("theme saved: ", err)
	quit()
