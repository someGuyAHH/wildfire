extends SceneTree
# Renders for the game icon (composited by tools/texgen/icon.py): a chase staged close up (you in
# teal, the Torch on fire lunging after you) and square plates of the maps behind it. Renders, so a
# window opens (owner's OK), fullscreen; each picture is the square middle of the frame.
#   PASS=cast|plates [ONLY=key,...] OUT=/some/dir timeout 600 godot --fixed-fps 120 -s res://tools/mapgen/icon_art.gd
# cast: per shot, <key>_beauty.png (on its map, as the game draws it), and <key>_black.png /
#   <key>_white.png: the cast alone over a black and a white backdrop (the map's geometry hidden,
#   its lights and sky lighting kept, particles held still), for a cutout: the backdrop shows
#   through by (white - black), and black is the cast's own (premultiplied) light.
# plates: <key>.png per map view, nobody in it.

const _YOU_TINT := Color(0.25, 0.82, 0.79)
## Cast shots: map index, the camera's eye (y: metres over the ground), the point it heads toward
## (sets the frame: x right, z forward, metres, snapped to the ground), what it looks at in that
## frame (y over the ground), fov, the cast (at / look in the frame, clip and time held).
const CAST := {
	"chase": {"map": 0, "eye": Vector3(4, 0.4, 12), "at": Vector3(0, 0, 0), "look": Vector3(0.2, 1.2, 4.4), "fov": 36.0, "cast": [
		{"at": Vector3(-0.5, 0, 3.5), "look": Vector3(-3.0, 0, 0.2), "clip": "Sprint", "t": 0.18, "you": true},
		{"at": Vector3(0.8, 0, 5.1), "look": Vector3(-0.5, 0, 3.5), "clip": "Dash", "t": 0.12, "torch": true},
	]},
	"chase2": {"map": 0, "eye": Vector3(4, 0.4, 12), "at": Vector3(0, 0, 0), "look": Vector3(0.2, 1.15, 4.4), "fov": 44.0, "cast": [
		{"at": Vector3(-0.45, 0, 3.6), "look": Vector3(-2.2, 0, -1.2), "clip": "Sprint", "t": 0.18, "you": true},
		{"at": Vector3(0.7, 0, 5.0), "look": Vector3(-0.45, 0, 3.6), "clip": "Dash", "t": 0.25, "torch": true},
	]},
	"chase3": {"map": 0, "eye": Vector3(4, 0.4, 12), "at": Vector3(0, 0, 0), "look": Vector3(0.2, 1.15, 4.4), "fov": 44.0, "cast": [
		{"at": Vector3(-0.45, 0, 3.6), "look": Vector3(-2.2, 0, -1.2), "clip": "Sprint", "t": 0.55, "you": true},
		{"at": Vector3(0.7, 0, 5.0), "look": Vector3(-0.45, 0, 3.6), "clip": "Sprint", "t": 0.3, "torch": true},
	]},
}
const PLATES := {
	"overworld_a": {"map": 1, "eye": Vector3(0, 3, 40), "at": Vector3(60, 8, -40), "fov": 60.0},
	"overworld_b": {"map": 1, "eye": Vector3(-60, 4, -30), "at": Vector3(0, 12, -70), "fov": 60.0},
	"jungle_a": {"map": 2, "eye": Vector3(0, 8, 60), "at": Vector3(0, 18, -30), "fov": 60.0},
	"jungle_b": {"map": 2, "eye": Vector3(-3, 3, 62), "at": Vector3(0, 14, -30), "fov": 55.0},
	"inferno_a": {"map": 3, "eye": Vector3(7, 40, 99), "at": Vector3(0, -14, 180), "fov": 60.0},
	"inferno_b": {"map": 3, "eye": Vector3(-4, 3, -40), "at": Vector3(20, 8, -90), "fov": 60.0},
}

var _main: Node
var _out: String


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_out = OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(_out)
	var only := OS.get_environment("ONLY")
	for f: int in 10: await process_frame
	var which := CAST if OS.get_environment("PASS") == "cast" else PLATES
	for key: String in which:
		if only != "" and key not in only.split(","): continue
		if which == CAST: await _shoot_cast(key, CAST[key])
		else: await _shoot_plate(key, PLATES[key])
	quit()


func _ground(x: float, z: float) -> float:
	var space := root.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -100.0, z), 1))
	return (hit.position as Vector3).y if hit else 0.0


func _hide_ui() -> void:
	for n: Node in root.find_children("*", "Label3D", true, false): (n as Label3D).visible = false
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	for n: Node in root.find_children("*", "Node3D", true, false):
		if n is TagFlash: (n as Node3D).visible = false


func _world_env() -> WorldEnvironment:
	for n: Node in (_main.get(&"_map") as Node).find_children("*", "WorldEnvironment", true, false): return n
	return null


func _camera(eye: Vector3, at: Vector3, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(at)
	cam.make_current()
	var we := _world_env()
	if we: we.camera_attributes = null # no eye adaptation: every pass at the same exposure
	return cam


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.save_png("%s/%s.png" % [_out, name])
	print("saved ", name, " ", side)


func _shoot_plate(key: String, s: Dictionary) -> void:
	_main.call(&"_start_match", 0, 1, 1, int(s["map"]))
	for f: int in 10: await process_frame
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"freeze")
	var me := _main.get(&"_player") as Character
	me.visible = false
	me.process_mode = Node.PROCESS_MODE_DISABLED
	_hide_ui()
	var cam := _camera(s["eye"], s["at"], float(s["fov"]))
	for f: int in 60: await process_frame
	await _save(key)
	cam.queue_free()
	_main.call(&"toggle_cheat", &"freeze")
	_main.call(&"toggle_cheat", &"alone")


