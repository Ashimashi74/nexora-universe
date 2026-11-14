extends Control
## v3 HOME = online rooms (the app's first screen; Nav "home", "hub" is an alias):
## Create room + join by code on top, the collapsible category drawers (Play · Online · Team & Shop ·
## Settings) for everything else, then the live room list with one-tap Join. The shell builds at once
## and works offline (drawers + offline play); the room list fills in once the server connects.
## params: {quick?: "1v1"|"2v2"|"3v3"} (Oracle "find me a quick match")
## Tables/RPC: room_list (select), realtime rooms/room_players (hub:rooms), rpc quick_match, join_room, create_room.

var params: Dictionary = {}
var rows_data: Array = []
var loaded := false
var err_msg := ""
var filter := "all"
var busy := ""
var ch: Variant = null
var vl: OUI.VList
var hdr: VBoxContainer
var count_lbl: Label
var code_in: LineEdit
var profile_slot: Control
var quick_btns: Dictionary = {}
var debounce: Timer
var poll: Timer
var _quick_done := false
var _create_busy := false


func setup(p: Dictionary) -> void:
	params = p


## which drawer is open (one at a time; remembered while the app runs)
static var open_drawer := ""
var connected := false
var _drawers: Dictionary = {}   # key -> [body: Control, chevron: Control]


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	_build()
	_connect()


## tapping Home again / Nav.online("hub", quick): run the quick match if one was asked for
func on_reselect(p: Dictionary = {}) -> void:
	var q := OUI.s(p.get("quick", ""))
	if q != "":
		if connected:
			_quick(q)
		else:
			params["quick"] = q
			_quick_done = false


func leave() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	Nav.chrome(true)


func on_back() -> bool:
	# home: a drawer open → close it first; otherwise Nav asks before quitting
	if open_drawer != "":
		_toggle(open_drawer)
		return true
	return false


func _back() -> void:
	if OUI.link != null:
		OUI.leave_room(false)
	Nav.back()


# ---------------------------------------------------------------- connect (guests sign in anonymously)
func _connect() -> void:
	err_msg = ""
	connected = false
	_set_empty()
	var id: String = await OUI.ensure()
	if not is_inside_tree():
		return
	if id == "":
		err_msg = I18n.t("m3.offline_hint")
		_set_empty()
		return
	connected = true
	_start_live()


func _build() -> void:
	OUI.clear(self)
	var root := OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(OUI.header(I18n.t("m3.title"), "", Callable(), _currency(), OUI.CYAN, _refresh))
	vl = OUI.VList.new(76, _make_row, _bind_row, 8)
	root.add_child(vl)
	hdr = _make_header()
	vl.set_header(hdr)
	_set_empty()
	OUI.fade_in(root)
	OUI.ebus().profile_changed.connect(_on_profile)
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", _on_store)


func _start_live() -> void:
	if ch != null:
		_load()
		return
	_load()
	# live room list
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.6
	debounce.timeout.connect(_load)
	add_child(debounce)
	poll = Timer.new()
	poll.wait_time = 20.0
	poll.timeout.connect(_load)
	add_child(poll)
	poll.start()
	ch = Supa.channel("hub:rooms", {})
	ch.on_postgres("*", "public", "rooms", "", func(_r: Variant) -> void: _soon())
	ch.on_postgres("*", "public", "room_players", "", func(_r: Variant) -> void: _soon())
	ch.subscribe(func(_s: Variant) -> void: pass)
	# Oracle "find me a quick match": once connected, run quick_match and drop straight into the lobby
	var q := OUI.s(params.get("quick", ""))
	if q != "" and not _quick_done:
		_quick_done = true
		_quick(q)


func _soon() -> void:
	if is_instance_valid(debounce):
		debounce.start()


func _on_profile(_p: Dictionary) -> void:
	if is_instance_valid(profile_slot):
		_fill_profile()
	_fill_currency()


