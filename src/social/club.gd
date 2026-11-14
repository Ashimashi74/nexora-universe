extends Control
## Club page (port of RN social/ClubPage.tsx): emblem, tag, description, stats, members with roles,
## join / request / accept invite, requests management, invite players, club chat, leave,
## leader actions (promote / demote / transfer / kick).
## params: {id: club uuid}
## Tables/RPC: club_list (view), club_members, club_requests, profiles; rpc join_club, leave_club,
## club_decide, club_invite, club_member_action; realtime club:<id>.

const ROLE_FA := {"leader": ["رهبر", OUI.GOLD], "officer": ["افسر", OUI.CYAN], "member": ["عضو", OUI.DIM]}

var id := ""
var club: Dictionary = {}
var members: Array = []
var reqs: Array = []
var err_msg := ""
var busy := ""
var msg := ""
var sure_leave := false
var ch: Variant = null
var body: VBoxContainer
var title_l: Label
var inv_found: VBoxContainer
var inv_timer: Timer
var inv_edit: LineEdit


func setup(p: Dictionary) -> void:
	id = OUI.s(p.get("id", ""))


func _ready() -> void:
	Nav.chrome(false)
	OUI.boot()
	var pg := OUI.page(self, I18n.t("data.club"), "CLUB", func() -> void: Nav.back(), null, OUI.GOLD, _load)
	body = pg["body"]
	title_l = pg["header"].get_meta("title")
	var cc := CenterContainer.new()
	cc.custom_minimum_size.y = OUI.px(300)
	cc.add_child(OUI.spinner(36))
	body.add_child(cc)
	inv_timer = Timer.new()
	inv_timer.one_shot = true
	inv_timer.wait_time = 0.3
	inv_timer.timeout.connect(_search_invite)
	add_child(inv_timer)
	_load()
	ch = Supa.channel("club:" + id, {})
	ch.on_postgres("*", "public", "club_members", "club_id=eq." + id, func(_r: Variant) -> void: _load())
	ch.on_postgres("*", "public", "club_requests", "club_id=eq." + id, func(_r: Variant) -> void: _load())
	ch.subscribe(func(_s: Variant) -> void: pass)


func leave() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _load() -> void:
	var c: Dictionary = await OUI.get_rows("club_list?select=*&id=eq." + id)
	var m: Dictionary = await OUI.get_rows("club_members?select=user_id,role,joined_at,profiles(username,avatar,avatar_url,level,rating,online_at)&club_id=eq." + id)
	var r: Dictionary = await OUI.get_rows("club_requests?select=user_id,kind,message,created_at,profiles(username,avatar,avatar_url,level)&club_id=eq." + id)
	if not is_inside_tree():
		return
	var cd: Variant = OUI.one(c)
	if not OUI.ok(c) or cd == null:
		err_msg = OUI.err(c) if not OUI.ok(c) else I18n.t("club.club_not_found")
		OUI.clear(body)
		body.add_child(OUI.error_state(err_msg, _load))
		return
	err_msg = ""
	club = cd
	var order := {"leader": 0, "officer": 1, "member": 2}
	members = OUI.rows(m)
	members.sort_custom(func(x: Variant, y: Variant) -> bool:
		var ox: int = order.get(OUI.s(x.get("role")), 2)
		var oy: int = order.get(OUI.s(y.get("role")), 2)
		if ox != oy:
			return ox < oy
		return OUI.i(OUI.d(x.get("profiles")).get("rating")) > OUI.i(OUI.d(y.get("profiles")).get("rating")))
	reqs = OUI.rows(r)
	_render()


func _run(k: String, fn: Callable, ok_msg: String = "") -> Dictionary:
	if busy != "":
		return {}
	busy = k
	var r: Dictionary = await fn.call()
	busy = ""
	if OUI.ok(r):
		if ok_msg != "":
			OUI.toast(ok_msg, "ok")
		OUI.buzz("success")
		if is_inside_tree():
			await _load()
		OUI.refresh_profile()
	else:
		OUI.toast_err(OUI.err(r))
		OUI.buzz("heavy")
	return r


