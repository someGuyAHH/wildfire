extends SceneTree
# Each round: which hall does everyone start in? (Inferno: one random hall per round, all together,
# in every mode.) Halls by direction from the centre: N E S W.
#   MAPI=3 MODE=0 godot --headless --fixed-fps 120 -s res://tools/checks/spawn_rooms.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _hall(p: Vector3) -> String:
	if Vector2(p.x, p.z).length() < 60.0: return "pit"
	if absf(p.x) > absf(p.z): return "E" if p.x > 0.0 else "W"
	return "S" if p.z > 0.0 else "N"


func _run() -> void:
	await create_timer(1.0).timeout
	var mode := int(OS.get_environment("MODE")) if OS.get_environment("MODE") != "" else 0
	_main.call(&"_start_match", mode, 9, 2, int(OS.get_environment("MAPI")))
	var tm := _main.get(&"tag_manager") as TagManager
	for r: int in 5:
		if r > 0: tm.start_round()
		await physics_frame
		var halls: PackedStringArray = []
		for c: Character in _main.get(&"_participants"): halls.append(_hall(c.global_position))
		print("round %d: %s" % [r, " ".join(halls)])
	quit()
