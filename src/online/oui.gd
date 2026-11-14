class_name OUI
extends RefCounted
## Shared building blocks for the online / social / oracle screens (port of RN src/online/ui.tsx,
## the online half of src/ui/kit.tsx, net/auth.tsx state and the OnlineRoot room bookkeeping).
## Everything is static: screens call OUI.xxx(). Widgets are built in code, RTL by default.
## Owner: OUI worker.

# ---------------------------------------------------------------- palette (RN ui/theme.ts C)
# flat v3: plain dark surfaces + ONE accent (former neon hues all map to NX.ACCENT)
const BG := Color("#0d1018")
const CYAN := NX.ACCENT
const SKY := NX.ACCENT
const BLUE := NX.ACCENT
const INDIGO := NX.ACCENT
const VIOLET := NX.ACCENT
const PINK := NX.ACCENT
const GOLD := NX.GOLD
const ORANGE := NX.ORANGE
const RED := NX.RED
const GREEN := NX.GREEN
const TEXT := NX.TEXT
const DIM := NX.DIM
const DIM2 := NX.DIM2
const LINE := Color(1, 1, 1, 0.08)
const LINE_HI := Color(0.3, 0.6, 1.0, 0.6)
const ROW_BG := NX.SURF
const PANEL_BG := NX.SURF
const GEM_BLUE := Color("#9fd8ff")

## button colours [edge, body, top] — flat: one colour per style
const G := {
	"primary": [NX.ACCENT, NX.ACCENT, NX.ACCENT],
	"gold": [NX.ACCENT, NX.ACCENT, NX.ACCENT],
	"green": [NX.GREEN, NX.GREEN, NX.GREEN],
	"red": [NX.RED, NX.RED, NX.RED],
	"dark": [NX.SURF2, NX.SURF2, NX.SURF2],
	"violet": [NX.ACCENT, NX.ACCENT, NX.ACCENT],
	"ghost": [NX.SURF2, NX.SURF2, NX.SURF2],
	"danger": [NX.RED, NX.RED, NX.RED],
}

## RN dp -> Godot px (base width 1080 vs ~400dp phone)
const K := 2.6
## spacing (RN S) and text sizes (RN TS) in dp
const S_XS := 4
const S_S := 8
const S_M := 12
const S_L := 16
const S_XL := 24
const TS_TITLE := 20
const TS_H := 16
const TS_BODY := 14
const TS_SMALL := 12
const TS_CAP := 11
const TS_TINY := 10


const MODES := ["1v1", "2v2", "3v3"]
const MODE_FA := {"1v1": "تک به تک", "2v2": "۲ به ۲", "3v3": "۳ به ۳"}
const KIND_FA := {"casual": ["دوستانه", GREEN], "quick": ["سریع", CYAN], "arena": ["آرنا", VIOLET], "tournament": ["تورنمنت", ORANGE]}
const LEAGUE_IMG := {"bronze": "medal_bronze", "silver": "medal_silver", "gold": "medal_gold", "platinum": "medal_epic", "diamond": "shield_epic", "master": "shield_star", "legend": "shield_crown"}
const RULES := [["g3", "تا ۳ گل"], ["g5", "تا ۵ گل"], ["t3", "۳ دقیقه"], ["t5", "۵ دقیقه"]]
const TURNS := [[10, "۱۰ث"], [15, "۱۵ث"], [20, "۲۰ث"], [0, "بدون"]]


# ---------------------------------------------------------------- signal bus (static classes can't emit)
class Bus extends RefCounted:
	signal profile_changed(p: Dictionary)
	signal link_changed()

static var bus: Bus = null  # use OUI.ebus()

# ---------------------------------------------------------------- caches
static var _tex: Dictionary = {}
static var _fonts: Dictionary = {}
static var leagues: Array = []
static var _leagues_loading := false

static func px(v: float) -> int:
	return int(round(v * K))


# ================================================================ text / numbers
static func fa_num(s: Variant) -> String:
	var t := str(s)
	if I18n.is_en():
		return t
	var out := ""
	for ch in t:
		var c := ch.unicode_at(0)
		if c >= 48 and c <= 57:
			out += char(0x06F0 + c - 48)
		else:
			out += ch
	return out


## n.toLocaleString('fa-IR'): Persian digits, '٬' thousands separator, '−' minus
static func fa(n: Variant) -> String:
	var v := float(n) if (n is int or n is float) else str(n).to_float()
	var neg := v < 0
	var iv := int(round(absf(v)))
	var digits := str(iv)
	var grouped := ""
	var cnt := 0
	for k in range(digits.length() - 1, -1, -1):
		grouped = digits[k] + grouped
		cnt += 1
		if cnt % 3 == 0 and k > 0:
			grouped = ("," if I18n.is_en() else "٬") + grouped
	return ("−" if neg else "") + fa_num(grouped)


static func pad2fa(n: int) -> String:
	return fa_num("%02d" % n)


static func is_rtl_text(s: String) -> bool:
	for ch in s:
		var c := ch.unicode_at(0)
		if c >= 0x0600 and c <= 0x06FF:
			return true
	return false


# ================================================================ time
static func now_s() -> float:
	return Time.get_unix_time_from_system()


static func iso_to_unix(iso: Variant) -> float:
	if iso == null or str(iso) == "":
		return 0.0
	var src := str(iso)
	var base := src.substr(0, 19)
	var t := Time.get_unix_time_from_datetime_string(base)
	# timezone suffix (+hh:mm / -hh:mm / Z) – Supabase returns +00:00
	var tz := src.substr(19)
	var p := tz.find("+")
	var m := tz.rfind("-")
	var idx := p if p >= 0 else m
	if idx >= 0 and tz.length() >= idx + 6:
		var hh := tz.substr(idx + 1, 2).to_int()
		var mm := tz.substr(idx + 4, 2).to_int()
		var off := hh * 3600 + mm * 60
		t -= off if idx == p else -off
	var dot := tz.find(".")
	if dot == 0:
		var frac := ""
		for ch in tz.substr(1):
			if ch >= "0" and ch <= "9":
				frac += ch
			else:
				break
		if frac != "":
			t += ("0." + frac).to_float()
	return float(t)


static func now_iso() -> String:
	return Time.get_datetime_string_from_unix_time(int(now_s()), false) + "Z"


static func is_online(at: Variant) -> bool:
	if at == null or str(at) == "":
		return false
	return now_s() - iso_to_unix(at) < 180.0


static func time_ago(iso: Variant) -> String:
	if iso == null or str(iso) == "":
		return ""
	var dt := now_s() - iso_to_unix(iso)
	if dt < 60:
		return I18n.t("oui.now")
	if dt < 3600:
		return I18n.t("oui.x_min") % fa(floor(dt / 60.0))
	if dt < 86400:
		return I18n.t("oui.x_h") % fa(floor(dt / 3600.0))
	return I18n.t("oui.x_d") % fa(floor(dt / 86400.0))