func _refresh() -> void:
	if not connected:
		_connect()
		return
	await _load()
	if is_inside_tree():
		OUI.toast(I18n.t("hub.updated"), "ok")


func _load() -> void:
	var r: Dictionary = await OUI.get_rows("room_list?select=*&order=created_at.desc&limit=60")
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		err_msg = OUI.err(r)
	else:
		err_msg = ""
		rows_data = OUI.rows(r)
		loaded = true
	_apply()


func _filtered() -> Array:
	if filter == "all":
		return rows_data
	return rows_data.filter(func(x: Variant) -> bool: return OUI.s(x.get("mode")) == filter)


func _apply() -> void:
	var data := _filtered() if loaded else []
	if is_instance_valid(count_lbl):
		count_lbl.text = (I18n.t("hub.x_rooms") % OUI.fa(data.size())) if loaded else ""
	vl.set_items(data)
	_set_empty()


func _set_empty() -> void:
	if vl == null:
		return
	if err_msg != "":
		vl.set_empty(OUI.error_state(err_msg, _connect if not connected else _load))
	elif not loaded:
		vl.set_empty(OUI.skeleton(4))
	else:
		vl.set_empty(OUI.empty(OUI.ui2("x_ball"), I18n.t("hub.no_open_rooms_right_now"), I18n.t("hub.create_a_room_and_invite"), I18n.t("hub.create_room"), _open_create))


# ---------------------------------------------------------------- header (profile, quick match, shortcuts, join)
func _make_header() -> VBoxContainer:
	var v := OUI.vbox(OUI.S_M)
	var m := OUI.margin(v, OUI.S_L, OUI.S_M, OUI.S_L, OUI.S_S)
	var outer := OUI.vbox(0)
	outer.add_child(m)
	# 1 · create room (primary) + join by code
	var cb := OUI.btn(I18n.t("hub.create_room"), _open_create, "primary")
	v.add_child(cb)
	var cj := OUI.hbox(OUI.S_S)
	code_in = OUI.line_edit(I18n.t("hub.6_digit_code"), 6, false, false, 48)
	code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_in.add_theme_font_override("font", OUI.font("head"))
	code_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_in.text_changed.connect(_on_code)
	code_in.text_submitted.connect(func(_t: String) -> void: _join_code())
	cj.add_child(code_in)
	var jb := OUI.btn(I18n.t("hub.join"), _join_code, "dark")
	jb.custom_minimum_size.x = OUI.px(96)
	cj.add_child(jb)
	v.add_child(cj)
	# 2 · everything else: collapsible category drawers
	v.add_child(OUI.spacer(OUI.S_XS))
	v.add_child(_drawer("play", I18n.t("m3.cat_play"), I18n.t("m3.cat_play_sub"), "play", _play_items))
	v.add_child(_drawer("online", I18n.t("m3.cat_online"), I18n.t("m3.cat_online_sub"), "globe", _online_items))
	v.add_child(_drawer("team", I18n.t("m3.cat_team"), I18n.t("m3.cat_team_sub"), "team", _team_items))
	v.add_child(_drawer("settings", I18n.t("m3.cat_settings"), I18n.t("m3.cat_settings_sub"), "gear", _settings_items))
	# 3 · room list title + mode filter
	v.add_child(OUI.spacer(OUI.S_XS))
	var th := OUI.hbox(OUI.S_S)
	th.add_child(OUI.lbl(I18n.t("m3.rooms"), OUI.TS_H, OUI.TEXT, "bold"))
	th.add_child(OUI.expand())
	count_lbl = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	th.add_child(count_lbl)
	v.add_child(th)
	v.add_child(OUI.segment([["all", I18n.t("challenges.all")], ["1v1", "1v1"], ["2v2", "2v2"], ["3v3", "3v3"]], filter, func(val: Variant) -> void:
		filter = str(val)
		_apply()))
	return outer


