extends SceneTree
# Bakes the mode cards' pictures (assets/images/ui/modes/<mode>.png, portrait): a few characters
# staged mid-run on a map, Torches lit, frozen in place. Renders, so a window opens (owner's OK).
#   [ONLY=classic] [OUT=res://assets/images/ui/modes] timeout 600 godot --fixed-fps 120 -s res://tools/mapgen/mode_art.gd
# Each shot: a map, a camera (eye position, a point it looks at, fov), and the cast, placed in the
# camera's frame (x right, z forward, metres; snapped to the ground below), each looking at a point
# in the same frame, holding a clip at a time; torch = on fire, you = the player (teal accents).

const SIZE := Vector2i(720, 1080)
const MAP_SIZE := Vector2i(640, 360)
## The map picker's shots: map index (Main's list, the Gym first) -> name, eye, look-at point.
const MAP_SHOTS := {
	"gym": {"map": 0, "eye": Vector3(26, 12, 38), "at": Vector3(0, 0, 0)},
	"overworld": {"map": 1, "eye": Vector3(0, 3, 40), "at": Vector3(60, 2, -40)},
	"jungle": {"map": 2, "eye": Vector3(0, 8, 60), "at": Vector3(0, 15, -30)},
	"inferno": {"map": 3, "eye": Vector3(7, 40, 99), "at": Vector3(0, -14, 180)},
}
const _YOU_TINT := Color(0.25, 0.82, 0.79)
const SHOTS := {
	"classic": {"mode": 0, "map": 1, "eye": Vector3(-6, 0, 30), "at": Vector3(30, 6, -40), "fov": 40.0, "cast": [
		{"at": Vector3(-0.3, 0, 4.8), "look": Vector3(-6, 0, -2), "clip": "Sprint", "t": 0.18, "you": true},
		{"at": Vector3(0.9, 0, 8.0), "look": Vector3(-2, 0, 3), "clip": "Sprint", "t": 0.52, "torch": true},
	]},
	"spread": {"mode": 1, "map": 2, "eye": Vector3(-3, 0, 62), "at": Vector3(0, 12, -30), "fov": 42.0, "cast": [
		{"at": Vector3(-0.6, 0, 5.0), "look": Vector3(-5, 0, -1), "clip": "Sprint", "t": 0.1, "you": true},
		{"at": Vector3(1.2, 0, 8.0), "look": Vector3(-2, 0, 3), "clip": "Sprint", "t": 0.45, "torch": true},
		{"at": Vector3(-2.0, 0, 10.5), "look": Vector3(-3, 0, 4), "clip": "Sprint", "t": 0.3, "torch": true},
		{"at": Vector3(2.6, 0, 12.5), "look": Vector3(6, 0, 7), "clip": "Sprint", "t": 0.7},
	]},
	"hunted": {"mode": 2, "map": 3, "eye": Vector3(-4, 0, -40), "at": Vector3(20, 4, -90), "fov": 46.0, "cast": [
		{"at": Vector3(-0.4, 0, 4.6), "look": Vector3(-3, 0, -2), "clip": "Sprint", "t": 0.3, "you": true},
		{"at": Vector3(-1.8, 0, 10.0), "look": Vector3(-1, 0, 3), "clip": "Sprint", "t": 0.05, "torch": true},
		{"at": Vector3(1.6, 0, 11.0), "look": Vector3(0, 0, 3), "clip": "Sprint", "t": 0.6, "torch": true},
		{"at": Vector3(-0.2, 0, 14.0), "look": Vector3(-1, 0, 6), "clip": "Sprint", "t": 0.35, "torch": true},
		{"at": Vector3(3.4, 0, 15.5), "look": Vector3(1, 0, 7), "clip": "Sprint", "t": 0.8, "torch": true},
	]},
	"hot_potato": {"mode": 3, "map": 1, "eye": Vector3(-60, 0, -30), "at": Vector3(0, 7, -70), "fov": 40.0, "cast": [
		{"at": Vector3(0.6, 0, 5.2), "look": Vector3(-4, 0, 3), "clip": "Sprint", "t": 0.2, "you": true},
		{"at": Vector3(-1.0, 0, 7.0), "look": Vector3(0.6, 0, 5.2), "clip": "Sprint", "t": 0.45, "torch": true},
		{"at": Vector3(2.4, 0, 10.5), "look": Vector3(7, 0, 12), "clip": "Sprint", "t": 0.25},
	]},
}

var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	# fullscreen: a small window only gets the corner of the view (owner, 2026-11-20); each picture
	# is the middle of the full frame, cropped to its shape and scaled down (_grab)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "res://assets/images/ui"
	for sub: String in ["modes", "maps"]: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "/" + sub))
	var only := OS.get_environment("ONLY")
	for f: int in 10: await process_frame
	for key: String in SHOTS:
		if only != "" and key not in only.split(","): continue
		await _shoot(key, SHOTS[key], out + "/modes")
	if only == "" or "maps" in only.split(","):
		for key: String in MAP_SHOTS: await _shoot_map(key, MAP_SHOTS[key], out + "/maps")
	quit()


