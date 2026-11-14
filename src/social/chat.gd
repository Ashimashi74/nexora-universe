extends Control
## Conversation screen (port of RN social/Chat.tsx) for DM / group / channel / club:
## realtime messages, image send (native picker → storage bucket "chat"), reply, delete own,
## typing indicator over broadcast, read receipts (last_read_at), info sheet for groups (members,
## add / promote / demote / remove, leave), paging (40 per page, older on scroll to top).
## params: {id: conversation uuid}
## Tables/RPC: conversations, conversation_members, messages (select/insert/update), profiles;
## rpc join_conversation, manage_member, leave_conversation; realtime conv:<id>.

const PAGE := 40
const KIND_LABEL := {"dm": "گفتگو", "group": "گروه", "channel": "کانال", "club": "باشگاه"}

var id := ""
var conv: Dictionary = {}
var members: Array = []
var by_id: Dictionary = {}
var msgs: Array = []          # newest first (like RN)
var msg_nodes: Dictionary = {} # id -> bubble
var more := true
var loading_more := false
var reply: Dictionary = {}
var typing: Dictionary = {}
var sending := false
var last_typing := 0.0
var ch: Variant = null
var hdr: Control
var title_l: Label
var right_slot: HBoxContainer
var sc: ScrollContainer
var list: VBoxContainer
var typing_l: Label
var reply_bar: PanelContainer
var input_slot: VBoxContainer
var txt: LineEdit
var overlay: Control = null
var spinner: Control
var _loaded := false


func setup(p: Dictionary) -> void:
	id = OUI.s(p.get("id", ""))


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	OUI.boot()
	OracleCoach.set_quiet("chat", true)
	var root := OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = OUI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)
	move_child(bg, 0)
	right_slot = OUI.hbox(0)
	hdr = OUI.header(I18n.t("lobby.chat"), "", func() -> void: Nav.back(), right_slot)
	title_l = hdr.get_meta("title")
	root.add_child(hdr)
	sc = OUI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	list = OUI.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(OUI.margin(list, OUI.S_M, OUI.S_S, OUI.S_M, OUI.S_S))
	spinner = CenterContainer.new()
	spinner.custom_minimum_size.y = OUI.px(200)
	spinner.add_child(OUI.spinner())
	list.add_child(spinner)
	sc.get_v_scroll_bar().value_changed.connect(_on_scroll)
	typing_l = OUI.lbl("", OUI.TS_CAP, OUI.CYAN)
	typing_l.visible = false
	root.add_child(OUI.margin(typing_l, OUI.S_L, 0, OUI.S_L, 2))
	reply_bar = PanelContainer.new()
	reply_bar.visible = false
	reply_bar.add_theme_stylebox_override("panel", OUI.sb(Color(10 / 255.0, 16 / 255.0, 44 / 255.0, 0.95), 0, OUI.LINE, 1, 6))
	root.add_child(reply_bar)
	input_slot = OUI.vbox(0)
	var ist := PanelContainer.new()
	ist.add_theme_stylebox_override("panel", OUI.sb(Color(4 / 255.0, 8 / 255.0, 24 / 255.0, 0.96), 0, OUI.LINE, 1, 8))
	ist.add_child(input_slot)
	root.add_child(ist)
	var tk := Timer.new()
	tk.wait_time = 1.5
	tk.timeout.connect(_typing_tick)
	add_child(tk)
	tk.start()
	OUI.fade_in(root)
	_start()


func leave() -> void:
	OracleCoach.set_quiet("chat", false)
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	_mark_read()
	Nav.chrome(true)


func on_back() -> bool:
	if overlay and is_instance_valid(overlay):
		_close_overlay()
		return true
	return false


