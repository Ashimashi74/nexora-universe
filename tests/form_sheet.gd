extends SceneTree
## v3: renders the kickoff layout of formation <form> for BOTH sides (team 0 bottom, team 1 = 180° rotation on top),
## no aim. DISPLAY=:99 godot --rendering-driver opengl3 --resolution 1080x1920 -s res://tests/form_sheet.gd -- form=0 out=/dir
var e: NxEngine
var v: MatchView
var out := "/tmp"
var form := 0
var field := 0
var frame := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("form="): form = int(a.substr(5))
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("field="): field = int(a.substr(6))
	e = NxEngine.new({"field": field, "ball": 3, "forms": [form, form], "ai": false, "turn_time": 0, "seed": 7, "teams": ["club0", "nat3"]})
	v = MatchView.new()
	v.setup(e, {"quality": "high"})
	root.add_child(v)
	v.fit(Vector2(1080, 1920), 60, 60)
	# sanity: every disc inside the play area and on its own half, mirrored 180°
	var bad := 0
	for b: NxBody in e.bodies:
		if b == e.ball: continue
		if b.x - b.r < e.Fl or b.x + b.r > e.Fr or b.y - b.r < e.Ft or b.y + b.r > e.Fb: bad += 1
		if (b.team == 0 and b.y < e.CY) or (b.team == 1 and b.y > e.CY): bad += 1
	for i in 5:
		var a: NxBody = e.bodies[i]
		var m: NxBody = e.bodies[5 + i]
		if absf((a.x + m.x) - (e.Fl + e.Fr)) > 0.01 or absf((a.y + m.y) - (e.Ft + e.Fb)) > 0.01: bad += 1
	print("FORM ", form, " ", e.D.FORMS[form][1], " checks_failed=", bad)

func _process(_d: float) -> bool:
	frame += 1
	if frame == 8:
		root.get_texture().get_image().save_png("%s/form_%d%s.png" % [out, form, ("" if field == 0 else "_f%d" % field)])
		return true
	return false