# ---------------------------------------------------------------- category drawers (accordion)
func _drawer(key: String, title: String, sub: String, icon: String, fill: Callable) -> Control:
	var box := OUI.vbox(0)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", OUI.sb(OUI.PANEL_BG, 16, OUI.LINE, 1, OUI.S_M))
	var h := OUI.hbox(OUI.S_M)
	var ic := NxIcon.new(icon, OUI.CYAN)
	ic.custom_minimum_size = Vector2(OUI.px(36), OUI.px(36))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := OUI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(OUI.lbl(title, OUI.TS_H, OUI.TEXT, "bold"))
	var sl := OUI.lbl(sub, OUI.TS_CAP, OUI.DIM)
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sl.clip_text = true
	tv.add_child(sl)
	h.add_child(tv)
	var chev := NxIcon.new("chev_down", OUI.DIM)
	chev.custom_minimum_size = Vector2(OUI.px(24), OUI.px(24))
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chev)
	head.add_child(h)
	var t := OUI.tap(head, func() -> void: _toggle(key), false)
	box.add_child(t)
	var body := OUI.vbox(OUI.S_XS)
	var bm := OUI.margin(body, OUI.S_S, OUI.S_XS, OUI.S_S, OUI.S_S)
	box.add_child(bm)
	fill.call(body)
	bm.visible = open_drawer == key
	chev.rotation = PI if open_drawer == key else 0.0
	chev.resized.connect(func() -> void: chev.pivot_offset = chev.size * 0.5)
	_drawers[key] = [bm, chev]
	return box


func _toggle(key: String) -> void:
	open_drawer = "" if open_drawer == key else key
	for k in _drawers:
		var d: Array = _drawers[k]
		var on: bool = k == open_drawer
		var bm: Control = d[0]
		var chev: Control = d[1]
		if is_instance_valid(bm):
			bm.visible = on
			if on:
				bm.modulate.a = 0.0
				bm.create_tween().tween_property(bm, "modulate:a", 1.0, 0.18)
		if is_instance_valid(chev):
			chev.pivot_offset = chev.size * 0.5
			chev.create_tween().tween_property(chev, "rotation", PI if on else 0.0, 0.18)


## one option row inside a drawer: title (+ sub) and a chevron; tap runs cb
func _item(title: String, sub: String, cb: Callable, dot := false) -> Control:
	var pc := PanelContainer.new()
	var st := OUI.sb(Color(1, 1, 1, 0.03), 14, Color(0, 0, 0, 0), 0)
	st.content_margin_left = OUI.px(OUI.S_M)
	st.content_margin_right = OUI.px(OUI.S_M)
	st.content_margin_top = OUI.px(10)
	st.content_margin_bottom = OUI.px(10)
	pc.add_theme_stylebox_override("panel", st)
	var h := OUI.hbox(OUI.S_S)
	var tv := OUI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(OUI.lbl(title, OUI.TS_BODY, OUI.TEXT, "bold"))
	if sub != "":
		var sl := OUI.lbl(sub, OUI.TS_CAP, OUI.DIM)
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.clip_text = true
		tv.add_child(sl)
	h.add_child(tv)
	if dot:
		var d := NxIcon.new("dot", NX.RED)
		d.custom_minimum_size = Vector2(OUI.px(10), OUI.px(10))
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(d)
	var chev := NxIcon.new("chev_fwd", OUI.DIM2)
	chev.custom_minimum_size = Vector2(OUI.px(18), OUI.px(18))
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chev)
	pc.add_child(h)
	return OUI.tap(pc, cb, false)


func _play_items(b: VBoxContainer) -> void:
	for m in Launch.modes():
		var k: String = m["k"]
		b.add_child(_item(m["name"], m["desc"], func() -> void: Nav.go("setup", {"mode": k})))
	b.add_child(_item(I18n.t("arena.arena"), "", func() -> void: Nav.online("arena")))
	b.add_child(_item(I18n.t("hub.tournament"), "", func() -> void: Nav.online("tournaments")))


