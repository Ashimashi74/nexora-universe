class_name UD
extends RefCounted
## UI-side bridge to the GAME/NET singletons (Data, Store, Sfx, Supa) + safe fallbacks.
## Every cross-worker call goes through here with has_method()/get() guards, so the UI never
## crashes (or fails to parse) when another worker's API differs or is not there yet.
## Fallback tables/formulas are 1:1 ports of src/game/data.ts, meta.ts, util.ts and store.tsx.

# ------------------------------------------------------------------ services
static func node(n: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(n)
	return null

static func has(n: String, m: String) -> bool:
	var s := node(n)
	return s != null and s.has_method(m)

static func callv_safe(n: String, m: String, args := [], fallback = null):
	var s := node(n)
	if s and s.has_method(m):
		return s.callv(m, args)
	return fallback

static func dget(name: String, fallback = null):
	var d := node("Data")
	if d:
		var v = d.get(name)
		if v != null:
			return v
	return fallback

static var _local_p := {}

static func p() -> Dictionary:
	var s := node("Store")
	if s:
		var v = s.get("p")
		if v is Dictionary:
			return v
	if _local_p.is_empty():
		_local_p = default_profile()
	return _local_p

static func pv(key: String, def = null):
	var d := p()
	if d.has(key):
		return d[key]
	var dp := default_profile()
	return dp.get(key, def)

static func set_p(patch: Dictionary) -> void:
	var s := node("Store")
	if s and s.has_method("set_p"):
		s.set_p(patch)
		return
	var d := p()
	for k in patch:
		d[k] = patch[k]

static func reset_store() -> void:
	if has("Store", "reset"):
		node("Store").reset()
	else:
		_local_p = default_profile()

static func sfx(key: String, vol := 1.0) -> void:
	var s := node("Sfx")
	if s and s.has_method("play"):
		s.play(key, vol)

static func haptic(kind := "light") -> void:
	var s := node("Sfx")
	if s and s.has_method("haptic"):
		s.haptic(kind)

static func menu_music(on: bool) -> void:
	var s := node("Sfx")
	if s == null:
		return
	if s.has_method("menu_music"):
		s.menu_music(on)
	elif s.has_method("music"):
		s.music(on)

static func apply_prefs() -> void:
	callv_safe("Sfx", "apply_prefs")

## signed-in online profile (Supa) if NET exposes one, else {}
static func online_profile() -> Dictionary:
	var s := node("Supa")
	if s == null:
		return {}
	for k in ["profile"]:
		var v = s.get(k)
		if v is Dictionary and not v.is_empty():
			return v
	return {}

static func signed_in() -> bool:
	var r = callv_safe("Supa", "signed_in", [], false)
	return r == true

# ------------------------------------------------------------------ textures
static var _tex := {}

static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex[path] = t
	return t

static func ui(n: String) -> Texture2D: return art(n.substr(1)) if n.begins_with("@") else tex("res://assets/g/ui/%s.webp" % n)
## new menu art (assets/ui): "mascot", "logo", "ic_quick", "bg/home" ...
static func art(n: String) -> Texture2D: return tex("res://assets/ui/%s.webp" % n)
static func ui2(n: String) -> Texture2D: return tex("res://assets/g/ui2/%s.webp" % n)
static func menu(n: String) -> Texture2D: return tex("res://assets/g/menu/%s.webp" % n)

static func team_key(t: Dictionary) -> String:
	return "%s%02d" % [t.get("cat", "club"), int(t.get("idx", 0))]

static func team_tex(id_or_team) -> Texture2D:
	var t: Dictionary = id_or_team if id_or_team is Dictionary else team_by_id(str(id_or_team))
	var k := team_key(t)
	var cat := data_cat("TEAM_IMG")
	if not cat.is_empty():
		var r0 := tex(str(cat.get(k, ""))) if cat.has(k) else null
		if r0:
			return r0
		for v in cat.values():
			return tex(str(v))
	return tex("res://assets/g/teams/%s.webp" % k)

## piece art for an online catalogue disc: local team by id, then by name, else null (no
## misleading fallback crest)
static func disc_tex(id: String, name_ := "") -> Texture2D:
	var ts := teams()
	team_by_id(id)
	if _team_idx.has(id):
		return team_tex(_team_idx[id])
	var nl := name_.strip_edges().to_lower()
	if nl != "":
		for t in ts:
			if str(t.get("name", "")).to_lower() == nl:
				return team_tex(t)
	var m := RegEx.create_from_string("^([a-z]+)(\\d+)$").search(id)
	if m:
		var cat := data_cat("TEAM_IMG")
		var k := "%s%02d" % [m.get_string(1), int(m.get_string(2))]
		if cat.has(k):
			return tex(str(cat[k]))
	return null

## Data's piece catalogs (TEAM_IMG / BALL_IMG): the only source of piece art paths.
static func data_cat(n: String) -> Dictionary:
	var d := node("Data")
	if d == null or d.get_script() == null:
		return {}
	var m: Dictionary = (d.get_script() as Script).get_script_constant_map()
	var v = m.get(n, d.get(n))
	return v if v is Dictionary else {}

static func ball_tex(i: int) -> Texture2D:
	var cat := data_cat("BALL_IMG")
	if not cat.is_empty():
		var r := tex(str(cat.get("b%d" % i, cat.get("b0", ""))))
		if r:
			return r
	return tex("res://assets/g/balls/b%d.webp" % i)

static func field_thumb(i: int) -> Texture2D:
	var f := field(i)
	return tex("res://assets/g/fthumb/%s.webp" % f.get("id", "pitch"))

static func item_tex(it: Dictionary) -> Texture2D:
	match str(it.get("kind", "")):
		"team": return team_tex(str(it.get("id", "club0")))
		"ball": return ball_tex(int(it.get("id", 0)))
		"field": return field_thumb(int(it.get("id", 0)))
	return ui2("x_coins")

# ------------------------------------------------------------------ static tables (port of data.ts)
const CATS = preload("res://src/core/data.gd").CATS
const FIELD_LIST := [["pitch", "NEXORA Pitch"], ["forest", "Forest"], ["ice", "Ice"], ["ocean", "Ocean"], ["street", "Street"], ["streetarena", "Street Arena"], ["lava", "Lava"], ["stadium", "Stadium"], ["checker", "Checker"], ["futsal", "Futsal"], ["arena", "Arena"], ["arena2", "Grand Arena"], ["desert", "Desert"], ["grove", "Grove"], ["pool", "Pool"], ["neon", "Neon Tech"], ["royal", "Royal"], ["mahogany", "Mahogany"], ["leather", "Leather"], ["aqua", "Aquarium"], ["asphalt", "Asphalt"], ["court", "Court"], ["cyberbox", "Cyber Box"], ["realmadrid", "Real Madrid"], ["psg", "Paris SG"], ["acmilan", "AC Milan"], ["barcelona", "FC Barcelona"], ["persepolis", "Persepolis"], ["esteghlal", "Esteghlal"], ["mancity", "Man City"]]
const BALL_NAMES := ["Bolt", "Prism", "Wave", "Starlight", "Classic", "Rainbow", "Neon", "Yin", "Fire", "Blade", "Ghost", "Ember", "Plasma", "Noir Copper", "Space Modern", "Purple Sky", "Black Lux", "Electron", "Cobalt Gold", "Aurora", "Crimson", "Teal Storm", "Royal Gold", "Gold Rush", "Classic Red", "Luxury", "Noir Chrome", "Violet Strike", "Emerald Edge", "Royal Blue Gold", "Crimson Noir", "Blaze Orange", "Aqua Wave", "Sunset Pro", "Elite Cobalt", "Crown Luxury"]
const TRAILS := [["#19b4ff", "#8fe6ff", "#ffffff"], ["#ff7bd5", "#7bd7ff", "#ffffff"], ["#2fe0d0", "#9ff7ef", "#ffffff"], ["#5cb6ff", "#bfe3ff", "#ffffff"], ["#e8ecf2", "#9aa3b0", "#ffffff"], ["#ff5b5b", "#ffd23a", "#5bff8a", "#5bd0ff", "#c05bff"], ["#4dff2a", "#b6ff9a", "#ffffff"], ["#ffffff", "#9b5cff", "#000000"], ["#ff8a1f", "#ffd24a", "#fff3c4"], ["#ff2b3a", "#ff8a92", "#ffffff"], ["#dbe7ff", "#8fb0ff", "#ffffff"], ["#ff6a1f", "#ffb347", "#fff0c8"], ["#2f8bff", "#7fc6ff", "#ffffff"], ["#d9915b", "#f2c9a0", "#fff4e6"], ["#2f7bff", "#8fd0ff", "#ffffff"], ["#9b5cff", "#e0b8ff", "#ffffff"], ["#e0a82e", "#ffe08a", "#fff7d6"], ["#2f6bff", "#7fb4ff", "#ffffff"], ["#2f8bff", "#e8b84a", "#ffffff"], ["#1fd6a0", "#3b9bff", "#ffffff"], ["#ff2b3a", "#ff8a92", "#ffffff"], ["#18d8c0", "#9ff5e6", "#ffffff"], ["#2f5bff", "#ffc83a", "#fff3c4"], ["#ffffff", "#e0a82e", "#000000"], ["#ff4a4a", "#9aa3b0", "#ffffff"], ["#e0a82e", "#fff0b0", "#ffffff"], ["#2f8bff", "#c0c8d8", "#ffffff"], ["#9b5cff", "#ffffff", "#ffffff"], ["#4dff2a", "#c0c8d8", "#ffffff"], ["#e8b84a", "#2f6bff", "#ffffff"], ["#ff2b3a", "#ff8a92", "#ffffff"], ["#ff8a1f", "#ffd24a", "#ffffff"], ["#3b9bff", "#2fe08a", "#ffffff"], ["#ff4a7a", "#9b5cff", "#ffffff"], ["#2f6bff", "#ffffff", "#ffffff"], ["#ffd56b", "#ffffff", "#ffffff"]]
const VIP_PRICES := [260, 275, 290, 255, 300, 265, 280, 270, 0, 295, 285, 250]
const FORMS := [["1-2-2", "Balanced", [[.09, 1], [.22, 2], [.36, 2]]], ["2-2-1", "Cautious", [[.10, 2], [.24, 2], [.37, 1]]], ["3-1-1", "Wall", [[.10, 3], [.25, 1], [.37, 1]]], ["2-1-2", "Diamond", [[.10, 2], [.24, 1], [.37, 2]]], ["1-3-1", "Midfield", [[.09, 1], [.23, 3], [.37, 1]]], ["1-1-3", "Attack", [[.09, 1], [.22, 1], [.36, 3]]]]
const RARITY := [{"n": "COMMON", "c": "#8ea3d6"}, {"n": "RARE", "c": "#4fe3ff"}, {"n": "EPIC", "c": "#b46bff"}, {"n": "LEGENDARY", "c": "#ffd257"}]
const LEAGUES := [["BRONZE", 0], ["SILVER", 300], ["GOLD", 800], ["PLATINUM", 1600], ["DIAMOND", 3000], ["NEXORA", 5000]]
const LEAGUE_FA := {"BRONZE": "برنز", "SILVER": "نقره", "GOLD": "طلا", "PLATINUM": "پلاتین", "DIAMOND": "الماس", "NEXORA": "نکسورا"}
const MEDAL := ["medal_bronze", "medal_silver", "medal_gold", "medal_epic", "shield_epic", "shield_crown"]
const DAILY := [{"coins": 100, "gems": 0}, {"coins": 150, "gems": 0}, {"coins": 250, "gems": 0}, {"coins": 300, "gems": 0}, {"coins": 400, "gems": 0}, {"coins": 450, "gems": 0}, {"coins": 800, "gems": 0}]
const ACHS := [
	{"id": "first", "name": "اولین قدم", "desc": "یک بازی انجام بده", "icon": "x_ball", "max": 1, "coins": 100, "gems": 0},
	{"id": "win5", "name": "برنده", "desc": "۵ بازی ببر", "icon": "x_medal", "max": 5, "coins": 250, "gems": 0},
	{"id": "goals25", "name": "گلزن", "desc": "۲۵ گل بزن", "icon": "x_statue", "max": 25, "coins": 300, "gems": 0},
	{"id": "streak3", "name": "شکست‌ناپذیر", "desc": "۳ برد پشت سر هم", "icon": "x_star", "max": 3, "coins": 350, "gems": 0},
	{"id": "cup1", "name": "قهرمان", "desc": "جام نکسورا را ببر", "icon": "x_trophy", "max": 1, "coins": 500, "gems": 0},
	{"id": "collect", "name": "کلکسیونر", "desc": "۱۵ دیسک ویژه باز کن", "icon": "x_team", "max": 15, "coins": 400, "gems": 0},
	{"id": "win25", "name": "اسطوره", "desc": "۲۵ بازی ببر", "icon": "x_crown", "max": 25, "coins": 800, "gems": 0},
	{"id": "gold", "name": "لیگ طلا", "desc": "به ۸۰۰ جام برس", "icon": "x_shield", "max": 800, "coins": 600, "gems": 0},
]
const CAT_FA = preload("res://src/core/data.gd").CAT_FA
const CAT_ORDER = preload("res://src/core/data.gd").CAT_ORDER
const CHEST_EVERY := 4 * 3600 * 1000
const DAY := 86400000

static var _teams: Array = []

static func teams() -> Array:
	var d = dget("TEAMS")
	if d is Array and not d.is_empty():
		return d
	if _teams.is_empty():
		for c in CATS:
			var i := 0
			for n in c[2]:
				_teams.append({"id": "%s%d" % [c[0], i], "cat": c[0], "name": n, "idx": i})
				i += 1
	return _teams

static var _team_idx := {}

static func team_by_id(id: String) -> Dictionary:
	var ts := teams()
	if _team_idx.size() != ts.size():
		_team_idx.clear()
		for t in ts:
			_team_idx[t["id"]] = t
	return _team_idx.get(id, ts[0])

static func teams_of(cat: String) -> Array:
	return teams().filter(func(t): return t["cat"] == cat)

static func fields() -> Array:
	var d = dget("FIELDS")
	if d is Array and not d.is_empty():
		return d
	var o := []
	for f in FIELD_LIST:
		o.append({"id": f[0], "name": f[1]})
	return o

static func field(i: int) -> Dictionary:
	var fs := fields()
	return fs[clampi(i, 0, fs.size() - 1)]

static func forms() -> Array:
	var d = dget("FORMS")
	return d if d is Array and not d.is_empty() else FORMS

static func ball_names() -> Array:
	var d = dget("BALL_NAMES")
	return d if d is Array and not d.is_empty() else BALL_NAMES

static func ball_name(i: int) -> String:
	var b := ball_names()
	return str(b[clampi(i, 0, b.size() - 1)])

static func trail(i: int) -> Array:
	var tr = dget("TRAILS")
	if tr is Array and not tr.is_empty():
		var e = tr[i % tr.size()]
		if e is Dictionary:
			return e.get("c", [])
		return e
	return TRAILS[i % TRAILS.size()]

static func slots(fi: int) -> Array:
	if has("Data", "slots"):
		return node("Data").slots(fi)
	var o := []
	for row in forms()[fi][2]:
		var ny: float = row[0]
		var c: int = int(row[1])
		for i in c:
			o.append([0.5 if c == 1 else (.27 + .46 * i if c == 2 else .17 + .33 * i), ny])
	return o

static func team_price(t: Dictionary) -> int:
	if has("Data", "team_price"):
		return int(node("Data").team_price(t))
	var c: String = t["cat"]
	var idx: int = int(t["idx"])
	if c == "vip":
		var v: int = VIP_PRICES[idx] if idx < VIP_PRICES.size() else 0
		return v if v else 250
	if c == "club" or c == "nat": return 0
	if c == "leg": return 520
	if c == "emb": return 220
	if c == "elite": return 0 if idx == 0 else 160
	if c == "chrome": return 180
	return 120

static func ball_price(i: int) -> int:
	if has("Data", "ball_price"):
		return int(node("Data").ball_price(i))
	return 0 if i < 6 else 60 + (i % 7) * 20

static func field_price(i: int) -> int:
	if has("Data", "field_price"):
		return int(node("Data").field_price(i))
	return 0 if i < 5 else 80 + ((i - 1) % 5) * 20

static func rarity(t: Dictionary) -> int:
	var c: String = t["cat"]
	if c == "vip" or c == "leg": return 3
	if c in ["lux", "car", "emb", "chrome"]: return 2
	if c == "spt" or c == "elite": return 1
	return 0

static func rarity_info(r: int) -> Dictionary:
	var e: Dictionary = RARITY[clampi(r, 0, 3)]
	return {"n": e["n"], "c": Color(e["c"])}

static func level(xp: int) -> Dictionary:
	if has("Data", "level"):
		var r = node("Data").level(xp)
		if r is Dictionary and r.has("level"):
			return r
	var l := 1
	var need := 100
	var x := xp
	while x >= need:
		x -= need
		l += 1
		need = int(round(need * 1.25))
	return {"level": l, "cur": x, "need": need}

static func league(t: int) -> Dictionary:
	var i := 0
	while i + 1 < LEAGUES.size() and t >= LEAGUES[i + 1][1]:
		i += 1
	return {"name": LEAGUES[i][0], "idx": i, "from": LEAGUES[i][1], "to": LEAGUES[i + 1][1] if i + 1 < LEAGUES.size() else LEAGUES[i][1] + 2000}

static func ach_cur(a: Dictionary, q: Dictionary) -> int:
	match str(a["id"]):
		"first": return int(q.get("played", 0))
		"win5", "win25": return int(q.get("wins", 0))
		"goals25": return int(q.get("goalsFor", 0))
		"streak3": return int(q.get("bestStreak", 0))
		"cup1": return int(q.get("cupsWon", 0))
		"collect":
			return (q.get("ownedTeams", []) as Array).filter(func(id): return not str(id).begins_with("club") and not str(id).begins_with("nat")).size()
		"gold": return int(q.get("trophies", 0))
	return 0

# ------------------------------------------------------------------ meta (port of meta.ts)
static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

static func all_items(q: Dictionary) -> Array:
	var out := []
	var ob: Array = q.get("ownedBalls", [])
	var of: Array = q.get("ownedFields", [])
	for i in 36:
		var pr := ball_price(i)
		if pr > 0 and not _has_num(ob, i):
			out.append({"kind": "ball", "id": i, "name": ball_name(i), "price": pr, "rar": 2 if pr > 140 else 1})
	var fs := fields()
	for i in fs.size():
		var pr := field_price(i)
		if pr > 0 and not _has_num(of, i):
			out.append({"kind": "field", "id": i, "name": fs[i]["name"], "price": pr, "rar": 2 if pr > 140 else 1})
	return out

static func _has_num(arr: Array, v: int) -> bool:
	for x in arr:
		if int(x) == v:
			return true
	return false

static func grant(it: Dictionary, q: Dictionary) -> Dictionary:
	match str(it["kind"]):
		"team":
			var a: Array = (q.get("ownedTeams", []) as Array).duplicate(); a.append(it["id"]); return {"ownedTeams": a}
		"ball":
			var a: Array = (q.get("ownedBalls", []) as Array).duplicate(); a.append(int(it["id"])); return {"ownedBalls": a}
		_:
			var a: Array = (q.get("ownedFields", []) as Array).duplicate(); a.append(int(it["id"])); return {"ownedFields": a}

static func daily_deals(q: Dictionary, n := 4) -> Array:
	var items := all_items(q)
	var day := int(now_ms() / DAY)
	var h: int = (day * 2654435761) & 0xFFFFFFFF
	var a := items.duplicate()
	for i in range(a.size() - 1, 0, -1):
		h = (h ^ (h << 13)) & 0xFFFFFFFF
		h = (h ^ (h >> 17)) & 0xFFFFFFFF
		h = (h ^ (h << 5)) & 0xFFFFFFFF
		var r := float(h % 10000) / 10000.0
		var j := int(floor(r * (i + 1)))
		var tmp = a[i]; a[i] = a[j]; a[j] = tmp
	var o := []
	for it in a.slice(0, n):
		var c: Dictionary = it.duplicate()
		c["price"] = int(round(it["price"] * .7 / 5.0)) * 5
		o.append(c)
	return o

static func roll_chest(q: Dictionary, premium: bool) -> Dictionary:
	if has("Data", "roll_chest"):
		var r = node("Data").roll_chest(q, premium)
		if r is Dictionary and r.has("coins"):
			return r
	var items := all_items(q).filter(func(i): return i["rar"] >= 2 if premium else true)
	if items.size() and randf() < (.75 if premium else .4):
		var w := items.map(func(i): return i["rar"] if premium else 4 - i["rar"])
		var sum := 0.0
		for x in w: sum += x
		var x := randf() * sum
		for i in items.size():
			x -= w[i]
			if x <= 0:
				return {"item": items[i], "coins": 60 if premium else 20, "gems": 0}
	return {"coins": (320 + int(round(randf() * 200))) if premium else (80 + int(round(randf() * 120))), "gems": 0}

# ------------------------------------------------------------------ discs (NET catalog bridge)
## stats {power, accuracy} from NET's disc catalog if loaded, else the RN fallback
static func disc_stats(id: String) -> Dictionary:
	var dz := discs()
	if dz and dz.has_method("stats"):
		var r = dz.stats(id)
		if r is Dictionary and r.has("power"):
			return r
	# same fallback as Data.disc_stats (single source of truth offline)
	if has("Data", "disc_stats"):
		var d = node("Data").disc_stats(id)
		if d is Dictionary and d.has("power"):
			return d
	var t := team_by_id(id)
	var base := 8 if t["cat"] in ["leg", "vip"] else (5 if t["cat"] in ["club", "nat"] else 6)
	return {"power": base, "accuracy": base}

static func is_free_disc(id: String) -> bool:
	return true

static func disc_owned(id: String) -> bool:
	return true

static func disc_price(id: String) -> int:
	return 0

## gem-priced, not-owned discs from the online catalog: Array of {id,name,price_gems,power,accuracy}
static func gem_discs() -> Array:
	return []

## NET disc catalog node (Supa.discs, src/net/discs.gd) or null
static func discs() -> Object:
	var sp := node("Supa")
	if sp:
		var d = sp.get("discs")
		if d is Object and is_instance_valid(d):
			return d
	return node("Discs")

## buy (if needed) + equip a disc through NET; returns true when equipped
static func buy_and_equip_disc(id: String, name_: String) -> bool:
	var dz := discs()
	if dz == null or not dz.has_method("buy_and_equip"):
		var nav := node("Nav")
		if nav: nav.toast(I18n.t("ud.you_need_to_be_online"), "err")
		return false
	var ok: bool = await dz.buy_and_equip(id, name_)
	if ok:
		set_p({"team": id})
		sfx("win")
		haptic("success")
	return ok

static func set_scene(s: String) -> void:
	var n := node("Sfx")
	if n and n.has_method("set_scene"):
		n.set_scene(s)

# ------------------------------------------------------------------ default profile (store.tsx DEFAULT)
static func default_profile() -> Dictionary:
	var free_teams := []
	for t in teams():
		if team_price(t) == 0:
			free_teams.append(t["id"])
	var ob := []
	for i in 36:
		if ball_price(i) == 0: ob.append(i)
	var of := []
	for i in fields().size():
		if field_price(i) == 0: of.append(i)
	of.append(7)
	return {
		"name": "Pilot", "coins": 600, "gems": 20, "xp": 0, "trophies": 0,
		"played": 0, "wins": 0, "losses": 0, "draws": 0, "goalsFor": 0, "goalsAgainst": 0,
		"team": "club0", "ball": 0, "field": 0, "form": 0,
		"ownedTeams": free_teams, "ownedBalls": ob, "ownedFields": of,
		"lastDaily": 0, "streak": 0,
		"sound": true, "music": true, "haptics": true, "aiLvl": 1, "limit": 3, "turnTime": 15,
		"cupsWon": 0, "winStreak": 0, "bestStreak": 0, "chests": 1, "lastChest": 0, "claimedAch": [], "quality": "high", "volume": 1.0, "oracle": true, "oracleTour": false, "fieldsV": 2,
	}

static func daily_ready() -> bool:
	return now_ms() - int(pv("lastDaily", 0)) > DAY

static func chest_ready() -> bool:
	return now_ms() - int(pv("lastChest", 0)) > CHEST_EVERY

## claim an achievement reward (RN Profile.claim); returns true if granted
static func claim_ach(id: String) -> bool:
	var q := p()
	var claimed: Array = (q.get("claimedAch", []) as Array).duplicate()
	if id in claimed:
		return false
	var a: Dictionary = {}
	for x in ACHS:
		if x["id"] == id:
			a = x
	if a.is_empty() or ach_cur(a, q) < int(a["max"]):
		return false
	claimed.append(id)
	set_p({"claimedAch": claimed, "coins": int(q.get("coins", 0)) + int(a["coins"]), "gems": int(q.get("gems", 0)) + int(a["gems"])})
	sfx("ui")
	haptic("heavy")
	var ml := Engine.get_main_loop() as SceneTree
	var nav := ml.root.get_node_or_null("Nav")
	if nav:
		nav.toast(I18n.t("ud.x_coins_x_gems") % [NX.fa(a["coins"]), NX.fa(a["gems"])], "ok")
		nav.refresh_chrome()
	return true

## natural single-line pixel width of a Label's text with its current font + size
## (used to give autowrap labels a sane minimum width instead of ~0)
static func text_w(l: Label) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null:
		return 0.0
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w
