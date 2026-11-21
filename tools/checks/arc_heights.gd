extends SceneTree
# Inferno: how high each spire pad's flight crosses the pit's wall (r 44..47) and the hall's
# inner-end wall (r 87..90), and how far it strays sideways there.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := (load("res://scn/map/inferno.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(map)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 80, 0)
	root.add_child(cam)
	cam.make_current()
	for i in 20: await physics_frame
	var char_scene := load("res://scn/character/character.tscn") as PackedScene
	for pad: Node in map.find_children("Pad*", "Area3D", true, false):
		var p := (pad as Node3D).global_position
		if Vector2(p.x, p.z).length() > 8.0 or p.y < 15.0: continue
		var c := char_scene.instantiate() as CharacterBody3D
		c.position = p + Vector3(0, 0.6, 0)
		root.add_child(c)
		var u := Vector2(p.x, p.z).normalized()
		var lo := [INF, -INF, INF, -INF]
		for i in 900:
			await physics_frame
			var q := Vector2(c.global_position.x, c.global_position.z)
			var r := q.length()
			var side := absf(q.dot(Vector2(-u.y, u.x)))
			if r > 40.0 and r < 50.0: lo[0] = minf(lo[0], c.global_position.y); lo[1] = maxf(lo[1], side)
			if r > 85.0 and r < 92.0: lo[2] = minf(lo[2], c.global_position.y); lo[3] = maxf(lo[3], side)
		print("pad %s dir %s: at pit wall y>=%.1f side<=%.1f; at hall wall y>=%.1f side<=%.1f; ends %s" % [pad.name, u.snapped(Vector2.ONE * 0.1), lo[0], lo[1], lo[2], lo[3], c.global_position.snapped(Vector3.ONE * 0.1)])
		c.queue_free()
	quit()