func _start() -> void:
	if OUI.uid() == "":
		await OUI.ensure()
	if not is_inside_tree():
		return
	_load_meta()
	_load_msgs("")
	_mark_read()
	ch = Supa.channel("conv:" + id, {"broadcast": {"self": false}})
	ch.on_postgres("INSERT", "public", "messages", "conversation_id=eq." + id, _on_insert)
	ch.on_postgres("UPDATE", "public", "messages", "conversation_id=eq." + id, _on_update)
	ch.on_postgres("*", "public", "conversation_members", "conversation_id=eq." + id, func(_r: Variant) -> void: _load_meta())
	ch.on_broadcast("typing", _on_typing)
	ch.subscribe(func(_s: Variant) -> void: pass)


func _uid() -> String:
	return OUI.uid()


func _mark_read() -> void:
	var u := _uid()
	if u != "" and id != "":
		OUI.patch("conversation_members?conversation_id=eq.%s&user_id=eq.%s" % [id, u], {"last_read_at": OUI.now_iso()})


# ---------------------------------------------------------------- data
func _load_meta() -> void:
	var c: Dictionary = await OUI.get_rows("conversations?select=*&id=eq." + id)
	var m: Dictionary = await OUI.get_rows("conversation_members?select=user_id,role,profiles(username,avatar,avatar_url,online_at)&conversation_id=eq.%s&limit=500" % id)
	if not is_inside_tree():
		return
	var cv: Variant = OUI.one(c)
	if cv is Dictionary:
		conv = cv
	if OUI.ok(m):
		members = OUI.rows(m)
		by_id = {}
		for x in members:
			by_id[OUI.s(x.get("user_id"))] = x
	_render_meta()
	# names inside bubbles depend on members
	if _loaded:
		_rebuild_list()


func _load_msgs(before: String) -> void:
	var path := "messages?select=*&conversation_id=eq.%s&order=created_at.desc&limit=%d" % [id, PAGE]
	if before != "":
		path += "&created_at=lt." + before.uri_encode()
	var r: Dictionary = await OUI.get_rows(path)
	loading_more = false
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		if before == "":
			msgs = []
			_loaded = true
			_rebuild_list()
		return
	var rows := OUI.rows(r)
	more = rows.size() == PAGE
	if before == "":
		msgs = rows
		_loaded = true
		_rebuild_list()
		_scroll_end()
	else:
		var old_max := sc.get_v_scroll_bar().max_value
		msgs.append_array(rows)
		_rebuild_list()
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value - old_max) + sc.scroll_vertical


func _on_scroll(v: float) -> void:
	if v < OUI.px(80) and more and not loading_more and _loaded and msgs.size() > 0:
		loading_more = true
		_load_msgs(OUI.s(msgs.back().get("created_at")))


func _on_insert(rec: Variant) -> void:
	var m := OUI.rec_new(rec)
	if m.is_empty():
		return
	_add_msg(m)
	var snd := OUI.s(m.get("sender"))
	if snd != _uid():
		OUI.sfx("chat")
		_mark_read()
	if snd != "":
		typing.erase(snd)
		_typing_tick()


func _on_update(rec: Variant) -> void:
	var m := OUI.rec_new(rec)
	var mid := OUI.i(m.get("id"))
	for k in msgs.size():
		if OUI.i(msgs[k].get("id")) == mid:
			msgs[k] = m
	_rebuild_list()


func _on_typing(payload: Variant) -> void:
	var p := OUI.d(payload)
	if p.has("payload"):
		p = OUI.d(p["payload"])
	var u := OUI.s(p.get("u"))
	if u != "" and u != _uid():
		typing[u] = Time.get_ticks_msec() / 1000.0
		_typing_tick()


func _typing_tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for k in typing.keys():
		if now - float(typing[k]) >= 4.0:
			typing.erase(k)
	var names: Array = []
	for k in typing:
		var n := OUI.s(OUI.d(OUI.d(by_id.get(k)).get("profiles")).get("username"))
		if n != "":
			names.append(n)
	typing_l.visible = names.size() > 0
	typing_l.text = I18n.t("chat.x_is_typing") % "، ".join(names)


