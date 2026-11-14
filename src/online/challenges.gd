class_name ChallengesScreen
extends Control
## Daily challenges (4 per Tehran day): progress, claim with animation, reset countdown (port of RN Challenges.tsx).
## Also: ChallengesScreen.load_challenges() (used by Oracle) and make_home_card() (RN HomeChallenges, for Home).
## Tables/RPC: rpc get_daily_challenges, claim_challenge(p_def); challenge_defs; realtime user_challenges (uc:<uid>).

static var defs_cache: Dictionary = {}

var list: Array = []
var loaded := false
var err_msg := ""
var ch: Variant = null
var body: VBoxContainer
var cd_l: Label
var tk: Timer


## next midnight in Asia/Tehran (UTC+03:30, no DST) — seconds
static func s_to_tehran_midnight(now: float = -1.0) -> float:
	var t := now if now >= 0 else Time.get_unix_time_from_system()
	var off := 3.5 * 3600.0
	var day := 86400.0
	return ceil((t + off + 0.001) / day) * day - off - t


## -> {ok, list, error}
static func load_challenges() -> Dictionary:
	var r: Dictionary = await Supa.call_rpc("get_daily_challenges", {})
	if not OUI.ok(r):
		return {"ok": false, "list": [], "error": OUI.err(r)}
	if defs_cache.is_empty():
		var dr: Dictionary = await OUI.get_rows("challenge_defs?select=*")
		for dd in OUI.rows(dr):
			defs_cache[OUI.s(dd.get("id"))] = dd
	var out: Array = []
	var data: Variant = r.get("data")
	for row in (data if data is Array else []):
		var did := OUI.s(row.get("def_id"))
		var c: Dictionary = OUI.d(row).duplicate()
		var def: Dictionary = defs_cache.get(did, {"title_fa": did, "target": 1, "reward_gems": 0, "reward_xp": 0})
		for k in def:
			c[k] = def[k]
		c["def_id"] = did
		c["progress"] = OUI.i(row.get("progress"))
		c["claimed"] = bool(row.get("claimed", false))
		out.append(c)
	return {"ok": true, "list": out, "error": ""}


## -> {ok, gems, xp, error}
static func claim(def_id: String) -> Dictionary:
	var r: Dictionary = await Supa.call_rpc("claim_challenge", {"p_def": def_id})
	if not OUI.ok(r):
		return {"ok": false, "error": OUI.err(r)}
	var dd := OUI.d(r.get("data"))
	OUI.sfx("win")
	OUI.buzz("success")
	OUI.toast(I18n.t("challenges.x_gems_x_xp") % [OUI.fa(OUI.i(dd.get("gems"))), OUI.fa(OUI.i(dd.get("xp")))], "ok")
	return {"ok": true, "gems": OUI.i(dd.get("gems")), "xp": OUI.i(dd.get("xp"))}


func setup(_p: Dictionary) -> void:
	pass


func _ready() -> void:
	Nav.chrome(false)
	OUI.boot()
	var pg := OUI.page(self, I18n.t("challenges.daily_challenges"), "DAILY CHALLENGES", func() -> void: Nav.back(), null, OUI.GREEN, _load)
	body = pg["body"]
	var hp := OUI.panel(OUI.GREEN)
	var h := OUI.hbox(OUI.S_M)
	h.add_child(OUI.img(OUI.ui2("c_calendar"), 48))
	var v := OUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(OUI.lbl(I18n.t("challenges.today_s_challenges"), OUI.TS_H, OUI.TEXT, "title"))
	cd_l = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	v.add_child(cd_l)
	h.add_child(v)
	hp.add_child(h)
	body.add_child(hp)
	var lst := OUI.vbox(OUI.S_S)
	lst.name = "List"
	body.add_child(OUI.margin(lst, 0, OUI.S_S, 0, 0))
	tk = Timer.new()
	tk.wait_time = 1.0
	tk.timeout.connect(_cd)
	add_child(tk)
	tk.start()
	_cd()
	_render()
	_start()


func leave() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _start() -> void:
	var u: String = await OUI.ensure()
	if not is_inside_tree() or u == "":
		if is_inside_tree():
			err_msg = I18n.t("challenges.sign_in_first")
			_render()
		return
	_load()
	ch = Supa.channel("uc:" + u, {})
	ch.on_postgres("*", "public", "user_challenges", "user_id=eq." + u, func(_r: Variant) -> void: _load())
	ch.subscribe(func(_s: Variant) -> void: pass)


func _cd() -> void:
	var left := s_to_tehran_midnight()
	var h := int(left / 3600.0)
	var m := int(fmod(left, 3600.0) / 60.0)
	var s := int(fmod(left, 60.0))
	cd_l.text = I18n.t("challenges.refreshes_in_x_x_x") % [OUI.fa(h), OUI.pad2fa(m), OUI.pad2fa(s)]


func _load() -> void:
	var r: Dictionary = await load_challenges()
	if not is_inside_tree():
		return
	if r["ok"]:
		list = r["list"]
		loaded = true
		err_msg = ""
	else:
		err_msg = r["error"]
	_render()


func _render() -> void:
	var lst := body.find_child("List", true, false) as VBoxContainer
	if lst == null:
		return
	OUI.clear(lst)
	if err_msg != "":
		lst.add_child(OUI.error_state(err_msg, _load))
	elif not loaded:
		lst.add_child(OUI.skeleton(4, 96))
	elif list.is_empty():
		lst.add_child(OUI.empty(OUI.ui2("x_ball"), I18n.t("challenges.no_challenges_today")))
	else:
		var k := 0
		for c in list:
			var card := challenge_card(c, false, func(cc: Control) -> void: _claim(c, cc))
			lst.add_child(card)
			OUI.enter(card, k)
			k += 1


