extends Control
## Tournaments (port of RN Tournaments.tsx): list (registration / running / finished) + create sheet,
## and the detail view (params.id) with bracket (single / double elimination) or standings
## (round robin / swiss / league), register / leave / start, organizer result override, live updates,
## "your next match" → open_tournament_room → lobby.
## Tables/RPC: tournaments (+ tournament_entries(count)), standings (view), tournament_matches;
## rpc create_tournament, join_tournament, leave_tournament, start_tournament, open_tournament_room,
## set_tournament_result; realtime tours:<status>, tour:<id>.

const FORMAT_FA := {"single_elim": "حذفی تک", "double_elim": "حذفی دوگانه", "round_robin": "دوره‌ای", "swiss": "سوئیسی", "league": "لیگ"}
const STATUS_FA := {"registration": ["ثبت‌نام", OUI.GREEN], "running": ["در جریان", OUI.ORANGE], "finished": ["پایان‌یافته", OUI.DIM]}
const BOX_W := 168.0
const BOX_H := 64.0
const GAP := 14.0
const COL_GAP := 28.0

var params: Dictionary = {}
var tid := ""
var ch: Variant = null
var debounce: Timer
var busy := ""
# list
var tab := "registration"
var vl: OUI.VList
var list_rows: Array = []
var list_loaded := false
var list_err := ""
# detail
var t: Dictionary = {}
var entries: Array = []
var matches: Array = []
var names: Dictionary = {}
var det_err := ""
var dtab := "board"
var team_name := ""
var body: VBoxContainer
var root: VBoxContainer
var _last_next := ""


func setup(p: Dictionary) -> void:
	params = p
	tid = OUI.s(p.get("id", ""))


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.timeout.connect(_reload)
	add_child(debounce)
	if tid == "":
		_build_list()
	else:
		_build_detail()


func leave() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _reload() -> void:
	if tid == "":
		_load_list()
	else:
		_load_detail()


func _soon(sec: float) -> void:
	debounce.wait_time = sec
	debounce.start()


# ================================================================ list
func _build_list() -> void:
	root = OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var add := OUI.pill("+", _open_create, OUI.GREEN, 44, 44)
	add.add_theme_font_override("font", OUI.font("title"))
	add.add_theme_font_size_override("font_size", OUI.px(22))
	root.add_child(OUI.header(I18n.t("tournaments.tournaments"), "TOURNAMENTS", func() -> void: Nav.back(), add, OUI.ORANGE, _load_list))
	vl = OUI.VList.new(92, _make_tour_row, _bind_tour_row, 8)
	root.add_child(vl)
	vl.set_header(OUI.margin(OUI.segment([["registration", I18n.t("tournaments.sign_up")], ["running", I18n.t("challenges.in_progress")], ["finished", I18n.t("tournaments.finished")]], tab, func(v: Variant) -> void:
		tab = str(v)
		list_loaded = false
		list_rows = []
		_apply_list()
		_load_list()
		_sub_list()), OUI.S_L, OUI.S_M, OUI.S_L, OUI.S_M))
	_apply_list()
	_load_list()
	_sub_list()
	OUI.fade_in(root)


func _sub_list() -> void:
	if ch != null:
		Supa.remove_channel(ch)
	ch = Supa.channel("tours:" + tab, {})
	ch.on_postgres("*", "public", "tournaments", "", func(_r: Variant) -> void: _soon(0.5))
	ch.on_postgres("*", "public", "tournament_entries", "", func(_r: Variant) -> void: _soon(0.5))
	ch.subscribe(func(_s: Variant) -> void: pass)


func _load_list() -> void:
	var want := tab
	var r: Dictionary = await OUI.get_rows("tournaments?select=*,entries:tournament_entries(count)&status=eq.%s&order=created_at.desc&limit=50" % tab)
	if not is_inside_tree() or want != tab:
		return
	if not OUI.ok(r):
		list_err = OUI.err(r)
	else:
		list_err = ""
		list_rows = OUI.rows(r)
		list_loaded = true
	_apply_list()


func _apply_list() -> void:
	vl.set_items(list_rows)
	if list_err != "":
		vl.set_empty(OUI.error_state(list_err, _load_list))
	elif not list_loaded:
		vl.set_empty(OUI.skeleton(4, 92))
	else:
		var reg := tab == "registration"
		vl.set_empty(OUI.empty(OUI.ui2("x_trophy"), I18n.t("tournaments.no_tournaments_in_this_section"), I18n.t("tournaments.create_the_first_tournament_yourself") if reg else "", I18n.t("tournaments.create_tournament") if reg else "", _open_create))


