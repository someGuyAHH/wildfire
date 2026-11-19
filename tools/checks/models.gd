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
	# models face out: the bark of every tree model (not the two-sided leaves) winds so the outside is
	# the front (clockwise in Godot; inside-out trunks showed their insides); the obstacle kits'
	# pieces (closed solids) by their signed volume
	var checked := {}
	var inside_out := 0
	var meshes := 0
	for n: Node in map.find_children("*", "MultiMeshInstance3D", true, false):
		var m: Mesh = n.get(&"model")
		if not m or checked.has(m) or m.resource_path.ends_with("_shadow.res"): continue # shadow-only lumps (not round the trunk's axis, never seen)
		checked[m] = true
		for s: int in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat and mat.resource_path.contains("foliage"): continue
			meshes += 1
			var a := m.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] else PackedInt32Array()
			var outw := 0
			var tri := (idx.size() if idx.size() > 0 else v.size()) / 3
			if m.resource_path.contains("/kits/"): # closed solids: right side out <=> signed volume < 0
				# (Godot's fronts wind clockwise, so each face's cross product points inward)
				var vol := 0.0
				for t: int in tri:
					var j0 := idx[t * 3] if idx.size() > 0 else t * 3
					vol += v[j0].dot((v[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1] - v[j0]).cross(v[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2] - v[j0]))
				if vol >= 0.0:
					inside_out += 1
					print("  inside out: ", m.resource_path.get_file(), " surface ", s)
				continue
			for t: int in tri:
				var i0 := idx[t * 3] if idx.size() > 0 else t * 3
				var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var c := (v[i0] + v[i1] + v[i2]) / 3.0
				var n2 := (v[i1] - v[i0]).cross(v[i2] - v[i0])
				var out := Vector3(c.x, maxf(c.y - 1000.0, 0.0), c.z) # sideways from the trunk's axis
				if n2.dot(out) < 0.0 or absf(n2.normalized().y) > 0.9: outw += 1 # (caps count as fine)
			if outw < tri * 0.85: inside_out += 1
	print("model surfaces facing out: %d of %d" % [meshes - inside_out, meshes])
	quit()
