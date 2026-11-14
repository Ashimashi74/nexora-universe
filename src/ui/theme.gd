class_name NX
extends RefCounted
## NEXORA design tokens (colours, fonts, gradients, sizes) — port of src/ui/theme.ts.
## All sizes are in viewport pixels for the 1080-wide base (1 RN dp ≈ 2.6 px).

const U := 2.6  # RN dp -> px

# ---- colours: flat v3 (plain dark surfaces, ONE accent colour, rounded cards) ----
## Every former neon hue (cyan / sky / blue / indigo / violet / pink / rose) maps to the single accent so
## older screens become one-accent without touching their code; gold / green / red keep their meaning.
const ACCENT := Color("#4c9aff")
const SURF := Color("#161b26")
const SURF2 := Color("#1f2533")
const BG := Color("#0d1018")
const BG2 := Color("#111521")
const CYAN := ACCENT
const SKY := ACCENT
const BLUE := ACCENT
const INDIGO := ACCENT
const VIOLET := ACCENT
const PINK := ACCENT
const ROSE := ACCENT
const GOLD := Color("#f2c14e")
const ORANGE := Color("#f59e0b")
const RED := Color("#ef5350")
const GREEN := Color("#34c98a")
const MINT := Color("#34c98a")
const TEXT := Color("#e8ecf4")
const DIM := Color("#8d97ab")
const DIM2 := Color("#5d6779")
const LINE := Color(1, 1, 1, 0.08)
const LINE_HI := Color(0.3, 0.6, 1.0, 0.6)
const PANEL := Color(0.086, 0.106, 0.149, 0.97)
const DARK_TXT := Color("#0d1018")
const VEIL := Color("#0b0e15")

# emissive (HDR > 1) accents: picked up by the WorldEnvironment glow in main
static func hdr(c: Color, _k := 1.8) -> Color:
	return c  # flat v3: no emissive boost (menu glow is off; matches keep their own art)

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)

# ---- gradients (3 stops like RN G.*) ----
const G := {
	"primary": [ACCENT, ACCENT, ACCENT],
	"blue": [ACCENT, ACCENT, ACCENT],
	"gold": [ACCENT, ACCENT, ACCENT],
	"green": [GREEN, GREEN, GREEN],
	"red": [RED, RED, RED],
	"danger": [RED, RED, RED],
	"dark": [SURF2, SURF2, SURF2],
	"ghost": [SURF2, SURF2, SURF2],
	"violet": [ACCENT, ACCENT, ACCENT],
}

static func grad(style: String) -> Array:
	return G.get(style, G["primary"])

# ---- fonts ----
const FONT_PATHS := {
	"title": "res://assets/fonts/Exo2_800ExtraBold.ttf",
	"head": "res://assets/fonts/Exo2_700Bold.ttf",
	"body": "res://assets/fonts/Exo2_700Bold.ttf",
	"medium": "res://assets/fonts/Exo2_500Medium.ttf",
	"bold": "res://assets/fonts/Exo2_800ExtraBold.ttf",
	"fa": "res://assets/fonts/Vazirmatn_500Medium.ttf",
	"fa_r": "res://assets/fonts/Vazirmatn_400Regular.ttf",
	"faB": "res://assets/fonts/Vazirmatn_800ExtraBold.ttf",
	"fa_b": "res://assets/fonts/Vazirmatn_700Bold.ttf",
}
static var _fonts := {}

static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = FONT_PATHS.get(kind, FONT_PATHS["body"])
	var f: Font = load(path)
	var fv := FontVariation.new()
	fv.base_font = f
	if not kind.begins_with("fa"):
		# latin fonts fall back to Vazirmatn so mixed strings never show tofu
		fv.fallbacks = [load(FONT_PATHS["faB"] if kind in ["title", "head", "bold"] else FONT_PATHS["fa"]), emoji_font()]
	else:
		fv.fallbacks = [load(FONT_PATHS["bold"]), emoji_font()]
	_fonts[kind] = fv
	return fv

static var _emoji: Font = null

## system colour-emoji font (Android ships Noto Color Emoji) so 🔥💎👋 don't render as boxes
static func emoji_font() -> Font:
	if _emoji == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Noto Color Emoji", "NotoColorEmoji", "Apple Color Emoji", "Segoe UI Emoji", "emoji"])
		_emoji = sf
	return _emoji

# ---- Persian helpers ----
const FA_DIGITS := "۰۱۲۳۴۵۶۷۸۹"
static var _fa_re: RegEx

static func is_fa(s: String) -> bool:
	if _fa_re == null:
		_fa_re = RegEx.create_from_string("[\\x{0600}-\\x{06FF}]")
	return _fa_re.search(s) != null

## Persian digits (like String.replace in faNum)
static func fa_num(v) -> String:
	var s := str(v)
	if I18n.is_en():
		return s
	var o := ""
	for ch in s:
		var c := ch.unicode_at(0)
		o += FA_DIGITS[c - 48] if c >= 48 and c <= 57 else ch
	return o

## number formatted like toLocaleString('fa-IR') ("۱٬۲۳۴")
static func fa(n) -> String:
	var neg: bool = float(n) < 0
	var s := str(absi(int(round(float(n)))))
	var o := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		o = s[i] + o
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			o = ("," if I18n.is_en() else "٬") + o
	return ("-" if neg else "") + fa_num(o)

static func en_num(n) -> String:
	var s := str(absi(int(n)))
	var o := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		o = s[i] + o
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			o = "," + o
	return ("-" if int(n) < 0 else "") + o

# ---- layout ----
const HUD_H := 150.0
const TAB_H := 186.0
const RADIUS := 44
const PAD := 42.0

## safe-area insets in viewport pixels (filled by main.gd)
static var safe_top := 0.0
static var safe_bottom := 0.0
static var safe_left := 0.0
static var safe_right := 0.0

# ---- styleboxes ----
static func box(bg: Color, radius := 44, border := 0.0, border_col := Color.TRANSPARENT, shadow := 0, shadow_col := Color(0, 0, 0, 0.5)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(int(round(border)))
		sb.border_color = border_col
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = shadow_col
	sb.anti_aliasing = true
	sb.corner_detail = 10
	return sb

static func glass_box(_accent := Color.TRANSPARENT, _glow := false) -> StyleBoxFlat:
	var sb := box(PANEL, 36, 2, LINE)  # flat v3: plain card, no glow / shadow / accent edge
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	return sb

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