func _online_items(b: VBoxContainer) -> void:
	# quick online match: one row of three mode buttons
	b.add_child(OUI.lbl(I18n.t("m3.quick_online"), OUI.TS_SMALL, OUI.DIM, "bold"))
	var qb := OUI.hbox(OUI.S_S)
	for k in 3:
		var mode: String = OUI.MODES[k]
		var bt := OUI.btn(mode.to_upper(), func() -> void: _quick(mode), "dark", true, OUI.MODE_FA[mode])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick_btns[mode] = bt
		qb.add_child(bt)
	b.add_child(qb)
	b.add_child(_item(I18n.t("hub.leaderboard"), "", func() -> void: Nav.go("ranks", {})))
	b.add_child(_item(I18n.t("hub.challenges"), "", func() -> void: Nav.go("challenges", {})))
	b.add_child(_item(I18n.t("m3.friends"), "", func() -> void: Nav.go("social", {})))
	b.add_child(_item(I18n.t("m3.assistant"), "", func() -> void: Nav.go("oracle", {})))


func _team_items(b: VBoxContainer) -> void:
	b.add_child(_item(I18n.t("m3.my_team"), I18n.t("m3.cat_team_sub"), func() -> void: Nav.go("team")))
	b.add_child(_item(I18n.t("kb.shop"), "", func() -> void: Nav.go("shop")))
	b.add_child(_item(I18n.t("daily.daily_reward"), "", func() -> void: Nav.go("daily"), UD.daily_ready()))
	b.add_child(_item(I18n.t("m3.profile"), "", func() -> void: Nav.go("profile")))


func _settings_items(b: VBoxContainer) -> void:
	b.add_child(_item(I18n.t("kb.settings"), I18n.t("m3.cat_settings_sub"), func() -> void: Nav.go("settings")))
	b.add_child(_item(I18n.t("settings.account"), "", func() -> void: Nav.go("account")))


## compact coins / gems in the header (tap → shop)
var _cur_l: Label
var _gem_l: Label
func _currency() -> Control:
	var pc := PanelContainer.new()
	var st := OUI.sb(NX.SURF2, 16, Color(0, 0, 0, 0), 0)
	st.content_margin_left = OUI.px(10)
	st.content_margin_right = OUI.px(10)
	pc.add_theme_stylebox_override("panel", st)
	var h := OUI.hbox(OUI.S_XS)
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	h.add_child(OUI.img(UD.art("h_coin"), 20))
	_cur_l = OUI.lbl("", OUI.TS_SMALL, OUI.TEXT, "bold")
	h.add_child(_cur_l)
	h.add_child(OUI.img(UD.art("h_gem"), 20))
	_gem_l = OUI.lbl("", OUI.TS_SMALL, OUI.TEXT, "bold")
	h.add_child(_gem_l)
	pc.add_child(h)
	_fill_currency()
	var t := OUI.tap(pc, func() -> void: Nav.go("shop"))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _fill_currency() -> void:
	if not is_instance_valid(_cur_l):
		return
	var p := UD.p()
	var op := UD.online_profile()
	var gems := int(op.get("gems", p.get("gems", 0))) if not op.is_empty() else int(p.get("gems", 0))
	_cur_l.text = NX.en_num(int(p.get("coins", 0)))
	if is_instance_valid(_gem_l):
		_gem_l.text = NX.en_num(gems)


func _on_store() -> void:
	_fill_currency()


