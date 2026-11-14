extends Node
## Disc catalog (gem prices + power/accuracy) and the signed-in user's inventory (port of net/discs.tsx).
## Created by Supa as its child: use `Supa.discs`. The catalog is public and cached on disk so offline
## matches use the real stats too.
##   Supa.discs.stats(id) -> {power, accuracy}      Supa.discs.price(id) -> int
##   Supa.discs.is_free(id) / has(id)                 await Supa.discs.buy(id) / equip(id) / buy_and_equip(id, name)
##   Supa.discs.catalog {id: row}  owned {id: true}  loaded  equipped()   signal changed

signal changed

const CACHE := "user://discs.v1.json"

var catalog := {}
var owned := {}
var loaded := false
var _inv_ch: RtChannel = null
var _uid := ""

func _ready() -> void:
	if FileAccess.file_exists(CACHE):
		var f := FileAccess.open(CACHE, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if v is Dictionary and not v.is_empty():
				catalog = v
				loaded = true
	var supa := get_parent()
	if supa and supa.has_signal("auth_changed"):
		supa.auth_changed.connect(_on_auth)
	load_catalog()

func _supa() -> Node:
	return get_parent()

func _on_auth(_ev: String, _s: Variant) -> void:
	var u: String = _supa().uid()
	if u == _uid:
		return
	_uid = u
	load_catalog()
	if _inv_ch:
		_supa().remove_channel(_inv_ch)
		_inv_ch = null
	owned = {}
	changed.emit()
	if u == "":
		return
	load_owned()
	_inv_ch = _supa().channel("inv:" + u)
	_inv_ch.on_postgres("*", "public", "inventory", "user_id=eq." + u, func(_c: Dictionary) -> void: load_owned())
	_inv_ch.subscribe()

func load_catalog() -> void:
	var r: Dictionary = await _supa().select("discs", "select=*")
	if not r.ok or not (r.data is Array) or r.data.is_empty():
		return
	var m := {}
	for d in r.data:
		if d is Dictionary:
			m[str(d.id)] = d
	catalog = m
	loaded = true
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m))
		f.close()
	changed.emit()

func load_owned() -> void:
	var u: String = _supa().uid()
	if u == "":
		return
	var r: Dictionary = await _supa().select("inventory", "select=disc_id&user_id=eq." + u)
	if r.ok and r.data is Array and _supa().uid() == u:
		var o := {}
		for x in r.data:
			o[str(x.disc_id)] = true
		owned = o
		changed.emit()

## deterministic fallback until the catalog has loaded once (same as RN)
func _fallback(id: String) -> Dictionary:
	var cat := ""
	var data := get_node_or_null("/root/Data")
	if data:
		for t in data.TEAMS:
			if str(t.id) == id:
				cat = str(t.cat)
				break
	var base := 8 if (cat == "leg" or cat == "vip") else (5 if (cat == "club" or cat == "nat") else 6)
	return {"power": base, "accuracy": base}

func stats(id: Variant) -> Dictionary:
	var k := str(id) if id != null else ""
	if k != "" and catalog.has(k):
		return {"power": float(catalog[k].get("power", 5)), "accuracy": float(catalog[k].get("accuracy", 5))}
	return _fallback(k if k != "" else "club0")

func price(id: String) -> int:
	return int(catalog[id].get("price_gems", 0)) if catalog.has(id) else 0

func is_free(id: String) -> bool:
	if catalog.has(id):
		return int(catalog[id].get("price_gems", 0)) == 0
	return RegEx.create_from_string("^(club|nat)\\d+$").search(id) != null or id == "elite0"

func has(id: String) -> bool:
	return is_free(id) or owned.has(id)

func equipped() -> Variant:
	var p: Variant = _supa().profile
	return p.get("equipped_disc") if p is Dictionary else null

## {ok, data: gems_left, error}
func buy(id: String) -> Dictionary:
	var r: Dictionary = await _supa().call_rpc("buy_disc", {"p_disc": id})
	if r.ok:
		owned[id] = true
		changed.emit()
	return r

func equip(id: String) -> Dictionary:
	return await _supa().call_rpc("equip_disc", {"p_disc": id})

## port of useBuyDisc: buy (if needed) + equip. Toasts via Nav.toast when available. Returns true when equipped.
func buy_and_equip(id: String, name_: String) -> bool:
	var supa := _supa()
	var nav := get_node_or_null("/root/Nav")
	var toast := func(m: String) -> void:
		if nav and nav.has_method("toast"):
			nav.toast(m)
	if not supa.signed_in():
		var u: String = await supa.ensure()
		if u == "":
			toast.call("برای خرید دیسک باید آنلاین باشی")
			return false
	if not has(id):
		var pr := price(id)
		var p: Variant = supa.profile
		var g := int(p.get("gems", 0)) if p is Dictionary else 0
		if p is Dictionary and g < pr:
			toast.call("%s الماس کم داری · چالش‌ها، فصل و تورنمنت‌ها الماس می‌دهند" % _fa(pr - g))
			return false
		var r := await buy(id)
		if not r.ok:
			toast.call(r.error)
			return false
		toast.call("%s باز شد!" % name_)
	var e := await equip(id)
	if not e.ok:
		toast.call(e.error)
		return false
	return true

func _fa(n: int) -> String:
	return NX.fa(n)
