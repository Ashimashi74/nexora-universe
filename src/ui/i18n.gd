class_name I18n
extends RefCounted
## Bilingual UI (Persian default / English) on top of Godot's TranslationServer.
##
## Strings live in CSV tables  res://assets/i18n/ui.csv  (UI worker) and
## res://assets/i18n/game_hud.csv (GAME worker), columns:  keys,fa,en
##   • I18n.t("hub.create_room")      -> text for the current locale (falls back to fa, then the key)
##   • I18n.f("ساخت اتاق")             -> translate a Persian source string (consts / data tables);
##                                       returns it unchanged in fa or when unknown
##   • tr("hub.create_room") works too (key tables are registered with the TranslationServer).
## The CSVs use the "keep" importer, so they ship as-is and are parsed here (FileAccess.get_csv_line).
## If a table was imported by Godot's CSV importer instead (<name>.<locale>.translation), those
## resources are loaded.
## Language: Store profile key "lang" ("fa" | "en"), default "fa". I18n.set_lang() switches the
## locale, layout direction (RTL/LTR) and reloads the UI.

const TABLES := ["res://assets/i18n/ui.csv", "res://assets/i18n/game_hud.csv", "res://assets/i18n/menu_v2.csv", "res://assets/i18n/menu_v3.csv"]
const LANGS := ["fa", "en"]

static var lang := "fa"
## start alignment for text (RIGHT in Persian, LEFT in English); use instead of HORIZONTAL_ALIGNMENT_RIGHT
static var AR: int = HORIZONTAL_ALIGNMENT_RIGHT
## end alignment (LEFT in Persian, RIGHT in English)
static var AL: int = HORIZONTAL_ALIGNMENT_LEFT
## layout direction for rows / screens (RTL in Persian, LTR in English)
static var LD: int = Control.LAYOUT_DIRECTION_RTL
## set by set_lang(): main.gd skips the intro after a language reload
static var skip_intro := false

static var _loaded := false
static var _fa := {}       # key -> fa
static var _en := {}       # key -> en
static var _fa2en := {}    # fa source text -> en
static var _tr: Dictionary = {}  # locale -> Translation


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for loc in LANGS:
		var t := Translation.new()
		t.locale = loc
		_tr[loc] = t
	for path in TABLES:
		_load_table(path)
	for loc in LANGS:
		TranslationServer.add_translation(_tr[loc])
	var st := Engine.get_main_loop()
	var want := "fa"
	if st is SceneTree:
		var store: Node = (st as SceneTree).root.get_node_or_null("Store")
		if store and store.get("p") is Dictionary:
			want = str((store.get("p") as Dictionary).get("lang", "fa"))
	if OS.has_environment("NX_LANG"):  # test hook
		want = OS.get_environment("NX_LANG")
	_apply(want if want in LANGS else "fa")