class TourRow extends Button:
	var im: TextureRect
	var name_l: Label
	var badges: HBoxContainer
	var cnt_l: Label
	var gem_l: Label
	var id := ""


func _make_tour_row() -> Control:
	var b := TourRow.new()
	b.focus_mode = Control.FOCUS_NONE
	var h := OUI.hbox(OUI.S_M)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = OUI.px(12)
	h.offset_right = -OUI.px(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.im = OUI.img(null, 52)
	h.add_child(b.im)
	var v := OUI.vbox(OUI.S_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	b.badges = OUI.hbox(OUI.S_XS)
	v.add_child(b.name_l)
	v.add_child(b.badges)
	h.add_child(v)
	var cv := OUI.vbox(2)
	cv.custom_minimum_size.x = OUI.px(60)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	b.cnt_l = OUI.lbl("", OUI.TS_H, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER)
	b.gem_l = OUI.lbl("", OUI.TS_CAP, OUI.GEM_BLUE, "body", HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(b.cnt_l)
	cv.add_child(b.gem_l)
	h.add_child(cv)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		OUI.press_fx(b)
		OUI.sfx("ui")
		Nav.go("tournaments", {"id": b.id}))
	return b


func _bind_tour_row(c: Control, item: Variant, _i: int) -> void:
	var b := c as TourRow
	var it := OUI.d(item)
	b.id = OUI.s(it.get("id"))
	var stf: Array = STATUS_FA.get(OUI.s(it.get("status")), STATUS_FA["registration"])
	var st := OUI.sb(OUI.PANEL_BG, 22, Color(stf[1], 0.55), 1.5)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.im.texture = OUI.ui2("x_medal" if OUI.s(it.get("status")) == "finished" else "x_trophy")
	b.name_l.text = OUI.s(it.get("name"))
	OUI.clear(b.badges)
	var fmt := OUI.s(it.get("format"))
	var fmt_t: String = FORMAT_FA.get(fmt, fmt.replace("_", " ").capitalize())
	if fmt_t != "":  # an unknown/empty format used to leave an empty pill
		b.badges.add_child(OUI.badge(fmt_t, OUI.VIOLET))
	b.badges.add_child(OUI.badge(OUI.s(it.get("mode")).to_upper(), OUI.SKY))
	b.badges.add_child(OUI.badge(stf[0], stf[1], OUI.s(it.get("status")) == "running"))
	var cnt := 0
	var en: Variant = it.get("entries")
	if en is Array and en.size() > 0:
		cnt = OUI.i(OUI.d(en[0]).get("count"))
	b.cnt_l.text = "%s/%s" % [OUI.fa(cnt), OUI.fa(OUI.i(it.get("max_entries")))]
	b.gem_l.text = "💎 %s" % OUI.fa(OUI.i(it.get("prize_gems")))


func _open_create() -> void:
	var st := {"format": "single_elim", "mode": "1v1", "max": 8, "rounds": 2, "gems": 20, "min_lv": 1}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_XS)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
	var nf := OUI.field(I18n.t("tournaments.tournament_name"), I18n.t("tournaments.galaxy_cup"), 40)
	v.add_child(nf)
	v.add_child(OUI.cap_label(I18n.t("tournaments.format")))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", OUI.px(8))
	fl.add_theme_constant_override("v_separation", OUI.px(8))
	var rounds_box := OUI.vbox(OUI.S_XS)
	var chips: Dictionary = {}
	var rebuild_rounds := func() -> void:
		OUI.clear(rounds_box)
		var f: String = st["format"]
		if f == "league" or f == "swiss":
			rounds_box.add_child(OUI.cap_label(I18n.t("tournaments.number_of_home_and_away") if f == "league" else I18n.t("tournaments.number_of_rounds")))
			var items: Array = [[1, I18n.t("tournaments.one")], [2, I18n.t("tournaments.two")], [3, I18n.t("tournaments.three")]] if f == "league" else [[3, I18n.t("tournaments.3")], [4, I18n.t("tournaments.4")], [5, I18n.t("tournaments.5")], [6, I18n.t("tournaments.6")]]
			if f == "swiss" and int(st["rounds"]) < 3:
				st["rounds"] = 3
			if f == "league" and int(st["rounds"]) > 3:
				st["rounds"] = 2
			rounds_box.add_child(OUI.segment(items, st["rounds"], func(x: Variant) -> void: st["rounds"] = x, OUI.VIOLET))
	var paint := func() -> void:
		for k in chips:
			var on: bool = k == st["format"]
			var b: Button = chips[k]
			var s2 := OUI.sb(Color(OUI.VIOLET, 0.2) if on else Color(8 / 255.0, 12 / 255.0, 34 / 255.0, 0.7), 22, OUI.VIOLET if on else OUI.LINE, 1)
			s2.content_margin_left = OUI.px(16)
			s2.content_margin_right = OUI.px(16)
			for stt in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(stt, s2)
			for kk in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(kk, Color.WHITE if on else OUI.DIM)
	for f in FORMAT_FA:
		var fk: String = f
		var b := OUI.pill(FORMAT_FA[f], func() -> void:
			st["format"] = fk
			paint.call()
			rebuild_rounds.call(), OUI.DIM, 44, 44)
		chips[f] = b
		fl.add_child(b)
	paint.call()
	v.add_child(fl)
	v.add_child(OUI.cap_label(I18n.t("hub.mode")))
	v.add_child(OUI.segment([["1v1", "1v1"], ["2v2", "2v2"], ["3v3", "3v3"]], "1v1", func(x: Variant) -> void: st["mode"] = x))
	v.add_child(OUI.cap_label(I18n.t("tournaments.capacity")))
	v.add_child(OUI.segment([[4, I18n.t("tournaments.4")], [8, I18n.t("tournaments.8")], [16, I18n.t("tournaments.16")], [32, I18n.t("tournaments.32")], [64, I18n.t("tournaments.64")]], 8, func(x: Variant) -> void: st["max"] = x, OUI.ORANGE))
	v.add_child(rounds_box)
	rebuild_rounds.call()
	v.add_child(OUI.cap_label(I18n.t("tournaments.champion_prize_gems_runner_up")))
	v.add_child(OUI.segment([[0, I18n.t("tournaments.0")], [10, I18n.t("tournaments.10")], [20, I18n.t("tournaments.20")], [30, I18n.t("tournaments.30")]], 20, func(x: Variant) -> void: st["gems"] = x, OUI.SKY))
	v.add_child(OUI.cap_label(I18n.t("tournaments.minimum_level")))
	v.add_child(OUI.segment([[1, I18n.t("tournaments.1")], [3, I18n.t("tournaments.3")], [5, I18n.t("tournaments.5")], [10, I18n.t("tournaments.10")]], 1, func(x: Variant) -> void: st["min_lv"] = x, OUI.GREEN))
	v.add_child(OUI.spacer(OUI.S_L))
	var go := OUI.btn(I18n.t("tournaments.create_tournament"), Callable(), "gold")
	go.pressed.connect(func() -> void:
		var nm := OUI.field_value(nf).strip_edges()
		if nm.length() < 3:
			OUI.toast_err(I18n.t("tournaments.tournament_name_must_be_at"))
			return
		go.disabled = true
		go.text = I18n.t("hub.creating")
		var f: String = st["format"]
		var r: Dictionary = await Supa.call_rpc("create_tournament", {"p_name": nm, "p_format": f, "p_mode": st["mode"], "p_max": st["max"], "p_rounds": st["rounds"] if (f == "league" or f == "swiss") else null, "p_prize_gems": st["gems"], "p_starts": null, "p_min_level": st["min_lv"]})
		if OUI.ok(r):
			OUI.sfx("ready")
			OUI.buzz("success")
			OUI.toast(I18n.t("tournaments.tournament_created"), "ok")
			Nav.close_sheet()
			var dd: Variant = r.get("data")
			if dd is Array and dd.size() > 0:
				dd = dd[0]
			Nav.go("tournaments", {"id": OUI.s(OUI.d(dd).get("id"))})
		else:
			OUI.toast_err(OUI.err(r))
			if is_instance_valid(go):
				go.disabled = false
				go.text = I18n.t("tournaments.create_tournament"))
	v.add_child(go)
	OUI.open_sheet(I18n.t("tournaments.create_tournament"), "NEW TOURNAMENT", sc, OUI.ORANGE, 0.9)


# ================================================================ detail
func _build_detail() -> void:
	var pg := OUI.page(self, I18n.t("hub.tournament"), "", func() -> void: Nav.back(), null, OUI.ORANGE, _load_detail)
	root = pg["root"]
	body = pg["body"]
	body.add_child(OUI.spinner(36))
	_load_detail()
	ch = Supa.channel("tour:" + tid, {})
	ch.on_postgres("*", "public", "tournaments", "id=eq." + tid, func(_r: Variant) -> void: _soon(0.3))
	ch.on_postgres("*", "public", "tournament_entries", "tournament_id=eq." + tid, func(_r: Variant) -> void: _soon(0.3))
	ch.on_postgres("*", "public", "tournament_matches", "tournament_id=eq." + tid, func(_r: Variant) -> void: _soon(0.3))
	ch.subscribe(func(_s: Variant) -> void: pass)


func _load_detail() -> void:
	var a: Dictionary = await OUI.get_rows("tournaments?select=*&id=eq." + tid)
	var b: Dictionary = await OUI.get_rows("standings?select=*&tournament_id=eq.%s&order=pos" % tid)
	var c: Dictionary = await OUI.get_rows("tournament_matches?select=*&tournament_id=eq.%s&order=round,idx" % tid)
	if not is_inside_tree():
		return
	if not OUI.ok(a) or not OUI.ok(b) or not OUI.ok(c):
		det_err = OUI.err(a if not OUI.ok(a) else (b if not OUI.ok(b) else c))
		if t.is_empty():
			OUI.clear(body)
			body.add_child(OUI.error_state(det_err, _load_detail))
		return
	det_err = ""
	var tt: Variant = OUI.one(a)
	if tt == null:
		OUI.clear(body)
		body.add_child(OUI.error_state(I18n.t("tournaments.tournament_not_found"), _load_detail))
		return
	t = tt
	entries = OUI.rows(b)
	matches = OUI.rows(c)
	names = {}
	for e in entries:
		names[OUI.s(e.get("id"))] = OUI.s(e.get("team_name"))
	_render_detail()


func _my_entry() -> Dictionary:
	var u := OUI.uid()
	if u == "":
		return {}
	for e in entries:
		if OUI.a(e.get("members")).has(u):
			return e
	return {}


func _is_elim() -> bool:
	var f := OUI.s(t.get("format"))
	return f == "single_elim" or f == "double_elim"


func _run(k: String, fn: Callable, ok_msg: String = "") -> void:
	if busy != "":
		return
	busy = k
	_render_detail()
	var r: Dictionary = await fn.call()
	busy = ""
	if not is_inside_tree():
		return
	if OUI.ok(r):
		if ok_msg != "":
			OUI.toast(ok_msg, "ok")
			OUI.buzz("success")
		await _load_detail()
	else:
		OUI.toast_err(OUI.err(r))
		OUI.buzz("heavy")
		_render_detail()


func _render_detail() -> void:
	if t.is_empty():
		return
	var hd: Control = root.get_child(0)
	var tl: Label = hd.get_meta("title")
	tl.text = OUI.s(t.get("name"))
	var me := _my_entry()
	var my_id := OUI.s(me.get("id"))
	var is_org := OUI.s(t.get("created_by")) == OUI.uid() and OUI.uid() != ""
	var next: Dictionary = {}
	if my_id != "":
		for m in matches:
			var stt := OUI.s(m.get("status"))
			if (stt == "ready" or stt == "live") and (OUI.s(m.get("entry_a")) == my_id or OUI.s(m.get("entry_b")) == my_id):
				next = m
				break
	if not next.is_empty() and OUI.s(next.get("status")) == "ready" and _last_next != OUI.s(next.get("id")):
		_last_next = OUI.s(next.get("id"))
		OracleCoach.react("tourReady")
	var status := OUI.s(t.get("status"))
	var stf: Array = STATUS_FA.get(status, STATUS_FA["registration"])
	OUI.clear(body)
	# info
	var ip := OUI.panel(stf[1])
	var iv := OUI.vbox(OUI.S_S)
	var bf := HFlowContainer.new()
	bf.add_theme_constant_override("h_separation", OUI.px(4))
	bf.add_theme_constant_override("v_separation", OUI.px(4))
	bf.add_child(OUI.badge(stf[0], stf[1], status == "running"))
	bf.add_child(OUI.badge(I18n.t("tournaments.x_x_players") % [OUI.fa(entries.size()), OUI.fa(OUI.i(t.get("max_entries")))], OUI.SKY))
	bf.add_child(OUI.badge(I18n.t("tournaments.x_champion") % OUI.fa(OUI.i(t.get("prize_gems"))), OUI.GEM_BLUE))
	bf.add_child(OUI.badge("%s XP" % OUI.fa(OUI.i(t.get("prize_xp"))), OUI.CYAN))
	bf.add_child(OUI.badge("%s · %s" % [FORMAT_FA.get(OUI.s(t.get("format")), ""), OUI.s(t.get("mode")).to_upper()], OUI.VIOLET))
	if OUI.i(t.get("min_level"), 1) > 1:
		bf.add_child(OUI.badge(I18n.t("tournaments.min_level_x") % OUI.fa(OUI.i(t.get("min_level"))), OUI.GREEN))
	if status != "registration" and OUI.i(t.get("current_round")) > 0:
		bf.add_child(OUI.badge(I18n.t("tournaments.round_x") % OUI.fa(OUI.i(t.get("current_round"))), OUI.VIOLET))
	iv.add_child(bf)
	var w := OUI.s(t.get("winner_entry"))
	if w != "" and names.has(w):
		var wh := OUI.hbox(OUI.S_S)
		wh.add_child(OUI.img(OUI.ui2("x_trophy"), 44))
		wh.add_child(OUI.flbl(I18n.t("tournaments.champion_x") % names[w], OUI.TS_H, OUI.GOLD, "title"))
		iv.add_child(wh)
	ip.add_child(iv)
	body.add_child(ip)
	# actions
	if status == "registration":
		if my_id != "":
			body.add_child(OUI.btn("…" if busy == "leave" else I18n.t("tournaments.leave_tournament"), func() -> void:
				_run("leave", func() -> Dictionary: return await Supa.call_rpc("leave_tournament", {"p_tid": tid}), I18n.t("tournaments.you_left_the_tournament")), "dark", true))
		elif entries.size() < OUI.i(t.get("max_entries")):
			if OUI.s(t.get("mode")) != "1v1":
				var nf := OUI.field(I18n.t("tournaments.team_name_optional"), "", 24)
				var le: LineEdit = nf.get_meta("input")
				le.text = team_name
				le.text_changed.connect(func(x: String) -> void: team_name = x)
				body.add_child(nf)
			body.add_child(OUI.btn("…" if busy == "join" else I18n.t("tournaments.sign_up"), func() -> void:
				var tn := team_name.strip_edges()
				_run("join", func() -> Dictionary: return await Supa.call_rpc("join_tournament", {"p_tid": tid, "p_team_name": tn if tn != "" else null, "p_members": null}), I18n.t("tournaments.you_re_signed_up")), "green"))
		else:
			body.add_child(OUI.lbl(I18n.t("tournaments.tournament_is_full"), OUI.TS_BODY, OUI.ORANGE, "body", HORIZONTAL_ALIGNMENT_CENTER))
	if is_org and status == "registration":
		var sb := OUI.btn("…" if busy == "start" else I18n.t("tournaments.start_tournament_x_players") % OUI.fa(entries.size()), func() -> void:
			_run("start", func() -> Dictionary: return await Supa.call_rpc("start_tournament", {"p_tid": tid}), I18n.t("tournaments.tournament_started")), "gold")
		sb.disabled = entries.size() < 2
		body.add_child(sb)
	if not next.is_empty():
		var np := OUI.panel(OUI.RED, OUI.S_M, true)
		var nv := OUI.vbox(OUI.S_S)
		nv.add_child(OUI.lbl(I18n.t("tournaments.your_next_match"), OUI.TS_SMALL, OUI.RED, "bold"))
		nv.add_child(OUI.lbl("%s  vs  %s" % [names.get(OUI.s(next.get("entry_a")), I18n.t("tournaments.sym")), names.get(OUI.s(next.get("entry_b")), I18n.t("tournaments.sym"))], OUI.TS_H, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		var nid := OUI.s(next.get("id"))
		nv.add_child(OUI.btn("…" if busy == "room" else I18n.t("tournaments.enter_match"), func() -> void: _open_room(nid), "red"))
		np.add_child(nv)
		body.add_child(np)
	body.add_child(OUI.spacer(OUI.S_S))
	body.add_child(OUI.segment([["board", I18n.t("tournaments.bracket") if _is_elim() else I18n.t("tournaments.table")], ["entries", I18n.t("tournaments.participants")]], dtab, func(v: Variant) -> void:
		dtab = str(v)
		_render_detail()))
	body.add_child(OUI.spacer(OUI.S_S))
	if dtab == "entries":
		if entries.is_empty():
			body.add_child(OUI.empty(OUI.ui2("x_ball"), I18n.t("tournaments.no_one_has_signed_up")))
		for e in entries:
			var row := OUI.row_box(OUI.S_M, 48)
			var h := OUI.hbox(OUI.S_S)
			var sl := OUI.lbl(("#%s" % OUI.fa(OUI.i(e.get("seed")))) if e.get("seed") != null else "•", OUI.TS_BODY, OUI.DIM, "bold")
			sl.custom_minimum_size.x = OUI.px(36)
			h.add_child(sl)
			h.add_child(OUI.flbl(OUI.s(e.get("team_name")), OUI.TS_BODY, OUI.TEXT, "bold"))
			if bool(e.get("eliminated", false)):
				h.add_child(OUI.badge(I18n.t("tournaments.out"), OUI.RED))
			elif OUI.i(e.get("final_rank")) == 1:
				h.add_child(OUI.badge(I18n.t("data.champion"), OUI.GOLD))
			row.add_child(h)
			body.add_child(row)
	elif status == "registration":
		body.add_child(OUI.empty(OUI.ui2("c_calendar"), I18n.t("tournaments.the_bracket_is_created_once"), I18n.t("tournaments.the_organizer_starts_the_tournament")))
	elif _is_elim():
		_bracket(my_id, is_org)
	else:
		_standings(my_id, is_org)


func _open_room(tm_id: String) -> void:
	if busy != "":
		return
	busy = "room"
	_render_detail()
	var r: Dictionary = await Supa.call_rpc("open_tournament_room", {"p_tm": tm_id})
	busy = ""
	if OUI.ok(r):
		OUI.enter_room(r.get("data"))
	else:
		OUI.toast_err(OUI.err(r))
		if is_inside_tree():
			_render_detail()


static func round_label(rnd: int, total: int) -> String:
	var left := total - rnd
	match left:
		0: return I18n.t("tournaments.final")
		1: return I18n.t("tournaments.semi_final")
		2: return I18n.t("tournaments.quarter_final")
		3: return I18n.t("tournaments.round_of_16")
		4: return I18n.t("tournaments.round_of_32")
	return I18n.t("tournaments.round_x") % OUI.fa(rnd)


func _bracket(my_id: String, is_org: bool) -> void:
	var sections: Array = []
	if OUI.s(t.get("format")) == "double_elim":
		sections = [[I18n.t("tournaments.winners_bracket"), "winners"], [I18n.t("tournaments.losers_bracket"), "losers"], [I18n.t("tournaments.grand_final"), "final"]]
	else:
		sections = [["", "main"]]
	for s in sections:
		var ms := matches.filter(func(m: Variant) -> bool: return OUI.s(m.get("bracket")) == s[1])
		if ms.is_empty():
			continue
		var labels: bool = OUI.s(t.get("format")) != "double_elim" or s[0] == I18n.t("tournaments.winners_bracket")
		if s[0] != "":
			body.add_child(OUI.lbl(s[0], OUI.TS_BODY, OUI.TEXT, "bold"))
		body.add_child(_bracket_section(ms, my_id, is_org, labels))


func _bracket_section(ms: Array, my_id: String, is_org: bool, labels: bool) -> Control:
	var by_round: Dictionary = {}
	for m in ms:
		var rnd := OUI.i(m.get("round"))
		if not by_round.has(rnd):
			by_round[rnd] = []
		by_round[rnd].append(m)
	var keys := by_round.keys()
	keys.sort()
	var rounds: Array = []
	for k in keys:
		var col: Array = by_round[k]
		col.sort_custom(func(x: Variant, y: Variant) -> bool: return OUI.i(x.get("idx")) < OUI.i(y.get("idx")))
		rounds.append(col)
	var total := rounds.size()
	var first_n := maxi(1, (rounds[0] as Array).size())
	var bw := OUI.px(BOX_W)
	var bh := OUI.px(BOX_H)
	var gap := OUI.px(GAP)
	var cg := OUI.px(COL_GAP)
	var lab_h := OUI.px(24)
	var H := maxf(first_n * (bh + gap), bh + gap)
	var view := BracketLines.new()
	view.layout_direction = Control.LAYOUT_DIRECTION_LTR
	view.custom_minimum_size = Vector2(total * (bw + cg), H + lab_h)
	var lines: Array = []
	for ri in total:
		var col: Array = rounds[ri]
		var x := ri * (bw + cg)
		var lab := OUI.lbl(round_label(ri + 1, total) if labels else I18n.t("tournaments.round_x") % OUI.fa(ri + 1), OUI.TS_CAP, OUI.CYAN, "bold", HORIZONTAL_ALIGNMENT_CENTER)
		lab.position = Vector2(x, 0)
		lab.size = Vector2(bw, lab_h)
		view.add_child(lab)
		var slot_h := H / col.size()
		for i2 in col.size():
			var m: Dictionary = col[i2]
			var top := lab_h + i2 * slot_h + (slot_h - bh) / 2.0
			var mine := my_id != "" and (OUI.s(m.get("entry_a")) == my_id or OUI.s(m.get("entry_b")) == my_id)
			var stt := OUI.s(m.get("status"))
			var box := _match_box(m, mine)
			var ctrl: Control = box
			if is_org and (stt == "ready" or stt == "live"):
				var mm := m
				ctrl = OUI.tap(box, func() -> void: _override(mm))
			ctrl.position = Vector2(x, top)
			ctrl.size = Vector2(bw, bh)
			view.add_child(ctrl)
			if ri < total - 1:
				var cy := top + bh / 2.0
				lines.append([Vector2(x + bw, cy), Vector2(x + bw + cg / 2.0, cy)])
				var vy0 := cy if i2 % 2 == 0 else cy - slot_h / 2.0
				lines.append([Vector2(x + bw + cg / 2.0, vy0), Vector2(x + bw + cg / 2.0, vy0 + slot_h / 2.0)])
				if i2 % 2 == 0:
					lines.append([Vector2(x + bw + cg / 2.0, cy + slot_h / 2.0), Vector2(x + bw + cg, cy + slot_h / 2.0)])
	view.lines = lines
	var sc := OUI.hscroll()
	sc.layout_direction = Control.LAYOUT_DIRECTION_LTR
	sc.custom_minimum_size.y = H + lab_h + OUI.px(8)
	sc.add_child(view)
	return sc


class BracketLines extends Control:
	var lines: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var c := Color(120 / 255.0, 200 / 255.0, 1, 0.45)
		for l in lines:
			draw_line(l[0], l[1], c, 2.0, true)


func _match_box(m: Dictionary, mine: bool) -> Control:
	var stt := OUI.s(m.get("status"))
	var live := stt == "live"
	var done := stt == "done" or stt == "bye"
	var pc := PanelContainer.new()
	var border := OUI.RED if live else (OUI.CYAN if mine else OUI.LINE)
	pc.add_theme_stylebox_override("panel", OUI.sb(Color(10 / 255.0, 16 / 255.0, 44 / 255.0, 0.95), 12, border, 1))
	if done:
		pc.modulate.a = 0.9
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_side(m, "entry_a", "score_a"))
	v.add_child(OUI.divider())
	v.add_child(_side(m, "entry_b", "score_b"))
	pc.add_child(v)
	if live:
		var dot := ColorRect.new()
		dot.color = OUI.RED
		dot.size = Vector2(OUI.px(7), OUI.px(7))
		dot.position = Vector2(OUI.px(4), OUI.px(4))
		pc.add_child(dot)
		dot.top_level = false
	return pc


func _side(m: Dictionary, ek: String, sk: String) -> Control:
	var e := OUI.s(m.get(ek))
	var win := e != "" and OUI.s(m.get("winner_entry")) == e
	var stt := OUI.s(m.get("status"))
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", OUI.sb(Color(1, 210 / 255.0, 87 / 255.0, 0.14) if win else Color(0, 0, 0, 0), 0))
	var h := OUI.hbox(4)
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var sc: Variant = m.get(sk)
	var sl := OUI.lbl(OUI.fa(OUI.i(sc)) if sc != null else ("–" if stt == "bye" and e != "" else ""), OUI.TS_SMALL, OUI.GOLD if win else OUI.DIM, "title", HORIZONTAL_ALIGNMENT_CENTER)
	sl.custom_minimum_size.x = OUI.px(22)
	h.add_child(sl)
	var nm: String = str(names.get(e, "…")) if e != "" else (I18n.t("tournaments.bye") if stt == "bye" else "—")
	h.add_child(OUI.flbl(nm, OUI.TS_SMALL, (OUI.GOLD if win else OUI.TEXT) if e != "" else OUI.DIM2, "bold" if win else "body"))
	pc.add_child(OUI.margin(h, 6, 0, 6, 0))
	return pc


func _standings(my_id: String, is_org: bool) -> void:
	var head := OUI.hbox(0)
	var heads := ["#", I18n.t("tournaments.team"), I18n.t("tournaments.match"), I18n.t("tournaments.w"), I18n.t("tournaments.d"), I18n.t("tournaments.l"), I18n.t("tournaments.goals"), I18n.t("online_result.rating")]
	for k in heads.size():
		var l := OUI.lbl(heads[k], OUI.TS_SMALL, OUI.DIM, "bold", I18n.AR if k == 1 else HORIZONTAL_ALIGNMENT_CENTER)
		if k == 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = OUI.px(44 if k == 6 else (40 if k == 7 else 30))
		head.add_child(l)
	head.custom_minimum_size.y = OUI.px(40)
	body.add_child(head)
	body.add_child(OUI.divider())
	for e in entries:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.1) if OUI.s(e.get("id")) == my_id else Color(0, 0, 0, 0), 8))
		var h := OUI.hbox(0)
		h.custom_minimum_size.y = OUI.px(40)
		var vals := [OUI.fa(OUI.i(e.get("pos"))), OUI.s(e.get("team_name")), OUI.fa(OUI.i(e.get("played"))), OUI.fa(OUI.i(e.get("wins"))), OUI.fa(OUI.i(e.get("draws"))), OUI.fa(OUI.i(e.get("losses"))), "%s:%s" % [OUI.fa(OUI.i(e.get("gf"))), OUI.fa(OUI.i(e.get("ga")))], OUI.fa(OUI.i(e.get("points")))]
		for k in vals.size():
			var l := OUI.lbl(vals[k], OUI.TS_SMALL, OUI.GOLD if k == 7 else OUI.TEXT, "title" if k == 7 else ("bold" if k == 1 else "body"), I18n.AR if k == 1 else HORIZONTAL_ALIGNMENT_CENTER)
			if k == 1:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else:
				l.custom_minimum_size.x = OUI.px(44 if k == 6 else (40 if k == 7 else 30))
			h.add_child(l)
		row.add_child(h)
		body.add_child(row)
	var open := matches.filter(func(m: Variant) -> bool: return OUI.s(m.get("status")) in ["ready", "live"])
	if open.is_empty():
		return
	body.add_child(OUI.section_title(I18n.t("tournaments.open_tournaments")))
	for m in open:
		var mine := my_id != "" and (OUI.s(m.get("entry_a")) == my_id or OUI.s(m.get("entry_b")) == my_id)
		var row := OUI.row_box(OUI.S_M, 48, OUI.CYAN if mine else OUI.LINE)
		var h := OUI.hbox(OUI.S_S)
		h.add_child(OUI.badge(I18n.t("tournaments.round_x") % OUI.fa(OUI.i(m.get("round"))), OUI.VIOLET))
		h.add_child(OUI.flbl("%s  vs  %s" % [names.get(OUI.s(m.get("entry_a")), I18n.t("tournaments.sym")), names.get(OUI.s(m.get("entry_b")), I18n.t("tournaments.sym"))], OUI.TS_SMALL))
		if OUI.s(m.get("status")) == "live":
			h.add_child(OUI.badge(I18n.t("hub.live"), OUI.RED, true))
		row.add_child(h)
		if is_org:
			var mm: Dictionary = m
			body.add_child(OUI.tap(row, func() -> void: _override(mm)))
		else:
			body.add_child(row)


