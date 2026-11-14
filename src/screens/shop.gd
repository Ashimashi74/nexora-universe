extends NxScreen
## Shop (RN Shop.tsx + v4): legendary discs banner + rail, free/royal chests (opening modal),
## daily -30% deals, gem exchange, catalogue (discs w/ gems · balls · fields w/ coins).

const RC := [Color("#8ea3d6"), Color("#4fe3ff"), Color("#b46bff"), Color("#ffd257")]
## gem → coin exchange packs (v4 "gem exchange")
const EXCHANGE := [[10, 500], [50, 2800], [120, 7500]]
var kind := 0  # 0 discs, 1 balls, 2 fields
var _timer_l: Label
var _timer_btn: NxButton

func build() -> void:
	make_scroll(20)
	_fill()
	end_body()
	var tm := Timer.new()
	tm.wait_time = 30.0
	tm.autostart = true
	tm.timeout.connect(_tick)
	add_child(tm)
	var sd := UD.discs()
	if sd and sd.has_signal("changed"):
		sd.connect("changed", func(): if is_inside_tree(): on_store_changed())

func on_store_changed() -> void:
	rebuild(_fill)

func _tick() -> void:
	if _timer_btn and is_instance_valid(_timer_btn):
		var left := _free_in()
		if left <= 0:
			on_store_changed()
		else:
			_timer_btn.set_text(_fmt(left))

func _free_in() -> int:
	return maxi(0, int(UD.pv("lastChest", 0)) + UD.CHEST_EVERY - UD.now_ms())

static func _fmt(ms: int) -> String:
	var m := int(ceil(ms / 60000.0))
	var h := m / 60
	return I18n.t("shop.xh_xm") % [NX.fa(h), NX.fa(m % 60)] if h else I18n.t("oui.x_min") % NX.fa(m)

