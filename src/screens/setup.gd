extends Control
## Match setup sheet (RN Setup.tsx): mode art, desc, reward, versus row (change team / reroll
## opponent), cup bracket, difficulty / rule / turn time segments, loadout row, start →
## builds the Launch exactly like RN buildLaunch and calls Nav.go("match", launch).

var mode := {}
var lvl := 1
var rule := "g3"
var tt := 15
var opp := {}
var opp_img: TextureRect
var opp_name: Label
var my_img: TextureRect
var my_name: Label

func setup(params: Dictionary) -> void:
	var m = params.get("mode", "quick")
	mode = m if m is Dictionary else Launch.mode(str(m))
	var p := UD.p()
	lvl = int(p.get("aiLvl", 1))
	rule = "g5" if int(p.get("limit", 3)) == 5 else "g3"
	tt = int(p.get("turnTime", 15))
	opp = params.get("opp", Launch.pick_opp())

func sheet_opts() -> Dictionary:
	return {"title": mode["name"], "en": mode["en"], "accent": mode["color"], "height": 0.9}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var k: String = mode["k"]
	var p := UD.p()
	var me := UD.team_by_id(str(p.get("team", "club0")))
	# flat v3: no stadium art / glow behind the setup sheet
	var sl := Kit.scroll_list(20)
	var sc: ScrollContainer = sl[0]
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var outer: VBoxContainer = sl[1]
	var v := Kit.vbox(20)
	outer.add_child(Kit.margin(v, NX.PAD, 0, NX.PAD, 120))
	v.add_child(Kit.para(mode["desc"], 34, NX.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var rw := PanelContainer.new()
	var rsb := NX.box(NX.SURF2, 36, 0)
	rsb.content_margin_left = 30; rsb.content_margin_right = 30; rsb.content_margin_top = 8; rsb.content_margin_bottom = 8
	rw.add_theme_stylebox_override("panel", rsb)
	rw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rh := Kit.hbox(14, true)
	rh.add_child(Kit.img(UD.ui2("c_coin"), 57))
	rh.add_child(Kit.label(mode["reward"], 31, NX.GOLD))
	rw.add_child(rh)
	v.add_child(rw)
	# versus
	var vs := PanelContainer.new()
	var vsb := NX.box(NX.SURF, 36, 2, NX.LINE)
	vsb.content_margin_top = 36; vsb.content_margin_bottom = 36; vsb.content_margin_left = 20; vsb.content_margin_right = 20
	vs.add_theme_stylebox_override("panel", vsb)
	var vg := NxGrad.new([Color(0.31, 0.89, 1.0, 0.18), Color(0.03, 0.047, 0.133, 0.0), Color(1, 0.29, 0.35, 0.18)], 50, 0.0, 0.0)
	vs.add_child(vg)
	var vh := Kit.hbox(10)
	vh.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := _side(UD.team_tex(me), me["name"], I18n.t("home.disc"), NX.CYAN, Callable())
	my_img = left.get_meta("img")
	my_name = left.get_meta("name")
	vh.add_child(left)
	var vs_l := Kit.title("VS", 56, NX.DIM)
	vs_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vh.add_child(vs_l)
	var local := k == "local"
	var right := _side(UD.team_tex(me) if local else UD.team_tex(opp), I18n.t("data.player_2") if local else opp["name"], " " if local else I18n.t("setup.another_opponent"), NX.RED, Callable() if local else _reroll)
	opp_img = right.get_meta("img")
	opp_name = right.get_meta("name")
	vh.add_child(right)
	vs.add_child(vh)
	v.add_child(vs)
	# cup bracket
	if k == "cup":
		var cup := PanelContainer.new()
		var csb := NX.box(Color(1, 0.82, 0.34, 0.07), 47, 3, Color(1, 0.82, 0.34, 0.25))
		csb.content_margin_top = 26; csb.content_margin_bottom = 26
		cup.add_theme_stylebox_override("panel", csb)
		var ch := Kit.hbox(0, true)
		var stages := [I18n.t("tournaments.quarter_final"), I18n.t("tournaments.semi_final"), I18n.t("tournaments.final")]
		var diffs := [I18n.t("settings.easy"), I18n.t("settings.normal"), I18n.t("settings.hard")]
		for i in 3:
			var c := Kit.vbox(2)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var im := Kit.img(UD.ui2("x_trophy" if i == 2 else "x_medal"), 120)
			im.modulate.a = 1.0 if i == 0 else 0.55
			c.add_child(Kit.center(im))
			var a := Kit.label(stages[i], 29, NX.GOLD if i == 0 else NX.DIM)
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(a)
			var b := Kit.label(diffs[i], 26, NX.DIM2)
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(b)
			ch.add_child(c)
		cup.add_child(ch)
		v.add_child(cup)
	if k == "quick":
		v.add_child(_row(I18n.t("setup.difficulty"), Kit.tabs([I18n.t("settings.easy"), I18n.t("settings.normal"), I18n.t("settings.hard")], func(i): lvl = i, lvl)))
	if k == "quick" or k == "local":
		var rules := ["g3", "g5", "t3"]
		v.add_child(_row(I18n.t("hub.rule"), Kit.tabs([I18n.t("oui.first_to_3_goals"), I18n.t("oui.first_to_5_goals"), I18n.t("oui.3_minutes")], func(i): rule = rules[i], rules.find(rule), NX.VIOLET)))
	if k != "train":
		var tts := [0, 10, 15, 20]
		var ti := tts.find(tt)
		v.add_child(_row(I18n.t("setup.turn_time"), Kit.tabs([I18n.t("setup.off"), I18n.t("oui.10s"), I18n.t("oui.15s"), I18n.t("oui.20s")], func(i): tt = tts[i], 2 if ti < 0 else ti, NX.GREEN)))
	# loadout: formation, ball and disc right here (no detour to the Team screen)
	var lo := NxLoadout.new(_on_loadout)
	var lp := PanelContainer.new()
	var lsb := NX.box(NX.SURF, 36, 2, NX.LINE)
	lsb.content_margin_left = 26; lsb.content_margin_right = 26; lsb.content_margin_top = 22; lsb.content_margin_bottom = 22
	lp.add_theme_stylebox_override("panel", lsb)
	lp.add_child(lo)
	v.add_child(lp)
	v.add_child(Kit.gap(16))
	v.add_child(Kit.button(I18n.t("setup.start_cup") if k == "cup" else I18n.t("lobby.start_match"), _go, "gold" if k == "cup" else "primary"))

func _side(tex: Texture2D, nm: String, sub: String, col: Color, cb: Callable) -> Control:
	var c := Kit.vbox(4)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := Panel.new()
	d.custom_minimum_size = Vector2(187, 187)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.add_theme_stylebox_override("panel", NX.box(NX.SURF2, 94, 4, col))
	var im := Kit.img(tex, 166)
	im.position = Vector2(10, 10)
	d.add_child(im)
	c.add_child(d)
	var n := Kit.label(nm, 31, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = 300
	c.add_child(n)
	var s := Kit.label(sub, 26, col)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(s)
	c.set_meta("img", im)
	c.set_meta("name", n)
	if cb.is_valid():
		Kit.tap(c, cb, 0.94)
	return c

func _row(label: String, w: Control) -> Control:
	var v := Kit.vbox(12)
	v.add_child(Kit.gap(10))
	v.add_child(Kit.label(label, 34, NX.DIM, true))
	v.add_child(w)
	return v

func _reroll() -> void:
	opp = Launch.pick_opp()
	opp_img.texture = UD.team_tex(opp)
	opp_name.text = opp["name"]
	var d := opp_img.get_parent() as Control
	d.pivot_offset = d.size * 0.5
	var tw := d.create_tween()
	tw.tween_property(d, "rotation", TAU, 0.45).from(0.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_loadout(kind: String, val) -> void:
	if kind == "team" and is_instance_valid(my_img):
		var t := UD.team_by_id(str(val))
		my_img.texture = UD.team_tex(t)
		my_name.text = t["name"]
		if mode.get("k", "") == "local" and is_instance_valid(opp_img):
			opp_img.texture = UD.team_tex(t)

func _team() -> void:
	Nav.close_sheet()
	Nav.go("team")

func _go() -> void:
	UD.set_p({"aiLvl": lvl, "limit": 5 if rule == "g5" else 3, "turnTime": tt})
	var launch := Launch.build(mode["k"], UD.p(), {"lvl": lvl, "rule": rule, "tt": tt, "opp": opp, "stage": 0})
	Nav.close_sheet()
	Nav.go("match", launch)
