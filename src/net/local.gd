extends Node
## Local autoload — v3 port of RN v6 src/net/local.ts. Local save that survives restarts and works offline:
##   • Local.load_v(key, fallback) / Local.save_v(key, value) / Local.drop(key): JSON files under user://local/
##   • Local.cached(key, loader: Callable) -> {data, offline, error}: stale-while-revalidate (last copy when offline)
##   • outbox: actions queued while offline (tournament registration, admin application, ...) are replayed when online:
##       var r := await Local.rpc_or_queue("register_tournament", {...}, "ثبت‌نام ...")   # r.queued == true when queued
##     replayed every 60 s, on app resume and on sign-in; result reported by the `outbox_done(label, ok, error)` signal.
## Keys (LK): tour.draft, tour.mine, tour.list.<tab>, tour.d.<id>, oracle.chat, admin.state, outbox, prof.<id>

signal outbox_done(label: String, ok: bool, error: String)

const DIR := "user://local/"
const LK := {
	"tour_draft": "tour.draft", "my_tours": "tour.mine", "tour_list": "tour.list", "oracle_chat": "oracle.chat",
	"admin": "admin.state", "outbox": "outbox",
}

var _flushing := false
var _timer: Timer

static func tour_detail_key(id: String) -> String: return "tour.d." + id
static func profile_key(id: String) -> String: return "prof." + id

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_timer = Timer.new()
	_timer.wait_time = 60.0
	_timer.autostart = true
	_timer.timeout.connect(flush_outbox)
	add_child(_timer)
	var sp := get_node_or_null("/root/Supa")
	if sp:
		if sp.has_signal("app_resumed"):
			sp.app_resumed.connect(func(_a): flush_outbox())
		if sp.has_signal("auth_changed"):
			sp.auth_changed.connect(func(_e, s): if s != null: flush_outbox())
	# toast the result like RN wireOutbox
	outbox_done.connect(func(label: String, ok: bool, _e: String):
		var nav := get_node_or_null("/root/Nav")
		if nav and nav.has_method("toast"):
			nav.toast(("انجام شد: " if ok else "ناموفق: ") + label, "ok" if ok else "err"))
	flush_outbox.call_deferred()

static func _path(key: String) -> String:
	return DIR + key.replace("/", "_").replace(":", "_") + ".json"

func load_v(key: String, fallback: Variant = null) -> Variant:
	var p := _path(key)
	if not FileAccess.file_exists(p): return fallback
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return fallback if v == null else v

func save_v(key: String, v: Variant) -> void:
	var f := FileAccess.open(_path(key), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v))
		f.close()

func drop(key: String) -> void:
	var p := _path(key)
	if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func is_net_error(r: Dictionary) -> bool:
	if r.get("ok", false): return false
	if int(r.get("status", -1)) == 0: return true
	var m := str(r.get("error", "")) + " " + str(r.get("raw", ""))
	return m.containsn("network") or m.containsn("timeout") or m.containsn("fetch")

## stale-while-revalidate: loader is a coroutine returning {ok, data, error}. Returns
## {data, offline: bool, error: String, from_cache: bool}; on success the fresh copy is saved under key.
func cached(key: String, loader: Callable) -> Dictionary:
	var r: Dictionary = await loader.call()
	if r.get("ok", false):
		save_v(key, {"at": Time.get_unix_time_from_system(), "d": r.get("data")})
		return {"data": r.get("data"), "offline": false, "error": "", "from_cache": false}
	var c: Variant = load_v(key, null)
	var d: Variant = c.get("d") if c is Dictionary else null
	return {"data": d, "offline": is_net_error(r), "error": str(r.get("error", "")), "from_cache": d != null}

# ------------------------------------------------------------------ outbox
func enqueue(fn: String, args: Dictionary, label: String) -> void:
	var q: Array = load_v(LK.outbox, [])
	q.append({"id": "%x" % randi(), "fn": fn, "args": args, "label": label, "at": Time.get_unix_time_from_system(), "tries": 0})
	save_v(LK.outbox, q)

func pending() -> Array:
	return load_v(LK.outbox, [])

## call the rpc; if the device is offline, queue it and return {ok: true, queued: true}
func rpc_or_queue(fn: String, args: Dictionary, label: String) -> Dictionary:
	var sp := get_node_or_null("/root/Supa")
	var r: Dictionary = await sp.call_rpc(fn, args) if sp else {"ok": false, "status": 0, "error": "offline"}
	if not r.get("ok", false) and is_net_error(r):
		enqueue(fn, args, label)
		return {"ok": true, "queued": true, "data": null, "error": ""}
	return r

func flush_outbox() -> void:
	if _flushing: return
	var sp := get_node_or_null("/root/Supa")
	if sp == null or not sp.signed_in(): return
	var q: Array = load_v(LK.outbox, [])
	if q.is_empty(): return
	_flushing = true
	var keep: Array = []
	for it in q:
		if not (it is Dictionary): continue
		var r: Dictionary = await sp.call_rpc(str(it.get("fn", "")), it.get("args", {}) if it.get("args") is Dictionary else {})
		if r.get("ok", false):
			outbox_done.emit(str(it.get("label", "")), true, "")
		elif is_net_error(r) and int(it.get("tries", 0)) < 20:
			it["tries"] = int(it.get("tries", 0)) + 1
			keep.append(it)
		else:
			outbox_done.emit(str(it.get("label", "")), false, str(r.get("error", "")))
	save_v(LK.outbox, keep)
	_flushing = false