func _fill() -> void:
	var p := UD.p()
	var legends := UD.teams_of("leg")
	# ---------------- v2 categories: FORMATION · ITEM · DISC · BALL (shop art)
	body.add_child(Kit.section(I18n.t("v2.categories"), "CATEGORIES", NX.PINK))
	var cats := Kit.hbox(18, true)
	for cd in [["formation", I18n.t("v2.formation"), -1], ["item", I18n.t("v2.item"), 2], ["disc", I18n.t("v2.disc"), 0], ["ball", I18n.t("v2.ball"), 1]]:
		var tile := NxNeon.new(38, 12, Color("#39d5ff"), Color("#ff4f8b"))
		tile.custom_minimum_size = Vector2(0, 236)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tv := Kit.vbox(6)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_child(Kit.center(Kit.img(UD.art("shop_" + cd[0]), Vector2(170, 140))))
		var tl := Kit.label(cd[1], 29, NX.TEXT, true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(tl)
		tile.add_child(tv)
		var target: int = cd[2]
		if target == kind:
			tile.strength = 2.2
		Kit.tap(tile, func():
			if target < 0:
				Nav.go("team")
			else:
				kind = target
				rebuild(_fill), 0.94)
		cats.add_child(tile)
	body.add_child(ent(padx(cats), 0))
	# ---------------- legends banner
	var ban := Control.new()
	ban.custom_minimum_size = Vector2(0, 390)
	ban.mouse_filter = Control.MOUSE_FILTER_PASS
	var g := NxGrad.new([Color("#4a1a3a"), Color("#1e1450"), Color("#08061e")], 62, 0.6, 0.18)
	g.set_border(3.0, Color(1, 0.82, 0.34, 0.5))
	g.set_glow(Color(1.4, 1.1, 0.4, 0.45), 32.0, 32.0)
	ban.add_child(g)
	var scr := Kit.img(UD.ui2("screens"), Vector2(676, 468))
	scr.modulate.a = 0.25
	ban.add_child(scr)
	var bh := Kit.hbox(10, true)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ban.add_child(bh)
	var col := Kit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var en := Kit.caps("LEGENDARY DISCS", 23, NX.hdr(NX.GOLD, 1.3), 8)
	en.horizontal_alignment = I18n.AR
	col.add_child(en)
	col.add_child(Kit.title(I18n.t("shop.legendary_discs"), 50))
	col.add_child(Kit.label(I18n.t("shop.high_power_and_accuracy_with"), 29, Color("#e8d7ad")))
	var tg := Kit.tag(I18n.t("shop.limited"), NX.GOLD, Color("#1b0e00"), 29)
	tg.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(tg)
	bh.add_child(col)
	var day_leg: Dictionary = legends[int(UD.now_ms() / UD.DAY) % legends.size()]
	var lw := Kit.stage(330, 360)
	var limg := Kit.img(UD.team_tex(day_leg), 300)
	Kit.put(lw, limg, 165, 180)
	Kit.bob(limg, 16, 2.6)
	bh.add_child(lw)
	ban.resized.connect(func():
		g.position = Vector2(-g.pad, -g.pad)
		g.size = ban.size + Vector2(g.pad * 2, g.pad * 2)
		scr.position = Vector2(ban.size.x - 600, -26)
		bh.position = Vector2(30, 0)
		bh.size = Vector2(ban.size.x - 60, ban.size.y))
	ban.clip_contents = false
	body.add_child(ent(padx(ban), 0))
	# legends rail
	var hs := Kit.hscroll(20)
	var rail: HBoxContainer = hs[1]
	rail.add_child(Kit.gap(0, 22))
	for t in legends:
		var own := UD.disc_owned(t["id"])
		var c := PanelContainer.new()
		c.custom_minimum_size = Vector2(302, 390)
		var sb := NX.box(Color("#0a0d26"), 52, 3, Color(1, 0.82, 0.34, 0.4))
		c.add_theme_stylebox_override("panel", sb)
		var cg := NxGrad.new([Color(1, 0.82, 0.34, 0.25), Color(0.2, 0.17, 0.2, 0.5), Color(0.04, 0.05, 0.13, 0.9)], 50, 1.57, 0.06)
		c.add_child(cg)
		var v := Kit.vbox(8)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(Kit.center(Kit.img(UD.team_tex(t), 240)))
		var n := Kit.label(t["name"], 29, NX.TEXT, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		if own:
			var o := Kit.label(I18n.t("shop.owned"), 29, NX.GREEN)
			o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(o)
		else:
			v.add_child(Kit.price_tag(UD.disc_price(t["id"]), true))
		c.add_child(v)
		if own:
			c.modulate.a = 0.6
		else:
			var id: String = t["id"]
			var nm: String = t["name"]
			Kit.tap(c, func(): UD.buy_and_equip_disc(id, nm), 0.94)
		rail.add_child(c)
	rail.add_child(Kit.gap(0, 22))
	(hs[0] as ScrollContainer).custom_minimum_size.y = 410
	body.add_child(hs[0])

	# ---------------- chests
	body.add_child(Kit.section(I18n.t("shop.chests"), "SUPPLY CHESTS", NX.VIOLET))
	var crow := Kit.hbox(20, true)
	var free_in := _free_in()
	var fc := Kit.glass(NX.CYAN, free_in == 0)
	fc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fv := Kit.vbox(4)
	var fimg := Kit.img(UD.ui2("c_chest"), 250)
	var fs := Kit.stage(250, 250)
	Kit.put(fs, fimg, 125, 125)
	if free_in == 0:
		Kit.wiggle(fimg)
	fv.add_child(Kit.center(fs))
	var ft := Kit.label(I18n.t("chest.free_chest"), 34, NX.TEXT, true)
	ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(ft)
	var fsub := Kit.label(I18n.t("shop.every_4_hours"), 26, NX.DIM)
	fsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(fsub)
	_timer_btn = Kit.button_small(_fmt(free_in) if free_in else I18n.t("shop.open"), func(): Nav.open_chest(false), "primary")
	_timer_btn.set_disabled(free_in > 0)
	fv.add_child(Kit.gap(6))
	fv.add_child(_timer_btn)
	fc.add_child(fv)
	crow.add_child(fc)
	var rcst := Kit.glass(NX.GOLD, true)
	rcst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := Kit.vbox(4)
	var rimg := Kit.img(UD.ui2("x_chest"), 250)
	var rs := Kit.stage(250, 250)
	Kit.put(rs, rimg, 125, 125)
	Kit.wiggle(rimg, 6.0, 2.2)
	rv.add_child(Kit.center(rs))
	var rt := Kit.label(I18n.t("chest.royal_chest"), 34, NX.TEXT, true)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rt)
	var rsub := Kit.label(I18n.t("shop.better_odds_of_a_rare"), 26, NX.DIM)
	rsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rsub)
	rv.add_child(Kit.gap(6))
	rv.add_child(Kit.button_small(I18n.t("shop.600_coins"), func():
		if int(UD.pv("coins", 0)) < 600:
			toast(I18n.t("nav.you_need_600_coins"), "err")
			return
		Nav.open_chest(true), "violet", UD.ui2("c_coin")))
	rcst.add_child(rv)
	crow.add_child(rcst)
	body.add_child(ent(padx(crow), 1))

	# ---------------- daily deals
	var deals: Array = UD.callv_safe("Data", "daily_deals", [p], null) if UD.has("Data", "daily_deals") else UD.daily_deals(p)
	if deals.size():
		body.add_child(Kit.section(I18n.t("shop.today_s_deal"), "DAILY DEALS · -30%", NX.GREEN))
		var dg := GridContainer.new()
		dg.columns = 2
		dg.layout_direction = I18n.LD
		dg.add_theme_constant_override("h_separation", 20)
		dg.add_theme_constant_override("v_separation", 20)
		var i := 0
		for it in deals:
			dg.add_child(ent(_deal(it), i + 2))
			i += 1
		body.add_child(padx(dg))

	# ---------------- gem exchange
	body.add_child(Kit.section(I18n.t("shop.convert_gems"), "GEM EXCHANGE", NX.CYAN))
	var ex := Kit.hbox(18, true)
	var gems := int(p.get("gems", 0))
	for e in EXCHANGE:
		var c2 := Kit.glass(NX.CYAN if gems >= e[0] else Color.TRANSPARENT, false)
		c2.set_pad(16, 22)
		c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v2 := Kit.vbox(6)
		v2.add_child(Kit.center(Kit.img(UD.ui2("x_coins"), 150)))
		var amt := Kit.title("+%s" % NX.en_num(e[1]), 36, NX.GOLD, "head")
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v2.add_child(amt)
		var cl := Kit.label(I18n.t("kb.coins"), 26, NX.DIM)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v2.add_child(cl)
		v2.add_child(Kit.price_tag(e[0], true))
		c2.add_child(v2)
		var ec: Array = e
		Kit.tap(c2, func(): _exchange(ec[0], ec[1]), 0.94)
		ex.add_child(c2)
	body.add_child(padx(ex))

	# ---------------- catalogue
	body.add_child(Kit.section(I18n.t("shop.all_gear"), "CATALOGUE"))
	var seg := Kit.tabs([I18n.t("home.disc"), I18n.t("home.ball"), I18n.t("hub.field")], func(i):
		kind = i
		rebuild(_fill), kind, NX.GOLD)
	body.add_child(padx(seg))
	var cell := (1080.0 - NX.PAD * 2 - 2 * 20) / 3.0
	var grid := GridContainer.new()
	grid.columns = 3
	grid.layout_direction = I18n.LD
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	if kind == 0:
		if UD.online_profile().is_empty():
			body.add_child(padx(Kit.para(I18n.t("shop.discs_are_priced_in_gems"), 29, NX.DIM)))
		var gd := UD.gem_discs()
		var n := 0
		for d in gd:
			if n >= 60: break
			grid.add_child(_disc_card(d, cell))
			n += 1
		if gd.is_empty():
			# offline: preview the premium catalogue from local data (prices from the server once online)
			for t in UD.teams().filter(func(x): return not UD.is_free_disc(x["id"])).slice(0, 30):
				grid.add_child(_disc_card({"id": t["id"], "name": t["name"], "price_gems": UD.disc_price(t["id"]), "power": UD.disc_stats(t["id"])["power"], "accuracy": UD.disc_stats(t["id"])["accuracy"]}, cell))
	else:
		var items: Array = UD.callv_safe("Data", "all_items", [p], null) if UD.has("Data", "all_items") else UD.all_items(p)
		var want := "ball" if kind == 1 else "field"
		var list := items.filter(func(it): return it["kind"] == want)
		for it in list.slice(0, 60):
			grid.add_child(_item_card(it, cell))
		if list.is_empty():
			body.add_child(Kit.para(I18n.t("shop.you_own_everything_in_this"), 33, NX.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(padx(grid))

func _deal(it: Dictionary) -> Control:
	var rar := int(it.get("rar", 1))
	var pn := Kit.glass(RC[rar], false)
	pn.set_pad(22, 22)
	pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Kit.hbox(16, true)
	var fld: bool = it["kind"] == "field"
	h.add_child(Kit.img(UD.item_tex(it), Vector2(104, 140) if fld else Vector2(140, 140), "cover" if fld else "contain"))
	var v := Kit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := Kit.label(it["name"], 31, NX.TEXT, true)
	n.horizontal_alignment = I18n.AR
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(n)
	var off := Kit.tag(I18n.t("shop.30"), NX.hdr(NX.GREEN, 1.1), Color("#03140c"), 25)
	off.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(off)
	var pt := Kit.price_tag(int(it["price"]))
	pt.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(pt)
	h.add_child(v)
	pn.add_child(h)
	Kit.tap(pn, func(): _buy(it), 0.95)
	return pn

func _item_card(it: Dictionary, cell: float) -> Control:
	var rar := int(it.get("rar", 1))
	var rc: Color = RC[rar]
	var c := PanelContainer.new()
	var sb := NX.box(Color(0.03, 0.047, 0.133, 0.8), 42, 3, Color(rc.r, rc.g, rc.b, 0.45))
	sb.content_margin_top = 24; sb.content_margin_bottom = 20
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size.x = cell
	var g := NxGrad.new([Color(rc.r, rc.g, rc.b, 0.2), Color(rc.r, rc.g, rc.b, 0.08), Color(0.03, 0.05, 0.13, 0.1)], 40, 1.57, 0.0)
	c.add_child(g)
	var v := Kit.vbox(8)
	var fld: bool = it["kind"] == "field"
	v.add_child(Kit.center(Kit.img(UD.item_tex(it), Vector2(cell * 0.52, cell * 0.7) if fld else Vector2(cell * 0.64, cell * 0.64), "cover" if fld else "contain")))
	var n := Kit.label(it["name"], 26, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = cell - 20
	v.add_child(n)
	v.add_child(Kit.price_tag(int(it["price"])))
	c.add_child(v)
	Kit.tap(c, func(): _buy(it), 0.93)
	return c

func _disc_card(d: Dictionary, cell: float) -> Control:
	var pg := int(d.get("price_gems", 0))
	var rc: Color = RC[3 if pg >= 250 else (2 if pg >= 180 else 1)]
	var c := PanelContainer.new()
	var sb := NX.box(Color(0.03, 0.047, 0.133, 0.8), 42, 3, Color(rc.r, rc.g, rc.b, 0.45))
	sb.content_margin_top = 24; sb.content_margin_bottom = 20; sb.content_margin_left = 16; sb.content_margin_right = 16
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size.x = cell
	var v := Kit.vbox(8)
	var dt := UD.disc_tex(str(d["id"]), str(d.get("name", "")))
	v.add_child(Kit.center(Kit.img(dt if dt else UD.menu("shield_gem"), cell * 0.6)))
	var n := Kit.label(str(d.get("name", "")), 26, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = cell - 40
	v.add_child(n)
	v.add_child(Kit.stat_bars(int(d.get("power", 5)), int(d.get("accuracy", 5)), true))
	v.add_child(Kit.price_tag(pg, true))
	c.add_child(v)
	var id := str(d["id"])
	var nm := str(d.get("name", ""))
	Kit.tap(c, func(): UD.buy_and_equip_disc(id, nm), 0.93)
	return c

func _buy(it: Dictionary) -> void:
	var p := UD.p()
	if int(p.get("coins", 0)) < int(it["price"]):
		toast(I18n.t("shop.not_enough_coins"), "err")
		UD.haptic("medium")
		return
	var patch := UD.grant(it, p)
	patch["coins"] = int(p["coins"]) - int(it["price"])
	UD.set_p(patch)
	UD.sfx("ui")
	UD.haptic("success")
	toast(I18n.t("shop.x_unlocked") % it["name"], "ok")

func _exchange(gems: int, coins: int) -> void:
	var p := UD.p()
	if int(p.get("gems", 0)) < gems:
		toast(I18n.t("shop.you_need_x_more_gems") % NX.fa(gems - int(p.get("gems", 0))), "err")
		UD.haptic("medium")
		return
	Nav.confirm(I18n.t("shop.convert_x_gems_into_x") % [NX.fa(gems), NX.fa(coins)], func():
		var q := UD.p()
		UD.set_p({"gems": int(q.get("gems", 0)) - gems, "coins": int(q.get("coins", 0)) + coins})
		UD.sfx("ui")
		UD.haptic("success")
		toast(I18n.t("nav.x_coins") % NX.fa(coins), "ok"))
