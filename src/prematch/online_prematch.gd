extends "res://src/prematch/pre_match.gd"
## Online pre-match (RN v6 OnlinePreMatch.tsx): room → TEAM SELECT (timer) → FORMATION SELECT (timer) → online_match.
## Host-authoritative over the room's game broadcast:
##  • each side's captain (slot 0) picks the disc and the formation; teammates / spectators watch it live (read-only)
##  • the host broadcasts {k:"pms", ph, rem, picks, ready} every second; a phase ends when both captains confirm or the
##    timer runs out (room settings pick_team / pick_form override 60 s / 30 s)
##  • a side without a human captain keeps its default and counts as ready
##  • online_match keeps answering with ph "go" so late joiners skip straight in; a client that never hears the host for
##    15 s starts with defaults (online_match then handles host loss)
## Params: same as online_match {room_id, match_id, link, before, spectator}; picks are added for online_match.

const T_TEAM := 60.0
const T_FORM := 30.0

var link: Variant = null
var me := ""
var is_host := false
var room0: Dictionary = {}
var t_team := T_TEAM
var t_form := T_FORM
var hst := {"ph": "team", "picks": {"teams": ["club0", "club0"], "forms": [8, 8]}, "ready": [false, false]}
var host_end := 0.0
var last_heard := 0.0
var ph := "team"
var i_am_captain := false
var _off: Callable
var _beat: Timer
var _gone := false

func setup(p: Dictionary) -> void:
	super.setup(p)
	link = p.get("link")
	if link == null or not is_instance_valid(link):
		link = Supa.link_for(str(p.get("room_id", ""))) if Supa.has_method("link_for") else null

func _ready() -> void:
	if link == null or not (link.state.room is Dictionary):
		Nav.go.call_deferred("online_match", params)
		return
	me = str(link.me)
	room0 = (link.state.room as Dictionary).duplicate(true)
	is_host = str(room0.get("host", "")) == me
	var s: Dictionary = room0.get("settings", {}) if room0.get("settings") is Dictionary else {}
	t_team = float(s.get("pick_team", T_TEAM)) if float(s.get("pick_team", 0)) > 0 else T_TEAM
	t_form = float(s.get("pick_form", T_FORM)) if float(s.get("pick_form", 0)) > 0 else T_FORM
	var c0 := _cap(0)
	var c1 := _cap(1)
	hst.picks.teams = [OnlineMatchS().disc_of(c0) if not c0.is_empty() else "club0", OnlineMatchS().disc_of(c1) if not c1.is_empty() else "club0"]
	hst.picks.forms = [D.FORM_DEFAULT, D.FORM_DEFAULT]
	var mine := _me_player()
	my_side = int(mine.team) if (not mine.is_empty() and str(mine.get("role", "")) == "player" and mine.get("team") != null and int(mine.team) in [0, 1]) else 0
	view_tab = my_side
	var spect := mine.is_empty() or str(mine.get("role", "")) != "player"
	i_am_captain = not spect and str(_cap(my_side).get("user_id", "")) == me
	host_end = _now_ms() + t_team * 1000.0
	last_heard = _now_ms()
	team_id = str(hst.picks.teams[my_side])
	form = int(hst.picks.forms[my_side])
	_apply_view()
	super._ready()
	_off = link.on_game(_on_msg)
	_beat = Timer.new()
	_beat.wait_time = 1.0
	_beat.autostart = true
	_beat.timeout.connect(_tick_net)
	add_child(_beat)
	if is_host: _host_tick()
	# captain: announce my saved defaults once
	if i_am_captain:
		var sp := UD.p()
		_send_pick({"team": str(sp.get("team", team_id)), "f": D.form_idx(int(sp.get("form", D.FORM_DEFAULT)))})

func OnlineMatchS() -> GDScript:
	return load("res://src/online/online_match.gd")

func leave() -> void:
	if _off.is_valid(): _off.call()

func _exit_tree() -> void:
	if _off.is_valid(): _off.call()

func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

func _players() -> Array:
	return link.state.players if link and link.state.players is Array else []

func _cap(t: int) -> Dictionary:
	var arr: Array = OnlineMatchS().team_of(_players(), t)
	return arr[0] if arr.size() > 0 else {}

func _me_player() -> Dictionary:
	for p in _players():
		if p is Dictionary and str(p.get("user_id", "")) == me: return p
	return {}

# ------------------------------------------------------------------ view state from the authoritative picks
func _side_of(t: int) -> Dictionary:
	var c := _cap(t)
	var pr: Dictionary = c.get("profiles", {}) if c.get("profiles") is Dictionary else {}
	var members: Array = []
	for p in OnlineMatchS().team_of(_players(), t):
		if str(p.get("user_id", "")) != str(c.get("user_id", "")):
			var pp: Variant = p.get("profiles")
			members.append(str(pp.get("username", "…")) if pp is Dictionary else "…")
	return {"label": "تیم دو" if t else "تیم یک", "team": str(hst.picks.teams[t]), "form": int(hst.picks.forms[t]), "ready": bool(hst.ready[t]),
		"captain": {"name": str(pr.get("username", "ربات")), "level": int(pr.get("level", 1)), "avatar": OnlineMatchS().disc_of(c) if not c.is_empty() else str(hst.picks.teams[t])},
		"members": members}