func _shoot_map(key: String, s: Dictionary, out: String) -> void:
	_main.call(&"_start_match", 0, 1, 1, int(s["map"]))
	for f: int in 10: await process_frame
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"freeze")
	var me := _main.get(&"_player") as Character
	me.visible = false
	me.process_mode = Node.PROCESS_MODE_DISABLED # (or its camera takes over again)
	for n: Node in root.find_children("*", "Label3D", true, false): (n as Label3D).visible = false
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.global_position = s["eye"]
	cam.look_at(s["at"])
	cam.make_current()
	for f: int in 45: await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, key]
	_grab(MAP_SIZE).save_png(path)
	print("saved ", path)
	cam.queue_free()
	_main.call(&"toggle_cheat", &"freeze")
	_main.call(&"toggle_cheat", &"alone")


func _ground(x: float, z: float) -> float:
	var space := (_main as Node3D).get_world_3d().direct_space_state if _main is Node3D else root.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -100.0, z), 1))
	return (hit.position as Vector3).y if hit else 0.0


func _shoot(key: String, s: Dictionary, out: String) -> void:
	var cast: Array = s["cast"]
	_main.call(&"_start_match", int(s["mode"]), cast.size(), 1, int(s["map"]))
	for f: int in 10: await process_frame # (no need to sit out the countdown: everyone's frozen and placed by hand)
	_main.call(&"toggle_cheat", &"freeze")
	var tm: Node = _main.get(&"tag_manager")
	var me := _main.get(&"_player") as Character
	var bots: Array[Character] = []
	for c: Character in tm.call(&"get_participants"):
		if c != me: bots.append(c)
		if tm.call(&"is_torch", c): tm.call(&"_remove_torch", c)
	me.visible = false # (first person: your own body doesn't draw) a bot in teal plays you
	me.process_mode = Node.PROCESS_MODE_DISABLED
	# the camera's frame, level, eye 1.4 m off the ground
	var eye: Vector3 = s["eye"]
	eye.y = _ground(eye.x, eye.z) + 1.4
	var at: Vector3 = s["at"]
	var flat := Vector3(at.x - eye.x, 0.0, at.z - eye.z).normalized()
	var right := flat.cross(Vector3.UP)
	var frame := func(p: Vector3) -> Vector3:
		var w := eye + right * p.x + flat * p.z
		return Vector3(w.x, _ground(w.x, w.z), w.z)
	var bi := 0
	for spec: Dictionary in cast:
		var c: Character = bots[bi]
		bi += 1
		var pos: Vector3 = frame.call(spec["at"])
		c.global_position = pos
		c.velocity = Vector3.ZERO
		var look: Vector3 = frame.call(spec["look"])
		c.visual.look_at(Vector3(look.x, pos.y + c.visual.global_position.y - c.global_position.y, look.z), Vector3.UP)
		if spec.get("torch", false): tm.call(&"_add_torch", c)
		elif spec.get("you", false): c.set_tint(_YOU_TINT)
		c.process_mode = Node.PROCESS_MODE_DISABLED
		var body := c.body
		body.process_mode = Node.PROCESS_MODE_ALWAYS # the skeleton keeps the back unit's fire on the back
		body.set_process(false) # (but the body doesn't pick its own clip)
		var anim := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		anim.play(StringName(spec["clip"]), 0.0)
		anim.seek(float(spec["t"]), true)
		anim.pause()
		for fx: Node in c.find_children("*", "Node3D", true, false):
			if fx is TorchFX: fx.process_mode = Node.PROCESS_MODE_ALWAYS # it moves the fire to the back unit
		for fx: Node in c.find_children("*", "GPUParticles3D", true, false): fx.process_mode = Node.PROCESS_MODE_ALWAYS
		for fx: Node in c.find_children("*", "CPUParticles3D", true, false): fx.process_mode = Node.PROCESS_MODE_ALWAYS
	for b: Character in bots.slice(bi): b.visible = false # the cast only
	for n: Node in root.find_children("*", "Node3D", true, false):
		if n is TagFlash: (n as Node3D).visible = false # catching fire's ring: not part of the picture
	for n: Node in root.find_children("*", "Label3D", true, false): (n as Label3D).visible = false
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = float(s["fov"])
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(at)
	cam.make_current()
	for f: int in 45: await process_frame # flames grow, shadows settle
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, key]
	_grab(SIZE).save_png(path)
	print("saved ", path)
	cam.queue_free()
	_main.call(&"toggle_cheat", &"freeze") # (the next shot's match replaces this one)


# the frame's middle at the shape of `out`, scaled to it (the camera's fov is vertical, so a
# narrower crop keeps the framing the shot was set up for)
func _grab(out: Vector2i) -> Image:
	var img := root.get_texture().get_image()
	var full := Vector2(img.get_size())
	var want := float(out.x) / float(out.y)
	var crop := Vector2(minf(full.x, full.y * want), minf(full.y, full.x / want))
	var at := ((full - crop) * 0.5).floor()
	var cut := img.get_region(Rect2i(Vector2i(at), Vector2i(crop)))
	cut.resize(out.x, out.y, Image.INTERPOLATE_LANCZOS)
	return cut

