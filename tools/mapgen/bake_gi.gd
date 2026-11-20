extends SceneTree
# Bakes a generated map's bounce light: each VoxelGI the generator placed (MapGen.add_baked_gi,
# group "baked_gi") is baked where it stands and written into its own data file (the same resource,
# so the map scene's reference to it stays good). Baked once, lit live by the map's lights: no
# per-frame rebuild round the camera like SDFGI. Needs the GPU, so it opens a window. Run it after
# the map's generator (which leaves an empty placeholder).
#   MAP=res://scn/map/inferno.tscn timeout 600 godot -s res://tools/mapgen/bake_gi.gd


func _initialize() -> void:
	# never left hanging on an error (a script error ends _run before its quit())
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("bake_gi.gd: gave up after 300 s")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	if OS.get_environment("MAP") == "":
		push_error("bake_gi.gd needs MAP (see the top of the file)")
		quit(1)
		return
	var map := (load(OS.get_environment("MAP")) as PackedScene).instantiate() as Node3D
	root.add_child(map)
	var gis := map.find_children("*", "VoxelGI", true, false)
	if gis.is_empty():
		push_error("%s has no VoxelGI (regenerate it: the generator places one)" % OS.get_environment("MAP"))
		quit(1)
		return
	for i: int in 10: await process_frame
	for n: Node in gis:
		var gi := n as VoxelGI
		var path := gi.data.resource_path # the file the scene points at
		gi.visible = true
		var t0 := Time.get_ticks_msec()
		gi.data = null
		gi.bake()
		var baked := gi.data
		baked.energy = float(gi.get_meta(&"gi_energy", 0.3))
		# over the placeholder's file, keeping its uid (the map scene refers to it by uid)
		var uid := ResourceLoader.get_resource_uid(path)
		baked.take_over_path(path)
		var err := ResourceSaver.save(baked, path, ResourceSaver.FLAG_COMPRESS)
		if uid != ResourceUID.INVALID_ID: ResourceSaver.set_uid(path, uid)
		print("baked %s in %d ms: %s cells, energy %.2f -> %s (%s)" % [gi.get_path(), Time.get_ticks_msec() - t0,
				baked.get_octree_size(), baked.energy, path, error_string(err)])
	quit()
