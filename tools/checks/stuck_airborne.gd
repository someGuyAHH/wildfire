extends SceneTree
# A character on the floor never stays "airborne": a jump that never leaves the ground (dashing up a
# slope: the lift is pressed back into it) used to leave the state airborne for good, the body stuck
# in the falling pose (owner's report). Puts you on a slope (the Overworld crater's outer bank, where
# it was seen), forces the airborne state while on the floor, and checks it lands again. Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/stuck_airborne.gd
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
	var ok := true
	for spot: Vector3 in [Vector3(-81.3, 3.0, 187.5), Vector3(-120.7, 10.0, 194.5)]:
		p.teleport(spot)
		for i: int in 120: await physics_frame
		var settled := p.get_state_name()
		# what a jump that never leaves the ground leaves behind: airborne, on the floor, not rising
		p.call(&"_set_state", Character.ST_AIRBORNE)
		p.velocity.y = 0.0
		for i: int in 30: await physics_frame
		var good := p.is_on_floor() and p.get_state() == Character.ST_GROUNDED
		ok = ok and good
		print("at %s: settled %s, then forced airborne -> %s (on floor %s)  %s" % [spot, settled, p.get_state_name(), p.is_on_floor(), "ok" if good else "STUCK"])
	print("stuck airborne: %s" % ("OK" if ok else "STUCK"))
	quit()
