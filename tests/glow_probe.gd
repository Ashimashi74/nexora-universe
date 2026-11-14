extends Node2D
## Compatibility-renderer probe: does WorldEnvironment 2D glow / hdr_2d bloom HDR colours? Saves shots/glow_probe.png
func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	for i in 7: env.set_glow_level(i, 1.0 if i < 5 else 0.0)
	we.environment = env
	add_child(we)
	print("hdr_2d=", get_viewport().use_hdr_2d, " method=", RenderingServer.get_current_rendering_method())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("NX_SHOTS") + "/glow_probe.png")
	get_tree().quit()
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1080, 1920), Color(0.02, 0.03, 0.08))
	draw_rect(Rect2(100, 200, 300, 40), Color(0.2, 0.8, 1.0))          # LDR
	draw_rect(Rect2(600, 200, 300, 40), Color(0.6, 2.4, 3.0))          # HDR
	draw_circle(Vector2(250, 600), 60, Color(1, 1, 1))
	draw_circle(Vector2(750, 600), 60, Color(3, 3, 3))