func _add_msg(m: Dictionary) -> void:
	var mid := OUI.i(m.get("id"))
	for x in msgs:
		if OUI.i(x.get("id")) == mid:
			return
	msgs.push_front(m)
	if not _loaded:
		return
	var at_end := sc.scroll_vertical >= sc.get_v_scroll_bar().max_value - sc.size.y - OUI.px(120)
	_rebuild_list()
	if at_end or OUI.s(m.get("sender")) == _uid():
		_scroll_end()


func _scroll_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------- render
func _me_member() -> Dictionary:
	return OUI.d(by_id.get(_uid()))


func _peer() -> Dictionary:
	if OUI.s(conv.get("kind")) != "dm":
		return {}
	for m in members:
		if OUI.s(m.get("user_id")) != _uid():
			return m
	return {}


func _can_post() -> bool:
	var me := _me_member()
	if me.is_empty():
		return false
	var role := OUI.s(me.get("role"))
	return OUI.s(conv.get("kind")) != "channel" or role == "owner" or role == "admin"


func _render_meta() -> void:
	var kind := OUI.s(conv.get("kind"))
	var peer := _peer()
	var pp := OUI.d(peer.get("profiles"))
	title_l.text = (OUI.s(pp.get("username"), I18n.t("lobby.chat")) if kind == "dm" else OUI.s(conv.get("title"), I18n.t("lobby.chat")))
	if title_l.text == "":
		title_l.text = I18n.t("lobby.chat")
	var en := ""
	if not conv.is_empty():
		en = ("ONLINE" if OUI.is_online(pp.get("online_at")) else "DIRECT") if kind == "dm" else I18n.t("chat.x_x_members") % [KIND_LABEL.get(kind, ""), OUI.fa(members.size())]
	var hv: VBoxContainer = title_l.get_parent()
	if hv.get_child_count() > 1:
		(hv.get_child(0) as Label).text = en
	elif en != "":
		var el := OUI.lbl(en, 9, OUI.CYAN, "head")
		hv.add_child(el)
		hv.move_child(el, 0)
	OUI.clear(right_slot)
	if kind == "dm" and not peer.is_empty():
		var pid := OUI.s(peer.get("user_id"))
		var av := NetImg.avatar(pp.get("avatar"), pp.get("avatar_url"), 40, OUI.GREEN if OUI.is_online(pp.get("online_at")) else OUI.LINE)
		right_slot.add_child(OUI.tap(av, func() -> void: Nav.go("public_profile", {"id": pid})))
	elif not conv.is_empty():
		right_slot.add_child(OUI.pill("ⓘ", _open_info, OUI.CYAN, 44, 44))
	# input area
	OUI.clear(input_slot)
	if _can_post():
		var row := OUI.hbox(OUI.S_S)
		row.layout_direction = Control.LAYOUT_DIRECTION_LTR
		var old := txt.text if is_instance_valid(txt) else ""
		txt = OUI.line_edit(I18n.t("ui_bits.message"), 2000, false, false, 44)
		txt.text = old
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.text_changed.connect(_on_type)
		txt.text_submitted.connect(func(_t: String) -> void: _send(""))
		row.add_child(txt)
		var send := OUI.pill("…" if sending else "➤", func() -> void: _send(""), OUI.CYAN, 44, 44)
		row.add_child(send)
		row.add_child(OUI.pill("🖼", _send_image, OUI.DIM, 44, 44))
		input_slot.add_child(row)
	elif not conv.is_empty() and _me_member().is_empty() and bool(conv.get("is_public", false)):
		input_slot.add_child(OUI.btn(I18n.t("chat.join"), func() -> void:
			var r: Dictionary = await Supa.call_rpc("join_conversation", {"p_conv": id})
			if OUI.ok(r):
				_load_meta()
			else:
				OUI.toast_err(OUI.err(r)), "green"))
	elif not conv.is_empty():
		input_slot.add_child(OUI.lbl(I18n.t("chat.only_channel_admins_can_post") if kind == "channel" else I18n.t("chat.can_t_send_messages"), OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))