func _fill_profile() -> void:
	if not is_instance_valid(profile_slot):
		return
	OUI.clear(profile_slot)
	var p := OUI.profile
	if p.is_empty():
		return
	var lp := OUI.level_progress(OUI.i(p.get("xp")))
	var pn := OUI.panel(OUI.GOLD, OUI.S_M)
	var h := OUI.hbox(OUI.S_M)
	h.add_child(NetImg.avatar(OUI.s(p.get("equipped_disc", "")) if OUI.s(p.get("equipped_disc", "")) != "" else p.get("avatar"), p.get("avatar_url"), 52, OUI.GOLD))
	var mid := OUI.vbox(OUI.S_XS)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh := OUI.hbox(OUI.S_XS)
	var nl := OUI.lbl(OUI.s(p.get("username")), OUI.TS_H, OUI.TEXT, "bold")
	nl.custom_minimum_size.x = OUI.px(60)
	nh.add_child(nl)
	nh.add_child(OUI.badge(I18n.t("hub.level_x") % OUI.fa(OUI.i(p.get("level"), 1)), OUI.GOLD))
	nh.add_child(OUI.expand())
	mid.add_child(nh)
	mid.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 6))
	mid.add_child(OUI.lbl(I18n.t("hub.x_x_xp_rating_x") % [OUI.fa(lp["cur"]), OUI.fa(lp["need"]), OUI.fa(OUI.i(p.get("rating")))], OUI.TS_TINY, OUI.DIM))
	h.add_child(mid)
	h.add_child(OUI.img(OUI.league_tex(p.get("league")), 48))
	pn.add_child(h)
	var t := OUI.tap(pn, func() -> void: Nav.go("ranks", {}))
	profile_slot.add_child(t)
	OUI.enter(t, 0)


func _on_code(t: String) -> void:
	var clean := ""
	for ch2 in t.to_upper():
		if (ch2 >= "A" and ch2 <= "Z") or (ch2 >= "0" and ch2 <= "9"):
			clean += ch2
	clean = clean.substr(0, 6)
	if clean != t:
		var c := code_in.caret_column
		code_in.text = clean
		code_in.caret_column = mini(c, clean.length())


# ---------------------------------------------------------------- actions
func _act(key: String, fn: Callable) -> void:
	if busy != "":
		return
	if not connected:
		OUI.toast_err(I18n.t("m3.not_connected"))
		_connect()
		return
	busy = key
	_busy_ui()
	var r: Dictionary = await fn.call()
	if not is_inside_tree():
		if OUI.ok(r):
			OUI.enter_room(r.get("data"))
		return
	busy = ""
	_busy_ui()
	if OUI.ok(r):
		OUI.sfx("join")
		OUI.buzz("medium")
		OUI.enter_room(r.get("data"))
	else:
		OUI.toast_err(OUI.err(r))
		OUI.buzz("heavy")


func _busy_ui() -> void:
	for m in quick_btns:
		var b: Button = quick_btns[m]
		if is_instance_valid(b):
			b.disabled = busy != ""
			b.text = ("…" if busy == "quick" + m else m.to_upper()) + "\n" + OUI.MODE_FA[m]
	vl.refresh_rows()


func _quick(m: String) -> void:
	if not connected:
		OUI.toast_err(I18n.t("m3.not_connected"))
		_connect()
		return
	OracleCoach.react("search")
	_act("quick" + m, func() -> Dictionary: return await Supa.call_rpc("quick_match", {"p_mode": m, "p_kind": "quick"}))


func _join(id: String, spectate: bool) -> void:
	_act(("w" if spectate else "j") + id, func() -> Dictionary: return await Supa.call_rpc("join_room", {"p_room": id, "p_spectate": spectate}))


func _join_code() -> void:
	var c := code_in.text.strip_edges().to_upper()
	if c.length() != 6:
		OUI.toast_err(I18n.t("hub.the_room_code_has_6"))
		return
	_act("code", func() -> Dictionary: return await Supa.call_rpc("join_room", {"p_code": c}))


# ---------------------------------------------------------------- room rows
class RoomRow extends PanelContainer:
	var av: NetImg.Avatar
	var name_l: Label
	var sub_l: Label
	var badges: HBoxContainer
	var cnt_l: Label
	var spec_l: Label
	var join_b: Button
	var watch_b: Button
	var id := ""


