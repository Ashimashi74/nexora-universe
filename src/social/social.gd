extends Control
## Social tab (port of RN social/Social.tsx): messages (inbox + user search + new group/channel +
## discover public groups), clubs (top list, search, create), friends (following / followers).
## params: {tab?: "msg"|"club"|"friends"}
## Tables/RPC: inbox (view), profiles, public_conversations (view), club_list (view), follows;
## rpc open_dm, create_conversation, join_conversation, create_club; realtime inbox:<uid>
## (INSERT messages, * conversation_members).

const KIND_LABEL := {"dm": "گفتگو", "group": "گروه", "channel": "کانال", "club": "باشگاه"}
const CLUB_EMBLEMS := ["emb0", "emb1", "emb2", "emb3", "emb4", "emb5", "emb6", "emb7", "emb8", "emb9", "emb10", "emb11", "emb12", "emb13", "emb14", "emb15"]

var tab := "msg"
var root: VBoxContainer
var content: Control
var ch: Variant = null
var debounce: Timer
var search_t: Timer
var vl: OUI.VList
# messages
var inbox: Array = []
var inbox_loaded := false
var inbox_err := ""
var q := ""
var found_box: VBoxContainer
# clubs
var clubs: Array = []
var clubs_loaded := false
var cq := ""
var club_btn_slot: VBoxContainer
# friends
var fmode := "following"
var friends: Array = []
var friends_loaded := false


func setup(p: Dictionary) -> void:
	var t := OUI.s(p.get("tab", "msg"), "msg")
	tab = t if t in ["msg", "club", "friends"] else "msg"


func _ready() -> void:
	Nav.chrome(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.4
	debounce.timeout.connect(_load_inbox)
	add_child(debounce)
	search_t = Timer.new()
	search_t.one_shot = true
	search_t.wait_time = 0.3
	search_t.timeout.connect(_do_search)
	add_child(search_t)
	OUI.ebus().profile_changed.connect(_on_profile)
	_build()


func leave() -> void:
	_unsub()


func _unsub() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null


func _on_profile(_p: Dictionary) -> void:
	if is_instance_valid(club_btn_slot):
		_fill_club_btn()


func _build() -> void:
	OUI.clear(self)
	_unsub()
	root = OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var top_pad := Control.new()
	top_pad.custom_minimum_size.y = float(Nav.insets().get("top", OUI.px(76)))
	top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_pad)
	if OUI.uid() == "":
		var cc := CenterContainer.new()
		cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var holder: Array = [null]
		var go := func() -> void:
			var b: Button = holder[0]
			if is_instance_valid(b):
				b.text = "…"
			var u: String = await OUI.ensure()
			if u == "":
				OUI.toast_err(I18n.t("account.couldn_t_connect"))
			if is_inside_tree():
				_build()
		var e := OUI.empty(OUI.ui2("c_profile"), I18n.t("home.social"), I18n.t("social.open_the_online_section_for"), I18n.t("social.sign_in_as_guest"), go)
		holder[0] = e.find_children("*", "Button", true, false)[0] if e.find_children("*", "Button", true, false).size() > 0 else null
		cc.add_child(e)
		root.add_child(cc)
		return
	root.add_child(OUI.margin(OUI.segment([["msg", I18n.t("kb.messages")], ["club", I18n.t("social.clubs")], ["friends", I18n.t("social.friends")]], tab, func(v: Variant) -> void:
		tab = str(v)
		_build()), OUI.S_L, 0, OUI.S_L, OUI.S_S))
	match tab:
		"msg": _build_messages()
		"club": _build_clubs()
		_: _build_friends()
	OUI.fade_in(root)


