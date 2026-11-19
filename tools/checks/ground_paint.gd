extends SceneTree
# The Overworld's painted ground (overworld_gen.gd _paint): the terrain's control map holds grass,
# dry earth and rock in sensible shares, rock where it's steep, the nav bit inside the arena, and
# the photo layers are loaded. Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/ground_paint.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := (load("res://scn/map/overworld.tscn") as PackedScene).instantiate() as Node3D
	var terrain := map.get_node(^"Terrain3D")
	# read before the terrain enters the tree: headless (dummy renderer) Terrain3D empties the list
	var list: Array = ((terrain.get(&"assets") as Object).call(&"get_texture_list") as Array).duplicate() # (its own array, by reference)
	root.add_child(map)
	for i: int in 10: await process_frame
	var data: Object = terrain.get(&"data")
	var ok := true
	var names: Array[String] = []
	for ta: Object in list:
		names.append(String(ta.get(&"name")))
		if not ta.get(&"albedo_texture") or not ta.get(&"normal_texture"): ok = false
	if list.size() != 3: ok = false
	var counts := {0: 0.0, 1: 0.0, 2: 0.0}
	var steep_rock := 0
	var steep := 0
	var nav_in := 0
	var n := 0
	var util := &"Terrain3DUtil"
	for z: int in range(-250, 251, 5):
		for x: int in range(-250, 251, 5):
			if Vector2(x, z).length() > 250.0: continue
			var c: int = data.call(&"get_control", Vector3(x, 0, z))
			var base: int = ClassDB.class_call_static(util, &"get_base", c)
			var over: int = ClassDB.class_call_static(util, &"get_overlay", c)
			var blend: float = ClassDB.class_call_static(util, &"get_blend", c) / 255.0
			counts[base] += 1.0 - blend
			counts[over] += blend
			n += 1
			if c & 0x2: nav_in += 1 # nav bit (enc_nav = bit 1)
			var nrm: Vector3 = data.call(&"get_normal", Vector3(x, 0, z))
			if nrm.y < 0.7:
				steep += 1
				if base == 0 and blend < 0.5: steep_rock += 1
	print("layers %s" % [names])
	print("arena ground: rock %.0f%%, grass %.0f%%, dirt %.0f%%; steep spots rocky %d / %d; nav bit %d / %d" % [
			counts[0] / n * 100.0, counts[1] / n * 100.0, counts[2] / n * 100.0, steep_rock, steep, nav_in, n])
	if counts[1] / n < 0.5 or counts[2] / n < 0.05 or counts[2] / n > 0.4: ok = false
	if steep > 0 and steep_rock < steep * 0.9: ok = false
	if nav_in < n: ok = false
	print("GROUND PAINT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