func _render() -> void:
	var u := OUI.uid()
	title_l.text = OUI.s(club.get("name"))
	OUI.clear(body)
	var mine: Dictionary = {}
	for m in members:
		if OUI.s(m.get("user_id")) == u:
			mine = m
	var role := OUI.s(mine.get("role"))
	var officer := role == "leader" or role == "officer"
	var my_req: Dictionary = {}
	for r in reqs:
		if OUI.s(r.get("user_id")) == u:
			my_req = r
	var requests := reqs.filter(func(r: Variant) -> bool: return OUI.s(r.get("kind")) == "request")
	var policy := OUI.s(club.get("join_policy"))
	# hero
	var hp := OUI.panel(OUI.GOLD, OUI.S_L, true)
	var hv := OUI.vbox(OUI.S_S)
	var em := OUI.img(OUI.disc_tex(club.get("emblem")), 96)
	em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hv.add_child(em)
	var nh := OUI.hbox(OUI.S_S, BoxContainer.ALIGNMENT_CENTER)
	nh.add_child(OUI.lbl(OUI.s(club.get("name")), 20, OUI.TEXT, "title"))
	nh.add_child(OUI.badge(OUI.s(club.get("tag")), OUI.GOLD))
	hv.add_child(nh)
	if OUI.s(club.get("description")) != "":
		hv.add_child(OUI.lbl(OUI.s(club.get("description")), OUI.TS_SMALL, Color("#d9e6ff"), "body", HORIZONTAL_ALIGNMENT_CENTER, true, 0))
	var sh := OUI.hbox(0)
	var pol_fa := I18n.t("club.open") if policy == "open" else (I18n.t("club.request") if policy == "request" else I18n.t("club.invite"))
	for it in [["%s/%s" % [OUI.fa(OUI.i(club.get("members"))), OUI.fa(OUI.i(club.get("max_members")))], I18n.t("club.members")], [OUI.fa(OUI.i(club.get("power"))), I18n.t("oui.power")], [pol_fa, I18n.t("club.recruiting")], [OUI.fa(OUI.i(club.get("min_level"), 1)), I18n.t("tournaments.minimum_level")]]:
		var sv := OUI.vbox(0)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(OUI.lbl(it[0], OUI.TS_BODY, OUI.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER))
		sv.add_child(OUI.lbl(it[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		sh.add_child(sv)
	hv.add_child(sh)
	hp.add_child(hv)
	body.add_child(hp)
	# membership actions
	if not mine.is_empty():
		var ah := OUI.hbox(OUI.S_S)
		var conv_id := OUI.s(club.get("conversation_id"))
		if conv_id != "":
			var cb := OUI.btn(I18n.t("club.club_chat"), func() -> void: Nav.go("chat", {"id": conv_id}), "green", true)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ah.add_child(cb)
		var lb := OUI.btn(I18n.t("club.are_you_sure") if sure_leave else I18n.t("club.leave_club"), func() -> void:
			if not sure_leave:
				sure_leave = true
				_render()
				return
			var r: Dictionary = await _run("leave", func() -> Dictionary: return await Supa.call_rpc("leave_club", {}), I18n.t("club.you_left_the_club"))
			if OUI.ok(r):
				Nav.back(), "red", true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(lb)
		body.add_child(ah)
	elif OUI.s(OUI.profile.get("club_id")) != "":
		body.add_child(OUI.lbl(I18n.t("club.you_re_already_in_another"), OUI.TS_BODY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	elif OUI.s(my_req.get("kind")) == "request":
		body.add_child(OUI.lbl(I18n.t("club.your_membership_request_is_pending"), OUI.TS_BODY, OUI.CYAN, "body", HORIZONTAL_ALIGNMENT_CENTER))
	elif policy == "invite" and OUI.s(my_req.get("kind")) != "invite":
		body.add_child(OUI.lbl(I18n.t("club.this_club_is_invite_only"), OUI.TS_BODY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var invited := OUI.s(my_req.get("kind")) == "invite"
		if policy == "request" and not invited:
			var mf := OUI.field(I18n.t("club.message_to_the_leader_optional"), "", 120)
			var le: LineEdit = mf.get_meta("input")
			le.text = msg
			le.text_changed.connect(func(t: String) -> void: msg = t)
			body.add_child(mf)
		var jb := OUI.btn("…" if busy == "join" else (I18n.t("club.accept_invite") if invited else (I18n.t("chat.join") if policy == "open" else I18n.t("club.send_request"))), _join, "gold")
		jb.disabled = busy != ""
		body.add_child(jb)
	# requests (officers)
	if officer and requests.size() > 0:
		body.add_child(OUI.section_title(I18n.t("club.requests_x") % OUI.fa(requests.size())))
		for r in requests:
			var ru := OUI.s(r.get("user_id"))
			var pp := OUI.d(r.get("profiles"))
			var row := OUI.row_box()
			var h := OUI.hbox(OUI.S_S)
			h.add_child(NetImg.avatar(pp.get("avatar"), pp.get("avatar_url"), 40))
			var v := OUI.vbox(0)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			v.add_child(OUI.lbl(OUI.s(pp.get("username"), "…"), OUI.TS_BODY, OUI.TEXT, "bold"))
			if OUI.s(r.get("message")) != "":
				v.add_child(OUI.lbl(OUI.s(r.get("message")), OUI.TS_CAP, OUI.DIM, "body", I18n.AR, true, 2))
			h.add_child(v)
			h.add_child(OUI.pill("✓", func() -> void: _run("d" + ru, func() -> Dictionary: return await Supa.call_rpc("club_decide", {"p_club": id, "p_user": ru, "p_accept": true}), I18n.t("club.accepted")), OUI.GREEN, 40, 44))
			h.add_child(OUI.pill("✕", func() -> void: _run("d" + ru, func() -> Dictionary: return await Supa.call_rpc("club_decide", {"p_club": id, "p_user": ru, "p_accept": false})), OUI.RED, 40, 44))
			row.add_child(h)
			body.add_child(row)
	# invite (officers)
	if officer:
		body.add_child(OUI.section_title(I18n.t("club.invite_player")))
		var old := inv_edit.text if is_instance_valid(inv_edit) else ""
		inv_edit = OUI.line_edit(I18n.t("chat.username"), 30)
		inv_edit.text = old
		inv_edit.text_changed.connect(func(_t: String) -> void: inv_timer.start())
		body.add_child(inv_edit)
		inv_found = OUI.vbox(OUI.S_S)
		body.add_child(inv_found)
		if old.strip_edges().length() >= 2:
			_search_invite()
	# members
	body.add_child(OUI.section_title(I18n.t("chat.members_x") % OUI.fa(members.size())))
	for m in members:
		var mu := OUI.s(m.get("user_id"))
		var mrole := OUI.s(m.get("role"))
		var pp := OUI.d(m.get("profiles"))
		var rf: Array = ROLE_FA.get(mrole, ROLE_FA["member"])
		var row := OUI.row_box()
		var h := OUI.hbox(OUI.S_S)
		var av := NetImg.avatar(pp.get("avatar"), pp.get("avatar_url"), 42, OUI.GREEN if OUI.is_online(pp.get("online_at")) else OUI.LINE)
		h.add_child(OUI.tap(av, func() -> void: Nav.go("public_profile", {"id": mu})))
		var v := OUI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(OUI.lbl(OUI.s(pp.get("username"), "…") + (I18n.t("ranks.you") if mu == u else ""), OUI.TS_BODY, OUI.TEXT, "bold"))
		var bh := OUI.hbox(OUI.S_XS)
		bh.add_child(OUI.badge(rf[0], rf[1]))
		bh.add_child(OUI.badge(I18n.t("hub.level_x") % OUI.fa(OUI.i(pp.get("level"), 1)), OUI.SKY))
		bh.add_child(OUI.expand())
		v.add_child(bh)
		h.add_child(v)
		if role == "leader" and mu != u:
			var up := mrole == "officer"
			h.add_child(OUI.pill("⬇" if up else "⬆", func() -> void: _run("a" + mu, func() -> Dictionary: return await Supa.call_rpc("club_member_action", {"p_club": id, "p_user": mu, "p_action": "demote" if up else "promote"})), OUI.CYAN, 40, 44))
			h.add_child(OUI.pill("👑", func() -> void: _run("a" + mu, func() -> Dictionary: return await Supa.call_rpc("club_member_action", {"p_club": id, "p_user": mu, "p_action": "transfer"}), I18n.t("club.leadership_transferred")), OUI.GOLD, 40, 44))
		if officer and mu != u and (mrole == "member" or (role == "leader" and mrole == "officer")):
			h.add_child(OUI.pill("✕", func() -> void: _run("a" + mu, func() -> Dictionary: return await Supa.call_rpc("club_member_action", {"p_club": id, "p_user": mu, "p_action": "kick"}), I18n.t("club.kicked")), OUI.RED, 40, 44))
		row.add_child(h)
		body.add_child(row)


func _join() -> void:
	var r: Dictionary = await _run("join", func() -> Dictionary: return await Supa.call_rpc("join_club", {"p_club": id, "p_message": msg.strip_edges() if msg.strip_edges() != "" else null}))
	if OUI.ok(r):
		if OUI.s(r.get("data")) == "joined":
			OUI.sfx("win")
			OUI.toast(I18n.t("club.you_joined_the_club"), "ok")
		else:
			OUI.toast(I18n.t("club.request_sent"), "ok")


func _search_invite() -> void:
	if not is_instance_valid(inv_found) or not is_instance_valid(inv_edit):
		return
	var term := OUI.ilike_term(inv_edit.text)
	OUI.clear(inv_found)
	if term.length() < 2:
		return
	var r: Dictionary = await OUI.get_rows("profiles?select=id,username,avatar,avatar_url,club_id&username=ilike.*%s*&club_id=is.null&limit=8" % term.uri_encode())
	if not is_instance_valid(inv_found):
		return
	OUI.clear(inv_found)
	for f in OUI.rows(r):
		var fid := OUI.s(f.get("id"))
		var row := OUI.row_box()
		var h := OUI.hbox(OUI.S_S)
		h.add_child(NetImg.avatar(f.get("avatar"), f.get("avatar_url"), 36))
		h.add_child(OUI.flbl(OUI.s(f.get("username")), OUI.TS_BODY))
		h.add_child(OUI.pill(I18n.t("club.invite"), func() -> void:
			_run("inv", func() -> Dictionary: return await Supa.call_rpc("club_invite", {"p_club": id, "p_user": fid}), I18n.t("club.invite_sent"))
			if is_instance_valid(inv_edit):
				inv_edit.text = ""
			OUI.clear(inv_found), OUI.GOLD, 56, 44))
		row.add_child(h)
		inv_found.add_child(row)
