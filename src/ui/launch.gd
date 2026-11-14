class_name Launch
extends RefCounted
## Game modes + MatchCfg builder (port of src/screens/Setup.tsx MODES / buildLaunch / pickOpp).
## Launch dict passed to Nav.go("match", launch):
##   {cfg: MatchCfg, teams: [teamDict, teamDict], names: [String, String], mode: String, stage: int}
## MatchCfg keys (SPEC): field, ball, forms[2], ai, ai_lvl, limit, match_time, turn_time, vip[2], first,
##   stats[2] ({power, accuracy}), teams[2] (team ids).
## Result screen (GAME) can rebuild with Launch.build(mode, Store.p, {lvl, rule, tt, opp, stage}).

static func modes() -> Array:
	return [
		{"k": "quick", "img": "@ic_quick", "name": I18n.t("kb.quick_play"), "en": "QUICK MATCH", "desc": I18n.t("launch.an_instant_match_against_the"), "reward": I18n.t("launch.coins_xp_and_trophies"), "color": Color("#4fe3ff"), "grad": "primary"},
		{"k": "cup", "img": "@trophy_worldcup", "name": I18n.t("home.nexora_cup"), "en": "NEXORA CUP", "desc": I18n.t("launch.three_opponents_in_a_row"), "reward": I18n.t("launch.2_rewards_20_champion_gems"), "color": NX.GOLD, "grad": "gold"},
		{"k": "galaxy", "img": "@planet", "name": I18n.t("launch.galactic_challenge"), "en": "GALAXY CHALLENGE", "desc": I18n.t("launch.two_minutes_vs_the_legendary"), "reward": I18n.t("launch.3_rewards"), "color": NX.VIOLET, "grad": "violet"},
		{"k": "local", "img": "@ic_local", "name": I18n.t("launch.two_players"), "en": "LOCAL 2 PLAYER", "desc": I18n.t("launch.play_with_a_friend_on"), "reward": I18n.t("launch.just_for_glory"), "color": Color("#3dffa8"), "grad": "green"},
		{"k": "train", "img": "portal_brain", "name": I18n.t("launch.practice"), "en": "TRAINING", "desc": I18n.t("launch.no_timer_easy_bot_to"), "reward": I18n.t("launch.low_xp_no_trophies"), "color": NX.SKY, "grad": "primary"},
	]

static func mode(k: String) -> Dictionary:
	for m in modes():
		if m["k"] == k:
			return m
	return modes()[0]

static func pool() -> Array:
	return UD.teams().filter(func(t): return t["cat"] in ["club", "nat", "elite"])

static func pick_opp() -> Dictionary:
	var p := pool()
	return p[randi() % p.size()]

static func boosted(t: Dictionary) -> bool:
	return t["cat"] == "vip" or t["cat"] == "leg"

## opt: {lvl: 0..2, rule: "g3"|"g5"|"t3", tt: int, opp: teamDict, stage: int}
static func build(mode_k: String, p: Dictionary, opt: Dictionary) -> Dictionary:
	if UD.has("Data", "build_launch"):
		var r = UD.node("Data").build_launch(mode_k, p, opt)
		if r is Dictionary and r.has("cfg"):
			return r
	var me := UD.team_by_id(str(p.get("team", "club0")))
	var opp: Dictionary = opt.get("opp", pick_opp())
	var opp_form := randi() % UD.forms().size()
	var ai := mode_k != "local"
	var lvl := int(opt.get("lvl", 1))
	var rule := str(opt.get("rule", "g3"))
	var limit := 5 if rule == "g5" else 3
	var match_time := 180 if rule == "t3" else 0
	var tt := int(opt.get("tt", 15))
	var stage := int(opt.get("stage", 0))
	if mode_k == "cup":
		lvl = mini(2, stage)
		limit = 3
		match_time = 0
	if mode_k == "galaxy":
		lvl = 2
		match_time = 120
		limit = 99
	if mode_k == "train":
		lvl = 0
		tt = 0
	var form := int(p.get("form", 0))
	var cfg := {
		"field": int(p.get("field", 0)), "ball": int(p.get("ball", 0)),
		"forms": [form, opp_form if ai else form],
		"ai": ai, "ai_lvl": lvl, "limit": limit, "match_time": match_time, "turn_time": tt,
		"vip": [boosted(me), boosted(opp)], "first": 0,
		"stats": [UD.disc_stats(me["id"]), UD.disc_stats(opp["id"])],
		"teams": [me["id"], opp["id"]],
	}
	return {"cfg": cfg, "teams": [me, opp], "names": [str(p.get("name", "Pilot")), opp["name"] if ai else I18n.t("data.player_2")], "mode": mode_k, "stage": stage}