# ================================================================ levels / rules (shared with backend)
static func xp_for_level(l: int) -> int:
	var x := maxi(1, l) - 1
	return x * x * 100


static func level_of(xp: int) -> int:
	return maxi(1, int(floor(sqrt(maxf(0.0, float(xp)) / 100.0))) + 1)


static func level_progress(xp: int) -> Dictionary:
	var l := level_of(xp)
	var lo := xp_for_level(l)
	var hi := xp_for_level(l + 1)
	return {"level": l, "cur": xp - lo, "need": hi - lo, "frac": float(xp - lo) / float(maxi(1, hi - lo))}


static func team_size(mode: String) -> int:
	return 1 if mode == "1v1" else (2 if mode == "2v2" else 3)


static func rule_to_settings(r: String) -> Dictionary:
	match r:
		"g3": return {"goals": 3, "time": 0}
		"g5": return {"goals": 5, "time": 0}
		"t5": return {"goals": 3, "time": 300}
	return {"goals": 3, "time": 180}


static func settings_to_rule(st: Variant) -> String:
	var dd: Dictionary = st if st is Dictionary else {}
	var t := float(dd.get("time", 0) if dd.get("time") != null else 0)
	var g := float(dd.get("goals", 3) if dd.get("goals") != null else 3)
	if t >= 300: return "t5"
	if t > 0: return "t3"
	if g >= 5: return "g5"
	return "g3"


static func rule_label(st: Variant) -> String:
	var dd: Dictionary = st if st is Dictionary else {}
	var t := float(dd.get("time", 0) if dd.get("time") != null else 0)
	if t > 0:
		return I18n.t("oui.x_min") % fa(round(t / 60.0))
	var g := int(dd.get("goals", 3) if dd.get("goals") != null else 3)
	return I18n.t("oui.first_to_x_goals") % fa(g if g > 0 else 3)


static func s(v: Variant, def: String = "") -> String:
	return def if v == null else str(v)


static func i(v: Variant, def: int = 0) -> int:
	if v == null:
		return def
	if v is int:
		return v
	if v is float:
		return int(v)
	return str(v).to_int()