# ================================================================ messages
func _build_messages() -> void:
	vl = OUI.VList.new(72, _make_inbox_row, _bind_inbox_row, 8)
	vl.pad_bottom = int(Nav.insets().get("bottom", OUI.px(110)))
	root.add_child(vl)
	var hv := OUI.vbox(OUI.S_S)
	var sf := OUI.line_edit(I18n.t("social.search_players_by_username"), 30)
	sf.text = q
	sf.text_changed.connect(func(t: String) -> void:
		q = t
		search_t.start())
	hv.add_child(sf)
	found_box = OUI.vbox(OUI.S_S)
	hv.add_child(found_box)
	var bh := OUI.hbox(OUI.S_S)
	var b1 := OUI.btn(I18n.t("social.new_group_channel"), _open_new_conv, "green", true)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := OUI.btn(I18n.t("social.discover_groups"), _open_discover, "dark", true)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(b1)
	bh.add_child(b2)
	hv.add_child(bh)
	vl.set_header(OUI.margin(hv, OUI.S_L, 0, OUI.S_L, OUI.S_M))
	_apply_inbox()
	_load_inbox()
	if q.strip_edges().length() >= 2:
		_do_search()
	var u := OUI.uid()
	ch = Supa.channel("inbox:" + u, {})
	ch.on_postgres("INSERT", "public", "messages", "", func(_r: Variant) -> void: debounce.start())
	ch.on_postgres("*", "public", "conversation_members", "user_id=eq." + u, func(_r: Variant) -> void: debounce.start())
	ch.subscribe(func(_s: Variant) -> void: pass)


func _load_inbox() -> void:
	var r: Dictionary = await OUI.get_rows("inbox?select=*&order=last_message_at.desc&limit=100")
	if not is_inside_tree() or tab != "msg":
		return
	if not OUI.ok(r):
		inbox_err = OUI.err(r)
	else:
		inbox_err = ""
		inbox = OUI.rows(r)
		inbox_loaded = true
	_apply_inbox()


func _apply_inbox() -> void:
	if vl == null or not is_instance_valid(vl):
		return
	vl.set_items(inbox)
	if inbox_err != "":
		vl.set_empty(OUI.error_state(inbox_err, _load_inbox))
	elif not inbox_loaded:
		vl.set_empty(OUI.skeleton(5, 64))
	else:
		vl.set_empty(OUI.empty(OUI.ui2("c_mega"), I18n.t("social.no_conversations_yet"), I18n.t("social.search_for_a_player_or")))


