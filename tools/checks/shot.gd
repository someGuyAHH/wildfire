extends SceneTree
# In-game screenshots from fixed cameras (renders: a window opens, only when the owner allows).
# Starts a Classic match on MAPI with the bots lifted out and the clock frozen, then for each
# camera in CAMS ("x,y,z>lx,ly,lz;..."; the camera at x,y,z looking at lx,ly,lz) waits for the
# picture to settle and saves OUT/<n>.png. HUD hidden. Settings untouched (never saved).
#   MAPI=2 CAMS="0,8,60>0,15,-30" OUT=/some/dir [HIDE=Shadow] timeout 120 godot -s res://tools/checks/shot.gd
# LIVE=1: the bots stay in and play (no cheats); a camera "@i" sits 3.5 m to the side of bot i
# (i = -1: you), at chest height, looking at it; GAP seconds (default 1.5) between shots.
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
	var live := OS.get_environment("LIVE") == "1"
	if not live:
		_main.call(&"toggle_cheat", &"alone")
		_main.call(&"toggle_cheat", &"freeze")
	else:
		await create_timer(6.0).timeout # through the countdown, everyone off and running
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	var hide := OS.get_environment("HIDE") # nodes whose name ends with this are hidden (compare with / without)
	if hide != "":
		for n: Node in root.find_children("*" + hide, "Node3D", true, false): (n as Node3D).visible = false
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 3000.0
	root.add_child(cam)
	var out := OS.get_environment("OUT")
	var i := 0
	for spec: String in OS.get_environment("CAMS").split(";", false):
		if spec.begins_with("@"):
			var who := _who(int(spec.substr(1)))
			var side := who.visual.global_basis.x if who.visual else Vector3.RIGHT
			cam.global_position = who.global_position + side * 3.5 + Vector3.UP * 1.3
			cam.look_at(who.global_position + Vector3.UP * 1.0)
			cam.fov = 45.0
		else:
			var parts := spec.split(">")
			cam.global_position = _v(parts[0])
			cam.look_at(_v(parts[1]))
			cam.fov = 80.0
		cam.make_current()
		for f: int in (2 if live else 40): await process_frame # let shadows, fog and fades settle (live: they have; the bot would run out of frame)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%d.png" % [out, i])
		i += 1
		if live: await create_timer(float(OS.get_environment("GAP")) if OS.get_environment("GAP") != "" else 1.5).timeout
	print("saved %d shots to %s" % [i, out])
	quit()


## Bot i of the match (-1: the player).
func _who(i: int) -> Character:
	var player := _main.get(&"_player") as Character
	if i < 0: return player
	var tm: Node = _main.get(&"tag_manager")
	var others: Array = tm.call(&"get_participants").filter(func(c: Character) -> bool: return c != player)
	return others[i % others.size()]
