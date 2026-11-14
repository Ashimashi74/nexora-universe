extends NxScreen
## Profile (RN Profile.tsx): online account entry, offline career card (avatar + level badge,
## editable name, XP bar), league panel, win-rate ring + records, 6 stat tiles, 8 achievements
## with claim buttons.

var name_edit: LineEdit

func build() -> void:
	make_scroll(20)
	_fill()
	end_body()

func on_store_changed() -> void:
	if name_edit and name_edit.has_focus():
		return
	rebuild(_fill)

func _fill() -> void:
	var p := UD.p()
	var lv := UD.level(int(p.get("xp", 0)))
	var tr := int(p.get("trophies", 0))
	var lg := UD.league(tr)
	var t := UD.team_by_id(str(p.get("team", "club0")))
	var played := int(p.get("played", 0))
	var wins := int(p.get("wins", 0))
	var wr := int(round(float(wins) / played * 100.0)) if played else 0
	var rose := NX.ROSE

	# ---------------- online account card
	body.add_child(ent(padx(_account_card()), 0))

	# ---------------- social (messages / clubs / friends)
	body.add_child(Kit.section(I18n.t("home.social"), "SOCIAL", NX.PINK))
	var soc := Kit.list_row(UD.ui2("x_team"), I18n.t("home.friends_clubs_chat"), I18n.t("social.open_the_online_section_for"), Kit.img(UD.menu("g_chevrons"), 60), func(): Nav.go("social"))
	body.add_child(ent(padx(soc), 1))

	body.add_child(Kit.section(I18n.t("profile.offline_profile"), "OFFLINE CAREER", rose))
	# ---------------- career card
	var pn := Kit.glass(rose, true)
	var v := Kit.vbox(8)
	var st := Kit.stage(1, 320)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := NxGrad.new([Color(1, 0.48, 0.84, 0.18), Color(1, 0.48, 0.84, 0.05), Color(0, 0, 0, 0)], 40, 1.57, 0.0)
	st.add_child(g)
	var b1 := Kit.img(UD.ui2("d_banner"), Vector2(88, 240))
	b1.modulate.a = 0.8
	st.add_child(b1)
	var b2 := Kit.img(UD.ui2("d_banner"), Vector2(88, 240))
	b2.modulate.a = 0.8
	st.add_child(b2)
	var avw := Control.new()
	avw.custom_minimum_size = Vector2(312, 312)
	avw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pul := Kit.pulse(286, Color(1, 0.48, 0.84, 0.4))
	Kit.put(avw, pul, 156, 150)
	var av := Panel.new()
	av.custom_minimum_size = Vector2(270, 270)
	av.add_theme_stylebox_override("panel", NX.box(Color("#050816"), 135, 8, NX.hdr(rose, 1.3)))
	var ai := Kit.img(UD.team_tex(t), 240)
	ai.position = Vector2(15, 15)
	av.add_child(ai)
	Kit.put(avw, av, 156, 150)
	var lvt := Kit.tag(I18n.t("hub.level_x") % NX.fa(lv["level"]), NX.GOLD, Color("#1b0e00"), 29)
	avw.add_child(lvt)
	lvt.ready.connect(func(): lvt.position = Vector2(156 - lvt.size.x * 0.5, 262))
	st.add_child(avw)
	st.resized.connect(func():
		g.position = Vector2.ZERO
		g.size = st.size
		b1.position = Vector2(st.size.x - 100, 0)
		b2.position = Vector2(12, 0)
		avw.position = Vector2(st.size.x * 0.5 - 156, 0))
	v.add_child(st)
	name_edit = LineEdit.new()
	name_edit.text = str(p.get("name", "Pilot"))
	name_edit.max_length = 16
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_override("font", NX.font("title"))
	name_edit.add_theme_font_size_override("font_size", 52)
	var esb := NX.box(Color(0, 0, 0, 0), 0)
	esb.border_width_bottom = 3
	esb.border_color = Color(1, 0.48, 0.84, 0.4)
	esb.content_margin_top = 10; esb.content_margin_bottom = 10
	name_edit.add_theme_stylebox_override("normal", esb)
	var esf := esb.duplicate() as StyleBoxFlat
	esf.border_color = NX.hdr(rose, 1.3)
	name_edit.add_theme_stylebox_override("focus", esf)
	name_edit.custom_minimum_size.x = 470
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_edit.text_submitted.connect(func(_t): _commit())
	name_edit.focus_exited.connect(_commit)
	v.add_child(name_edit)
	var hint := Kit.label(I18n.t("profile.tap_to_change_name"), 26, NX.DIM2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	v.add_child(Kit.gap(10))
	v.add_child(Kit.progress(float(lv["cur"]) / maxf(1.0, float(lv["need"])), rose, NX.VIOLET, 26))
	var xp := Kit.title("%d / %d XP" % [lv["cur"], lv["need"]], 26, NX.DIM, "head")
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(xp)
	pn.add_child(v)
	body.add_child(ent(padx(pn), 1))

	# ---------------- league
	var lp := Kit.glass(NX.GOLD, false)
	var lh := Kit.hbox(26, true)
	var medal := Kit.img(UD.ui(UD.MEDAL[mini(int(lg["idx"]), 5)]), 172)
	var ms := Kit.stage(172, 172)
	Kit.put(ms, medal, 86, 86)
	Kit.bob(medal, 8, 2.2)
	lh.add_child(ms)
	var lc := Kit.vbox(10)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.alignment = BoxContainer.ALIGNMENT_CENTER
	lc.add_child(Kit.title(I18n.t("ranks.x_league") % UD.LEAGUE_FA[lg["name"]], 44))
	lc.add_child(Kit.progress(float(tr - int(lg["from"])) / maxf(1.0, float(int(lg["to"]) - int(lg["from"]))), NX.GOLD, NX.ORANGE))
	lc.add_child(Kit.label(I18n.t("profile.x_of_x_trophies") % [NX.fa(tr), NX.fa(lg["to"])], 29, NX.DIM))
	lh.add_child(lc)
	lp.add_child(lh)
	body.add_child(ent(padx(lp), 2))

	# ---------------- win-rate ring + records
	var rp := Kit.glass()
	var rh := Kit.hbox(36, true)
	var ring := Kit.ring(wr, 240)
	var rl := Kit.vbox(0)
	rl.alignment = BoxContainer.ALIGNMENT_CENTER
	rl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pc := Kit.title(I18n.t("profile.x") % NX.fa(wr), 47)
	pc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_child(pc)
	var pcl := Kit.label(I18n.t("profile.win_rate"), 23, NX.DIM)
	pcl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_child(pcl)
	ring.add_child(rl)
	rh.add_child(ring)
	var rows := Kit.vbox(0)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gd := int(p.get("goalsFor", 0)) - int(p.get("goalsAgainst", 0))
	for r in [[I18n.t("profile.best_win_streak"), NX.fa(int(p.get("bestStreak", 0)))], [I18n.t("profile.current_win_streak"), NX.fa(int(p.get("winStreak", 0)))], [I18n.t("profile.goal_difference"), ("+" if gd >= 0 else "") + NX.fa(gd)], [I18n.t("profile.discs_unlocked"), NX.fa(UD.teams().size())]]:
		var row := Kit.hbox(10, true)
		row.custom_minimum_size.y = 74
		row.add_child(Kit.label(r[0], 31, NX.DIM))
		var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(sp)
		row.add_child(Kit.label(r[1], 34, NX.TEXT, true))
		rows.add_child(row)
		var ln := ColorRect.new()
		ln.color = Color(1, 1, 1, 0.08)
		ln.custom_minimum_size.y = 2
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(ln)
	rh.add_child(rows)
	rp.add_child(rh)
	body.add_child(ent(padx(rp), 3))

	# ---------------- stat tiles
	var grid := GridContainer.new()
	grid.columns = 3
	grid.layout_direction = I18n.LD
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	var stats := [["x_ball", I18n.t("tournaments.match"), played], ["x_medal", I18n.t("profile.wins"), wins], ["x_shield", I18n.t("profile.losses"), int(p.get("losses", 0))], ["x_star", I18n.t("profile.draws"), int(p.get("draws", 0))], ["x_statue", I18n.t("profile.goals_scored"), int(p.get("goalsFor", 0))], ["x_trophy", I18n.t("profile.cups_won"), int(p.get("cupsWon", 0))]]
	var i := 0
	for s in stats:
		var tp := Kit.glass()
		tp.set_pad(10, 26)
		tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tv := Kit.vbox(2)
		tv.add_child(Kit.center(Kit.img(UD.ui2(s[0]), 104)))
		var n := Kit.title(NX.fa(s[2]), 47)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(n)
		var k := Kit.label(s[1], 26, NX.DIM)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(k)
		tp.add_child(tv)
		grid.add_child(ent(tp, i + 3))
		i += 1
	body.add_child(padx(grid))

	# ---------------- achievements
	body.add_child(Kit.section(I18n.t("profile.achievements"), "ACHIEVEMENTS", NX.GREEN))
	var achs: Array = UD.ACHS
	var claimed: Array = p.get("claimedAch", [])
	var j := 0
	for a in achs:
		body.add_child(ent(padx(_ach(a, p, a["id"] in claimed)), j))
		j += 1

func _ach(a: Dictionary, p: Dictionary, claimed: bool) -> Control:
	var mx := int(a["max"])
	var cur := mini(mx, UD.ach_cur(a, p))
	var done := cur >= mx
	var pn := Kit.glass(NX.GREEN if done and not claimed else Color.TRANSPARENT, done and not claimed)
	pn.set_pad(26, 22)
	if claimed:
		pn.modulate.a = 0.6
	var h := Kit.hbox(24, true)
	h.add_child(Kit.img(UD.ui2(a["icon"]), 130))
	var v := Kit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Kit.hbox(8, true)
	t.add_child(Kit.label(a["name"], 34, NX.TEXT, true))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE; t.add_child(sp)
	t.add_child(Kit.label("%s/%s" % [NX.fa(cur), NX.fa(mx)], 29, NX.GREEN if done else NX.DIM))
	v.add_child(t)
	v.add_child(Kit.label(a["desc"], 29, NX.DIM))
	v.add_child(Kit.progress(float(cur) / mx, NX.GREEN if done else NX.CYAN, NX.INDIGO, 16))
	h.add_child(v)
	var r := Control.new()
	r.custom_minimum_size = Vector2(192, 0)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	var rv := Kit.vbox(0)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if claimed:
		var l := Kit.label(I18n.t("profile.claimed"), 26, NX.GREEN)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rv.add_child(l)
	elif done:
		var id: String = a["id"]
		rv.add_child(Kit.button_small(I18n.t("challenges.claim"), func(): UD.claim_ach(id), "green"))
	else:
		rv.add_child(Kit.center(Kit.img(UD.ui2("c_coin"), 62)))
		var c := Kit.title("+%d" % int(a["coins"]), 26, NX.GOLD, "head")
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rv.add_child(c)
	r.add_child(rv)
	h.add_child(r)
	pn.add_child(h)
	return pn

func _commit() -> void:
	if name_edit == null:
		return
	var n := name_edit.text.strip_edges().substr(0, 16)
	if n == "":
		n = "Pilot"
	if n != str(UD.pv("name", "")):
		UD.set_p({"name": n})

func leave() -> void:
	_commit()

func _account_card() -> Control:
	var op := UD.online_profile()
	var pn := Kit.glass(NX.VIOLET, true)
	pn.set_pad(30, 24)
	var h := Kit.hbox(24, true)
	if op.is_empty():
		h.add_child(Kit.img(UD.ui("portal_globe"), 150))
		var v := Kit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(Kit.label(I18n.t("account.online_account"), 42, NX.TEXT, true))
		v.add_child(Kit.para(I18n.t("profile.sign_in_or_register_for"), 29, NX.DIM))
		h.add_child(v)
		var b := Kit.button_small(I18n.t("hub.join"), func(): Nav.go("account"), "violet")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	else:
		var key = op.get("avatar_url", null)
		if key == null or str(key) == "":
			key = op.get("equipped_disc", str(UD.pv("team", "club0")))
		h.add_child(Kit.avatar(key, 150, NX.VIOLET))
		var v2 := Kit.vbox(4)
		v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v2.alignment = BoxContainer.ALIGNMENT_CENTER
		v2.add_child(Kit.label(str(op.get("username", "")), 42, NX.TEXT, true))
		v2.add_child(Kit.label(I18n.t("play.rating_x_gems_x") % [NX.fa(int(op.get("rating", 0))), NX.fa(int(op.get("gems", 0)))], 29, NX.GOLD, true))
		h.add_child(v2)
		h.add_child(Kit.img(UD.menu("g_chevrons"), 60))
	pn.add_child(h)
	Kit.tap(pn, func(): Nav.go("account"), 0.98)
	return pn
