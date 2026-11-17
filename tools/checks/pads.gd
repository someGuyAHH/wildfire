extends SceneTree
# Every jump pad on a map lands where its nav link says? Fires a hands-off character from each.
#   SCENE=res://scn/map/jungle.tscn godot --headless --fixed-fps 120 -s res://tools/checks/pads.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := (load(OS.get_environment("SCENE")) as PackedScene).instantiate() as Node3D
	root.add_child(map)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 80, 0)
	root.add_child(cam)
	cam.make_current()
	for i in 20: await physics_frame
	var pad_links: Array[NavigationLink3D] = []
	for l: Node in map.get_node(^"Navigation").get_children():
		if l is NavigationLink3D and int(l.get_meta(&"link_kind", 0)) == 1: pad_links.append(l)
	var char_scene := load("res://scn/character/character.tscn") as PackedScene
	var runs := []
	for pad: Node in map.find_children("Pad*", "Area3D", true, false):
		var p := (pad as Node3D).global_position
		var best: NavigationLink3D = null
		for l in pad_links:
			if best == null or l.start_position.distance_to(p) < best.start_position.distance_to(p): best = l
		var c := char_scene.instantiate() as CharacterBody3D
		c.position = p + Vector3(0, 0.6, 0)
		root.add_child(c)
		runs.append([pad, c, best])
	var air := {}
	var touch := {}
	for i in 1500:
		await physics_frame
		for r in runs:
			var c: CharacterBody3D = r[1]
			if touch.has(c): continue
			if not c.is_on_floor(): air[c] = air.get(c, 0) + 1
			elif air.get(c, 0) > 30: touch[c] = c.global_position
	var good := 0
	for r in runs:
		var c: CharacterBody3D = r[1]
		var target: Vector3 = (r[2] as NavigationLink3D).end_position
		var at: Vector3 = touch.get(c, c.global_position)
		var miss := Vector2(at.x - target.x, at.z - target.z).length()
		if miss < 3.0 and absf(at.y - target.y) < 1.5: good += 1
		else: print("  %s at %s: miss %.1f m, dy %.1f" % [(r[0] as Node).name, (r[0] as Node3D).global_position.snapped(Vector3.ONE * 0.1), miss, at.y - target.y])
	print("pads landing on target: %d / %d" % [good, runs.size()])
	quit()