func _override(m: Dictionary) -> void:
	var sc := [0, 0]
	var v := OUI.vbox(OUI.S_S)
	v.add_child(OUI.lbl(I18n.t("tournaments.result_entry_by_the_organizer"), OUI.TS_H, OUI.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER))
	for side in 2:
		var e := OUI.s(m.get("entry_a" if side == 0 else "entry_b"))
		var h := OUI.hbox(OUI.S_S)
		h.add_child(OUI.flbl(names.get(e, I18n.t("tournaments.sym")), OUI.TS_BODY))
		var step := OUI.hbox(4)
		step.layout_direction = Control.LAYOUT_DIRECTION_LTR
		var val := OUI.lbl(I18n.t("tournaments.0"), 24, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER)
		val.custom_minimum_size.x = OUI.px(40)
		var sd := side
		step.add_child(OUI.pill("−", func() -> void:
			sc[sd] = maxi(0, sc[sd] - 1)
			val.text = OUI.fa(sc[sd]), OUI.TEXT, 44, 44))
		step.add_child(val)
		step.add_child(OUI.pill("+", func() -> void:
			sc[sd] = mini(30, sc[sd] + 1)
			val.text = OUI.fa(sc[sd]), OUI.TEXT, 44, 44))
		h.add_child(step)
		v.add_child(h)
	var holder: Array = [null]
	var close := func() -> void:
		if holder[0] != null and is_instance_valid(holder[0]):
			(holder[0] as Node).queue_free()
	var mid := OUI.s(m.get("id"))
	v.add_child(OUI.btn(I18n.t("tournaments.submit"), func() -> void:
		close.call()
		_run("ovr", func() -> Dictionary: return await Supa.call_rpc("set_tournament_result", {"p_tm": mid, "p_sa": sc[0], "p_sb": sc[1]}), I18n.t("tournaments.result_saved")), "gold"))
	v.add_child(OUI.btn(I18n.t("nav.cancel"), close, "dark", true))
	holder[0] = OUI.modal(self, v, OUI.GOLD, close)
