extends Control
## Arena: ranked ladder by arena points (+30 win +5/streak, −20 loss), streaks, find-match buttons
## (port of RN Arena.tsx). Tables/RPC: profiles (arena_points ladder), rpc quick_match(p_kind 'arena').

const Ranks := preload("res://src/online/ranks.gd")

var vl: OUI.VList
var rows_data: Array = []
var loaded := false
var err_msg := ""
var busy := ""
var hdr: Control
var pts_l: Label
var streak_l: Label
var best_l: Label
var btns: Dictionary = {}


func setup(_p: Dictionary) -> void:
	pass


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	var root := OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(OUI.header(I18n.t("arena.arena"), "ARENA LADDER", func() -> void: Nav.back(), null, OUI.VIOLET, _load))
	vl = OUI.VList.new(58, Ranks.make_lb_row, _bind, 6)
	root.add_child(vl)
	hdr = _make_header()
	vl.set_header(hdr)
	_apply()
	OUI.ebus().profile_changed.connect(_on_profile)
	OUI.fade_in(root)
	_load()
	OUI.refresh_profile()


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _make_header() -> Control:
	var v := OUI.vbox(OUI.S_S)
	var p := OUI.panel(OUI.VIOLET, OUI.S_L, true)
	var pv := OUI.vbox(OUI.S_S)
	var h := OUI.hbox(OUI.S_M)
	h.add_child(OUI.img(OUI.ui2("x_crown"), 64))
	var mv := OUI.vbox(0)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(OUI.lbl(I18n.t("arena.arena_rating"), OUI.TS_SMALL, OUI.DIM))
	pts_l = OUI.lbl("", 32, Color("#e2c8ff"), "title")
	mv.add_child(pts_l)
	h.add_child(mv)
	h.add_child(OUI.expand())
	pv.add_child(h)
	# stats row: two equal tiles (win streak · best streak), full width
	var sr := OUI.hbox(OUI.S_S)
	streak_l = OUI.lbl("", 20, OUI.ORANGE, "title", HORIZONTAL_ALIGNMENT_CENTER)
	best_l = OUI.lbl("", 20, Color("#e2c8ff"), "title", HORIZONTAL_ALIGNMENT_CENTER)
	for pair in [[streak_l, I18n.t("arena.win_streak")], [best_l, I18n.t("arena.best_x").replace("%s", "").strip_edges()]]:
		var tile := OUI.row_box(OUI.S_S, 64)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tv := OUI.vbox(0)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		(pair[0] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(pair[0])
		tv.add_child(OUI.lbl(str(pair[1]), OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(tv)
		sr.add_child(tile)
	pv.add_child(sr)
	pv.add_child(OUI.lbl(I18n.t("arena.win_30_and_5_per"), OUI.TS_CAP, OUI.DIM, "body", I18n.AR, true, 2))
	var bh := OUI.hbox(OUI.S_S)
	var styles := ["violet", "primary", "gold"]
	for k in 3:
		var m: String = OUI.MODES[k]
		var b := OUI.btn(m.to_upper(), func() -> void: _find(m), styles[k], true, I18n.t("arena.find_opponent"))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns[m] = b
		bh.add_child(b)
	pv.add_child(bh)
	p.add_child(pv)
	v.add_child(p)
	v.add_child(OUI.section_title(I18n.t("arena.arena_ladder")))
	_on_profile(OUI.profile)
	return OUI.margin(v, OUI.S_L, OUI.S_M, OUI.S_L, 0)


func _on_profile(p: Dictionary) -> void:
	if not is_instance_valid(pts_l):
		return
	pts_l.text = OUI.fa(OUI.i(p.get("arena_points")))
	streak_l.text = OUI.fa(OUI.i(p.get("win_streak")))
	best_l.text = OUI.fa(OUI.i(p.get("best_streak")))


func _load() -> void:
	var r: Dictionary = await OUI.get_rows("profiles?select=id,username,avatar,avatar_url,level,xp,rating,league,wins,losses,draws,trophies,arena_points&arena_points=gt.0&order=arena_points.desc&limit=50")
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		err_msg = OUI.err(r)
	else:
		err_msg = ""
		rows_data = []
		var k := 0
		for it in OUI.rows(r):
			k += 1
			var x: Dictionary = it.duplicate()
			x["rank"] = k
			rows_data.append(x)
		loaded = true
	_apply()


func _apply() -> void:
	vl.set_items(rows_data)
	if err_msg != "":
		vl.set_empty(OUI.error_state(err_msg, _load))
	elif not loaded:
		vl.set_empty(OUI.skeleton(6, 58))
	else:
		vl.set_empty(OUI.empty(OUI.ui2("x_crown"), I18n.t("arena.no_one_has_an_arena"), I18n.t("arena.be_the_first_to_win")))


func _bind(c: Control, item: Variant, _i: int) -> void:
	var it := OUI.d(item)
	var id := OUI.s(it.get("id"))
	Ranks.bind_lb_row(c, it, id == OUI.uid(), func() -> void: Nav.go("public_profile", {"id": id}), OUI.i(it.get("arena_points")), I18n.t("arena.arena"))


func _find(m: String) -> void:
	if busy != "":
		return
	busy = m
	for k in btns:
		(btns[k] as Button).disabled = true
		(btns[k] as Button).text = ("…" if k == m else k.to_upper()) + I18n.t("arena.nfind_opponent")
	var e: String = await OUI.quick_match(m, "arena")
	if not is_inside_tree():
		return
	busy = ""
	for k in btns:
		(btns[k] as Button).disabled = false
		(btns[k] as Button).text = k.to_upper() + I18n.t("arena.nfind_opponent")
	if e != "":
		OUI.toast_err(e)
