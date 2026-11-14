extends Control
## Leaderboard (top 100 by rating, my rank highlighted) + league ladder with season countdown & rewards
## (port of RN Ranks.tsx). params: {tab?: "top"|"leagues"}
## Tables/RPC: leaderboard (view), leagues, season_rewards, rpc current_season, claim_season_reward.

var params: Dictionary = {}
var tab := "top"
var root: VBoxContainer
var hdr: Control
var content: Control
var vl: OUI.VList
var lb_rows: Array = []
var lb_me: Dictionary = {}
var lb_err := ""
var lb_loaded := false
var season: Dictionary = {}
var rewards: Dictionary = {}
var season_l: Label
var claim_busy := false
var tick: Timer


func setup(p: Dictionary) -> void:
	params = p
	tab = OUI.s(p.get("tab", "top"), "top")
	if OUI.s(p.get("entry", "")) == "leagues":
		tab = "leagues"
	if tab != "leagues":
		tab = "top"


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	tick = Timer.new()
	tick.wait_time = 30.0
	tick.timeout.connect(_upd_season)
	add_child(tick)
	tick.start()
	_build()


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _build() -> void:
	OUI.clear(root)
	if root == null:
		root = OUI.vbox(0)
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(root)
	hdr = OUI.header(I18n.t("hub.leaderboard") if tab == "top" else I18n.t("ranks.leagues_season"), "LEADERBOARD" if tab == "top" else "LEAGUES · SEASON", func() -> void: Nav.back(), null, OUI.GOLD, _reload)
	root.add_child(hdr)
	root.add_child(OUI.margin(OUI.segment([["top", I18n.t("ranks.top_players")], ["leagues", I18n.t("ranks.leagues")]], tab, func(v: Variant) -> void:
		tab = str(v)
		_build()), OUI.S_L, OUI.S_S, OUI.S_L, OUI.S_S))
	if tab == "top":
		vl = OUI.VList.new(58, make_lb_row, _bind, 6)
		root.add_child(vl)
		_apply_lb()
		_load_lb()
	else:
		var sc := OUI.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(sc)
		content = OUI.vbox(OUI.S_S)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(OUI.margin(content, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
		_load_leagues()
	OUI.fade_in(root)


func _reload() -> void:
	if tab == "top":
		await _load_lb()
	else:
		await _load_leagues()


# ---------------------------------------------------------------- leaderboard
func _load_lb() -> void:
	var u := OUI.uid()
	var a: Dictionary = await OUI.get_rows("leaderboard?select=*&order=rank&limit=100")
	var b: Dictionary = {}
	if u != "":
		b = await OUI.get_rows("leaderboard?select=*&id=eq." + u)
	if not is_inside_tree() or tab != "top":
		return
	if not OUI.ok(a):
		lb_err = OUI.err(a)
	else:
		lb_err = ""
		lb_rows = OUI.rows(a)
		lb_me = OUI.d(OUI.one(b))
		lb_loaded = true
	_apply_lb()


func _apply_lb() -> void:
	if vl == null or not is_instance_valid(vl):
		return
	var u := OUI.uid()
	var in_top := false
	for r in lb_rows:
		if OUI.s(r.get("id")) == OUI.s(lb_me.get("id")):
			in_top = true
	if not lb_me.is_empty() and not in_top:
		var h := make_lb_row()
		h.custom_minimum_size.y = OUI.px(58)
		bind_lb_row(h, lb_me, true, Callable())
		vl.set_header(OUI.margin(h, OUI.S_L, 0, OUI.S_L, OUI.S_S))
	else:
		vl.set_header(null)
	vl.set_items(lb_rows)
	if lb_err != "":
		vl.set_empty(OUI.error_state(lb_err, _load_lb))
	elif not lb_loaded:
		vl.set_empty(OUI.skeleton(8, 60))
	else:
		vl.set_empty(OUI.empty(OUI.ui2("x_ball"), I18n.t("ranks.no_one_is_on_the")))
	var _u := u


func _bind(c: Control, item: Variant, _i: int) -> void:
	var it := OUI.d(item)
	var id := OUI.s(it.get("id"))
	bind_lb_row(c, it, id == OUI.uid(), func() -> void: Nav.go("public_profile", {"id": id}))


class LbRow extends Button:
	var rank_bg: PanelContainer
	var rank_l: Label
	var av: NetImg.Avatar
	var name_l: Label
	var sub_l: Label
	var lg: TextureRect
	var metric_l: Label
	var metric_cap: Label
	var bg: StyleBoxFlat
	var cb: Callable


## shared with arena.gd (RN LbItem)
static func make_lb_row() -> Control:
	var b := LbRow.new()
	b.focus_mode = Control.FOCUS_NONE
	b.bg = OUI.sb(OUI.ROW_BG, 16, OUI.LINE, 1)
	b.bg.content_margin_left = OUI.px(8)
	b.bg.content_margin_right = OUI.px(8)
	for stt in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(stt, b.bg)
	var h := OUI.hbox(OUI.S_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = OUI.px(8)
	h.offset_right = -OUI.px(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.rank_bg = PanelContainer.new()
	b.rank_bg.custom_minimum_size = Vector2(OUI.px(34), OUI.px(34))
	b.rank_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.rank_l = OUI.lbl("", 13, OUI.DIM, "title", HORIZONTAL_ALIGNMENT_CENTER)
	b.rank_bg.add_child(b.rank_l)
	h.add_child(b.rank_bg)
	b.av = NetImg.avatar(null, null, 40)
	h.add_child(b.av)
	var v := OUI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	b.sub_l = OUI.lbl("", OUI.TS_TINY, OUI.DIM)
	v.add_child(b.name_l)
	v.add_child(b.sub_l)
	h.add_child(v)
	b.lg = OUI.img(null, 30)
	h.add_child(b.lg)
	var mv := OUI.vbox(0)
	mv.custom_minimum_size.x = OUI.px(56)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	b.metric_l = OUI.lbl("", 14, OUI.GOLD, "title", HORIZONTAL_ALIGNMENT_CENTER)
	b.metric_cap = OUI.lbl(I18n.t("online_result.rating"), 9, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
	mv.add_child(b.metric_l)
	mv.add_child(b.metric_cap)
	h.add_child(mv)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		OUI.press_fx(b)
		OUI.sfx("ui")
		if b.cb.is_valid():
			b.cb.call())
	return b


static func bind_lb_row(c: Control, r: Dictionary, mine: bool, cb: Callable, metric: Variant = null, metric_label: String = "") -> void:
	var b := c as LbRow
	b.cb = cb
	var rank := OUI.i(r.get("rank"))
	var medal: Variant = null
	if rank >= 1 and rank <= 3:
		medal = [OUI.GOLD, Color("#d6e2f0"), Color("#e0954a")][rank - 1]
	var st := b.bg.duplicate() as StyleBoxFlat
	st.border_color = OUI.CYAN if mine else OUI.LINE
	st.bg_color = Color(79 / 255.0, 227 / 255.0, 1, 0.12) if mine else OUI.ROW_BG
	for stt in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(stt, st)
	b.rank_bg.add_theme_stylebox_override("panel", OUI.sb(Color(medal, 0.2) if medal is Color else Color(0, 0, 0, 0), 17, medal if medal is Color else OUI.LINE, 1))
	b.rank_l.text = OUI.fa(rank)
	b.rank_l.add_theme_color_override("font_color", medal if medal is Color else OUI.DIM)
	b.av.set_data(r.get("avatar"), r.get("avatar_url"), medal if medal is Color else OUI.LINE)
	b.name_l.text = OUI.s(r.get("username")) + (I18n.t("ranks.you") if mine else "")
	b.sub_l.text = I18n.t("ranks.level_x_x_wins") % [OUI.fa(OUI.i(r.get("level"), 1)), OUI.fa(OUI.i(r.get("wins")))]
	b.lg.texture = OUI.league_tex(r.get("league"))
	b.metric_l.text = OUI.fa(metric if metric != null else OUI.i(r.get("rating")))
	b.metric_cap.text = metric_label if metric_label != "" else I18n.t("online_result.rating")


# ---------------------------------------------------------------- leagues + season
func _load_leagues() -> void:
	OUI.clear(content)
	content.add_child(OUI.skeleton(4, 64))
	var res: Array = await OUI.load_leagues()
	var s: Dictionary = await Supa.call_rpc("current_season", {})
	var rw: Dictionary = await OUI.get_rows("season_rewards?select=*")
	await OUI.refresh_profile()
	if not is_inside_tree() or tab != "leagues":
		return
	if OUI.ok(s):
		var sd: Variant = s.get("data")
		season = OUI.d(sd[0] if sd is Array and sd.size() > 0 else sd)
	rewards = {}
	for r in OUI.rows(rw):
		rewards[OUI.s(r.get("league"))] = OUI.i(r.get("gems"))
	_render_leagues(res)


func _season_text() -> String:
	if season.is_empty():
		return "…"
	var left := maxf(0.0, OUI.iso_to_unix(season.get("ends_at")) - OUI.now_s())
	var dd := int(floor(left / 86400.0))
	var hh := int(floor(fmod(left, 86400.0) / 3600.0))
	return I18n.t("ranks.x_days_x_hours_until") % [OUI.fa(dd), OUI.fa(hh)]


func _upd_season() -> void:
	if is_instance_valid(season_l):
		season_l.text = _season_text()


func _render_leagues(list0: Array) -> void:
	OUI.clear(content)
	# season card
	var sp := OUI.panel(OUI.VIOLET, OUI.S_M, true)
	var sv := OUI.vbox(OUI.S_S)
	var sh := OUI.hbox(OUI.S_M)
	sh.add_child(OUI.img(OUI.ui2("c_calendar"), 48))
	var stv := OUI.vbox(2)
	stv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stv.add_child(OUI.lbl(OUI.s(season.get("name"), I18n.t("ranks.current_season")) if not season.is_empty() else I18n.t("ranks.current_season"), OUI.TS_H, OUI.TEXT, "title"))
	season_l = OUI.lbl(_season_text(), OUI.TS_CAP, OUI.DIM)
	stv.add_child(season_l)
	sh.add_child(stv)
	sv.add_child(sh)
	sv.add_child(OUI.lbl(I18n.t("ranks.at_the_end_of_each"), OUI.TS_CAP, OUI.DIM, "body", I18n.AR, true, 3))
	var cb := OUI.btn(I18n.t("ranks.claim_last_season_s_reward"), Callable(), "violet", true)
	cb.pressed.connect(func() -> void:
		if claim_busy:
			return
		claim_busy = true
		cb.text = "…"
		cb.disabled = true
		var r: Dictionary = await Supa.call_rpc("claim_season_reward", {})
		claim_busy = false
		if is_instance_valid(cb):
			cb.text = I18n.t("ranks.claim_last_season_s_reward")
			cb.disabled = false
		if OUI.ok(r):
			OUI.sfx("win")
			OUI.buzz("success")
			var g := OUI.i(OUI.d(r.get("data")).get("gems"))
			OUI.toast(I18n.t("ranks.x_gems_season_reward") % OUI.fa(g), "ok")
			OracleCoach.react("reward", I18n.t("ranks.x_gems") % OUI.fa(g))
		else:
			OUI.toast_err(OUI.err(r)))
	sv.add_child(cb)
	sp.add_child(sv)
	content.add_child(sp)
	# my league progress
	var rating := OUI.i(OUI.profile.get("rating"))
	var list := list0.duplicate()
	list.sort_custom(func(x: Variant, y: Variant) -> bool: return OUI.i(x.get("sort")) < OUI.i(y.get("sort")))
	var cn := OUI.league_for(rating)
	var cur: Variant = cn[0]
	var nxt: Variant = cn[1]
	if not OUI.profile.is_empty() and cur != null:
		var cc := OUI.league_color(cur)
		var cp := OUI.panel(cc)
		var ch := OUI.hbox(OUI.S_M)
		ch.add_child(OUI.img(OUI.league_tex(cur.get("id")), 56))
		var cv := OUI.vbox(OUI.S_XS)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(OUI.lbl(I18n.t("ranks.x_league") % OUI.s(cur.get("name_fa")), OUI.TS_H, cc, "title"))
		var frac := 1.0
		if nxt != null:
			frac = float(rating - OUI.i(cur.get("min_rating"))) / float(maxi(1, OUI.i(nxt.get("min_rating")) - OUI.i(cur.get("min_rating"))))
		cv.add_child(OUI.bar(frac, cc, OUI.INDIGO))
		cv.add_child(OUI.lbl((I18n.t("ranks.x_x_to_x_league") % [OUI.fa(rating), OUI.fa(OUI.i(nxt.get("min_rating"))), OUI.s(nxt.get("name_fa"))]) if nxt != null else I18n.t("ranks.x_top_league") % OUI.fa(rating), OUI.TS_CAP, OUI.DIM))
		ch.add_child(cv)
		cp.add_child(ch)
		content.add_child(cp)
	content.add_child(OUI.section_title(I18n.t("ranks.league_ladder")))
	if list.is_empty():
		content.add_child(OUI.skeleton(7, 64))
		return
	list.reverse()
	for l in list:
		var col := OUI.league_color(l)
		var on := cur != null and OUI.s(cur.get("id")) == OUI.s(l.get("id"))
		var reached := rating >= OUI.i(l.get("min_rating"))
		var row := OUI.row_box(OUI.S_S, 68, col if on else OUI.LINE, Color(col, 0.12) if on else OUI.ROW_BG)
		var h := OUI.hbox(OUI.S_S)
		var im := OUI.img(OUI.league_tex(l.get("id")), 44)
		im.modulate.a = 1.0 if reached else 0.4
		h.add_child(im)
		var v := OUI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(OUI.lbl(OUI.s(l.get("name_fa")), OUI.TS_BODY, col if reached else OUI.DIM, "bold"))
		v.add_child(OUI.lbl(I18n.t("ranks.from_x_rating") % OUI.fa(OUI.i(l.get("min_rating"))), OUI.TS_TINY, OUI.DIM))
		h.add_child(v)
		if on:
			var bd := OUI.badge(I18n.t("ranks.your_league"), col)
			bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(bd)
		var rv := OUI.vbox(0)
		rv.custom_minimum_size.x = OUI.px(64)
		rv.alignment = BoxContainer.ALIGNMENT_CENTER
		rv.add_child(OUI.lbl("💎 %s" % OUI.fa(int(rewards.get(OUI.s(l.get("id")), 0))), OUI.TS_SMALL, OUI.GEM_BLUE, "bold", HORIZONTAL_ALIGNMENT_CENTER))
		rv.add_child(OUI.lbl(I18n.t("ranks.season_reward"), 9, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		h.add_child(rv)
		row.add_child(h)
		content.add_child(row)
