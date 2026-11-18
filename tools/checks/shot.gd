extends SceneTree
# In-game screenshots from fixed cameras (renders: a window opens, only when the owner allows).
# Starts a Classic match on MAPI with the bots lifted out and the clock frozen, then for each
# camera in CAMS ("x,y,z>lx,ly,lz;..."; the camera at x,y,z looking at lx,ly,lz) waits for the
# picture to settle and saves OUT/<n>.png. HUD hidden. Settings untouched (never saved).
#   MAPI=2 CAMS="0,8,60>0,15,-30" OUT=/some/dir timeout 120 godot -s res://tools/checks/shot.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 3, 1, int(OS.get_environment("MAPI")))
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"freeze")
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 3000.0
	root.add_child(cam)
	var out := OS.get_environment("OUT")
	var i := 0
	for spec: String in OS.get_environment("CAMS").split(";", false):
		var parts := spec.split(">")
		cam.global_position = _v(parts[0])
		cam.look_at(_v(parts[1]))
		cam.make_current()
		for f: int in 40: await process_frame # let shadows, fog and fades settle
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%d.png" % [out, i])
		i += 1
	print("saved %d shots to %s" % [i, out])
	quit()