func _apply_view() -> void:
	sides = [_side_of(0), _side_of(1)]
	read_only = not i_am_captain or bool(hst.ready[my_side])
	team_id = str(hst.picks.teams[my_side])
	form = int(hst.picks.forms[my_side])
	if i_am_captain:
		start_label = "آماده ✓ منتظر حریف" if bool(hst.ready[my_side]) else "شروع بازی"
		confirm_label = "آماده ✓" if bool(hst.ready[my_side]) else "تأیید ترکیب"
	else:
		start_label = "منتظر کاپیتان‌ها"
		confirm_label = "منتظر کاپیتان‌ها"
	total_s = t_form if ph == "form" else t_team

func _rebuild_for_phase() -> void:
	if _gone: return
	if ph == "go":
		_go_match(); return
	var want := "form" if ph == "form" else "team"
	_apply_view()
	if want != step:
		step = want
		_build()
	elif step == "team":
		_refresh_team()
		if _start_btn: _start_btn.set_text(start_label)
	elif _form_picker and is_instance_valid(_form_picker):
		_form_picker.set_value(form)
		_form_picker.read_only = read_only

# ------------------------------------------------------------------ captain actions (overrides of the offline flow)
func owned_list() -> Array:
	return super.owned_list()

func _on_team_changed(id: String) -> void:
	if i_am_captain: _send_pick({"team": id})

func _on_form_changed(fi: int) -> void:
	if i_am_captain: _send_pick({"f": fi})

func _confirm_team() -> void:
	if i_am_captain: _send_pick({"ready": true})

func _go_form() -> void:
	pass   # the host moves everyone to the formation phase

func _confirm_form() -> void:
	if i_am_captain: _send_pick({"ready": true})

func on_back() -> bool:
	return true   # the lobby is left from the match screen; the pre-match runs on the room timers

func _send_pick(x: Dictionary) -> void:
	if not i_am_captain: return
	if is_host:
		_host_apply(my_side, x)
		_host_broadcast()
		_rebuild_for_phase()
	else:
		var m := {"k": "pm", "t": my_side}
		m.merge(x)
		link.send_game(m)

# ------------------------------------------------------------------ host authority
func _host_apply(t: int, x: Dictionary) -> void:
	if hst.ph == "go": return
	if x.has("team") and hst.ph == "team" and not D.team_by_id(str(x.team)).is_empty() and str(D.team_by_id(str(x.team)).id) == str(x.team):
		hst.picks.teams[t] = str(x.team)
	if x.has("f") and int(x.f) >= 0 and int(x.f) < D.FORMS.size():
		hst.picks.forms[t] = int(x.f)
	if bool(x.get("ready", false)):
		hst.ready[t] = true

func _host_tick() -> void:
	var now := _now_ms()
	for t in 2:
		if _cap(t).is_empty(): hst.ready[t] = true
	if hst.ph != "go" and (now >= host_end or (hst.ready[0] and hst.ready[1])):
		if hst.ph == "team":
			hst.ph = "form"; hst.ready = [false, false]; host_end = now + t_form * 1000.0
			for t in 2:
				if _cap(t).is_empty(): hst.ready[t] = true
		else:
			hst.ph = "go"
	_host_broadcast()
	ph = hst.ph
	deadline_ms = host_end
	_rebuild_for_phase()

func _host_broadcast() -> void:
	link.send_game({"k": "pms", "ph": hst.ph, "rem": maxf(0.0, host_end - _now_ms()), "picks": hst.picks, "ready": hst.ready})

func _tick_net() -> void:
	if _gone: return
	if is_host:
		_host_tick()
	elif _now_ms() - last_heard > 15000.0:
		ph = "go"; _rebuild_for_phase()

func _on_msg(m: Variant, from: String) -> void:
	if _gone or not (m is Dictionary): return
	var k := str(m.get("k", ""))
	if is_host and k == "pm":
		var t := int(m.get("t", -1))
		if t < 0 or t > 1 or str(_cap(t).get("user_id", "")) != from: return   # only that side's captain
		_host_apply(t, m)
		_host_tick()
	elif not is_host and k == "pms":
		last_heard = _now_ms()
		var pk: Variant = m.get("picks")
		if pk is Dictionary and pk.get("teams") is Array and pk.get("forms") is Array:
			hst.picks = {"teams": [str(pk.teams[0]), str(pk.teams[1])], "forms": [int(pk.forms[0]), int(pk.forms[1])]}
		var rd: Variant = m.get("ready")
		if rd is Array and rd.size() >= 2: hst.ready = [bool(rd[0]), bool(rd[1])]
		ph = str(m.get("ph", "team"))
		hst.ph = ph
		deadline_ms = _now_ms() + float(m.get("rem", 0))
		_rebuild_for_phase()

func _go_match() -> void:
	if _gone: return
	_gone = true
	if _off.is_valid(): _off.call()
	var p := params.duplicate()
	p["picks"] = {"teams": [str(hst.picks.teams[0]), str(hst.picks.teams[1])], "forms": [int(hst.picks.forms[0]), int(hst.picks.forms[1])]}
	Nav.go("online_match", p)