static func d(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func a(v: Variant) -> Array:
	return v if v is Array else []


## PostgREST helpers ---------------------------------------------------------
static func enc(v: String) -> String:
	return v.uri_encode()


static func ilike_term(term: String) -> String:
	return term.replace("%", "").replace("_", "").replace(",", "").replace("(", "").replace(")", "").strip_edges()


# ================================================================ textures
static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex[path] = t
	return t


static func ui(name: String) -> Texture2D:
	var t := tex("res://assets/g/ui/%s.webp" % name)
	return t if t else tex("res://assets/g/ui/%s.png" % name)


static func ui2(name: String) -> Texture2D:
	return tex("res://assets/g/ui2/%s.webp" % name)


static func menu(name: String) -> Texture2D:
	return tex("res://assets/g/menu/%s.webp" % name)


static func oracle_tex(mood: String) -> Texture2D:
	var t := tex("res://assets/g/oracle/oracle_%s.webp" % mood)
	return t if t else tex("res://assets/g/oracle/oracle_idle.webp")


static func league_tex(lg: Variant) -> Texture2D:
	return ui(LEAGUE_IMG.get(s(lg), "medal_bronze"))


## avatar / disc key ("club0" team id or "club00" team key) -> team skin texture (RN discImg)
static func disc_key(key: Variant) -> String:
	var k := s(key)
	var rx := RegEx.create_from_string("^([a-z]+)(\\d+)$")
	var m := rx.search(k)
	if m == null:
		return "club00"
	var full := "%s%02d" % [m.get_string(1), m.get_string(2).to_int()]
	if ResourceLoader.exists("res://assets/g/teams/%s.webp" % full):
		return full
	return "club00"


## piece art (NX8 catalog) only through Data/Kit
static func disc_tex(key: Variant) -> Texture2D:
	var k := s(key)
	var t: Texture2D = null
	if k != "" and not Data.team_by_id(k).is_empty():
		t = Data.team_tex(k)
	if t == null:
		t = Kit._team_tex_from_key(k)
	if t == null:
		t = Data.team_tex("club0")
	return t


static func field_count() -> int:
	return Data.FIELDS.size()


static func field_name(i: int) -> String:
	if i >= 0 and i < Data.FIELDS.size():
		var f: Variant = Data.FIELDS[i]
		if f is Dictionary:
			return s(f.get("name", "Field"))
	return "Field"


static func field_thumb(i: int) -> Texture2D:
	if i >= 0 and i < Data.FIELDS.size():
		var f: Variant = Data.FIELDS[i]
		if f is Dictionary:
			var t := tex("res://assets/g/fthumb/%s.webp" % s(f.get("id", "")))
			if t:
				return t
	return null


# ================================================================ fonts
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var files := {
		"title": ["Orbitron_900Black.ttf", "Vazirmatn_800ExtraBold.ttf"],
		"head": ["Orbitron_700Bold.ttf", "Vazirmatn_700Bold.ttf"],
		"bold": ["Vazirmatn_800ExtraBold.ttf", "Exo2_800ExtraBold.ttf"],
		"body": ["Vazirmatn_500Medium.ttf", "Exo2_500Medium.ttf"],
		"latin": ["Exo2_700Bold.ttf", "Vazirmatn_700Bold.ttf"],
	}
	var list: Array = files.get(kind, files["body"])
	var fv := FontVariation.new()
	var base: Font = null
	var fb: Array[Font] = []
	for fname in list:
		var p := "res://assets/fonts/%s" % fname
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if base == null:
				base = f
			else:
				fb.append(f)
	if base == null:
		base = ThemeDB.fallback_font
	fv.base_font = base
	fb.append(NX.emoji_font())
	fv.fallbacks = fb
	_fonts[kind] = fv
	return fv


# ================================================================ widgets
static func lbl(text: String, size: float = TS_BODY, color: Color = TEXT, kind: String = "body", align: int = I18n.AR, wrap: bool = false, lines: int = 1) -> Label:
	var l: Label = Label.new() if wrap else FitLabel.new()
	text = I18n.f(text)
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Persian text must be an RTL paragraph: with AUTO, a string that starts with a (weak) Persian
	# digit came out scrambled ("۲ به ۲" rendered as "۲ ۲ به")
	l.text_direction = Control.TEXT_DIRECTION_RTL if is_rtl_text(text) else Control.TEXT_DIRECTION_AUTO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if lines > 0:
			l.max_lines_visible = lines
	else:
		# A clipped / ellipsis Label reports ~0 minimum width, so inside any container that does
		# not stretch it (badges, pills, shrink HBoxes) it collapsed to 1 px ("…" or nothing).
		# Keep its natural width as minimum (capped, so a long user name can still trim with "…"
		# instead of pushing the row off-screen).
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		if l is FitLabel:
			(l as FitLabel).refit()
	return l


## single-line label: minimum width = its natural text width (capped at `cap` px, beyond that it
## trims with "…"). Label's native minimum ignores script overrides and is ~0 once clip/ellipsis
## is on, so the width is kept in custom_minimum_size and refreshed whenever the text (and with
## it the minimum size) changes.
class FitLabel extends Label:
	var cap := 390.0
	var _last := "\u0001"
	func _init() -> void:
		minimum_size_changed.connect(refit)
	func _notification(what: int) -> void:
		# text set later (counters, names): Label redraws on every text change
		if what == NOTIFICATION_DRAW and text != _last:
			refit()
	func refit() -> void:
		var f := get_theme_font("font")
		if f == null:
			return
		var fs := get_theme_font_size("font_size")
		var w := 0.0
		for line in text.split("\n"):
			w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		_last = text
		text_direction = Control.TEXT_DIRECTION_RTL if OUI.is_rtl_text(text) else Control.TEXT_DIRECTION_AUTO
		var nw := minf(ceilf(w) + 4.0, cap)
		if absf(custom_minimum_size.x - nw) > 0.5:
			custom_minimum_size.x = nw





## label that takes the remaining width of an HBox (trims with "…" when the row is too narrow)
static func flbl(text: String, size: float = TS_BODY, color: Color = TEXT, kind: String = "body", wrap := false, lines := 1) -> Label:
	var l := lbl(text, size, color, kind, I18n.AR, wrap, lines)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not wrap:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		if l is FitLabel:
			(l as FitLabel).cap = px(40)  # expands to the row anyway; may shrink to "…"
			(l as FitLabel).refit()
	return l


static func sb(bg: Color, radius: float = 18, border: Color = Color(0, 0, 0, 0), bw: float = 0, pad: float = 0, glow: Color = Color(0, 0, 0, 0), glow_size: float = 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(px(radius))
	if bw > 0:
		st.border_color = border
		st.set_border_width_all(maxi(1, int(round(bw * K * 0.6))))
	if pad > 0:
		st.set_content_margin_all(px(pad))
	if glow.a > 0 and glow_size > 0:
		st.shadow_color = glow
		st.shadow_size = px(glow_size)
	st.anti_aliasing = true
	return st


## glass panel (RN Panel): accent tints the border; glow adds a coloured shadow
static func panel(accent: Variant = null, pad: float = S_M, glow := false) -> PanelContainer:
	var pc := PanelContainer.new()
	var ac: Color = accent if accent is Color else LINE
	var border := ac if accent is Color and ac.a > 0 else LINE
	if accent is Color and ac.a > 0:
		border = Color(ac, 0.55)
	pc.add_theme_stylebox_override("panel", sb(PANEL_BG, 16, LINE if not (accent is Color and ac.a > 0) else Color(border, 0.35), 1, pad))
	if glow: pass  # flat v3: no glow
	return pc


static func row_box(pad_h: float = S_S, min_h: float = 60, border: Color = LINE, bg: Color = ROW_BG) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := sb(bg, 16, border, 1)
	st.content_margin_left = px(pad_h)
	st.content_margin_right = px(pad_h)
	st.content_margin_top = px(4)
	st.content_margin_bottom = px(4)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size.y = px(min_h)
	return pc


static func hbox(sep: float = S_S, align: int = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", px(sep))
	b.alignment = align
	return b


static func vbox(sep: float = S_S) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", px(sep))
	return b


static func margin(child: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", px(l))
	m.add_theme_constant_override("margin_top", px(t))
	m.add_theme_constant_override("margin_right", px(r))
	m.add_theme_constant_override("margin_bottom", px(b))
	if child:
		m.add_child(child)
	return m


static func spacer(h: float = 0, w: float = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px(w), px(h))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func img(t: Texture2D, size: float, h: float = -1.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px(size), px(size if h < 0 else h))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## springy press feedback + ui sound
static func press_fx(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(0.96, 0.96), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func sfx(key: String) -> void:
	if Engine.get_main_loop() and (Engine.get_main_loop() as SceneTree).root.has_node("Sfx"):
		Sfx.play(key)


static func buzz(kind: String) -> void:
	if Engine.get_main_loop() and (Engine.get_main_loop() as SceneTree).root.has_node("Sfx"):
		Sfx.haptic("heavy" if kind == "success" else kind)


static func toast(msg: String, kind: String = "info") -> void:
	if msg != "":
		Nav.toast(msg, kind)


static func toast_err(msg: String) -> void:
	if msg != "":
		Nav.toast(msg, "err")


static func _btn_style(cols: Array, state: String, radius: float) -> StyleBoxFlat:
	var body: Color = cols[1]
	var top: Color = cols[2]
	if state == "pressed":
		body = body.darkened(0.15)
	elif state == "hover":
		body = body.lightened(0.06)
	elif state == "disabled":
		body = Color(body.darkened(0.45), 0.7)
		top = Color(top, 0.3)
	var st := sb(body, radius, Color(top, 0.0), 0)
	st.content_margin_left = px(10)
	st.content_margin_right = px(10)
	st.content_margin_top = px(4)
	st.content_margin_bottom = px(4)
	return st


## RN Btn: gradient-ish pill button. style = key of G. small → 44dp else 54dp. sub = second line.
static func btn(text: String, cb: Callable, style: String = "primary", small := false, sub: String = "") -> Button:
	var b := Button.new()
	var cols: Array = G.get(style, G["primary"])
	var r := 16.0 if small else 20.0
	for stt in ["normal", "hover", "pressed", "disabled", "focus"]:
		var st := _btn_style(cols, "normal" if stt == "focus" else stt, r)
		if stt == "focus":
			st.draw_center = false
			st.border_color = Color(1, 1, 1, 0)
		b.add_theme_stylebox_override(stt, st)
	b.text = I18n.f(text) if sub == "" else I18n.f(text) + "\n" + I18n.f(sub)
	if is_rtl_text(b.text):
		b.text_direction = Control.TEXT_DIRECTION_RTL
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", px(TS_SMALL if small else 15))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.custom_minimum_size.y = px(44 if small else 54) + (px(14) if sub != "" else 0)
	b.focus_mode = Control.FOCUS_NONE
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	b.pressed.connect(func() -> void:
		press_fx(b)
		sfx("ui")
		if cb.is_valid():
			cb.call())
	return b


## flat outlined chip button (RN Press + pill styles)
static func pill(text: String, cb: Callable, color: Color = CYAN, min_w: float = 44, h: float = 44) -> Button:
	var b := Button.new()
	var st := sb(Color(8 / 255.0, 14 / 255.0, 40 / 255.0, 0.85), 14, Color(color, 0.55), 1)
	st.content_margin_left = px(10)
	st.content_margin_right = px(10)
	for stt in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s2 := st.duplicate() as StyleBoxFlat
		if stt == "pressed":
			s2.bg_color = Color(color, 0.25)
		if stt == "disabled":
			s2.bg_color.a = 0.4
		b.add_theme_stylebox_override(stt, s2)
	b.text = I18n.f(text)
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", px(TS_SMALL))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, color)
	b.custom_minimum_size = Vector2(px(min_w), px(h))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		press_fx(b)
		sfx("ui")
		if cb.is_valid():
			cb.call())
	return b


## invisible tap target wrapping arbitrary content (RN Press)
static func tap(content: Control, cb: Callable, scale_fx := true) -> Button:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for stt in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(stt, empty)
	b.focus_mode = Control.FOCUS_NONE
	b.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_mouse(content)
	b.custom_minimum_size = content.get_combined_minimum_size()
	content.minimum_size_changed.connect(func() -> void:
		if is_instance_valid(b) and is_instance_valid(content):
			b.custom_minimum_size = content.get_combined_minimum_size())
	b.pressed.connect(func() -> void:
		if scale_fx:
			press_fx(b)
		sfx("ui")
		if cb.is_valid():
			cb.call())
	return b


static func _ignore_mouse(c: Node) -> void:
	for ch in c.get_children():
		if ch is Control and not (ch is BaseButton) and not (ch is LineEdit) and not (ch is TextEdit) and not (ch is ScrollContainer):
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse(ch)


static func badge(text: String, color: Color = CYAN, live := false) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := sb(Color(color, 0.13), 11, Color(color, 0.53), 1)
	st.content_margin_left = px(8)
	st.content_margin_right = px(8)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size.y = px(22)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	if live:
		var dot := ColorRect.new()
		dot.color = color
		dot.custom_minimum_size = Vector2(px(6), px(6))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
		var tw := dot.create_tween().set_loops()
		tw.tween_property(dot, "modulate:a", 0.4, 0.7)
		tw.tween_property(dot, "modulate:a", 1.0, 0.7)
	h.add_child(lbl(text, TS_TINY, color, "bold", HORIZONTAL_ALIGNMENT_CENTER))
	return pc


## rotating ring spinner (RN ActivityIndicator)
static func spinner(size: float = 28, color: Color = CYAN) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(px(size), px(size))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sp := Spin.new()
	sp.col = color
	sp.custom_minimum_size = Vector2(px(size), px(size))
	holder.add_child(sp)
	return holder


class Spin extends Control:
	var col: Color = Color("#4fe3ff")
	var ang := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		ang = fmod(ang + dt * TAU * 1.1, TAU)
		queue_redraw()
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.42
		var c := size * 0.5
		draw_arc(c, r, 0, TAU, 40, Color(col, 0.15), r * 0.22, true)
		draw_arc(c, r, ang, ang + TAU * 0.7, 32, col, r * 0.22, true)


## pulsing placeholder rows while lists load (RN Skeleton)
static func skeleton(rows: int = 4, h: float = 72) -> Control:
	var v := vbox(S_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for _k in rows:
		var p := Panel.new()
		p.custom_minimum_size.y = px(h)
		p.add_theme_stylebox_override("panel", sb(Color(60 / 255.0, 90 / 255.0, 180 / 255.0, 0.18), 18, LINE, 1))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(p)
	var tw := v.create_tween().set_loops()
	tw.tween_property(v, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(v, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	return margin(v, S_L, 0, S_L, 0)


static func empty(t: Texture2D, title: String, sub: String = "", action: String = "", cb: Callable = Callable()) -> Control:
	var v := vbox(S_XS)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var im := img(t if t else ui2("x_ball"), 72)
	im.modulate.a = 0.85
	im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(im)
	v.add_child(lbl(title, TS_H, TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER, true, 3))
	if sub != "":
		v.add_child(lbl(sub, TS_SMALL, DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, true, 4))
	if action != "" and cb.is_valid():
		var b := btn(action, cb, "dark", true)
		b.custom_minimum_size.x = px(160)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(spacer(S_M))
		v.add_child(b)
	return margin(v, S_XL, S_XL, S_XL, S_XL)


static func error_state(msg: String, retry: Callable = Callable()) -> Control:
	return empty(ui2("c_bell"), I18n.t("oui.something_went_wrong"), msg, I18n.t("oui.try_again") if retry.is_valid() else "", retry)


## text field with label + error (RN Field). The LineEdit is meta "input".
static func field(label: String = "", placeholder: String = "", max_len: int = 0, secret := false, ltr := false) -> VBoxContainer:
	var v := vbox(S_XS)
	if label != "":
		v.add_child(lbl(label, TS_SMALL, DIM, "bold"))
	var le := line_edit(placeholder, max_len, secret, ltr)
	v.add_child(le)
	v.set_meta("input", le)
	return v


static func line_edit(placeholder: String = "", max_len: int = 0, secret := false, ltr := false, h: float = 48) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = I18n.f(placeholder)
	if max_len > 0:
		le.max_length = max_len
	le.secret = secret
	le.custom_minimum_size.y = px(h)
	var st := sb(Color(6 / 255.0, 10 / 255.0, 30 / 255.0, 0.85), 14, LINE, 1)
	st.content_margin_left = px(12)
	st.content_margin_right = px(12)
	var stf := st.duplicate() as StyleBoxFlat
	stf.border_color = CYAN
	le.add_theme_stylebox_override("normal", st)
	le.add_theme_stylebox_override("focus", stf)
	le.add_theme_stylebox_override("read_only", st)
	le.add_theme_font_override("font", font("body"))
	le.add_theme_font_size_override("font_size", px(15))
	le.add_theme_color_override("font_color", TEXT)
	le.add_theme_color_override("font_placeholder_color", DIM2)
	le.add_theme_color_override("caret_color", CYAN)
	le.add_theme_color_override("selection_color", Color(CYAN, 0.35))
	le.alignment = HORIZONTAL_ALIGNMENT_LEFT if ltr else I18n.AR
	le.structured_text_bidi_override = TextServer.STRUCTURED_TEXT_DEFAULT
	le.text_direction = Control.TEXT_DIRECTION_LTR if ltr else Control.TEXT_DIRECTION_AUTO
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	return le


static func text_area(placeholder: String, h: float = 80) -> TextEdit:
	var te := TextEdit.new()
	te.placeholder_text = placeholder
	te.custom_minimum_size.y = px(h)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var st := sb(Color(6 / 255.0, 10 / 255.0, 30 / 255.0, 0.85), 14, LINE, 1, 8)
	te.add_theme_stylebox_override("normal", st)
	var stf := st.duplicate() as StyleBoxFlat
	stf.border_color = CYAN
	te.add_theme_stylebox_override("focus", stf)
	te.add_theme_font_override("font", font("body"))
	te.add_theme_font_size_override("font_size", px(14))
	te.add_theme_color_override("font_color", TEXT)
	te.add_theme_color_override("font_placeholder_color", DIM2)
	te.text_direction = Control.TEXT_DIRECTION_AUTO
	return te


static func field_value(f: Control) -> String:
	if f == null:
		return ""
	if f is LineEdit:
		return (f as LineEdit).text
	if f is TextEdit:
		return (f as TextEdit).text
	if f.has_meta("input"):
		return field_value(f.get_meta("input"))
	return ""


## segmented selector (RN Segment / Tabs). items = [[value, label], ...]. Returns HBox; call
## seg.set_meta / use seg_set(seg, value) to change selection programmatically.
static func segment(items: Array, value: Variant, cb: Callable, accent: Color = CYAN, h: float = 44) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := sb(Color(6 / 255.0, 10 / 255.0, 30 / 255.0, 0.8), h / 2.0, LINE, 1)
	st.set_content_margin_all(px(3))
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size.y = px(h)
	var row := hbox(2)
	pc.add_child(row)
	var group := ButtonGroup.new()
	for it in items:
		var v: Variant = it[0]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_override("font", font("bold"))
		b.add_theme_font_size_override("font_size", px(TS_SMALL))
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", TEXT)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		var off := StyleBoxEmpty.new()
		var on := sb(Color(accent, 0.22), (h - 6) / 2.0, accent, 1)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off)
		b.add_theme_stylebox_override("focus", off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.set_meta("value", v)
		b.button_pressed = (str(v) == str(value))
		b.pressed.connect(func() -> void:
			sfx("ui")
			buzz("light")
			pc.set_meta("value", v)
			if cb.is_valid():
				cb.call(v))
		row.add_child(b)
	pc.set_meta("value", value)
	return pc


static func seg_value(seg: Control) -> Variant:
	return seg.get_meta("value") if seg and seg.has_meta("value") else null


## pill switch (56x32 dp) with a sliding knob. Was a bare CheckButton, which rendered as a ~105px
## square hit box with the theme's tiny check dot in it.
static func toggle(on: bool, cb: Callable, accent: Color = GREEN) -> NxToggle:
	var t := NxToggle.new(on, func(v: bool) -> void:
		if cb.is_valid():
			cb.call(v), accent)
	t.custom_minimum_size = Vector2(px(56), px(32))
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## option row: title + sub on the right, toggle on the left (CreateRoom row)
static func opt_row(title: String, sub: String, on: bool, cb: Callable) -> Control:
	var h := hbox(S_M)
	h.custom_minimum_size.y = px(56)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var v := vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(lbl(title, TS_BODY, TEXT, "bold"))
	v.add_child(lbl(sub, TS_CAP, DIM, "body", I18n.AR, true, 2))
	h.add_child(v)
	h.add_child(toggle(on, cb))
	return h


## gradient progress bar (RN Bar)
static func bar(frac: float, color: Color = CYAN, color2: Variant = null, h: float = 8) -> Control:
	var b := Bar.new()
	b.frac = clampf(frac, 0.0, 1.0)
	b.c1 = color
	b.c2 = color2 if color2 is Color else color
	b.custom_minimum_size.y = px(h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


class Bar extends Control:
	var frac := 0.0
	var shown := 0.0
	var c1 := Color("#4fe3ff")
	var c2 := Color("#a35bff")
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween()
		tw.tween_property(self, "shown", frac, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	func set_frac(f: float) -> void:
		frac = clampf(f, 0.0, 1.0)
		shown = frac
		queue_redraw()
	func _process(_dt: float) -> void:
		if not is_equal_approx(shown, frac):
			queue_redraw()
	func _draw() -> void:
		var r := size.y * 0.5
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.1)
		bg.set_corner_radius_all(int(r))
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var w := size.x * shown
		if w < 1:
			return
		# RTL: fills from the right edge like the RN bars inside row-reverse layouts
		var fg := StyleBoxFlat.new()
		fg.bg_color = c1.lerp(c2, 0.5)
		fg.set_corner_radius_all(int(r))
		fg.shadow_color = Color(c1, 0.5)
		fg.shadow_size = 3
		draw_style_box(fg, Rect2(Vector2(size.x - w, 0), Vector2(w, size.y)))
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(c1, 0.9)
		hl.set_corner_radius_all(int(r))
		draw_style_box(hl, Rect2(Vector2(size.x - w, 0), Vector2(w * 0.5, size.y)))


## power / accuracy bars 1–10 (RN StatBars)
static func stat_bars(power: int, accuracy: int, compact := false) -> Control:
	var v := vbox(2 if compact else 4)
	for row in [[I18n.t("oui.power"), power, ORANGE], [I18n.t("oui.accuracy"), accuracy, CYAN]]:
		var h := hbox(4)
		var l := lbl(row[0], 9 if compact else TS_TINY, DIM)
		l.custom_minimum_size.x = px(26 if compact else 34)
		h.add_child(l)
		var cells := hbox(1.5)
		cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in 10:
			var c := Panel.new()
			c.custom_minimum_size = Vector2(0, px(4 if compact else 6))
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			c.add_theme_stylebox_override("panel", sb(row[2] if k < int(row[1]) else Color(1, 1, 1, 0.1), 2))
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cells.add_child(c)
		h.add_child(cells)
		if not compact:
			var n := lbl(fa(row[1]), TS_TINY, row[2], "bold", I18n.AL)
			n.custom_minimum_size.x = px(16)
			h.add_child(n)
		v.add_child(h)
	return v


static func divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(120 / 255.0, 180 / 255.0, 1.0, 0.14)
	c.custom_minimum_size.y = 1
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func section_title(text: String, top: float = S_L) -> Control:
	return margin(lbl(text, TS_H, TEXT, "bold"), 0, top, 0, S_S)


static func cap_label(text: String) -> Control:
	return margin(lbl(text, TS_SMALL, DIM, "bold"), 0, S_L, 0, S_S)


## red unread counter bubble
static func unread_dot(n: int) -> Control:
	var pc := PanelContainer.new()
	var st := sb(RED, 11)
	st.content_margin_left = px(5)
	st.content_margin_right = px(5)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size = Vector2(px(22), px(22))
	pc.add_child(lbl(fa(mini(99, n)), 10, Color.WHITE, "bold", HORIZONTAL_ALIGNMENT_CENTER))
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


## screen header with 44dp back button, optional right-side control (RN Header)
static func header(title: String, en: String, on_back: Callable, right: Control = null, accent: Color = CYAN, on_refresh: Callable = Callable()) -> Control:
	var wrap := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(NX.BG, 0.96)
	st.content_margin_left = px(S_M)
	st.content_margin_right = px(S_M)
	st.content_margin_top = px(S_S) + top_inset()
	st.content_margin_bottom = px(S_M)
	wrap.add_theme_stylebox_override("panel", st)
	var h := hbox(S_S)
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	wrap.add_child(h)
	# v3: one back control everywhere — the round close/back button, top-left (none on the root screen)
	if on_back.is_valid():
		var back := Kit.back_button(on_back, px(40))
		back.set_meta("back", true)
		h.add_child(back)
	if on_refresh.is_valid():
		var rb := pill("⟳", on_refresh, CYAN, 44, 44)
		rb.add_theme_font_size_override("font_size", px(20))
		h.add_child(rb)
	if right:
		h.add_child(right)
	var v := vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if false and en != "":  # v3: no English caps sub-title
		var e := lbl(en, 9, accent, "head", I18n.AR)
		e.add_theme_constant_override("outline_size", 0)
		v.add_child(e)
	var tl := lbl(title, TS_TITLE, TEXT, "title", I18n.AR)
	wrap.set_meta("title", tl)
	v.add_child(tl)
	h.add_child(v)
	return wrap


static func top_inset() -> int:
	var r := DisplayServer.get_display_safe_area()
	return maxi(0, r.position.y) if OS.has_feature("mobile") else 0


## standard page: header on top + scroll body. Returns {root, body(VBox), scroll}
static func page(owner: Control, title: String, en: String, on_back: Callable, right: Control = null, accent: Color = CYAN, on_refresh: Callable = Callable()) -> Dictionary:
	owner.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner.layout_direction = I18n.LD
	var root := vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.add_child(root)
	var hd := header(title, en, on_back, right, accent, on_refresh)
	root.add_child(hd)
	var sc := scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	var body := vbox(S_S)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(margin(body, S_L, S_M, S_L, S_XL * 2))
	return {"root": root, "body": body, "scroll": sc, "header": hd}


static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	fill_width(sc)
	return sc


## A ScrollContainer sizes its content to the content's MINIMUM width unless the content has
## SIZE_EXPAND. Every vertical scroller wraps its body in a MarginContainer, whose minimum width
## is only the widest non-wrapping child; autowrap/ellipsis labels report ~0, so whole pages and
## sheets collapsed into a narrow column (cards at ~45% width, text wrapping one letter per line).
## This makes every direct content child of `sc` fill the scroller's width.
static func fill_width(sc: ScrollContainer) -> void:
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.child_entered_tree.connect(func(n: Node) -> void:
		if n is Control and not (n is ScrollBar) and n.get_parent() == sc:
			(n as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL)


static func hscroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	return sc


static func clear(c: Node) -> void:
	if c == null:
		return
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


static func fade_in(c: CanvasItem, dur := 0.22) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, dur)


## staggered entrance (RN Enter)
static func enter(c: Control, idx: int) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(0.05 * idx)
	tw.tween_property(c, "modulate:a", 1.0, 0.25)


## bottom sheet (RN Sheet): Nav.sheet draws the grip + title row; content fills the body.
static func open_sheet(title: String, en: String, content: Control, accent: Color = CYAN, height_frac := 0.85) -> Control:
	content.layout_direction = I18n.LD
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Nav.sheet(content, {"title": title, "en": en, "accent": accent, "height": height_frac})


## centered modal card over a dim veil (RN Modal) added into `host`
static func modal(host: Control, content: Control, accent: Color = CYAN, on_close: Callable = Callable()) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.6)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.layout_direction = I18n.LD
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(cc)
	var p := panel(accent, S_L, true)
	p.custom_minimum_size.x = minf(px(380), host.size.x * 0.88 if host.size.x > 0 else px(340))
	if on_close.is_valid():
		# v3: same close button, same corner (top-left) as every other popup
		var wrapv := vbox(S_XS)
		var top := hbox(0)
		top.layout_direction = Control.LAYOUT_DIRECTION_LTR
		top.add_child(Kit.close_button(on_close, px(34)))
		wrapv.add_child(top)
		wrapv.add_child(content)
		p.add_child(wrapv)
	else:
		p.add_child(content)
	cc.add_child(p)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and on_close.is_valid():
			var r := p.get_global_rect()
			if not r.has_point(ev.global_position):
				on_close.call())
	host.add_child(veil)
	Nav.push_overlay(veil, on_close)  # Android back closes this popup first
	fade_in(veil, 0.15)
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(0.92, 0.92)
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return veil


# ================================================================ Supabase helpers (results are {ok,data,error})
static func rows(res: Variant) -> Array:
	if res is Dictionary and res.get("ok", false):
		var dd: Variant = res.get("data")
		if dd is Array:
			return dd
		if dd is Dictionary:
			return [dd]
	return []


static func one(res: Variant) -> Variant:
	var r := rows(res)
	return r[0] if r.size() > 0 else null


static func err(res: Variant) -> String:
	if res is Dictionary:
		var e := s(res.get("error", ""))
		if e != "":
			return e
	return I18n.t("oui.unknown_error_try_again")


static func ok(res: Variant) -> bool:
	return res is Dictionary and bool(res.get("ok", false))


static func get_rows(path: String) -> Dictionary:
	return await Supa.rest("GET", path)


static func post(table: String, body: Variant, ret := false) -> Dictionary:
	return await Supa.rest("POST", table + ("?select=*" if ret else ""), body, "return=representation" if ret else "return=minimal")


static func patch(path: String, body: Variant) -> Dictionary:
	return await Supa.rest("PATCH", path, body, "return=minimal")


static func del(path: String) -> Dictionary:
	return await Supa.rest("DELETE", path, null, "return=minimal")


# ================================================================ auth / own profile (RN net/auth.tsx)
## OUI.profile mirrors Supa.profile (Supa keeps the own profiles row live over realtime).
static var profile: Dictionary = {}
static var _booted := false


## signal bus accessor that never returns null (static init order / script reloads)
static func ebus() -> Bus:
	if bus == null:
		bus = Bus.new()
	return bus


static func uid() -> String:
	return Supa.uid() if Supa.signed_in() else ""


static func session_user() -> Dictionary:
	var ss: Variant = Supa.session
	if ss is Dictionary:
		return d(ss.get("user"))
	return {}


static func email() -> String:
	return s(session_user().get("email", ""))


static func is_guest() -> bool:
	if not Supa.signed_in():
		return false
	return Supa.is_guest()


## idempotent: hooks Supa auth/profile changes
static func boot() -> void:
	if _booted:
		return
	_booted = true
	if not Supa.auth_changed.is_connected(_on_auth):
		Supa.auth_changed.connect(_on_auth)
	if not Supa.profile_changed.is_connected(_on_supa_profile):
		Supa.profile_changed.connect(_on_supa_profile)
	_on_supa_profile(Supa.profile)


## Supa.auth_changed(event, session)
static func _on_auth(_event: Variant = "", _session: Variant = null) -> void:
	if str(_event) == "PASSWORD_RECOVERY" and Nav.main != null:
		var acc: Variant = load("res://src/screens/account.gd")
		if acc is GDScript:
			acc.show_recovery()
	if not Supa.signed_in():
		if not profile.is_empty():
			profile = {}
			ebus().profile_changed.emit(profile)
		return
	_on_supa_profile(Supa.profile)


static func _on_supa_profile(p: Variant) -> void:
	var np: Dictionary = (p as Dictionary).duplicate() if p is Dictionary else {}
	if not np.is_empty() and s(np.get("id")) != "" and s(np.get("id")) != uid():
		return
	profile = np
	ebus().profile_changed.emit(profile)


## guests are signed in anonymously on first visit (RN auth.ensure)
static func ensure() -> String:
	boot()
	var u: String = await Supa.ensure()
	return u


static func refresh_profile() -> Dictionary:
	if uid() == "":
		return {}
	var p: Variant = await Supa.refresh_profile()
	return p if p is Dictionary else {}


## RN setUsername (validation lives in Supa.set_username)
static func set_username(name: String) -> Dictionary:
	if uid() == "":
		return {"ok": false, "error": I18n.t("challenges.sign_in_first")}
	var r: Dictionary = await Supa.set_username(name)
	if not ok(r):
		return {"ok": false, "error": err(r)}
	profile["username"] = name.strip_edges()
	ebus().profile_changed.emit(profile)
	return {"ok": true}


static func sign_out() -> void:
	drop_link()
	await Supa.sign_out()  # calls leave_all_rooms first
	profile = {}
	ebus().profile_changed.emit(profile)


# ================================================================ leagues (static table, cached once)
static func load_leagues() -> Array:
	if not leagues.is_empty():
		return leagues
	if _leagues_loading:
		while _leagues_loading:
			await (Engine.get_main_loop() as SceneTree).process_frame
		return leagues
	_leagues_loading = true
	var r := await get_rows("leagues?select=*&order=sort")
	_leagues_loading = false
	if ok(r):
		leagues = rows(r)
	return leagues


static func league_color(lg: Dictionary) -> Color:
	var c := s(lg.get("color", ""))
	return Color.from_string(c, CYAN) if c != "" else CYAN


## [current, next] league for a rating (sorted by sort)
static func league_for(rating: int) -> Array:
	var list := leagues.duplicate()
	list.sort_custom(func(x: Variant, y: Variant) -> bool: return i(x.get("sort")) < i(y.get("sort")))
	var cur: Variant = null
	var nxt: Variant = null
	for l in list:
		if i(l.get("min_rating")) <= rating:
			cur = l
		elif nxt == null:
			nxt = l
	return [cur, nxt]


# ================================================================ disc catalog (stats for StatBars)
static func load_discs() -> void:
	var dz: Variant = Supa.discs
	if dz != null and (not dz.loaded or (dz.catalog as Dictionary).is_empty()):
		await dz.load_catalog()


## {power, accuracy} from the shared disc catalog (Supa.discs.stats)
static func disc_stats(id: Variant) -> Dictionary:
	var k := s(id, "club0")
	if k == "":
		k = "club0"
	var dz: Variant = Supa.discs
	if dz != null:
		var st: Dictionary = dz.stats(k)
		return {"power": i(st.get("power"), 5), "accuracy": i(st.get("accuracy"), 5)}
	# same offline fallback as Data.disc_stats so UI bars match real shot power
	var d: Variant = Data.disc_stats(k)
	if d is Dictionary and d.has("power"):
		return {"power": i(d.get("power"), 5), "accuracy": i(d.get("accuracy"), 5)}
	return {"power": 5, "accuracy": 5}


# ================================================================ room bookkeeping (RN OnlineRoot)
static var link: Variant = null
static var skip_match := ""
static var first_load := true
static var before_profile: Dictionary = {}


static func link_state() -> Dictionary:
	if link == null:
		return {}
	return d(link.state)


## enter a room's lobby (creates the RoomLink once per room)
static func enter_room(room: Variant) -> void:
	var r := d(room)
	if r.is_empty():
		return
	var u := uid()
	if u == "":
		return
	var rid := s(r.get("id"))
	if link != null and s(link.id) == rid:
		Nav.go("lobby", {"room_id": rid, "link": link})
		return
	drop_link()
	first_load = true
	skip_match = ""
	var name := s(profile.get("username", ""), "Pilot")
	if name == "":
		name = "Pilot"
	var l: Variant = RoomLink.new(rid, u, name)  # parents itself under Supa
	link = l
	ebus().link_changed.emit()
	Nav.go("lobby", {"room_id": rid, "link": l})


static func drop_link() -> void:
	if link == null:
		return
	var l: Variant = link
	link = null
	if is_instance_valid(l):
		l.destroy()  # frees itself
	prune_history()
	ebus().link_changed.emit()


## leave_room rpc + destroy link + back to the hub
static func leave_room(to_hub := true) -> void:
	var l: Variant = link
	if l != null:
		Supa.call_rpc("leave_room", {"p_room": s(l.id)})
		drop_link()
	if Engine.get_main_loop() and (Engine.get_main_loop() as SceneTree).root.has_node("Sfx"):
		Sfx.music(true)
	if to_hub:
		Nav.go("hub", {})
		prune_history()


## room screens in Nav's back history are dead once the link is gone (and "hub" must not stack)
static func prune_history() -> void:
	var h: Array = Nav.history
	for k in range(h.size() - 1, -1, -1):
		if h[k] is Array and str(h[k][0]) in ["lobby", "online_result", "online_match", "hub"]:
			h.remove_at(k)


## shared quick/arena matchmaking (RN Hub.quick / Arena.find)
static func quick_match(mode: String, kind: String = "quick") -> String:
	OracleCoach.react("search")
	var r: Dictionary = await Supa.call_rpc("quick_match", {"p_mode": mode, "p_kind": kind})
	if not ok(r):
		buzz("heavy")
		return err(r)
	sfx("join")
	buzz("medium")
	enter_room(r.get("data"))
	return ""


# ================================================================ media (RN net/media.ts)
## Pick an image with the native picker (Android/desktop), resize/compress to JPEG and upload.
## cb.call({ok, url, error, cancelled}).
static func pick_and_upload(bucket: String, size: int, square: bool, cb: Callable) -> void:
	var u := uid()
	if u == "":
		cb.call({"ok": false, "error": I18n.t("challenges.sign_in_first"), "cancelled": false})
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		cb.call({"ok": false, "error": "", "cancelled": true, "unsupported": true})
		return
	# No runtime permission needed: the Android picker (SAF) grants access to the chosen file.
	# (OS.request_permissions() here used to prompt for every dangerous permission: mic, Bluetooth...)
	var on_pick := func(status: bool, paths: PackedStringArray, _fi: int) -> void:
		if not status or paths.is_empty():
			cb.call({"ok": false, "error": "", "cancelled": true})
			return
		var res: Dictionary = await _process_upload(bucket, u, paths[0], size, square)
		cb.call(res)
	var e := DisplayServer.file_dialog_show(I18n.t("oui.choose_photo"), "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images", "image/*"]), on_pick)
	if e != OK:
		cb.call({"ok": false, "error": "", "cancelled": true, "unsupported": true})


static func _process_upload(bucket: String, u: String, path: String, size: int, square: bool) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "error": I18n.t("oui.choosing_or_uploading_the_photo"), "cancelled": false}
	var im := Image.new()
	var e := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 3 and bytes[0] == 0x89 and bytes[1] == 0x50:
		e = im.load_png_from_buffer(bytes)
	elif bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		e = im.load_jpg_from_buffer(bytes)
	elif bytes.size() > 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		e = im.load_webp_from_buffer(bytes)
	if e != OK:
		return {"ok": false, "error": I18n.t("oui.photo_processing_failed"), "cancelled": false}
	if square:
		var m := mini(im.get_width(), im.get_height())
		im = im.get_region(Rect2i((im.get_width() - m) / 2, (im.get_height() - m) / 2, m, m))
	if im.get_width() > size or im.get_height() > size:
		if im.get_width() >= im.get_height():
			im.resize(size, maxi(1, int(round(float(im.get_height()) * size / im.get_width()))), Image.INTERPOLATE_LANCZOS)
		else:
			im.resize(maxi(1, int(round(float(im.get_width()) * size / im.get_height()))), size, Image.INTERPOLATE_LANCZOS)
	if im.has_mipmaps():
		im.clear_mipmaps()
	if im.get_format() != Image.FORMAT_RGB8:
		im.convert(Image.FORMAT_RGB8)
	var jpg := im.save_jpg_to_buffer(0.82)
	var rnd := ""
	for _k in 6:
		rnd += "abcdefghijklmnopqrstuvwxyz0123456789"[randi() % 36]
	var p := "%s/%d-%s.jpg" % [u, int(now_s() * 1000), rnd]
	var r: Variant = await Supa.upload(bucket, p, jpg, "image/jpeg")
	var url := ""
	if r is String:
		url = r
	elif r is Dictionary and ok(r):
		url = s(r.get("data", ""))
	if url == "":
		return {"ok": false, "error": I18n.t("oui.photo_upload_failed"), "cancelled": false}
	NetImg.put(url, ImageTexture.create_from_image(im))
	return {"ok": true, "url": url}


# ================================================================ virtualized list
## Fixed-row-height recycled list inside a ScrollContainer (RN FlatList). A free-height header
## sits above the rows; `empty` replaces the rows when there is no data.
##   var vl := OUI.VList.new(row_h_dp, make_row: Callable() -> Control, bind_row: Callable(ctrl, item, idx))
##   vl.set_header(ctrl); vl.set_items(arr); vl.set_empty(ctrl)
class VList extends ScrollContainer:
	var row_h := 0
	var gap := 0
	var make_row: Callable
	var bind_row: Callable
	var items: Array = []
	var pad_x := 0
	var pad_bottom := 0
	var _content: Control
	var _header: Control = null
	var _empty: Control = null
	var _pool: Array[Control] = []
	var _bound: Dictionary = {}   # row ctrl -> index
	var _dirty := true

	func _init(rh_dp: float = 64, mk: Callable = Callable(), bind: Callable = Callable(), gap_dp: float = 8) -> void:
		row_h = OUI.px(rh_dp)
		gap = OUI.px(gap_dp)
		make_row = mk
		bind_row = bind
		pad_x = OUI.px(OUI.S_L)
		pad_bottom = OUI.px(OUI.S_XL * 2)
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content = Control.new()
		_content.mouse_filter = Control.MOUSE_FILTER_PASS
		_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_content)

	func _ready() -> void:
		get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _layout())
		resized.connect(func() -> void: _dirty = true)

	func set_header(h: Control) -> void:
		if _header and is_instance_valid(_header):
			_header.queue_free()
		_header = h
		if h:
			_content.add_child(h)
			h.minimum_size_changed.connect(func() -> void: _dirty = true)
		_dirty = true

	func set_empty(e: Control) -> void:
		if _empty and is_instance_valid(_empty):
			_empty.queue_free()
		_empty = e
		if e:
			_content.add_child(e)
		_dirty = true

	func set_items(arr: Array) -> void:
		items = arr
		_bound.clear()
		_dirty = true

	func refresh_rows() -> void:
		_bound.clear()
		_dirty = true

	func _process(_dt: float) -> void:
		if _dirty:
			_dirty = false
			_layout()

	func _hh() -> float:
		if _header and is_instance_valid(_header):
			return _header.get_combined_minimum_size().y
		return 0.0

	func _layout() -> void:
		var w := size.x
		if w <= 0:
			return
		var hh := _hh()
		if _header and is_instance_valid(_header):
			_header.position = Vector2.ZERO
			_header.size = Vector2(w, hh)
		var n := items.size()
		var body_h := float(n) * (row_h + gap)
		if _empty and is_instance_valid(_empty):
			_empty.visible = n == 0
			if n == 0:
				var eh := _empty.get_combined_minimum_size().y
				_empty.position = Vector2(0, hh)
				_empty.size = Vector2(w, eh)
				body_h = eh
		_content.custom_minimum_size = Vector2(0, hh + body_h + pad_bottom)
		# visible window
		var top := float(scroll_vertical) - hh
		var first := maxi(0, int(floor(top / float(row_h + gap))) - 2)
		var last := mini(n - 1, int(ceil((top + size.y) / float(row_h + gap))) + 2)
		var need := maxi(0, last - first + 1)
		while _pool.size() < need and make_row.is_valid():
			var r: Control = make_row.call()
			_content.add_child(r)
			_pool.append(r)
		var used: Dictionary = {}
		var free_rows: Array[Control] = []
		for r in _pool:
			var idx: int = _bound.get(r, -1)
			if idx >= first and idx <= last and idx < n and not used.has(idx):
				used[idx] = r
			else:
				free_rows.append(r)
		for idx in range(first, last + 1):
			if used.has(idx):
				continue
			if free_rows.is_empty():
				break
			var r2: Control = free_rows.pop_back()
			_bound[r2] = idx
			used[idx] = r2
			if bind_row.is_valid():
				bind_row.call(r2, items[idx], idx)
		for r3 in free_rows:
			r3.visible = false
			_bound[r3] = -1
		for idx in used:
			var r4: Control = used[idx]
			r4.visible = true
			r4.position = Vector2(pad_x, hh + idx * (row_h + gap))
			r4.size = Vector2(w - pad_x * 2, row_h)


## realtime postgres_changes payload → the new row (accepts {new:…}, {record:…} or the row itself)
static func rec_new(rec: Variant) -> Dictionary:
	var r := d(rec)
	if r.has("new") and r["new"] is Dictionary:
		return r["new"]
	if r.has("record") and r["record"] is Dictionary:
		return r["record"]
	if r.has("data") and r["data"] is Dictionary and (r["data"] as Dictionary).has("record"):
		return d(r["data"]["record"])
	return r
