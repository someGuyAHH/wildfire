extends SceneTree
const Gen := preload("res://tools/mapgen/jungle_gen.gd")
# The Jungle's water sits in its banks: the edges of the river ribbon and the pools are under the
# terrain (the banks cut the shoreline), never hanging in the air past them.
# Also: how full the river is along its length.
#   timeout 60 godot --headless -s res://tools/checks/water.gd
func _initialize() -> void:
	var map := (load("res://scn/map/jungle.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(map)
	await physics_frame
	await physics_frame
	var gm := map as GameMap
	for path: String in ["Props/River/Water", "Props/Falls/Pool0", "Props/Falls/Pool1"]:
		var mi := map.get_node(path) as MeshInstance3D
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var mid := Vector3.ZERO
		for q: Vector3 in v: mid += q
		mid /= v.size()
		var edge := 0
		var above := 0
		var worst := -INF
		for i: int in v.size():
			var p := mi.global_transform * v[i]
			var gh := gm.ground_height(p.x, p.z)
			# only the outer edge vertices (river: every corner is on an edge; pools: not the centre)
			if path.contains("Pool") and Vector2(p.x - mid.x, p.z - mid.z).length() < 1.0: continue # a disc's centre
			if path.contains("Pool") and Gen._river_dist(Vector2(p.x, p.z)) < 13.0: continue # over the river's mouth: water on water
			edge += 1
			if p.y > gh + 0.05: above += 1
			worst = maxf(worst, p.y - gh)
		print("%s: %d edge vertices, %d above the ground (highest %.2f m %s it)" % [path, edge, above, absf(worst), "above" if worst > 0.0 else "below"])
	# how full the river is: water depth at its middle, every row of the ribbon (left+right edge mid)
	var river := map.get_node("Props/River/Water") as MeshInstance3D
	var rv: PackedVector3Array = river.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var dry := 0
	var rows := 0
	var depth_sum := 0.0
	for i: int in range(0, rv.size(), 6): # each quad: corners 0 and 1 are the row's left and right
		var mid := (rv[i] + rv[i + 1]) * 0.5
		var depth := mid.y - gm.ground_height(mid.x, mid.z)
		rows += 1
		depth_sum += maxf(depth, 0.0)
		if depth < 0.4: dry += 1
	print("river: %d rows, %d with under 0.4 m of water in the middle, mean depth %.2f m" % [rows, dry, depth_sum / maxi(rows, 1)])
	quit()