func _shoot_cast(key: String, s: Dictionary) -> void:
	var cast: Array = s["cast"]
	_main.call(&"_start_match", 0, cast.size(), 1, int(s["map"]))
	for f: int in 10: await process_frame
	_main.call(&"toggle_cheat", &"freeze")
	var tm: Node = _main.get(&"tag_manager")
	var me := _main.get(&"_player") as Character
	var bots: Array[Character] = []
	for c: Character in tm.call(&"get_participants"):
		if c != me: bots.append(c)
		if tm.call(&"is_torch", c): tm.call(&"_remove_torch", c)
	me.visible = false
	me.process_mode = Node.PROCESS_MODE_DISABLED
	var eye: Vector3 = s["eye"]
	var lift := eye.y
	eye.y = _ground(eye.x, eye.z) + lift
	var at: Vector3 = s["at"]
	var flat := Vector3(at.x - eye.x, 0.0, at.z - eye.z).normalized()
	var right := flat.cross(Vector3.UP)
	var frame := func(p: Vector3) -> Vector3:
		var w := eye + right * p.x + flat * p.z
		return Vector3(w.x, _ground(w.x, w.z) + p.y, w.z)
	for i: int in cast.size():
		var spec: Dictionary = cast[i]
		var c: Character = bots[i]
		var pos: Vector3 = frame.call(spec["at"])
		c.global_position = pos
		c.velocity = Vector3.ZERO
		var look: Vector3 = frame.call(spec["look"])
		c.visual.look_at(Vector3(look.x, pos.y + c.visual.global_position.y - c.global_position.y, look.z), Vector3.UP)
		if spec.get("torch", false): tm.call(&"_add_torch", c)
		elif spec.get("you", false): c.set_tint(_YOU_TINT)
		c.process_mode = Node.PROCESS_MODE_DISABLED
		var body := c.body
		body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.set_process(false)
		var anim := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		anim.play(StringName(spec["clip"]), 0.0)
		anim.seek(float(spec["t"]), true)
		anim.pause()
		for fx: Node in c.find_children("*", "Node3D", true, false):
			if fx is TorchFX: fx.process_mode = Node.PROCESS_MODE_ALWAYS
		for fx: Node in c.find_children("*", "GPUParticles3D", true, false): fx.process_mode = Node.PROCESS_MODE_ALWAYS
		for fx: Node in c.find_children("*", "CPUParticles3D", true, false): fx.process_mode = Node.PROCESS_MODE_ALWAYS
	for b: Character in bots.slice(cast.size()): b.visible = false
	for c: Character in bots: if c.marker: c.marker.visible = false # (the Torch's arrow overhead)
	_hide_ui()
	# lit by the fire behind them: hot orange lights at their backs (their edges catch it), the sun
	# turned down so the sky's cool light is the fill on the faces
	for n: Node in (_main.get(&"_map") as Node).find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).light_energy *= 0.35
	for l: Array in [[Vector3(0.3, 0.8, 7.6), Color(1.0, 0.42, 0.12), 9.0, 9.0], [Vector3(-0.9, 0.9, 4.9), Color(1.0, 0.5, 0.16), 7.0, 5.0]]:
		var o := OmniLight3D.new()
		root.add_child(o)
		o.global_position = frame.call(l[0])
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		o.omni_attenuation = 1.2
	var cam := _camera(eye, frame.call(s["look"]), float(s["fov"]))
	for f: int in 60: await process_frame # flames grow, shadows settle
	# hold the fire still, so all three passes see the same flames
	for c: Character in bots:
		for p: Node in c.find_children("*", "GPUParticles3D", true, false): (p as GPUParticles3D).speed_scale = 0.0
		for p: Node in c.find_children("*", "CPUParticles3D", true, false): (p as CPUParticles3D).speed_scale = 0.0
		for fx: Node in c.find_children("*", "Node3D", true, false):
			if fx is TorchFX: fx.process_mode = Node.PROCESS_MODE_DISABLED
	for f: int in 3: await process_frame
	await _save(key + "_beauty")
	# the cast alone: the map's geometry out (its lights stay), a flat backdrop, no fog or glow
	var hidden: Array[Node3D] = []
	for n: Node in (_main.get(&"_map") as Node).find_children("*", "", true, false):
		if (n is GeometryInstance3D or n.get_class() == "Terrain3D") and (n as Node3D).visible:
			(n as Node3D).visible = false
			hidden.append(n)
	var we := _world_env()
	var env: Environment = we.environment
	var keep := env.duplicate() as Environment
	var flat_env := env.duplicate() as Environment
	flat_env.background_mode = Environment.BG_COLOR
	if flat_env.sky:
		flat_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		flat_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	flat_env.fog_enabled = false
	flat_env.volumetric_fog_enabled = false
	flat_env.glow_enabled = false
	flat_env.background_energy_multiplier = 1.0
	we.environment = flat_env
	for c: Character in bots: # (the fire gets painted in the composite: the cutout is the bodies)
		for p: Node in c.find_children("*", "GPUParticles3D", true, false): (p as Node3D).visible = false
		for p: Node in c.find_children("*", "CPUParticles3D", true, false): (p as Node3D).visible = false
	for bg: Color in [Color.BLACK, Color.WHITE]:
		flat_env.background_color = bg
		for f: int in 4: await process_frame
		await _save("%s_%s" % [key, "black" if bg == Color.BLACK else "white"])
	we.environment = keep
	for n: Node3D in hidden: n.visible = true
	cam.queue_free()
	_main.call(&"toggle_cheat", &"freeze")