func _do_search() -> void:
	if not is_instance_valid(found_box):
		return
	var term := OUI.ilike_term(q)
	if term.length() < 2:
		OUI.clear(found_box)
		return
	var r: Dictionary = await OUI.get_rows("profiles?select=id,username,avatar,avatar_url,level,online_at&username=ilike.*%s*&id=neq.%s&limit=20" % [term.uri_encode(), OUI.uid()])
	if not is_instance_valid(found_box) or OUI.ilike_term(q) != term:
		return
	OUI.clear(found_box)
	var list := OUI.rows(r)
	if list.is_empty():
		found_box.add_child(OUI.lbl(I18n.t("social.no_one_found"), OUI.TS_BODY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		return
	for p in list:
		var id := OUI.s(p.get("id"))
		var row := OUI.row_box(OUI.S_S, 60)
		var h := OUI.hbox(OUI.S_S)
		var av := NetImg.avatar(p.get("avatar"), p.get("avatar_url"), 40, OUI.GREEN if OUI.is_online(p.get("online_at")) else OUI.LINE)
		h.add_child(OUI.tap(av, func() -> void: Nav.go("public_profile", {"id": id})))
		var v := OUI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(OUI.lbl(OUI.s(p.get("username")), OUI.TS_BODY, OUI.TEXT, "bold"))
		v.add_child(OUI.lbl(I18n.t("hub.level_x") % OUI.fa(OUI.i(p.get("level"), 1)), OUI.TS_TINY, OUI.DIM))
		h.add_child(v)
		h.add_child(OUI.pill(I18n.t("kb.message"), func() -> void: _dm(id), OUI.CYAN, 60, 44))
		row.add_child(h)
		found_box.add_child(row)


func _dm(id: String) -> void:
	var r: Dictionary = await Supa.call_rpc("open_dm", {"p_user": id})
	if OUI.ok(r):
		q = ""
		Nav.go("chat", {"id": OUI.s(r.get("data"))})
	else:
		OUI.toast_err(OUI.err(r))


class InboxRow extends Button:
	var av: NetImg.Avatar
	var icon_wrap: PanelContainer
	var icon_tex: TextureRect
	var title_l: Label
	var kind_slot: HBoxContainer
	var last_l: Label
	var time_l: Label
	var unread_slot: VBoxContainer
	var id := ""


func _make_inbox_row() -> Control:
	var b := InboxRow.new()
	b.focus_mode = Control.FOCUS_NONE
	var st := OUI.sb(OUI.ROW_BG, 16, OUI.LINE, 1)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var h := OUI.hbox(OUI.S_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = OUI.px(8)
	h.offset_right = -OUI.px(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.av = NetImg.avatar(null, null, 48)
	h.add_child(b.av)
	b.icon_wrap = PanelContainer.new()
	b.icon_wrap.custom_minimum_size = Vector2(OUI.px(48), OUI.px(48))
	b.icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon_tex = OUI.img(null, 32)
	b.icon_wrap.add_child(b.icon_tex)
	h.add_child(b.icon_wrap)
	var v := OUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var th := OUI.hbox(OUI.S_XS)
	b.title_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	b.title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(b.title_l)
	b.kind_slot = OUI.hbox(0)
	th.add_child(b.kind_slot)
	v.add_child(th)
	b.last_l = OUI.lbl("", OUI.TS_SMALL, OUI.DIM)
	v.add_child(b.last_l)
	h.add_child(v)
	b.unread_slot = OUI.vbox(4)
	b.unread_slot.custom_minimum_size.x = OUI.px(48)
	b.unread_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	b.time_l = OUI.lbl("", OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
	b.unread_slot.add_child(b.time_l)
	h.add_child(b.unread_slot)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		OUI.press_fx(b)
		OUI.sfx("ui")
		Nav.go("chat", {"id": b.id}))
	return b


func _bind_inbox_row(c: Control, item: Variant, _i: int) -> void:
	var b := c as InboxRow
	var r := OUI.d(item)
	b.id = OUI.s(r.get("id"))
	var kind := OUI.s(r.get("kind"), "dm")
	var peer := OUI.d(r.get("peer"))
	var is_dm := kind == "dm"
	var kc := OUI.GOLD if kind == "club" else (OUI.VIOLET if kind == "channel" else OUI.CYAN)
	b.av.visible = is_dm
	b.icon_wrap.visible = not is_dm
	if is_dm:
		b.av.set_data(peer.get("avatar"), peer.get("avatar_url"), OUI.GREEN if OUI.is_online(peer.get("online_at")) else OUI.LINE)
		b.av.dot = OUI.GREEN if OUI.is_online(peer.get("online_at")) else null
	else:
		b.icon_wrap.add_theme_stylebox_override("panel", OUI.sb(Color("#050816"), 24, kc, 2))
		var url := OUI.s(r.get("avatar_url"))
		b.icon_tex.texture = OUI.ui2("x_shield" if kind == "club" else ("c_mega" if kind == "channel" else "x_team"))
		if url != "":
			var want := b.id
			NetImg.fetch(url, func(t: Texture2D) -> void:
				if is_instance_valid(b) and b.id == want and t:
					b.icon_tex.texture = t)
	b.title_l.text = OUI.s(peer.get("username"), I18n.t("lobby.chat")) if is_dm else (OUI.s(r.get("title")) if OUI.s(r.get("title")) != "" else KIND_LABEL.get(kind, ""))
	OUI.clear(b.kind_slot)
	if not is_dm:
		b.kind_slot.add_child(OUI.badge(KIND_LABEL.get(kind, ""), kc))
	var lm := OUI.d(r.get("last_message"))
	var unread := OUI.i(r.get("unread"))
	if lm.is_empty():
		b.last_l.text = I18n.t("social.no_messages")
	elif OUI.s(lm.get("image_url")) != "" and OUI.s(lm.get("body")) == "":
		b.last_l.text = I18n.t("chat.photo")
	else:
		b.last_l.text = OUI.s(lm.get("body"))
	b.last_l.add_theme_color_override("font_color", OUI.TEXT if unread > 0 else OUI.DIM)
	b.time_l.text = OUI.time_ago(lm.get("created_at") if not lm.is_empty() else r.get("last_message_at"))
	while b.unread_slot.get_child_count() > 1:
		var x := b.unread_slot.get_child(1)
		b.unread_slot.remove_child(x)
		x.queue_free()
	if unread > 0:
		b.unread_slot.add_child(OUI.unread_dot(unread))


func _open_new_conv() -> void:
	var st := {"kind": "group", "pub": true}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_S)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL))
	var hint := OUI.lbl(I18n.t("social.in_a_group_every_member"), OUI.TS_CAP, OUI.DIM, "body", I18n.AR, true, 2)
	v.add_child(OUI.segment([["group", I18n.t("kb.group")], ["channel", I18n.t("kb.channel")]], "group", func(x: Variant) -> void:
		st["kind"] = x
		hint.text = I18n.t("social.in_a_group_every_member") if x == "group" else I18n.t("social.in_a_channel_only_the")))
	v.add_child(hint)
	var tf := OUI.field(I18n.t("social.title"), "", 40)
	v.add_child(tf)
	v.add_child(OUI.lbl(I18n.t("social.description_optional"), OUI.TS_SMALL, OUI.DIM, "bold"))
	var about := OUI.text_area("", 80)
	v.add_child(about)
	v.add_child(OUI.opt_row(I18n.t("social.public"), I18n.t("social.show_in_discover_so_anyone"), true, func(x: bool) -> void: st["pub"] = x))
	var go := OUI.btn(I18n.t("social.create"), Callable(), "green")
	go.pressed.connect(func() -> void:
		var title := OUI.field_value(tf).strip_edges()
		if title.length() < 2:
			OUI.toast_err(I18n.t("social.a_title_is_required"))
			return
		go.disabled = true
		go.text = "…"
		var ab := about.text.strip_edges().substr(0, 200)
		var r: Dictionary = await Supa.call_rpc("create_conversation", {"p_kind": st["kind"], "p_title": title, "p_about": ab if ab != "" else null, "p_public": st["pub"], "p_members": []})
		if OUI.ok(r):
			OUI.sfx("ready")
			Nav.close_sheet()
			Nav.go("chat", {"id": OUI.s(r.get("data"))})
		else:
			OUI.toast_err(OUI.err(r))
			if is_instance_valid(go):
				go.disabled = false
				go.text = I18n.t("social.create"))
	v.add_child(go)
	OUI.open_sheet(I18n.t("social.new_group_or_channel"), "NEW CONVERSATION", sc, OUI.CYAN, 0.82)


func _open_discover() -> void:
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_S)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL))
	v.add_child(OUI.skeleton(4))
	OUI.open_sheet(I18n.t("social.discover_groups_and_channels"), "DISCOVER", sc, OUI.CYAN, 0.82)
	var r: Dictionary = await OUI.get_rows("public_conversations?select=*&order=members.desc&limit=50")
	if not is_instance_valid(v):
		return
	OUI.clear(v)
	var list := OUI.rows(r)
	if list.is_empty():
		v.add_child(OUI.empty(OUI.ui2("x_ball"), I18n.t("social.no_public_groups_yet"), I18n.t("social.create_the_first_group_yourself")))
		return
	for it in list:
		var id := OUI.s(it.get("id"))
		var kind := OUI.s(it.get("kind"))
		var row := OUI.row_box(OUI.S_S, 60)
		var h := OUI.hbox(OUI.S_S)
		var ic := PanelContainer.new()
		ic.custom_minimum_size = Vector2(OUI.px(48), OUI.px(48))
		ic.add_theme_stylebox_override("panel", OUI.sb(Color("#050816"), 24, OUI.VIOLET if kind == "channel" else OUI.CYAN, 2))
		ic.add_child(OUI.img(OUI.ui2("c_mega" if kind == "channel" else "x_team"), 30))
		h.add_child(ic)
		var tv := OUI.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(OUI.lbl(OUI.s(it.get("title")), OUI.TS_BODY, OUI.TEXT, "bold"))
		var ab := OUI.s(it.get("about"))
		tv.add_child(OUI.lbl(I18n.t("social.x_x_membersx") % [KIND_LABEL.get(kind, ""), OUI.fa(OUI.i(it.get("members"))), (" · " + ab) if ab != "" else ""], OUI.TS_CAP, OUI.DIM))
		h.add_child(tv)
		h.add_child(OUI.pill(I18n.t("chat.join"), func() -> void:
			var jr: Dictionary = await Supa.call_rpc("join_conversation", {"p_conv": id})
			if OUI.ok(jr):
				OUI.sfx("join")
				Nav.close_sheet()
				Nav.go("chat", {"id": id})
			else:
				OUI.toast_err(OUI.err(jr)), OUI.GREEN, 64, 44))
		row.add_child(h)
		v.add_child(row)


