extends Control
## Public profile of any player (port of RN social/PublicProfile.tsx): avatar/photo, level, league,
## stats, followers, follow / unfollow, message, block, club.
## params: {id: user uuid}
## Tables/RPC: profiles, profile_stats (view), follows (select/insert/delete), user_blocks
## (select/insert/delete), clubs, leagues; rpc open_dm.

var id := ""
var p: Dictionary = {}
var stats: Dictionary = {}
var club: Dictionary = {}
var following := false
var liked := false
var likes_n := 0
var blocked := false
var busy := false
var body: VBoxContainer
var title_l: Label


func setup(prm: Dictionary) -> void:
	id = OUI.s(prm.get("id", ""))


func _ready() -> void:
	Nav.chrome(false)
	OUI.boot()
	var pg := OUI.page(self, I18n.t("public_profile.profile"), "PILOT PROFILE", func() -> void: Nav.back(), null, OUI.CYAN, _load)
	body = pg["body"]
	title_l = pg["header"].get_meta("title")
	var cc := CenterContainer.new()
	cc.custom_minimum_size.y = OUI.px(300)
	cc.add_child(OUI.spinner(36))
	body.add_child(cc)
	_load()


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _load() -> void:
	OUI.load_leagues()
	OUI.load_discs()
	var r: Dictionary = await OUI.get_rows("profiles?select=*&id=eq." + id)
	if not is_inside_tree():
		return
	var pr: Variant = OUI.one(r)
	if not OUI.ok(r) or pr == null:
		OUI.clear(body)
		body.add_child(OUI.error_state(OUI.err(r) if not OUI.ok(r) else I18n.t("public_profile.player_not_found"), _load))
		return
	p = pr
	var u := OUI.uid()
	var s: Dictionary = await OUI.get_rows("profile_stats?select=*&id=eq." + id)
	var f: Dictionary = {}
	var b: Dictionary = {}
	var lk: Dictionary = {}
	var lk_n := 0
	if u != "":
		f = await OUI.get_rows("follows?select=followee&follower=eq.%s&followee=eq.%s" % [u, id])
		b = await OUI.get_rows("user_blocks?select=blocked&blocker=eq.%s&blocked=eq.%s" % [u, id])
		lk = await OUI.get_rows("profile_likes?select=liked&liker=eq.%s&liked=eq.%s" % [u, id])
	var ls: Dictionary = await OUI.get_rows("profile_like_stats?select=likes&id=eq." + id)
	lk_n = OUI.i(OUI.d(OUI.one(ls)).get("likes")) if OUI.one(ls) != null else 0
	var c: Dictionary = {}
	if OUI.s(p.get("club_id")) != "":
		c = await OUI.get_rows("clubs?select=id,name,tag,emblem&id=eq." + OUI.s(p.get("club_id")))
	await OUI.load_leagues()
	if not is_inside_tree():
		return
	stats = OUI.d(OUI.one(s))
	following = OUI.one(f) != null
	liked = OUI.one(lk) != null
	likes_n = lk_n
	blocked = OUI.one(b) != null
	club = OUI.d(OUI.one(c))
	_render()