static func _load_table(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		# imported by Godot's CSV importer: <base>.<locale>.translation next to the csv
		var base := path.get_basename()
		for loc in LANGS:
			var rp := "%s.%s.translation" % [base, loc]
			if ResourceLoader.exists(rp):
				var tr := load(rp) as Translation
				if tr:
					TranslationServer.add_translation(tr)
					for k in tr.get_message_list():
						var v := str(tr.get_message(k))
						if loc == "fa": _fa[str(k)] = v
						else: _en[str(k)] = v
		for k in _fa:
			if _en.has(k) and not _fa2en.has(_fa[k]):
				_fa2en[_fa[k]] = _en[k]
		return
	var head := f.get_csv_line()
	var ci := {}
	for i in head.size():
		ci[head[i].strip_edges().to_lower()] = i
	var ik: int = ci.get("keys", ci.get("key", 0))
	var ifa: int = ci.get("fa", 1)
	var ien: int = ci.get("en", 2)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= maxi(ik, maxi(ifa, ien)):
			continue
		var k := row[ik].strip_edges()
		if k == "" or k.begins_with("#"):
			continue
		var vfa := _unesc(row[ifa])
		var ven := _unesc(row[ien])
		if ven == "":
			ven = vfa
		_fa[k] = vfa
		_en[k] = ven
		(_tr["fa"] as Translation).add_message(k, vfa)
		(_tr["en"] as Translation).add_message(k, ven)
		# fa source text -> en is kept out of the TranslationServer on purpose: with the project's
		# fallback locale "en" every Persian Label would get auto-translated even in fa
		if vfa != "" and not _fa2en.has(vfa):
			_fa2en[vfa] = ven


static func _unesc(s: String) -> String:
	return s.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")


static func _apply(l: String) -> void:
	lang = l
	TranslationServer.set_locale(l)
	var fa := l == "fa"
	AR = HORIZONTAL_ALIGNMENT_RIGHT if fa else HORIZONTAL_ALIGNMENT_LEFT
	AL = HORIZONTAL_ALIGNMENT_LEFT if fa else HORIZONTAL_ALIGNMENT_RIGHT
	LD = Control.LAYOUT_DIRECTION_RTL if fa else Control.LAYOUT_DIRECTION_LTR
static func is_en() -> bool:
	ensure()
	return lang == "en"


## text for `key` in the current language
static func t(key: String) -> String:
	ensure()
	var d: Dictionary = _en if lang == "en" else _fa
	if d.has(key):
		return d[key]
	if _fa.has(key):
		return _fa[key]
	return key


## translate a Persian source string (const tables, data names); unchanged in fa / when unknown.
## Text that is not a whole known string (e.g. "League برنز", "فصل ۱") gets each Persian run /
## word translated when known, and Persian digits turned into Latin ones.
static func f(s) -> String:
	var txt := str(s)
	if lang != "en":
		return txt
	ensure()
	if _fa2en.has(txt):
		return _fa2en[txt]
	if not _has_fa(txt):
		return txt
	return _runs(txt)


static func _is_fa_ch(c: int) -> bool:
	return (c >= 0x0600 and c <= 0x06FF) or c == 0x200C


static func _has_fa(s: String) -> bool:
	for i in s.length():
		if _is_fa_ch(s.unicode_at(i)):
			return true
	return false


static func _runs(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		var c := s.unicode_at(i)
		if c >= 0x06F0 and c <= 0x06F9:  # Persian digit
			out += char(48 + c - 0x06F0)
			i += 1
		elif c == 0x066C:  # Arabic thousands separator
			out += ","
			i += 1
		elif _is_fa_ch(c):
			var j := i
			# a run of Persian words (letters, ZWNJ, single spaces between them)
			while j < n and (_is_fa_ch(s.unicode_at(j)) and not (s.unicode_at(j) >= 0x06F0 and s.unicode_at(j) <= 0x06F9) or (s[j] == " " and j + 1 < n and _is_fa_ch(s.unicode_at(j + 1)))):
				j += 1
			out += _words(s.substr(i, j - i))
			i = j
		else:
			out += s[i]
			i += 1
	return out


static func _words(run: String) -> String:
	if _fa2en.has(run):
		return _fa2en[run]
	var ws := run.split(" ")
	# longest known prefix group first
	var res: PackedStringArray = []
	var k := 0
	while k < ws.size():
		var hit := false
		for e in range(ws.size(), k, -1):
			var seg := " ".join(ws.slice(k, e))
			if _fa2en.has(seg):
				res.append(_fa2en[seg])
				k = e
				hit = true
				break
		if not hit:
			res.append(ws[k])
			k += 1
	return " ".join(res)


## switch language, persist it, and rebuild the whole UI (skipping the intro)
static func set_lang(l: String) -> void:
	ensure()
	if not l in LANGS or l == lang:
		return
	_apply(l)
	var st := Engine.get_main_loop()
	if st is SceneTree:
		var store: Node = (st as SceneTree).root.get_node_or_null("Store")
		if store and store.has_method("set_p"):
			store.call("set_p", {"lang": l})
		skip_intro = true
		(st as SceneTree).call_deferred("reload_current_scene")