func _make_row() -> Control:
	# v3: one compact line per room — avatar · name / host · mode · players — one-tap Join (Watch when live/full)
	var r := RoomRow.new()
	r.add_theme_stylebox_override("panel", OUI.sb(OUI.PANEL_BG, 16, OUI.LINE, 1, OUI.S_S))
	var h := OUI.hbox(OUI.S_S)
	r.av = NetImg.avatar(null, null, 40)
	h.add_child(r.av)
	var mid := OUI.vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	r.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	r.name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r.name_l.clip_text = true
	r.sub_l = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	r.sub_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r.sub_l.clip_text = true
	r.badges = OUI.hbox(OUI.S_XS)
	mid.add_child(r.name_l)
	mid.add_child(r.sub_l)
	h.add_child(mid)
	r.cnt_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER)
	r.cnt_l.custom_minimum_size.x = OUI.px(40)
	h.add_child(r.cnt_l)
	r.spec_l = OUI.lbl("", OUI.TS_TINY, OUI.DIM)
	r.spec_l.visible = false
	r.join_b = OUI.btn(I18n.t("hub.join"), func() -> void: _join(r.id, false), "primary", true)
	r.join_b.custom_minimum_size.x = OUI.px(84)
	r.join_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.watch_b = OUI.btn(I18n.t("hub.watch"), func() -> void: _join(r.id, true), "dark", true)
	r.watch_b.custom_minimum_size.x = OUI.px(84)
	r.watch_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(r.join_b)
	h.add_child(r.watch_b)
	r.add_child(h)
	return r


func _bind_row(c: Control, item: Variant, _idx: int) -> void:
	var r := c as RoomRow
	var it := OUI.d(item)
	r.id = OUI.s(it.get("id"))
	var players := OUI.i(it.get("players"))
	var cap := OUI.i(it.get("capacity"), 2)
	var full := players >= cap
	var playing := OUI.s(it.get("status")) == "playing"
	r.av.set_data(it.get("host_avatar"), it.get("host_avatar_url"), OUI.RED if playing else OUI.CYAN)
	r.name_l.text = OUI.s(it.get("name"))
	var kind: Array = OUI.KIND_FA.get(OUI.s(it.get("kind")), OUI.KIND_FA["casual"])
	r.sub_l.text = "%s · %s · %s%s" % [OUI.s(it.get("mode")).to_upper(), I18n.f(str(kind[0])), OUI.s(it.get("host_name")), (" · " + I18n.t("hub.live")) if playing else ""]
	r.cnt_l.text = "%s/%s" % [OUI.fa(players), OUI.fa(cap)]
	r.cnt_l.add_theme_color_override("font_color", OUI.ORANGE if full else OUI.TEXT)
	var can_join := not playing and not full
	r.join_b.visible = can_join
	r.watch_b.visible = not can_join
	r.join_b.text = "…" if busy == "j" + r.id else I18n.t("hub.join")
	r.watch_b.text = "…" if busy == "w" + r.id else I18n.t("hub.watch")
	r.join_b.disabled = busy != ""
	r.watch_b.disabled = busy != ""


