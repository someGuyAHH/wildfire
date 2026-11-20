extends SceneTree
# Dash trail: a dash leaves a streak (points recorded behind the runner, a mesh built from them),
# in the character's colour, gone again shortly after. Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/dash_trail.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 1)
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"no_tag")
	for i: int in 300: await physics_frame
	var p := _main.get(&"_player") as Character
	var trail := p.find_children("*", "MeshInstance3D", false, false).filter(func(n: Node) -> bool: return n is DashTrail)[0] as DashTrail
	p.call(&"_try_dash")
	var most := 0
	var built := false
	for i: int in 30:
		await process_frame
		most = maxi(most, trail._points.size())
		built = built or (trail.mesh as ImmediateMesh).get_surface_count() > 0
	for i: int in 90: await process_frame
	var left := trail._points.size()
	print("dash trail: up to %d points, mesh built %s, colour %s, %d left after" % [most, built, trail.color, left])
	print("dash trail: %s" % ("OK" if most >= 4 and built and left == 0 else "CHECK"))
	quit()
