extends SceneTree
# One map piece (a Props holder: its merged boxes and placed models) to an OBJ, in the piece's own space,
# for a look outside the game: tools/blender/preview_obj.py renders it with the real textures.
#   KIT=G0_00_treehouse OUT=/some/dir/piece.obj timeout 120 godot --headless -s res://tools/checks/export_obj.gd
# (Jungle only for now: the scene path is fixed.)
func _initialize() -> void:
	var map := (load("res://scn/map/jungle.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(map)
	var holder := map.find_child(OS.get_environment("KIT"), true, false) as Node3D
	var out := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	var base := 1
	var parts: Array = []
	for n: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.mesh: continue
		parts.append([mi.mesh, holder.global_transform.affine_inverse() * mi.global_transform])
	for n: Node in holder.find_children("*", "MultiMeshInstance3D", true, false):
		if not n.has_method(&"get_count") or String(n.name).ends_with("Shadow"): continue
		for i: int in n.call(&"get_count"):
			parts.append([n.get(&"model"), (n.call(&"get_transform_of", i) as Transform3D)])
	for p: Array in parts:
		var mesh := p[0] as Mesh
		var xf := p[1] as Transform3D
		for s: int in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var mname := mat.resource_path.get_file().get_basename() if mat else "none"
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] else PackedInt32Array()
			out.store_line("o part_%d_%s\nusemtl %s" % [base, mname, mname])
			for q: Vector3 in v:
				var w := xf * q
				out.store_line("v %f %f %f" % [w.x, w.y, w.z])
			for i: int in v.size():
				var t: Vector2 = uv[i] if i < uv.size() else Vector2.ZERO
				out.store_line("vt %f %f" % [t.x, 1.0 - t.y])
			var tri := idx.size() / 3 if idx.size() > 0 else v.size() / 3
			for t: int in tri:
				var i0 := (idx[t * 3] if idx.size() > 0 else t * 3) + base
				var i1 := (idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1) + base
				var i2 := (idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2) + base
				out.store_line("f %d/%d %d/%d %d/%d" % [i0, i0, i2, i2, i1, i1]) # godot cw -> obj ccw
			base += v.size()
	out.close()
	print("wrote ", parts.size(), " parts")
	quit()
