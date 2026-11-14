extends Node
## Local profile — port of src/store.tsx (DEFAULT, migrate, debounced save). Autoload name: Store.
## Store.p is the live profile Dictionary (camelCase keys exactly like the RN Profile type).
## Store.set_p(patch) merges + emits `changed` + saves 250 ms later. Store.update(func(p): return patch) for functional updates.

const D := preload("res://src/core/data.gd")

signal changed

const PATH := "user://profile.json"
const INT_KEYS := ["coins", "gems", "xp", "trophies", "played", "wins", "losses", "draws", "goalsFor", "goalsAgainst", "ball", "field", "form",
	"lastDaily", "streak", "aiLvl", "limit", "turnTime", "cupsWon", "winStreak", "bestStreak", "chests", "lastChest", "fieldsV"]

var p: Dictionary = {}
var ready_ok := false
var _save_timer: Timer

func default_profile() -> Dictionary:
	var free_teams: Array = []
	for t in D.TEAMS:
		if D.team_price(t) == 0: free_teams.append(t.id)
	var balls: Array = []
	for i in 36:
		if D.ball_price(i) == 0: balls.append(i)
	var fields: Array = []
	for i in D.FIELDS.size():
		if D.field_price(i) == 0: fields.append(i)
	fields.append(7)  # 7 = Stadium (old default, stays owned)
	return {
		"name": "Pilot", "coins": 600, "gems": 20, "xp": 0, "trophies": 0,
		"played": 0, "wins": 0, "losses": 0, "draws": 0, "goalsFor": 0, "goalsAgainst": 0,
		"team": "club0", "ball": 0, "field": D.DEFAULT_FIELD, "form": 0,
		"ownedTeams": free_teams, "ownedBalls": balls, "ownedFields": fields,
		"lastDaily": 0, "streak": 0,
		"sound": true, "music": true, "haptics": true, "aiLvl": 1, "limit": 3, "turnTime": 15,
		"cupsWon": 0, "winStreak": 0, "bestStreak": 0, "chests": 1, "lastChest": 0, "claimedAch": [], "quality": "high", "volume": 1.0,
		"oracle": true, "oracleTour": false, "fieldsV": D.FIELDS_VERSION,
	}

func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.25
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	p = default_profile()
	if FileAccess.file_exists(PATH):
		var s := FileAccess.get_file_as_string(PATH)
		var raw = JSON.parse_string(s)
		if raw is Dictionary:
			var q := default_profile()
			q["fieldsV"] = raw.get("fieldsV", 1)
			for k in raw: q[k] = raw[k]
			p = migrate(_normalize(q))
	ready_ok = true
	changed.emit()

## JSON brings numbers back as floats: restore ints so Array.has()/indexing behave
func _normalize(q: Dictionary) -> Dictionary:
	for k in INT_KEYS:
		if q.has(k) and (q[k] is float or q[k] is int): q[k] = int(q[k])
	for k in ["ownedBalls", "ownedFields"]:
		var a: Array = []
		for v in q.get(k, []): a.append(int(v))
		q[k] = a
	if q.has("volume"): q["volume"] = float(q["volume"])
	return q

func _free_fields() -> Array:
	var a: Array = []
	for i in D.FIELDS.size():
		if D.field_price(i) == 0: a.append(i)
	return a

func migrate(q: Dictionary) -> Dictionary:
	var n := q.duplicate(true)
	if int(n.get("fieldsV", 1)) < 2:
		var old: int = int(n.field) if (n.get("field") is int or n.get("field") is float) else 6
		var of: Array = []
		for i in n.get("ownedFields", []): of.append(int(i) + 1)
		n.ownedFields = of
		n.field = D.DEFAULT_FIELD if old == 6 else old + 1
		n.fieldsV = 2
	var seen := {}
	var fl: Array = []
	for i in _free_fields() + [7] + Array(n.get("ownedFields", [])):
		var v := int(i)
		if seen.has(v) or v < 0 or v >= D.FIELDS.size(): continue
		seen[v] = true; fl.append(v)
	n.ownedFields = fl
	if not (int(n.field) >= 0 and int(n.field) < D.FIELDS.size()) or not fl.has(int(n.field)): n.field = D.DEFAULT_FIELD
	var ts := {}
	var tl: Array = []
	var free_teams: Array = []
	for t in D.TEAMS:
		if D.team_price(t) == 0: free_teams.append(t.id)
	for id in free_teams + Array(n.get("ownedTeams", [])):
		if ts.has(id): continue
		ts[id] = true; tl.append(id)
	n.ownedTeams = tl
	var ok := false
	for t in D.TEAMS:
		if t.id == n.team: ok = true; break
	if not ok: n.team = "club0"   # also catches discs removed by the art audit (Data.REMOVED_TEAMS)
	if not (int(n.get("form", 0)) >= 0 and int(n.get("form", 0)) < D.FORMS.size()): n.form = 0
	return n

func set_p(patch: Dictionary) -> void:
	for k in patch: p[k] = patch[k]
	_save_timer.start()
	changed.emit()

## functional update like set(q => ({...})): fn receives the current profile and returns a patch
func update(fn: Callable) -> void:
	set_p(fn.call(p))

func save_now() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(p)); f.close()

func reset() -> void:
	p = default_profile()
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	changed.emit()

func level() -> Dictionary: return D.level(int(p.xp))
func league() -> Dictionary: return D.league(int(p.trophies))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _save_timer and not _save_timer.is_stopped(): _save_timer.stop(); save_now()