# ================================================================ clubs
func _build_clubs() -> void:
	vl = OUI.VList.new(70, _make_club_row, _bind_club_row, 8)
	vl.pad_bottom = int(Nav.insets().get("bottom", OUI.px(110)))
	root.add_child(vl)
	var hv := OUI.vbox(OUI.S_S)
	club_btn_slot = OUI.vbox(0)
	hv.add_child(club_btn_slot)
	_fill_club_btn()
	var sf := OUI.line_edit(I18n.t("social.search_club_name_or_tag"), 24)
	sf.text = cq
	var ct := Timer.new()
	ct.one_shot = true
	ct.wait_time = 0.25
	ct.timeout.connect(_load_clubs)
	add_child(ct)
	sf.text_changed.connect(func(t: String) -> void:
		cq = t
		ct.start())
	hv.add_child(sf)
	hv.add_child(OUI.lbl(I18n.t("social.top_clubs"), OUI.TS_H, OUI.TEXT, "bold"))
	vl.set_header(OUI.margin(hv, OUI.S_L, 0, OUI.S_L, OUI.S_S))
	_apply_clubs()
	_load_clubs()


func _fill_club_btn() -> void:
	OUI.clear(club_btn_slot)
	var cid := OUI.s(OUI.profile.get("club_id"))
	if cid != "":
		club_btn_slot.add_child(OUI.btn(I18n.t("social.my_club"), func() -> void: Nav.go("club", {"id": cid}), "gold", true))
	else:
		club_btn_slot.add_child(OUI.btn(I18n.t("social.create_club_50_gems"), _open_create_club, "green", true))