func _claim(c: Dictionary, card: Control) -> void:
	_pop(card)
	var r: Dictionary = await claim(OUI.s(c.get("def_id")))
	if not is_inside_tree():
		return
	if r["ok"]:
		c["claimed"] = true
		_render()
	else:
		OUI.toast_err(r["error"])


static func _pop(card: Control) -> void:
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2(1.06, 1.06), 0.12)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## RN ChallengeCard. on_claim.call(card)
static func challenge_card(c: Dictionary, compact: bool, on_claim: Callable) -> Control:
	var target := maxi(1, OUI.i(c.get("target"), 1))
	var prog := OUI.i(c.get("progress"))
	var done := prog >= target
	var claimed := bool(c.get("claimed", false))
	var p := OUI.panel(OUI.GREEN if done and not claimed else null, OUI.S_S if compact else OUI.S_M, done and not claimed)
	if claimed:
		p.modulate.a = 0.6
	var h := OUI.hbox(OUI.S_S)
	h.add_child(OUI.img(OUI.ui2("x_medal" if claimed else ("x_star" if done else "x_ball")), 36 if compact else 44))
	var v := OUI.vbox(OUI.S_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(OUI.lbl(OUI.s(c.get("title_fa")), OUI.TS_SMALL if compact else OUI.TS_BODY, OUI.TEXT, "bold", I18n.AR, true, 2))
	v.add_child(OUI.bar(minf(1.0, float(prog) / target), OUI.GREEN if done else OUI.CYAN, null, 6))
	v.add_child(OUI.lbl("%s/%s · 💎%s · %sXP" % [OUI.fa(mini(prog, target)), OUI.fa(target), OUI.fa(OUI.i(c.get("reward_gems"))), OUI.fa(OUI.i(c.get("reward_xp")))], OUI.TS_TINY, OUI.DIM))
	h.add_child(v)
	var side := OUI.vbox(0)
	side.custom_minimum_size.x = OUI.px(76)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	if claimed:
		side.add_child(OUI.lbl(I18n.t("challenges.claimed"), OUI.TS_CAP, OUI.GREEN, "body", HORIZONTAL_ALIGNMENT_CENTER))
	elif done:
		var b := OUI.btn(I18n.t("challenges.claim"), Callable(), "green", true)
		b.pressed.connect(func() -> void:
			b.disabled = true
			on_claim.call(p))
		side.add_child(b)
	else:
		side.add_child(OUI.lbl(I18n.t("challenges.in_progress"), OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	h.add_child(side)
	p.add_child(h)
	return p


## Home card: today's challenges at a glance (only when signed in). For the UI worker's Home screen.
static func make_home_card() -> Control:
	var holder := HomeCard.new()
	return holder


class HomeCard extends VBoxContainer:
	var list: Array = []
	var ch: Variant = null
	var uid := ""
	func _ready() -> void:
		layout_direction = I18n.LD
		visible = false
		OUI.boot()
		OUI.ebus().profile_changed.connect(_auth)
		_auth()
	func _exit_tree() -> void:
		if ch != null:
			Supa.remove_channel(ch)
			ch = null
	func _auth(_p: Variant = null) -> void:
		var u := OUI.uid()
		if u == uid:
			return
		uid = u
		if ch != null:
			Supa.remove_channel(ch)
			ch = null
		if u == "":
			visible = false
			return
		_load()
		ch = Supa.channel("uc:home:" + u, {})
		ch.on_postgres("*", "public", "user_challenges", "user_id=eq." + u, func(_r: Variant) -> void: _load())
		ch.subscribe(func(_s: Variant) -> void: pass)
	func _load() -> void:
		var r: Dictionary = await ChallengesScreen.load_challenges()
		if not is_inside_tree():
			return
		if r["ok"]:
			list = r["list"]
		_render()
	func _render() -> void:
		OUI.clear(self)
		visible = OUI.uid() != "" and not list.is_empty()
		if not visible:
			return
		var done := list.filter(func(c: Variant) -> bool: return bool(c.get("claimed", false))).size()
		var p := OUI.panel(OUI.GREEN)
		var v := OUI.vbox(OUI.S_S)
		var h := OUI.hbox(OUI.S_S)
		h.add_child(OUI.img(OUI.ui2("c_calendar"), 34))
		var tv := OUI.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(OUI.lbl(I18n.t("challenges.today_s_challenges"), OUI.TS_BODY, OUI.TEXT, "bold"))
		tv.add_child(OUI.lbl(I18n.t("challenges.x_x_done_refreshes_in") % [OUI.fa(done), OUI.fa(list.size()), OUI.fa(int(ChallengesScreen.s_to_tehran_midnight() / 3600.0))], OUI.TS_TINY, OUI.DIM))
		h.add_child(tv)
		var all := OUI.btn(I18n.t("challenges.all"), func() -> void: Nav.go("challenges", {}), "dark", true)
		all.custom_minimum_size.x = OUI.px(72)
		h.add_child(all)
		v.add_child(h)
		for c in list.slice(0, 4):
			v.add_child(ChallengesScreen.challenge_card(c, true, func(card: Control) -> void:
				ChallengesScreen._pop(card)
				var r: Dictionary = await ChallengesScreen.claim(OUI.s(c.get("def_id")))
				if r["ok"]:
					c["claimed"] = true
					if is_inside_tree():
						_render()
				else:
					OUI.toast_err(r["error"])))
		p.add_child(v)
		add_child(p)
