extends SceneTree
# Dash out of a slide (and a slide out of a dash) must not leave you floating (owner's report: a
# couple of seconds up in the air before grounding). Presses slide, then dash, on flat ground and on
# the crater's bank, and traces the height above the floor and the state every few frames. Headless.
#   timeout 200 godot --headless --fixed-fps 120 -s res://tools/checks/dash_slide_float.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


# how far above the ground below the character is
func _height(p: Character) -> float:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.5, p.global_position + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return p.global_position.y - hit.position.y if hit else 99.0


func _trace(p: Character, label: String, steps: int, every: int) -> float:
	var worst := 0.0
	var line: PackedStringArray = []
	for i: int in steps:
		await physics_frame
		var h := _height(p)
		worst = maxf(worst, h)
		if h > 0.6 and worst == h and i % 10 == 0: pass
		var clip := ""
		if p.body: clip = String((p.body.get(&"_anim") as AnimationPlayer).current_animation)
		if i % every == 0: line.append("%s %.1fm/%s %.0fm/s" % ["%.2fs" % (i / 120.0), h, p.get_state_name(), p.get_horizontal_speed()])
	print("%s: worst height %.2f m   %s" % [label, worst, "  ".join(line)])
	return worst


func _run() -> void:
	await create_timer(0.5).timeout
	var p: Character
	# the crater's floor, a running start up its bank: slide only, slide then dash, dash then slide
	_main.call(&"_start_match", 0, 3, 1, 1)
	_main.call(&"toggle_cheat", &"alone")
	_main.call(&"toggle_cheat", &"no_tag")
	for i: int in 420: await physics_frame
	p = _main.get(&"_player") as Character
	p.get_node(^"Input").process_mode = Node.PROCESS_MODE_DISABLED
	var start := p.global_position
	var bad := false
	for order: String in ["slide only", "slide, dash", "dash, slide", "slide, dash, jump"]:
		p.teleport(start)
		for i: int in 120: await physics_frame
		var fwd := Vector3(0, 0, -1)
		p.intent.set_wish(fwd)
		p.intent.set_look(fwd)
		for i: int in 150: await physics_frame
		match order:
			"slide only": p.intent.slide_held = true
			"slide, dash", "slide, dash, jump":
				p.intent.slide_held = true
				for i: int in 50: await physics_frame
				p.intent.dash_pressed = true
				if order.ends_with("jump"):
					for i: int in 12: await physics_frame
					p.intent.jump_pressed = true
			"dash, slide":
				p.intent.dash_pressed = true
				for i: int in 12: await physics_frame
				p.intent.slide_held = true
		var worst := await _trace(p, order, 420, 30)
		p.intent.slide_held = false
		p.intent.set_wish(Vector3.ZERO)
		for i: int in 90: await physics_frame
		if worst > 3.0 and not order.ends_with("jump"): bad = true # (a jump's own 2.5 m is fine)
	print("dash/slide float: %s" % ("FLOATS" if bad else "ok"))
	quit()