func _rebuild_list() -> void:
	OUI.clear(list)
	msg_nodes.clear()
	if msgs.is_empty():
		list.add_child(OUI.empty(OUI.ui2("c_mega"), I18n.t("chat.send_the_first_message")))
		return
	if more:
		var ld := CenterContainer.new()
		ld.custom_minimum_size.y = OUI.px(40)
		ld.add_child(OUI.spinner(22))
		list.add_child(ld)
	var by_mid: Dictionary = {}
	for m in msgs:
		by_mid[OUI.i(m.get("id"))] = m
	var dm := OUI.s(conv.get("kind")) == "dm"
	var u := _uid()
	for k in range(msgs.size() - 1, -1, -1):
		var m: Dictionary = msgs[k]
		var prev: Dictionary = msgs[k + 1] if k + 1 < msgs.size() else {}
		var snd := OUI.s(m.get("sender"))
		var show_name := not dm and snd != u and OUI.s(prev.get("sender")) != snd
		var rt: Dictionary = OUI.d(by_mid.get(OUI.i(m.get("reply_to")))) if m.get("reply_to") != null else {}
		var b := _bubble(m, snd == u, show_name, rt)
		list.add_child(b)
		msg_nodes[OUI.i(m.get("id"))] = b


func _uname(u: String) -> String:
	return OUI.s(OUI.d(OUI.d(by_id.get(u)).get("profiles")).get("username"))


func _bubble(m: Dictionary, mine: bool, show_name: bool, rt: Dictionary) -> Control:
	var outer := HBoxContainer.new()
	outer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN if mine else BoxContainer.ALIGNMENT_END
	var deleted := bool(m.get("deleted", false))
	var pc := PanelContainer.new()
	var st := OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.16) if mine else Color(20 / 255.0, 30 / 255.0, 70 / 255.0, 0.92), 16, Color(79 / 255.0, 227 / 255.0, 1, 0.35) if mine else OUI.LINE, 1)
	st.content_margin_left = OUI.px(12)
	st.content_margin_right = OUI.px(12)
	st.content_margin_top = OUI.px(6)
	st.content_margin_bottom = OUI.px(6)
	if mine:
		st.corner_radius_bottom_left = OUI.px(4)
	else:
		st.corner_radius_bottom_right = OUI.px(4)
	pc.add_theme_stylebox_override("panel", st)
	if deleted:
		pc.modulate.a = 0.5
	var v := OUI.vbox(2)
	v.layout_direction = I18n.LD
	var maxw := OUI.px(290)
	if show_name:
		v.add_child(OUI.lbl(_uname(OUI.s(m.get("sender"))) if OUI.s(m.get("sender")) != "" else "…", OUI.TS_TINY, OUI.CYAN, "bold"))
	if not rt.is_empty():
		var q := PanelContainer.new()
		var qs := OUI.sb(Color(0, 0, 0, 0.2), 6, Color(0, 0, 0, 0), 0)
		qs.border_width_right = OUI.px(3)
		qs.border_color = OUI.CYAN
		qs.content_margin_right = OUI.px(6)
		qs.content_margin_left = OUI.px(4)
		q.add_theme_stylebox_override("panel", qs)
		var qv := OUI.vbox(0)
		qv.add_child(OUI.lbl(_uname(OUI.s(rt.get("sender"))), 10, OUI.CYAN))
		qv.add_child(OUI.lbl(I18n.t("chat.message_deleted") if bool(rt.get("deleted", false)) else (OUI.s(rt.get("body")) if OUI.s(rt.get("body")) != "" else I18n.t("chat.photo")), OUI.TS_CAP, OUI.DIM))
		q.add_child(qv)
		v.add_child(q)
	var img_url := OUI.s(m.get("image_url"))
	if deleted:
		v.add_child(OUI.lbl(I18n.t("chat.this_message_was_deleted"), OUI.TS_SMALL, OUI.DIM))
	else:
		if img_url != "":
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(OUI.px(220), OUI.px(220))
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.texture = NetImg.get_tex(img_url)
			if tr.texture == null:
				NetImg.fetch(img_url, func(t: Texture2D) -> void:
					if is_instance_valid(tr):
						tr.texture = t)
			var clip := Panel.new()
			clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
			clip.add_theme_stylebox_override("panel", OUI.sb(Color.WHITE, 12))
			clip.custom_minimum_size = tr.custom_minimum_size
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			clip.add_child(tr)
			v.add_child(clip)
		var body_t := OUI.s(m.get("body"))
		if body_t != "":
			var bl := OUI.lbl(body_t, 14, OUI.TEXT, "body", I18n.AR, true, 0)
			var f := bl.get_theme_font("font")
			var w := f.get_string_size(body_t, HORIZONTAL_ALIGNMENT_LEFT, -1, bl.get_theme_font_size("font_size")).x + 6
			bl.custom_minimum_size.x = clampf(w, OUI.px(30), maxw)
			v.add_child(bl)
	v.add_child(OUI.lbl(OUI.time_ago(m.get("created_at")), 9, OUI.DIM2, "body", I18n.AL if mine else I18n.AR))
	pc.add_child(v)
	var lp := LongPress.new()
	lp.add_child(pc)
	lp.on_long = func() -> void:
		if not deleted:
			_menu(m)
	if img_url != "" and not deleted:
		lp.on_tap = func() -> void: _view(img_url)
	outer.add_child(lp)
	return outer