func _render() -> void:
	OUI.clear(body)
	title_l.text = OUI.s(p.get("username"))
	var lg: Dictionary = {}
	for l in OUI.leagues:
		if OUI.s(l.get("id")) == OUI.s(p.get("league")):
			lg = l
	var lc := OUI.league_color(lg) if not lg.is_empty() else OUI.CYAN
	var lp := OUI.level_progress(OUI.i(p.get("xp")))
	var wins := OUI.i(p.get("wins"))
	var played := wins + OUI.i(p.get("losses")) + OUI.i(p.get("draws"))
	var wr := int(round(float(wins) / played * 100.0)) if played > 0 else 0
	var me := OUI.uid() == id
	var on := OUI.is_online(p.get("online_at"))
	# hero
	var hp := OUI.panel(lc, OUI.S_L, true)
	var hv := OUI.vbox(OUI.S_S)
	var eq := OUI.s(p.get("equipped_disc"))
	var av := NetImg.avatar(eq if eq != "" else p.get("avatar"), p.get("avatar_url"), 104, lc)
	if on:
		av.dot = OUI.GREEN
	hv.add_child(av)
	hv.add_child(OUI.lbl(OUI.s(p.get("username")), 20, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
	hv.add_child(OUI.lbl(I18n.t("hub.online") if on else I18n.t("public_profile.last_seen_x_ago") % OUI.time_ago(p.get("online_at")), OUI.TS_CAP, OUI.GREEN if on else OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	if OUI.s(p.get("bio")) != "":
		hv.add_child(OUI.lbl(OUI.s(p.get("bio")), OUI.TS_SMALL, Color("#cfe0ff"), "body", HORIZONTAL_ALIGNMENT_CENTER, true, 0))
	var bf := HFlowContainer.new()
	bf.alignment = FlowContainer.ALIGNMENT_CENTER
	bf.add_theme_constant_override("h_separation", OUI.px(4))
	bf.add_theme_constant_override("v_separation", OUI.px(4))
	bf.add_child(OUI.badge(I18n.t("hub.level_x") % OUI.fa(OUI.i(p.get("level"), 1)), OUI.GOLD))
	if not lg.is_empty():
		bf.add_child(OUI.badge(I18n.t("ranks.x_league") % OUI.s(lg.get("name_fa")), lc))
	if bool(p.get("is_guest", false)):
		bf.add_child(OUI.badge(I18n.t("kb.guest"), OUI.DIM))
	if not club.is_empty():
		bf.add_child(OUI.badge("[%s] %s" % [OUI.s(club.get("tag")), OUI.s(club.get("name"))], OUI.ORANGE))
	hv.add_child(bf)
	hv.add_child(OUI.spacer(OUI.S_XS))
	hv.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 8))
	hv.add_child(OUI.lbl(I18n.t("account.x_x_xp_to_level") % [OUI.fa(lp["cur"]), OUI.fa(lp["need"]), OUI.fa(lp["level"] + 1)], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	var sh := OUI.hbox(0)
	for it in [[OUI.i(stats.get("followers")), I18n.t("public_profile.followers")], [OUI.i(stats.get("following")), I18n.t("public_profile.following_2")], [OUI.i(p.get("trophies")), I18n.t("public_profile.trophies")]]:
		var sv := OUI.vbox(0)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(OUI.lbl(OUI.fa(it[0]), 18, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		sv.add_child(OUI.lbl(it[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		sh.add_child(sv)
	hv.add_child(sh)
	if not me:
		var ah := OUI.hbox(OUI.S_S)
		var fb := OUI.btn(I18n.t("public_profile.following") if following else I18n.t("public_profile.follow"), _toggle_follow, "dark" if following else "primary", true)
		fb.disabled = busy
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lb := OUI.btn(("❤️ " + OUI.fa(likes_n)) + (" " + I18n.t("public_profile.liked") if liked else ""), _toggle_like, "red" if liked else "dark", true)
		lb.disabled = busy
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mb := OUI.btn(I18n.t("kb.message"), _message, "green", true)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(fb)
		ah.add_child(lb)
		ah.add_child(mb)
		hv.add_child(ah)
	hp.add_child(hv)
	body.add_child(hp)
	OUI.enter(hp, 0)
	# stat grid
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", OUI.px(8))
	grid.add_theme_constant_override("v_separation", OUI.px(8))
	var cells := [["x_ball", I18n.t("tournaments.match"), OUI.fa(played)], ["x_medal", I18n.t("profile.wins"), OUI.fa(wins)], ["x_shield", I18n.t("profile.losses"), OUI.fa(OUI.i(p.get("losses")))], ["x_star", I18n.t("profile.win_rate"), I18n.t("profile.x") % OUI.fa(wr)], ["x_statue", I18n.t("tournaments.goals"), OUI.fa(OUI.i(p.get("goals")))], ["x_crown", I18n.t("arena.arena"), OUI.fa(OUI.i(p.get("arena_points")))]]
	var k := 1
	for cl in cells:
		var cp := OUI.panel(null, OUI.S_S)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := OUI.vbox(2)
		var im := OUI.img(OUI.ui2(cl[0]), 34)
		im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(im)
		cv.add_child(OUI.lbl(cl[2], 16, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		cv.add_child(OUI.lbl(cl[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		cp.add_child(cv)
		grid.add_child(cp)
		OUI.enter(cp, k)
		k += 1
	body.add_child(grid)
	# active disc
	var dp := OUI.panel(null)
	var dh := OUI.hbox(OUI.S_M)
	dh.add_child(OUI.img(OUI.disc_tex(eq), 56))
	var dv := OUI.vbox(OUI.S_XS)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(OUI.lbl(I18n.t("public_profile.active_disc"), OUI.TS_SMALL, OUI.TEXT, "bold"))
	var ds := OUI.disc_stats(eq)
	dv.add_child(OUI.stat_bars(ds["power"], ds["accuracy"]))
	dh.add_child(dv)
	if not lg.is_empty():
		dh.add_child(OUI.img(OUI.league_tex(lg.get("id")), 48))
	dp.add_child(dh)
	body.add_child(dp)
	if not club.is_empty():
		var cid := OUI.s(club.get("id"))
		body.add_child(OUI.btn(I18n.t("public_profile.club_x") % OUI.s(club.get("name")), func() -> void: Nav.go("club", {"id": cid}), "gold", true))
	if not me:
		var bl := OUI.tap(OUI.lbl(I18n.t("public_profile.unblock") if blocked else I18n.t("public_profile.block_this_user"), OUI.TS_SMALL, OUI.RED, "body", HORIZONTAL_ALIGNMENT_CENTER), _toggle_block)
		bl.custom_minimum_size.y = OUI.px(44)
		body.add_child(bl)


func _toggle_follow() -> void:
	var u := OUI.uid()
	if u == "" or busy:
		return
	busy = true
	var r: Dictionary
	if following:
		r = await OUI.del("follows?follower=eq.%s&followee=eq.%s" % [u, id])
	else:
		r = await OUI.post("follows", {"follower": u, "followee": id})
	busy = false
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		_render()
		return
	stats["followers"] = OUI.i(stats.get("followers")) + (-1 if following else 1)
	following = not following
	OUI.buzz("medium")
	if following:
		OUI.sfx("ready")
	_render()


func _toggle_like() -> void:
	var u := OUI.uid()
	if u == "" or busy:
		return
	busy = true
	var r: Dictionary
	if liked:
		r = await OUI.del("profile_likes?liker=eq.%s&liked=eq.%s" % [u, id])
	else:
		r = await OUI.post("profile_likes", {"liker": u, "liked": id})
	busy = false
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		_render()
		return
	likes_n = maxi(0, likes_n + (-1 if liked else 1))
	liked = not liked
	OUI.buzz("light")
	if liked:
		OUI.sfx("ready")
	_render()


func _message() -> void:
	var r: Dictionary = await Supa.call_rpc("open_dm", {"p_user": id})
	if OUI.ok(r):
		Nav.go("chat", {"id": OUI.s(r.get("data"))})
	else:
		OUI.toast_err(OUI.err(r))


func _toggle_block() -> void:
	var u := OUI.uid()
	if u == "":
		return
	var r: Dictionary
	if blocked:
		r = await OUI.del("user_blocks?blocker=eq.%s&blocked=eq.%s" % [u, id])
	else:
		r = await OUI.post("user_blocks", {"blocker": u, "blocked": id})
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		return
	OUI.toast(I18n.t("public_profile.unblocked") if blocked else I18n.t("public_profile.user_blocked"))
	blocked = not blocked
	_render()
