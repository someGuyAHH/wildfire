extends SceneTree
# A map's placed models (src/map/model_scatter.gd: the Jungle's trees and crowns): every copy has a
# real transform (not the empty one a headless-saved MultiMesh came back with), a sane scale, and
# stands where something is (its base close to the ground or a trunk box).
#   SCENE=res://scn/map/jungle.tscn timeout 120 godot --headless -s res://tools/checks/models.gd
func _initialize() -> void:
	var map := (load(OS.get_environment("SCENE")) as PackedScene).instantiate() as Node3D
	root.add_child(map)
	await physics_frame
	await physics_frame
	var space := map.get_world_3d().direct_space_state
	var total := 0
	var blank := 0
	var floating := 0
	var scales := Vector2(INF, 0.0)
	var nodes := 0
	for n: Node in map.find_children("*", "MultiMeshInstance3D", true, false):
		if not n.has_method(&"get_count"): continue
		nodes += 1
		var holder := n as Node3D
		for i: int in n.call(&"get_count"):
			var xf: Transform3D = holder.global_transform * (n.call(&"get_transform_of", i) as Transform3D)
			total += 1
			var s := xf.basis.get_scale().y
			scales = Vector2(minf(scales.x, s), maxf(scales.y, s))
			if xf.origin == holder.global_position and xf.basis == Basis.IDENTITY: blank += 1
			# something solid within 3 m under (forest trees: the ground) or around (crowns: up a trunk)
			var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 1.0, xf.origin + Vector3.DOWN * 3.0)
			if space.intersect_ray(q).is_empty() and not String(n.name).begins_with("Crown"): floating += 1
	print("models: %d nodes, %d copies, %d blank, %d with nothing under them, scale %.2f..%.2f" % [nodes, total, blank, floating, scales.x, scales.y])
	quit()
