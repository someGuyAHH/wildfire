extends SceneTree
# The Freeze frost (assets/gdshaders/frost_vignette.gdshader) over a live Inferno view at a few
# strengths, saved as OUT/frost_<strength>.png. Renders: a window opens (owner's OK), fullscreen.
#   OUT=/some/dir timeout 120 godot --fixed-fps 120 -s res://tools/checks/frost_shot.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	for f: int in 30: await process_frame
	_main.call(&"_start_match", 4, 5, 1, 3)
	for f: int in 240: await process_frame
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/gdshaders/frost_vignette.gdshader")
	mat.set_shader_parameter(&"frost", load("res://assets/images/vfx/frost.png"))
	rect.material = mat
	layer.add_child(rect)
	for s: float in [0.3, 0.6, 1.0]:
		mat.set_shader_parameter(&"strength", s)
		for f: int in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/frost_%.1f.png" % [OS.get_environment("OUT"), s])
		print("saved ", s)
	quit()
