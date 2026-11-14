extends MarginContainer
## 7-day daily reward calendar (RN App.tsx DailyCard), shown as a modal via Nav.go("daily").

func setup(_params: Dictionary) -> void:
	pass

func modal_accent() -> Color:
	return NX.GOLD

func _ready() -> void:
	var p := UD.p()
	var ready_ := UD.daily_ready()
	var last := int(p.get("lastDaily", 0))
	var streak := int(p.get("streak", 0))
	var next := ((streak % 7) + 1 if UD.now_ms() - last < 2 * UD.DAY else 1) if ready_ else streak
	var left := maxi(0, last + UD.DAY - UD.now_ms())
	var h := left / 3600000
	var m := int(ceil((left % 3600000) / 60000.0))
	var v := Kit.vbox(8)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		add_theme_constant_override(k, 46)
	add_child(v)
	var cal := Kit.img(UD.ui2("c_calendar"), 250)
	var cs := Kit.stage(250, 250)
	cs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Kit.put(cs, cal, 125, 125)
	Kit.bob(cal, 8, 1.8)
	v.add_child(cs)
	var t := Kit.title(I18n.t("daily.daily_reward"), 55)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := Kit.label(I18n.t("daily.check_in_every_day_the"), 31, NX.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(Kit.gap(20))
	var daily: Array = UD.dget("DAILY", UD.DAILY)
	var flow := HFlowContainer.new()
	flow.layout_direction = I18n.LD
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	for i in daily.size():
		var d: Dictionary = daily[i]
		var day := i + 1
		var got := day < next if ready_ else day <= next
		var cur := ready_ and day == next
		var c := PanelContainer.new()
		var bg := Color(0.24, 1.0, 0.66, 0.1) if got else (Color(1, 0.82, 0.34, 0.16) if cur else Color(0.03, 0.047, 0.133, 0.8))
		var bc := NX.hdr(NX.GREEN, 1.1) if got else (NX.hdr(NX.GOLD, 1.4) if cur else NX.LINE)
		var sb := NX.box(bg, 36, 3, bc, 26 if cur else 0, Color(1, 0.82, 0.34, 0.7))
		sb.content_margin_top = 18; sb.content_margin_bottom = 18
		c.add_theme_stylebox_override("panel", sb)
		c.custom_minimum_size = Vector2(344 if day == 7 else 161, 0)
		var cv := Kit.vbox(2)
		var dl := Kit.label(I18n.t("daily.day_x") % NX.fa(day), 26, NX.GOLD if cur else NX.DIM)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(dl)
		cv.add_child(Kit.center(Kit.img(UD.ui2("x_chest") if day == 7 else (UD.ui2("x_gem") if int(d.get("gems", 0)) else UD.ui2("c_coin")), 88)))
		var amt := I18n.t("daily.x_x_gems") % [NX.fa(d["coins"]), NX.fa(d["gems"])] if int(d.get("gems", 0)) else NX.fa(d["coins"])
		var al := Kit.label(amt, 27, NX.TEXT, true)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(al)
		c.add_child(cv)
		if got:
			var tick := PanelContainer.new()
			tick.add_theme_stylebox_override("panel", NX.box(NX.hdr(NX.GREEN, 1.1), 21))
			tick.custom_minimum_size = Vector2(42, 42)
			var tl := Kit.label("✓", 26, Color("#03140c"), true)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tick.add_child(tl)
			tick.position = Vector2(10, 10)
			c.add_child(tick)
		if cur:
			c.ready.connect(func():
				c.pivot_offset = c.size * 0.5
				var tw := c.create_tween().set_loops()
				tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				tw.tween_property(c, "scale", Vector2(1.07, 1.07), 0.7)
				tw.tween_property(c, "scale", Vector2.ONE, 0.7))
		flow.add_child(c)
	v.add_child(flow)
	v.add_child(Kit.gap(30))
	if ready_:
		v.add_child(Kit.button(I18n.t("daily.claim_day_x_reward") % NX.fa(next), func(): Nav.claim_daily(), "gold"))
	else:
		v.add_child(Kit.button_small(I18n.t("daily.next_reward_xh_xm") % [NX.fa(h), NX.fa(m)], func(): Nav.close_modal(), "dark"))
