extends Control
## Settings sheet (RN Settings.tsx): account entry, sound / music / haptics / oracle toggles,
## volume, graphics quality, default AI, replay intro, reset progress (tap twice), version.

var sure := false
var reset_btn: NxButton

func setup(_params: Dictionary) -> void:
	pass

func sheet_opts() -> Dictionary:
	return {"title": I18n.t("kb.settings"), "en": "SYSTEMS", "accent": NX.SKY, "height": 0.78}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sl := Kit.scroll_list(22)
	var sc: ScrollContainer = sl[0]
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var v: VBoxContainer = sl[1]
	var p := UD.p()
	var i := 0
	# account entry (OUI owns the account screen)
	var op := UD.online_profile()
	var acc_sub := I18n.t("settings.signed_in_x") % str(op.get("username", "")) if not op.is_empty() else I18n.t("settings.sign_in_register_or_play")
	v.add_child(_pad(Kit.enter(Kit.list_row(UD.ui2("c_profile"), I18n.t("settings.account"), acc_sub, Kit.img(UD.menu("g_chevrons"), 60), func(): Nav.go("account")), i)))
	var rows := [["c_mega", I18n.t("settings.sounds"), I18n.t("settings.shots_goals_crowd"), "sound"], ["c_bell", I18n.t("kb.music"), I18n.t("settings.menu_music"), "music"], ["x_gear", I18n.t("kb.vibration"), I18n.t("settings.haptic_feedback_on_hits"), "haptics"], ["oracle", I18n.t("settings.show_oracle"), I18n.t("settings.floating_assistant_match_coach_and"), "oracle"]]
	for r in rows:
		i += 1
		var key: String = r[3]
		var icon: Texture2D = UD.tex("res://assets/g/oracle/oracle_idle.webp") if r[0] == "oracle" else UD.ui2(r[0])
		if icon == null:
			icon = UD.ui2("c_star")
		var tg := Kit.toggle(bool(p.get(key, true)), func(on): UD.set_p({key: on}); UD.apply_prefs())
		v.add_child(_pad(Kit.enter(Kit.list_row(icon, r[1], r[2], tg), i)))
	# language (fa / en): rebuilds the whole UI
	v.add_child(_pad(Kit.enter(_seg_panel(I18n.t("settings.language"), I18n.t("settings.language_sub"), [I18n.t("settings.lang_fa"), I18n.t("settings.lang_en")], 1 if I18n.is_en() else 0, func(k):
		Nav.close_sheet(true)
		I18n.set_lang("en" if k == 1 else "fa"), NX.GREEN), 5)))
	# volume
	var vols := [0.25, 0.5, 0.75, 1.0]
	var vi := vols.find(snappedf(float(p.get("volume", 1.0)), 0.25))
	v.add_child(_pad(Kit.enter(_seg_panel(I18n.t("settings.volume"), "", [I18n.t("settings.25"), I18n.t("settings.50"), I18n.t("settings.75"), I18n.t("settings.100")], 3 if vi < 0 else vi, func(k): UD.set_p({"volume": vols[k]}); UD.apply_prefs(), NX.CYAN), 5)))
	v.add_child(_pad(Kit.enter(_seg_panel(I18n.t("settings.graphics_quality"), I18n.t("settings.choose_smooth_on_low_end"), [I18n.t("settings.high"), I18n.t("settings.smooth")], 1 if str(p.get("quality", "high")) == "low" else 0, func(k): UD.set_p({"quality": "low" if k == 1 else "high"}), NX.VIOLET), 6)))
	v.add_child(_pad(Kit.enter(_seg_panel(I18n.t("settings.default_bot_difficulty"), "", [I18n.t("settings.easy"), I18n.t("settings.normal"), I18n.t("settings.hard")], int(p.get("aiLvl", 1)), func(k): UD.set_p({"aiLvl": k}), NX.CYAN), 7)))
	v.add_child(Kit.gap(8))
	v.add_child(_pad(Kit.button_small(I18n.t("settings.replay_intro"), func():
		Nav.close_sheet()
		UD.menu_music(false)
		Nav.go("intro"), "dark")))
	reset_btn = Kit.button_small(I18n.t("settings.reset_progress"), _reset, "danger")
	v.add_child(_pad(reset_btn))
	var ver := Kit.caps("NEXORA · Finger Soccer · v5.0", 26, NX.DIM2, 4)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(Kit.gap(30))
	v.add_child(ver)
	v.add_child(Kit.gap(100))

func _pad(c: Control) -> Control:
	return Kit.margin(c, NX.PAD, 0, NX.PAD, 0)

func _seg_panel(title: String, sub: String, items: Array, idx: int, cb: Callable, acc: Color) -> Control:
	var pn := Kit.glass()
	var v := Kit.vbox(12)
	v.add_child(Kit.label(title, 39, NX.TEXT, true))
	if sub != "":
		v.add_child(Kit.label(sub, 29, NX.DIM))
	v.add_child(Kit.tabs(items, cb, idx, acc))
	pn.add_child(v)
	return pn

func _reset() -> void:
	if not sure:
		sure = true
		reset_btn.set_text(I18n.t("account.are_you_sure_tap_again"))
		return
	UD.reset_store()
	sure = false
	reset_btn.set_text(I18n.t("settings.reset_progress"))
	Nav.toast(I18n.t("settings.progress_reset"), "ok")
	Nav.refresh_chrome()