## press = tap, hold 0.45 s = long press (bubbles)
class LongPress extends Container:
	var on_tap: Callable
	var on_long: Callable
	var _t := -1.0
	var _fired := false
	var _start := Vector2.ZERO
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					fit_child_in_rect(c, Rect2(Vector2.ZERO, size))
	func _get_minimum_size() -> Vector2:
		var m := Vector2.ZERO
		for c in get_children():
			if c is Control:
				m = m.max((c as Control).get_combined_minimum_size())
		return m
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_t = 0.0
				_fired = false
				_start = ev.position
			else:
				if _t >= 0 and not _fired and on_tap.is_valid():
					on_tap.call()
				_t = -1.0
		elif ev is InputEventMouseMotion and _t >= 0 and ev.position.distance_to(_start) > 16:
			_t = -1.0
	func _process(dt: float) -> void:
		if _t >= 0 and not _fired:
			_t += dt
			if _t >= 0.45:
				_fired = true
				_t = -1.0
				OUI.buzz("light")
				if on_long.is_valid():
					on_long.call()


# ---------------------------------------------------------------- input
func _on_type(v: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if v != "" and now - last_typing > 2.5 and ch != null:
		last_typing = now
		ch.send_broadcast("typing", {"u": _uid()})


func _send(image_url: String) -> void:
	var body_t := txt.text.strip_edges() if is_instance_valid(txt) else ""
	var u := _uid()
	if u == "" or (body_t == "" and image_url == "") or sending:
		return
	sending = true
	var row := {"conversation_id": id, "sender": u, "body": body_t.substr(0, 2000) if body_t != "" else null, "image_url": image_url if image_url != "" else null, "reply_to": reply.get("id") if not reply.is_empty() else null}
	var r: Dictionary = await OUI.post("messages", row, true)
	sending = false
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		return
	if is_instance_valid(txt):
		txt.text = ""
	_set_reply({})
	OUI.buzz("light")
	var m: Variant = OUI.one(r)
	if m is Dictionary:
		_add_msg(m)


func _send_image() -> void:
	if sending:
		return
	sending = true
	OUI.pick_and_upload("chat", 1280, false, func(res: Dictionary) -> void:
		sending = false
		if not is_inside_tree():
			return
		if not res.get("ok", false):
			if res.get("unsupported", false):
				OUI.toast_err(I18n.t("chat.choosing_a_photo_isn_t"))
			elif not res.get("cancelled", false):
				OUI.toast_err(OUI.s(res.get("error")))
			return
		_send(OUI.s(res.get("url"))))


func _set_reply(m: Dictionary) -> void:
	reply = m
	OUI.clear(reply_bar)
	reply_bar.visible = not m.is_empty()
	if m.is_empty():
		return
	var h := OUI.hbox(OUI.S_S)
	var v := OUI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(OUI.lbl(I18n.t("chat.replying_to_x") % _uname(OUI.s(m.get("sender"))), OUI.TS_TINY, OUI.CYAN))
	v.add_child(OUI.lbl(OUI.s(m.get("body")) if OUI.s(m.get("body")) != "" else I18n.t("chat.photo"), OUI.TS_SMALL))
	h.add_child(v)
	h.add_child(OUI.pill("✕", func() -> void: _set_reply({}), OUI.DIM, 44, 44))
	reply_bar.add_child(OUI.margin(h, OUI.S_M, 0, OUI.S_M, 0))


# ---------------------------------------------------------------- overlays
func _close_overlay() -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


func _menu(m: Dictionary) -> void:
	_close_overlay()
	var v := OUI.vbox(0)
	var u := _uid()
	var snd := OUI.s(m.get("sender"))
	var item := func(label: String, cb: Callable, col: Color) -> void:
		var b := OUI.tap(OUI.margin(OUI.lbl(label, OUI.TS_BODY, col, "bold"), OUI.S_L, 0, OUI.S_L, 0), cb, false)
		b.custom_minimum_size.y = OUI.px(52)
		v.add_child(b)
	if _can_post():
		item.call(I18n.t("chat.reply"), func() -> void:
			_close_overlay()
			_set_reply(m)
			if is_instance_valid(txt):
				txt.grab_focus(), OUI.TEXT)
	if snd != "" and snd != u:
		item.call(I18n.t("chat.view_profile"), func() -> void:
			_close_overlay()
			Nav.go("public_profile", {"id": snd}), OUI.TEXT)
	if snd == u:
		item.call(I18n.t("chat.delete_message"), func() -> void:
			_close_overlay()
			var r: Dictionary = await OUI.patch("messages?id=eq.%d" % OUI.i(m.get("id")), {"deleted": true, "body": null})
			if not OUI.ok(r):
				OUI.toast_err(OUI.err(r)), OUI.RED)
	item.call(I18n.t("nav.cancel"), _close_overlay, OUI.DIM)
	overlay = OUI.modal(self, v, OUI.CYAN, _close_overlay)


func _view(url: String) -> void:
	_close_overlay()
	var veil := ColorRect.new()
	veil.color = Color(1 / 255.0, 3 / 255.0, 12 / 255.0, 0.92)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = OUI.px(12)
	tr.offset_right = -OUI.px(12)
	tr.offset_top = OUI.px(80)
	tr.offset_bottom = -OUI.px(80)
	tr.texture = NetImg.get_tex(url)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(tr)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_overlay())
	add_child(veil)
	OUI.fade_in(veil, 0.15)
	overlay = veil


