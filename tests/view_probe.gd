extends SceneTree
## Rendered probe of MatchView (formation layout, turn ring, aim arrow near a sideline, sharp corners).
## DISPLAY=:99 godot --rendering-driver opengl3 --resolution 1080x1920 -s res://tests/view_probe.gd -- form=0 out=/abs/dir
var e: NxEngine
var v: MatchView
var out := "/tmp"
var form := 0
var frame := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("form="): form = int(a.substr(5))
		if a.begins_with("out="): out = a.substr(4)
	e = NxEngine.new({"field": 0, "ball": 3, "forms": [form, (form + 4) % 9], "ai": false, "turn_time": 0, "seed": 7, "teams": ["club0", "nat3"]})
	v = MatchView.new()
	v.setup(e, {"quality": "high"})
	root.add_child(v)
	v.fit(Vector2(1080, 1920), 200, 60)

func _process(_d: float) -> bool:
	frame += 1
	e.update(1.0 / 60.0)
	if frame == 10:
		# grab the bottom-team disc closest to the right sideline and pull toward the pitch centre -> arrow points to the wall
		var best: NxBody = null
		for b: NxBody in e.bodies:
			if b.team == 0 and b != e.ball and (best == null or b.x > best.x): best = b
		e.pick(best.x, best.y)
		e.move(best.x - 190, best.y + 120)
	if frame == 30:
		var img := root.get_texture().get_image()
		img.save_png("%s/view_form%d.png" % [out, form])
		print("saved form ", form)
		return true
	return false
