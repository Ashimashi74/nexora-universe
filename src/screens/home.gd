extends NxScreen
## Home hub (RN v4 Home): hero pedestal + hovering disc + mascot, quick play, league strip,
## quick actions, game-mode rail, command-deck plates, daily reward, loadout, missions.

var hero: Control
var _hero_y := 0.0
var _say: Control = null
var _say_tw: Tween = null

func build() -> void:
	# menu track on Home (Sfx picks menu_music.mp3, else music.mp3); Settings' music toggle wins
	if bool(UD.pv("music", true)):
		UD.menu_music(true)
	make_scroll(20)
	_fill()
	end_body()
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)

var _ch_card: Control

func on_store_changed() -> void:
	# keep the online challenges card alive across rebuilds (it owns a realtime channel)
	if _ch_card and is_instance_valid(_ch_card) and _ch_card.get_parent():
		_ch_card.get_parent().remove_child(_ch_card)
	rebuild(_fill)

func _exit_tree() -> void:
	if _ch_card and is_instance_valid(_ch_card) and not _ch_card.is_inside_tree():
		_ch_card.queue_free()

## RN HomeChallenges (OUI: ChallengesScreen.make_home_card()) when available
func _challenges_card() -> Control:
	if _ch_card and is_instance_valid(_ch_card):
		return _ch_card
	var path := "res://src/online/challenges.gd"
	if not ResourceLoader.exists(path):
		return null
	var sc = load(path)
	if sc is GDScript and (sc as GDScript).can_instantiate():
		var c = sc.call("make_home_card")
		if c is Control:
			_ch_card = c
	return _ch_card

func _on_scroll(v: float) -> void:
	# parallax: hero drifts slower than content and fades
	if hero:
		hero.position.y = v * 0.35
		hero.modulate.a = clampf(1.0 - v / 700.0, 0.35, 1.0)
	if Nav.main and Nav.main.backdrop:
		Nav.main.backdrop.set_drift(v)

