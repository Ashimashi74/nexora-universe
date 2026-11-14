extends Node
## Rendered probe of the formation picker sheet content (runs with the real autoloads).
## DISPLAY=:99 NX_SHOTS=/abs/dir godot --rendering-driver opengl3 --resolution 1080x1920 --path . res://tests/form_probe.tscn
var frame := 0
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#040510"); bg.size = Vector2(1080, 1920)
	add_child(bg)
	var p := FormationPicker.new()
	p.position = Vector2(40, 60); p.size = Vector2(1000, 1800)
	add_child(p)
func _process(_d: float) -> void:
	frame += 1
	if frame == 20:
		var out := OS.get_environment("NX_SHOTS")
		if out != "": get_viewport().get_texture().get_image().save_png(out + "/form_picker.png")
		print("saved")
		get_tree().quit()
