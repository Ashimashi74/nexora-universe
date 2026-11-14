extends SceneTree
## Headless smoke test for the Voice autoload (owner: VOICE worker).
## Run: godot --headless -s res://tests/voice_smoke.gd
## Off Android the plugin is absent: supported() must be false and join() must end in an error state
## with the Persian reason, without touching the network.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node = root.get_node_or_null("/root/Voice")
	var ok := true
	if v == null:
		print("FAIL: Voice autoload missing"); quit(1); return
	var states: Array = []
	v.state_changed.connect(func(s: Dictionary) -> void: states.append(s.duplicate(true)))
	ok = ok and _expect(v.supported() == false, "supported() false off-Android")
	ok = ok and _expect(v.support_reason() == "چت صوتی فقط روی اندروید", "reason text")
	v.join("room-123")
	ok = ok and _expect(str(v.state.status) == "error", "join -> error state")
	ok = ok and _expect(str(v.state.error) == "چت صوتی فقط روی اندروید", "join error text")
	v.set_mic(true)
	ok = ok and _expect(v.state.mic == false, "set_mic no-op")
	v.set_speaker(false)
	ok = ok and _expect(v.state.speaker == false, "set_speaker stored")
	v.leave()
	ok = ok and _expect(str(v.state.status) == "off" and str(v.state.error) == "", "leave -> off")
	ok = ok and _expect(states.size() >= 3, "state_changed emitted (%d)" % states.size())
	ok = ok and _expect(v._fa_or("boom", "x") == "x" and v._fa_or("خطا", "x") == "خطا", "_fa_or")
	print("VOICE SMOKE: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(c: bool, what: String) -> bool:
	print(("  ok   " if c else "  FAIL ") + what)
	return c