func _load_clubs() -> void:
	var path := "club_list?select=*&order=power.desc&limit=50"
	var term := OUI.ilike_term(cq)
	if term != "":
		var e := term.uri_encode()
		path += "&or=(name.ilike.*%s*,tag.ilike.*%s*)" % [e, e]
	var r: Dictionary = await OUI.get_rows(path)
	if not is_inside_tree() or tab != "club":
		return
	clubs = OUI.rows(r)
	clubs_loaded = true
	_apply_clubs()


func _apply_clubs() -> void:
	if vl == null or not is_instance_valid(vl):
		return
	vl.set_items(clubs)
	vl.set_empty(OUI.skeleton(5, 70) if not clubs_loaded else OUI.empty(OUI.ui2("x_shield"), I18n.t("social.no_clubs_found")))


class ClubRow extends Button:
	var rank_l: Label
	var emb: TextureRect
	var name_l: Label
	var tag_slot: HBoxContainer
	var sub_l: Label
	var pow_l: Label
	var bg: StyleBoxFlat
	var id := ""


func _make_club_row() -> Control:
	var b := ClubRow.new()
	b.focus_mode = Control.FOCUS_NONE
	var h := OUI.hbox(OUI.S_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = OUI.px(8)
	h.offset_right = -OUI.px(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.rank_l = OUI.lbl("", OUI.TS_BODY, OUI.DIM, "title", HORIZONTAL_ALIGNMENT_CENTER)
	b.rank_l.custom_minimum_size.x = OUI.px(28)
	h.add_child(b.rank_l)
	b.emb = OUI.img(null, 46)
	h.add_child(b.emb)
	var v := OUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var nh := OUI.hbox(OUI.S_XS)
	b.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	nh.add_child(b.name_l)
	b.tag_slot = OUI.hbox(0)
	nh.add_child(b.tag_slot)
	nh.add_child(OUI.expand())
	v.add_child(nh)
	b.sub_l = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	v.add_child(b.sub_l)
	h.add_child(v)
	var pv := OUI.vbox(0)
	pv.custom_minimum_size.x = OUI.px(64)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	b.pow_l = OUI.lbl("", 13, OUI.ORANGE, "title", HORIZONTAL_ALIGNMENT_CENTER)
	pv.add_child(b.pow_l)
	pv.add_child(OUI.lbl(I18n.t("oui.power"), 9, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	h.add_child(pv)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		OUI.press_fx(b)
		OUI.sfx("ui")
		Nav.go("club", {"id": b.id}))
	return b


func _bind_club_row(c: Control, item: Variant, idx: int) -> void:
	var b := c as ClubRow
	var it := OUI.d(item)
	b.id = OUI.s(it.get("id"))
	var st := OUI.sb(OUI.ROW_BG, 16, OUI.GOLD if b.id == OUI.s(OUI.profile.get("club_id")) else OUI.LINE, 1)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.rank_l.text = OUI.fa(idx + 1)
	b.rank_l.add_theme_color_override("font_color", OUI.GOLD if idx < 3 else OUI.DIM)
	b.emb.texture = OUI.disc_tex(it.get("emblem"))
	b.name_l.text = OUI.s(it.get("name"))
	OUI.clear(b.tag_slot)
	b.tag_slot.add_child(OUI.badge(OUI.s(it.get("tag")), OUI.GOLD))
	var pol := OUI.s(it.get("join_policy"))
	b.sub_l.text = I18n.t("social.x_x_members_x") % [OUI.fa(OUI.i(it.get("members"))), OUI.fa(OUI.i(it.get("max_members"))), I18n.t("club.open") if pol == "open" else (I18n.t("social.by_request") if pol == "request" else I18n.t("social.invite_only"))]
	b.pow_l.text = OUI.fa(OUI.i(it.get("power")))


func _open_create_club() -> void:
	var st := {"emblem": "emb0", "policy": "open"}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_S)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
	var nf := OUI.field(I18n.t("social.club_name"), "", 24)
	v.add_child(nf)
	var tf := OUI.field(I18n.t("social.tag_2_to_5_english"), "", 5, false, true)
	var tle: LineEdit = tf.get_meta("input")
	tle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tle.add_theme_font_override("font", OUI.font("head"))
	tle.text_changed.connect(func(t: String) -> void:
		var clean := ""
		for c in t.to_upper():
			if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
				clean += c
		clean = clean.substr(0, 5)
		if clean != t:
			tle.text = clean
			tle.caret_column = clean.length())
	v.add_child(tf)
	v.add_child(OUI.lbl(I18n.t("social.description"), OUI.TS_SMALL, OUI.DIM, "bold"))
	var desc := OUI.text_area("", 80)
	v.add_child(desc)
	v.add_child(OUI.cap_label(I18n.t("data.emblem")))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", OUI.px(8))
	grid.add_theme_constant_override("v_separation", OUI.px(8))
	var cells: Dictionary = {}
	var paint := func() -> void:
		for k in cells:
			var on: bool = k == st["emblem"]
			(cells[k] as PanelContainer).add_theme_stylebox_override("panel", OUI.sb(Color(1, 210 / 255.0, 87 / 255.0, 0.15) if on else Color(0, 0, 0, 0), 14, OUI.GOLD if on else OUI.LINE, 1, 6))
	for e in CLUB_EMBLEMS:
		var ek: String = e
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(OUI.px(56), OUI.px(56))
		pc.add_child(OUI.img(OUI.disc_tex(e), 40))
		cells[e] = pc
		grid.add_child(OUI.tap(pc, func() -> void:
			st["emblem"] = ek
			paint.call()))
	paint.call()
	v.add_child(grid)
	v.add_child(OUI.cap_label(I18n.t("club.recruiting")))
	v.add_child(OUI.segment([["open", I18n.t("club.open")], ["request", I18n.t("social.by_request")], ["invite", I18n.t("social.invite_only")]], "open", func(x: Variant) -> void: st["policy"] = x, OUI.GOLD))
	v.add_child(OUI.spacer(OUI.S_L))
	var go := OUI.btn(I18n.t("social.create_club_50_gems_2"), Callable(), "gold")
	go.pressed.connect(func() -> void:
		var name := OUI.field_value(nf).strip_edges()
		var tag := tle.text
		if name.length() < 3 or name.length() > 24:
			OUI.toast_err(I18n.t("social.club_name_must_be_3"))
			return
		if RegEx.create_from_string("^[A-Z0-9]{2,5}$").search(tag) == null:
			OUI.toast_err(I18n.t("social.tag_2_to_5_uppercase"))
			return
		if OUI.i(OUI.profile.get("gems")) < 50:
			OUI.toast_err(I18n.t("social.you_need_50_gems"))
			OracleCoach.react("nogems")
			return
		go.disabled = true
		go.text = "…"
		var ds := desc.text.strip_edges().substr(0, 300)
		var r: Dictionary = await Supa.call_rpc("create_club", {"p_name": name, "p_tag": tag, "p_emblem": st["emblem"], "p_desc": ds if ds != "" else null, "p_policy": st["policy"], "p_min_level": 1})
		if OUI.ok(r):
			OUI.sfx("win")
			OUI.buzz("success")
			OUI.toast(I18n.t("social.club_created"), "ok")
			OUI.refresh_profile()
			Nav.close_sheet()
			Nav.go("club", {"id": OUI.s(r.get("data"))})
		else:
			OUI.toast_err(OUI.err(r))
			if is_instance_valid(go):
				go.disabled = false
				go.text = I18n.t("social.create_club_50_gems_2"))
	v.add_child(go)
	OUI.open_sheet(I18n.t("social.create_club"), "NEW CLUB", sc, OUI.GOLD, 0.9)


# ================================================================ friends
func _build_friends() -> void:
	vl = OUI.VList.new(60, _make_friend_row, _bind_friend_row, 8)
	vl.pad_bottom = int(Nav.insets().get("bottom", OUI.px(110)))
	root.add_child(vl)
	vl.set_header(OUI.margin(OUI.segment([["following", I18n.t("social.following")], ["followers", I18n.t("social.followers")]], fmode, func(x: Variant) -> void:
		fmode = str(x)
		_load_friends(), OUI.GREEN), OUI.S_L, 0, OUI.S_L, OUI.S_S))
	_load_friends()


func _load_friends() -> void:
	friends_loaded = false
	friends = []
	_apply_friends()
	var u := OUI.uid()
	var want := fmode
	var col := "follower" if fmode == "following" else "followee"
	var other := "followee" if fmode == "following" else "follower"
	var r: Dictionary = await OUI.get_rows("follows?select=%s&%s=eq.%s&limit=200" % [other, col, u])
	var ids: Array = []
	for x in OUI.rows(r):
		ids.append(OUI.s(x.get(other)))
	var ps: Array = []
	if not ids.is_empty():
		var r2: Dictionary = await OUI.get_rows("profiles?select=id,username,avatar,avatar_url,level,online_at,league&id=in.(%s)" % ",".join(ids))
		ps = OUI.rows(r2)
	if not is_inside_tree() or tab != "friends" or want != fmode:
		return
	ps.sort_custom(func(a: Variant, b: Variant) -> bool: return int(OUI.is_online(a.get("online_at"))) > int(OUI.is_online(b.get("online_at"))))
	friends = ps
	friends_loaded = true
	_apply_friends()


func _apply_friends() -> void:
	if vl == null or not is_instance_valid(vl):
		return
	vl.set_items(friends)
	if not friends_loaded:
		var cc := CenterContainer.new()
		cc.custom_minimum_size.y = OUI.px(80)
		cc.add_child(OUI.spinner())
		vl.set_empty(cc)
	else:
		vl.set_empty(OUI.empty(OUI.ui2("x_player"), I18n.t("social.you_re_not_following_anyone") if fmode == "following" else I18n.t("social.you_have_no_followers_yet"), I18n.t("social.find_players_from_the_leaderboard")))


class FriendRow extends Button:
	var av: NetImg.Avatar
	var name_l: Label
	var sub_l: Label
	var lv_slot: HBoxContainer
	var id := ""


func _make_friend_row() -> Control:
	var b := FriendRow.new()
	b.focus_mode = Control.FOCUS_NONE
	var st := OUI.sb(OUI.ROW_BG, 16, OUI.LINE, 1)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var h := OUI.hbox(OUI.S_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = OUI.px(8)
	h.offset_right = -OUI.px(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.av = NetImg.avatar(null, null, 44)
	h.add_child(b.av)
	var v := OUI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	b.sub_l = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	v.add_child(b.name_l)
	v.add_child(b.sub_l)
	h.add_child(v)
	b.lv_slot = OUI.hbox(0)
	b.lv_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b.lv_slot)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		OUI.press_fx(b)
		OUI.sfx("ui")
		Nav.go("public_profile", {"id": b.id}))
	return b


func _bind_friend_row(c: Control, item: Variant, _i: int) -> void:
	var b := c as FriendRow
	var it := OUI.d(item)
	b.id = OUI.s(it.get("id"))
	var on := OUI.is_online(it.get("online_at"))
	b.av.set_data(it.get("avatar"), it.get("avatar_url"), OUI.GREEN if on else OUI.LINE)
	b.name_l.text = OUI.s(it.get("username"))
	b.sub_l.text = I18n.t("hub.online") if on else I18n.t("public_profile.last_seen_x_ago") % OUI.time_ago(it.get("online_at"))
	b.sub_l.add_theme_color_override("font_color", OUI.GREEN if on else OUI.DIM)
	OUI.clear(b.lv_slot)
	b.lv_slot.add_child(OUI.badge(I18n.t("hub.level_x") % OUI.fa(OUI.i(it.get("level"), 1)), OUI.GOLD))
