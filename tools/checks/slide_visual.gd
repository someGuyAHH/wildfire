extends SceneTree
# Where the runner model's feet are (lowest bone) above the floor while you press slide: the body
# must be on the ground at once, not float for a second (owner's report). Headless.
#   MAPI=1 timeout 200 godot --headless --fixed-fps 120 -s res://tools/checks/slide_visual.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


# the lowest bone's height above the character's feet (its origin), model space included
func _head(p: Character) -> float:
	var skel := p.body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hi := -INF
	for b: int in skel.get_bone_count():
		hi = maxf(hi, (skel.global_transform * skel.get_bone_global_pose(b)).origin.y)
	return hi - p.global_position.y


func _feet(p: Character) -> float:
	var skel := p.body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var low := INF
	for b: int in skel.get_bone_count():
		var y := (skel.global_transform * skel.get_bone_global_pose(b)).origin.y
		low = minf(low, y)
	return low - p.global_position.y


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, int(OS.get_environment("MAPI") if OS.get_environment("MAPI") != "" else "1"))
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"no_tag")
	for i: int in 420: await physics_frame
	var p := _main.get(&"_player") as Character
	p.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	var fwd := Vector3(0, 0, 1)
	var worst := 0.0
	var low_head := 99.0
	for order: String in ["standing", "run", "run, slide"]:
		p.teleport(p.global_position)
		for i: int in 120: await physics_frame
		p.intent.set_look(fwd)
		if order != "standing": p.intent.set_wish(fwd)
		for i: int in (30 if order != "standing" else 120): await physics_frame # (a short run: a wall's not far)
		if order == "run, slide":
			p.intent.slide_held = true
			p.intent.slide_pressed = true # the key going down, as the player's input does
		var line: PackedStringArray = []
		for i: int in 240:
			await physics_frame
			var f := _feet(p)
			if order == "run, slide":
				worst = maxf(worst, f)
				if i == 30: low_head = _head(p) # 0.25 s in
			if i % 10 == 0: line.append("%.2fs feet %.2f head %.2f/%s/%s" % [i / 120.0, f, _head(p), p.get_state_name(), (p.body.get(&"_anim") as AnimationPlayer).current_animation])
		print("%s: feet above floor (m)   %s" % [order, "  ".join(line)])
		p.intent.slide_held = false
		p.intent.set_wish(Vector3.ZERO)
		for i: int in 60: await physics_frame
	print("slide visual: head %.2f m 0.25 s after pressing slide (standing 1.5): %s" % [low_head, "OK" if low_head < 0.9 else "STILL UPRIGHT"])
	quit()