func _fill() -> void:
	var p := UD.p()
	var W := 1080.0
	# ---------------- hero: mascot (left) + NEXORA logo (right), small drifting planets
	var hh := 470.0
	var wrap := Kit.stage(W, hh)
	wrap.clip_contents = false
	hero = Control.new()
	hero.mouse_filter = Control.MOUSE_FILTER_PASS
	hero.size = Vector2(W, hh)
	wrap.add_child(hero)
	var orb := Kit.img(UD.art("planet"), 120)
	Kit.put(hero, orb, W * 0.5, 70)
	orb.modulate = Color(1, 1, 1, 0.55)
	Kit.bob(orb, 10, 4.2, 0.3)
	var logo := Kit.img(UD.art("logo"), Vector2(560, 336))
	Kit.put(hero, logo, W * 0.68, hh * 0.5)
	logo.modulate.a = 0.0
	var lw := logo.create_tween().set_parallel(true)
	lw.tween_property(logo, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lw.tween_property(logo, "position:y", logo.position.y, 0.55).from(logo.position.y + 40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pad := Kit.img(UD.menu("holo_ring"), Vector2(240, 70))
	Kit.put(hero, pad, 210, hh - 40)
	pad.modulate = Color(0.6, 0.8, 1.4, 0.7)
	var mas := Kit.img(UD.art("mascot"), Vector2(300, 380))
	Kit.put(hero, mas, 210, hh * 0.5 - 10)
	mas.modulate.a = 0.0
	var mw := mas.create_tween()
	mw.tween_interval(0.15)
	mw.tween_property(mas, "modulate:a", 1.0, 0.45)
	Kit.bob(mas, 14, 2.4, 0.4)
	Kit.tap(mas, func(): UD.sfx("ui"); _mascot_say(I18n.t("home.hi_captain_ready_to_play")), 0.9)
	body.add_child(wrap)

	# ---------------- Quick Match pill (gradient, play glyph, chevron disc, shine sweep)
	var play := NxButton.new(I18n.t("v2.quick_match"), func(): Nav.go("setup", {"mode": "quick"}), "primary", false)
	play.custom_minimum_size = Vector2(700, 160)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.lbl.add_theme_font_size_override("font_size", 50)
	play.row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var tri := Glyph.new("play")
	tri.custom_minimum_size = Vector2(56, 64)
	play.row.add_child(tri)
	play.row.move_child(tri, 0)
	var gap := Control.new()
	gap.custom_minimum_size.x = 40
	play.row.add_child(gap)
	var chev := Glyph.new("chev")
	chev.custom_minimum_size = Vector2(86, 86)
	play.row.add_child(chev)
	var sh := play.create_tween().set_loops()
	sh.tween_method(func(v): play.bg.shine = v, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	sh.tween_interval(0.9)
	body.add_child(ent(Kit.center(play), 0))

	# ---------------- main menu categories (clear, logical grouping — matches the hub drawers)
	var tiles := Kit.hbox(14, true)
	var tdef := [
		["🎮", I18n.t("m3.cat_play"), func(): Nav.go("play"), NX.CYAN],
		["🌐", I18n.t("m3.cat_online"), func(): Nav.online("hub"), NX.GREEN],
		["🛒", I18n.t("m3.cat_team"), func(): Nav.go("team"), NX.GOLD],
		["🏆", I18n.t("hub.leaderboard"), func(): Nav.online("ranks"), NX.VIOLET],
		["⚙️", I18n.t("m3.cat_settings"), func(): Nav.go("settings"), NX.PINK],
	]
	for i in tdef.size():
		var td: Array = tdef[i]
		var c := NxNeon.new(36, 10, td[3], Color("#ff4f8b"))
		c.custom_minimum_size = Vector2(0, 196)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := Kit.vbox(10)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := Kit.label(str(td[0]), 54, NX.TEXT, true)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ic)
		var l := Kit.label(td[1], 22 if I18n.is_en() else 26, NX.TEXT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l)
		c.add_child(v)
		var cc := c
		cc.resized.connect(func(): cc.pivot_offset = cc.size * 0.5)
		Kit.tap(cc, td[2], 0.93)
		tiles.add_child(cc)
	body.add_child(ent(Kit.margin(tiles, 34, 6, 34, 0), 1))

	# ---------------- level / XP card
	body.add_child(ent(padx(_level_card(p)), 2))

	# ---------------- game modes
	body.add_child(Kit.section(I18n.t("home.game_modes"), "GAME MODES", NX.PINK, I18n.t("home.all"), func(): Nav.go("play")))
	var hs := Kit.hscroll(24)
	var rail: HBoxContainer = hs[1]
	(hs[0] as ScrollContainer).custom_minimum_size.y = 420
	rail.add_child(Kit.gap(0, 20))
	for m in Launch.modes():
		rail.add_child(_mode_card(m))
	rail.add_child(Kit.gap(0, 20))
	body.add_child(ent(hs[0], 3))

	# ---------------- daily reward
	body.add_child(Kit.section(I18n.t("daily.daily_reward"), "DAILY REWARD", NX.GOLD))
	var dr := UD.daily_ready()
	var dp := NxNeon.new(40, 26, NX.GOLD, Color("#ff4f8b"))
	var dh := Kit.hbox(26, true)
	dh.add_child(Kit.img(UD.art("h_gift"), 96))
	var dc := Kit.vbox(2)
	dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dc.alignment = BoxContainer.ALIGNMENT_CENTER
	dc.add_child(Kit.label(I18n.t("home.today_s_reward_is_ready") if dr else I18n.t("home.day_x_of_7") % NX.fa(int(p.get("streak", 0))), 36, NX.TEXT, true))
	dc.add_child(Kit.label(I18n.t("home.free_coins_and_gems_bigger") if dr else I18n.t("home.come_back_tomorrow"), 29, NX.DIM))
	dh.add_child(dc)
	var cta := Kit.chip(I18n.t("challenges.claim") if dr else I18n.t("home.details"), NX.PINK if dr else NX.DIM, dr)
	cta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.add_child(cta)
	dp.add_child(dh)
	Kit.tap(dp, func(): Nav.go("daily"), 0.98)
	body.add_child(ent(padx(dp), 4))

	# ---------------- missions
	body.add_child(Kit.section(I18n.t("home.missions"), "MISSIONS", NX.PINK, I18n.t("home.challenges"), func(): Nav.online("challenges")))
	var mv := Kit.vbox(18)
	var shown := 0
	for a in UD.ACHS:
		if a["id"] in (p.get("claimedAch", []) as Array):
			continue
		mv.add_child(_mission(a, p))
		shown += 1
		if shown >= 3:
			break
	if shown == 0:
		mv.add_child(Kit.para(I18n.t("home.you_ve_completed_every_mission"), 31, NX.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var occ := _challenges_card()
	if occ:
		mv.add_child(occ)
	var ch := Kit.list_row(UD.art("t_events"), I18n.t("challenges.today_s_challenges"), I18n.t("home.daily_online_challenges_gem_rewards"), Glyph.new("chev").sized(76), func(): Nav.online("challenges"))
	mv.add_child(ch)
	body.add_child(ent(padx(mv), 5))

func _level_card(p: Dictionary) -> Control:
	var op := UD.online_profile()
	var xp := int(op.get("xp", p.get("xp", 0))) if not op.is_empty() else int(p.get("xp", 0))
	var lv := UD.level(xp)
	var card := NxNeon.new(48, 26, Color("#39d5ff"), Color("#ff4f8b"))
	card.strength = 1.4
	card.custom_minimum_size.y = 210
	var h := Kit.hbox(26, true)
	h.add_child(Kit.img(UD.art("lvl_star"), 150))
	var sep := ColorRect.new()
	sep.color = Color(0.56, 0.5, 1.0, 0.35)
	sep.custom_minimum_size = Vector2(3, 120)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	var col := Kit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(Kit.label(I18n.t("v2.level_x") % NX.fa(int(lv["level"])), 42, NX.TEXT, true))
	col.add_child(Kit.label(I18n.t("v2.xp_x") % [NX.fa(int(lv["cur"])), NX.fa(int(lv["need"]))], 28, NX.DIM))
	var bar := Kit.progress(float(lv["cur"]) / maxf(1.0, float(lv["need"])), Color("#ff9a66"), Color("#ff4f8b"), 16)
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	col.add_child(bar)
	h.add_child(col)
	h.add_child(Glyph.new("chev").sized(86))
	card.add_child(h)
	Kit.tap(card, func(): Nav.go("profile"), 0.98)
	return card

func _league_strip(p: Dictionary) -> Control:
	var tr := int(p.get("trophies", 0))
	var lg := UD.league(tr)
	var pn := Kit.glass(NX.GOLD, false)
	pn.set_pad(30, 18)
	var h := Kit.hbox(24, true)
	var medal := Kit.img(UD.ui(UD.MEDAL[mini(int(lg["idx"]), 5)]), 120)
	h.add_child(medal)
	var col := Kit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := Kit.hbox(12, true)
	top.add_child(Kit.label(I18n.t("ranks.x_league") % UD.LEAGUE_FA[lg["name"]], 38, NX.TEXT, true))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	top.add_child(Kit.label("%s / %s" % [NX.fa(tr), NX.fa(lg["to"])], 29, NX.GOLD))
	col.add_child(top)
	var bar := Kit.progress(float(tr - int(lg["from"])) / maxf(1.0, float(int(lg["to"]) - int(lg["from"]))), NX.GOLD, NX.ORANGE, 18)
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	col.add_child(bar)
	h.add_child(col)
	pn.add_child(h)
	Kit.tap(pn, func(): Nav.go("play"), 0.98)
	return pn

func _mode_card(m: Dictionary) -> Control:
	var col: Color = m["color"]
	var c := NxNeon.new(48, 0, Color(col.r, col.g, col.b), Color("#ff4f8b"))
	c.custom_minimum_size = Vector2(300, 380)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := Kit.stage(300, 380)
	var art := Kit.img(UD.ui(m["img"]), Vector2(220, 220))
	Kit.put(st, art, 150, 140)
	Kit.bob(art, 8, 2.2 + randf() * 0.6)
	var e := Kit.caps(m["en"], 19, NX.hdr(col, 1.3), 3)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.position = Vector2(0, 268)
	e.size = Vector2(300, 30)
	st.add_child(e)
	var n := Kit.label(m["name"], 36, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 298)
	n.size = Vector2(300, 60)
	st.add_child(n)
	c.add_child(st)
	var k: String = m["k"]
	Kit.tap(c, func(): Nav.go("setup", {"mode": k}), 0.94)
	return c

func _plate(pl: Array) -> Control:
	var col: Color = pl[3]
	var pn := PanelContainer.new()
	pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pn.custom_minimum_size.y = 200
	var sb := NX.box(Color(0.045, 0.07, 0.19, 0.86), 44, 3, Color(col.r, col.g, col.b, 0.42))
	sb.content_margin_left = 24; sb.content_margin_right = 24; sb.content_margin_top = 16; sb.content_margin_bottom = 16
	pn.add_theme_stylebox_override("panel", sb)
	var g := NxGrad.new([Color(col.r, col.g, col.b, 0.22), Color(col.r, col.g, col.b, 0.06), Color(0, 0, 0, 0)], 40, 0.0, 0.1)
	g.layout_direction = Control.LAYOUT_DIRECTION_LTR
	pn.add_child(g)
	var h := Kit.hbox(14, true)
	h.add_child(Kit.img(UD.ui(pl[0]), 128))
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(Kit.label(pl[1], 38, NX.TEXT, true))
	var s := Kit.label(pl[2], 25, NX.DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	h.add_child(v)
	pn.add_child(h)
	Kit.tap(pn, pl[4], 0.95)
	return pn

func _loadout(p: Dictionary, me: Dictionary) -> Control:
	var pn := Kit.glass()
	pn.set_pad(26, 22)
	var h := Kit.hbox(18, true)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var bi := int(p.get("ball", 0))
	var fi := int(p.get("field", 0))
	var fo := int(p.get("form", 0))
	var items := [
		[UD.team_tex(me), I18n.t("home.disc"), me["name"], false],
		[UD.ball_tex(bi), I18n.t("home.ball"), UD.ball_name(bi), false],
		[UD.field_thumb(fi), I18n.t("hub.field"), UD.field(fi)["name"], true],
		[UD.menu("g_chevrons"), I18n.t("kb.formation"), UD.forms()[fo][0], false],
	]
	for it in items:
		var v := Kit.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override("panel", NX.box(Color(0.02, 0.03, 0.09, 0.7), 34, 2, NX.LINE))
		holder.custom_minimum_size = Vector2(170, 170)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var im := Kit.img(it[0], Vector2(100, 136) if it[3] else Vector2(136, 136), "cover" if it[3] else "contain")
		holder.add_child(Kit.center(im))
		v.add_child(holder)
		var a := Kit.label(it[1], 25, NX.DIM)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		var b := Kit.label(it[2], 27, NX.TEXT, true)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.x = 180
		v.add_child(b)
		h.add_child(v)
	pn.add_child(h)
	Kit.tap(pn, func(): Nav.go("team"), 0.98)
	return pn

func _mission(a: Dictionary, p: Dictionary) -> Control:
	var mx := int(a["max"])
	var cur := mini(mx, UD.ach_cur(a, p))
	var done := cur >= mx
	var pn := Kit.glass(NX.GREEN if done else Color.TRANSPARENT, done)
	pn.set_pad(26, 20)
	var h := Kit.hbox(22, true)
	h.add_child(Kit.img(UD.ui2(a["icon"]), 110))
	var v := Kit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Kit.hbox(8, true)
	t.add_child(Kit.label(a["name"], 34, NX.TEXT, true))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.add_child(sp)
	t.add_child(Kit.label("%s/%s" % [NX.fa(cur), NX.fa(mx)], 29, NX.GREEN if done else NX.DIM))
	v.add_child(t)
	v.add_child(Kit.label(a["desc"], 28, NX.DIM))
	var bar := Kit.progress(float(cur) / mx, NX.GREEN if done else NX.CYAN, NX.INDIGO, 15)
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v.add_child(bar)
	h.add_child(v)
	if done:
		var id: String = a["id"]
		var b := Kit.button_small(I18n.t("challenges.claim"), func(): UD.claim_ach(id), "green")
		b.custom_minimum_size.x = 200
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	else:
		var r := Kit.vbox(0)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		r.add_child(Kit.center(Kit.img(UD.ui2("c_coin"), 62)))
		var c := Kit.title("+%d" % int(a["coins"]), 26, NX.GOLD, "head")
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.add_child(c)
		r.custom_minimum_size.x = 150
		h.add_child(r)
	pn.add_child(h)
	return pn


## speech bubble beside the mascot (was a toast that collapsed into a one-letter column):
## right of the mascot, max 70% of the screen width, auto height, auto-dismiss.
func _mascot_say(text: String) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if _say and is_instance_valid(_say):
		_say.queue_free()
	if _say_tw:
		_say_tw.kill()
	var W := 1080.0
	var b := Kit.speech(text, W * 0.7, 38)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.z_index = 5
	hero.add_child(b)
	b.reset_size()
	var sz := b.get_combined_minimum_size()
	b.size = sz
	# mascot box: x 60..360, y 25..405; bubble sits right of its head, tail towards it
	b.position = Vector2(clampf(350.0, 20.0, W - sz.x - 20.0), maxf(10.0, 120.0 - sz.y * 0.5))
	b.pivot_offset = Vector2(0, sz.y)
	(func():
		if is_instance_valid(b):
			b.size = Vector2.ZERO
			b.reset_size()).call_deferred()
	var tail := Polygon2D.new()
	tail.color = Color(0.04, 0.07, 0.2, 0.97)
	tail.polygon = PackedVector2Array([Vector2(4, sz.y - 70), Vector2(-26, sz.y - 30), Vector2(4, sz.y - 40)])
	b.add_child(tail)
	Kit.tap(b, func(): _hide_say(), 0.97)
	_say = b
	b.modulate.a = 0.0
	b.scale = Vector2(0.85, 0.85)
	_say_tw = b.create_tween()
	_say_tw.set_parallel(true)
	_say_tw.tween_property(b, "modulate:a", 1.0, 0.2)
	_say_tw.tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_say_tw.chain().tween_interval(clampf(2.2 + text.length() * 0.06, 2.5, 7.0))
	_say_tw.chain().tween_callback(_hide_say)

func _hide_say() -> void:
	var b := _say
	_say = null
	if b == null or not is_instance_valid(b):
		return
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 0.0, 0.22)
	tw.tween_callback(b.queue_free)


## small vector glyphs for the v2 pills/cards: "play" (gradient-free white triangle) and
## "chev" (dark disc with a ring and a chevron that follows the reading direction)
class Glyph extends Control:
	var kind := "play"
	func _init(k := "play") -> void:
		kind = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func sized(d: float) -> Glyph:
		custom_minimum_size = Vector2(d, d)
		return self
	func _draw() -> void:
		var c := size * 0.5
		if kind == "play":
			var s := minf(size.x, size.y) * 0.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s, 0), c + Vector2(-s * 0.7, s)]), Color(1, 1, 1, 0.95))
			return
		var r := minf(size.x, size.y) * 0.5 - 3
		draw_circle(c, r, Color(0.08, 0.04, 0.16, 0.55), true, -1.0, true)
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.5, true)
		var d := r * 0.28
		var dir := 1.0 if I18n.is_en() else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(-d * 0.5 * dir, -d), c + Vector2(d * 0.6 * dir, 0), c + Vector2(-d * 0.5 * dir, d)]), Color(1, 1, 1, 0.9), 4.0, true)