func _open_info() -> void:
	var kind := OUI.s(conv.get("kind"))
	var my_role := OUI.s(_me_member().get("role"))
	var admin := my_role == "owner" or my_role == "admin"
	var u := _uid()
	var scr := OUI.scroll()
	var v := OUI.vbox(OUI.S_S)
	scr.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
	var refs := {}
	var act := func(target: String, a: String) -> void:
		var r: Dictionary = await Supa.call_rpc("manage_member", {"p_conv": id, "p_user": target, "p_action": a})
		if OUI.ok(r):
			OUI.buzz("light")
			await _load_meta()
			(refs["refill"] as Callable).call()
		else:
			OUI.toast_err(OUI.err(r))
	var mem_box := OUI.vbox(0)
	var refill := func() -> void:
		if not is_instance_valid(mem_box):
			return
		OUI.clear(mem_box)
		mem_box.add_child(OUI.section_title(I18n.t("chat.members_x") % OUI.fa(members.size()), OUI.S_S))
		for m in members:
			var mu := OUI.s(m.get("user_id"))
			var pp := OUI.d(m.get("profiles"))
			var role := OUI.s(m.get("role"))
			var h := OUI.hbox(OUI.S_S)
			h.custom_minimum_size.y = OUI.px(56)
			var av := NetImg.avatar(pp.get("avatar"), pp.get("avatar_url"), 40, OUI.GREEN if OUI.is_online(pp.get("online_at")) else OUI.LINE)
			h.add_child(OUI.tap(av, func() -> void:
				Nav.close_sheet()
				Nav.go("public_profile", {"id": mu})))
			var tv := OUI.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.alignment = BoxContainer.ALIGNMENT_CENTER
			tv.add_child(OUI.lbl(OUI.s(pp.get("username"), "…") + (I18n.t("ranks.you") if mu == u else ""), OUI.TS_BODY, OUI.TEXT, "bold"))
			if role != "member":
				var bh := OUI.hbox(0)
				bh.add_child(OUI.badge(I18n.t("chat.owner") if role == "owner" else I18n.t("chat.admin"), OUI.GOLD if role == "owner" else OUI.CYAN))
				bh.add_child(OUI.expand())
				tv.add_child(bh)
			h.add_child(tv)
			if my_role == "owner" and mu != u and kind != "club":
				h.add_child(OUI.pill(I18n.t("chat.demote") if role == "admin" else I18n.t("chat.make_admin"), func() -> void: act.call(mu, "demote" if role == "admin" else "promote"), OUI.CYAN, 44, 44))
			if admin and mu != u and role != "owner" and kind != "club":
				h.add_child(OUI.pill(I18n.t("tournaments.out"), func() -> void: act.call(mu, "remove"), OUI.RED, 44, 44))
			mem_box.add_child(h)
			mem_box.add_child(OUI.divider())
	if OUI.s(conv.get("about")) != "":
		v.add_child(OUI.lbl(OUI.s(conv.get("about")), OUI.TS_BODY, OUI.DIM, "body", I18n.AR, true, 0))
	if admin and kind != "club":
		var af := OUI.field(I18n.t("chat.add_member"), I18n.t("chat.username"), 30)
		var le: LineEdit = af.get_meta("input")
		v.add_child(af)
		var found := OUI.vbox(0)
		v.add_child(found)
		var st := Timer.new()
		st.one_shot = true
		st.wait_time = 0.3
		scr.add_child(st)
		st.timeout.connect(func() -> void:
			var term := OUI.ilike_term(le.text)
			OUI.clear(found)
			if term.length() < 2:
				return
			var r: Dictionary = await OUI.get_rows("profiles?select=id,username,avatar,avatar_url&username=ilike.*%s*&limit=10" % term.uri_encode())
			if not is_instance_valid(found):
				return
			OUI.clear(found)
			for f in OUI.rows(r):
				var fid := OUI.s(f.get("id"))
				if by_id.has(fid):
					continue
				var h := OUI.hbox(OUI.S_S)
				h.custom_minimum_size.y = OUI.px(56)
				h.add_child(NetImg.avatar(f.get("avatar"), f.get("avatar_url"), 36))
				h.add_child(OUI.flbl(OUI.s(f.get("username")), OUI.TS_BODY))
				h.add_child(OUI.pill(I18n.t("chat.add"), func() -> void:
					act.call(fid, "add")
					le.text = ""
					OUI.clear(found), OUI.GREEN, 60, 44))
				found.add_child(h))
		le.text_changed.connect(func(_t: String) -> void: st.start())
	refs["refill"] = refill
	v.add_child(mem_box)
	refill.call()
	if kind != "club" and kind != "dm":
		v.add_child(OUI.spacer(OUI.S_L))
		v.add_child(OUI.btn(I18n.t("chat.leave_conversation"), func() -> void:
			var r: Dictionary = await Supa.call_rpc("leave_conversation", {"p_conv": id})
			if OUI.ok(r):
				OUI.toast(I18n.t("chat.you_left"), "ok")
				Nav.close_sheet()
				Nav.back()
			else:
				OUI.toast_err(OUI.err(r)), "red", true))
	var t := OUI.s(conv.get("title"))
	OUI.open_sheet(t if t != "" else KIND_LABEL.get(kind, ""), "%s INFO" % KIND_LABEL.get(kind, ""), scr, OUI.CYAN, 0.85)