# ---------------------------------------------------------------- create room sheet
func _open_create() -> void:
	if not connected:
		OUI.toast_err(I18n.t("m3.not_connected"))
		_connect()
		return
	var st := {"name": "", "mode": "1v1", "priv": false, "ranked": true, "voice": true, "rule": "g3", "turn": 15, "field": 0}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_XS)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
	var nf := OUI.field(I18n.t("hub.room_name"), I18n.t("hub.e_g_galactic_final"), 40)
	v.add_child(nf)
	v.add_child(OUI.cap_label(I18n.t("hub.mode")))
	var mi: Array = []
	for m in OUI.MODES:
		mi.append([m, OUI.MODE_FA[m]])
	v.add_child(OUI.segment(mi, "1v1", func(x: Variant) -> void: st["mode"] = x))
	v.add_child(OUI.cap_label(I18n.t("hub.rule")))
	v.add_child(OUI.segment(OUI.RULES, "g3", func(x: Variant) -> void: st["rule"] = x, OUI.VIOLET))
	v.add_child(OUI.cap_label(I18n.t("hub.turn_time")))
	v.add_child(OUI.segment(OUI.TURNS, 15, func(x: Variant) -> void: st["turn"] = x, OUI.GREEN))
	v.add_child(OUI.cap_label(I18n.t("hub.field")))
	v.add_child(field_picker(0, func(i: int) -> void: st["field"] = i))
	v.add_child(OUI.spacer(OUI.S_M))
	v.add_child(OUI.opt_row(I18n.t("hub.private"), I18n.t("hub.join_only_with_the_room"), false, func(x: bool) -> void: st["priv"] = x))
	v.add_child(OUI.opt_row(I18n.t("hub.ranked"), I18n.t("hub.affects_rating_and_league"), true, func(x: bool) -> void: st["ranked"] = x))
	v.add_child(OUI.opt_row(I18n.t("hub.voice_chat"), I18n.t("hub.players_can_talk_to_each"), true, func(x: bool) -> void: st["voice"] = x))
	v.add_child(OUI.spacer(OUI.S_L))
	var go := OUI.btn(I18n.t("hub.create_room"), Callable(), "green")
	go.pressed.connect(func() -> void:
		if busy != "":
			return
		go.text = I18n.t("hub.creating")
		go.disabled = true
		var nm := OUI.field_value(nf).strip_edges()
		var settings := OUI.rule_to_settings(str(st["rule"]))
		settings["field"] = st["field"]
		settings["turn"] = st["turn"]
		settings["ball"] = 0
		var args := {"p_mode": st["mode"], "p_name": nm if nm != "" else null, "p_private": st["priv"], "p_ranked": st["ranked"], "p_voice": st["voice"], "p_settings": settings}
		busy = "create"
		var r: Dictionary = await Supa.call_rpc("create_room", args)
		busy = ""
		if OUI.ok(r):
			Nav.close_sheet()
			OUI.sfx("join")
			OUI.buzz("medium")
			OUI.enter_room(r.get("data"))
		else:
			if is_instance_valid(go):
				go.text = I18n.t("hub.create_room")
				go.disabled = false
			OUI.toast_err(OUI.err(r))
			OUI.buzz("heavy"))
	v.add_child(go)
	OUI.open_sheet(I18n.t("hub.create_room"), "CREATE ROOM", sc, OUI.GREEN, 0.88)


## horizontal field thumbnails (RN FieldPicker) — shared with lobby settings
static func field_picker(value: int, cb: Callable) -> Control:
	var sc := OUI.hscroll()
	sc.custom_minimum_size.y = OUI.px(96)
	var h := OUI.hbox(OUI.S_S)
	sc.add_child(h)
	var boxes: Array = []
	for k in OUI.field_count():
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(OUI.px(78), OUI.px(88))
		var v := OUI.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var th := OUI.img(OUI.field_thumb(k), 44, 58)
		th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		th.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(th)
		var nl := OUI.lbl(OUI.field_name(k), OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(nl)
		pc.add_child(v)
		boxes.append([pc, nl])
		var idx := k
		var set_sel := func(sel: int) -> void:
			for j in boxes.size():
				var on: bool = j == sel
				(boxes[j][0] as PanelContainer).add_theme_stylebox_override("panel", OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.12) if on else Color(0, 0, 0, 0), 12, OUI.CYAN if on else OUI.LINE, 1, 4))
				(boxes[j][1] as Label).add_theme_color_override("font_color", OUI.TEXT if on else OUI.DIM)
		var t := OUI.tap(pc, func() -> void:
			set_sel.call(idx)
			cb.call(idx))
		h.add_child(t)
		if k == OUI.field_count() - 1:
			set_sel.call(value)
	return sc
