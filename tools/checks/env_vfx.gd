extends SceneTree
# The maps' own effects: the Inferno's lava sparks find open lava (some emitters, none under the
# halls) and each Jungle waterfall has its spray (mist and droplets). Headless.
# One map a run (WHICH=inferno or jungle; freeing a map mid-load crashed the engine).
#   WHICH=inferno timeout 120 godot --headless -s res://tools/checks/env_vfx.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ok := true
	if OS.get_environment("WHICH") == "jungle":
		ok = await _jungle()
		print("map effects: %s" % ("OK" if ok else "CHECK"))
		quit()
		return
	var inferno := (load("res://scn/map/inferno.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(inferno)
	for i: int in 5: await physics_frame
	var sparks := inferno.get_node(^"LavaSparks")
	var n: int = sparks.get_meta(&"emitters", 0)
	var under := 0
	var space := inferno.get_world_3d().direct_space_state
	for e: Node in sparks.get_children():
		var p := (e as Node3D).global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 120.0, p, 1))
		if hit: under += 1
	print("lava sparks: %d emitters over open lava, %d under something" % [n, under])
	ok = ok and n > 20 and under == 0
	print("map effects: %s" % ("OK" if ok else "CHECK"))
	quit()


func _jungle() -> bool:
	var ok := true
	var jungle := (load("res://scn/map/jungle.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(jungle)
	await process_frame
	var sprays := jungle.find_children("Spray*", "Node3D", true, false)
	for s: Node in sprays:
		var parts := s.find_children("*", "GPUParticles3D", false, false).size()
		print("  %s at %s: %d emitters" % [s.name, (s as Node3D).global_position.snappedf(0.1), parts])
		ok = ok and parts == 2
	return ok and sprays.size() == 2
