extends SceneTree
# Hot Potato: a burned-out player teleported while out (lava, kill height) must still be able to
# move next round. (It used to stay frozen forever: teleport dropped the frozen state but kept the
# endless timer, and the round's thaw only cleared the timer of a frozen character.)
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/out_thaw.gd
func _initialize() -> void:
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	await create_timer(1.0).timeout
	main.call(&"_start_match", 3, 3, 1, 3)
	var tm := main.get(&"tag_manager") as TagManager
	var p := main.get(&"_player") as Character
	main.call(&"toggle_cheat", &"alone") # no bot shoves or stuns muddying it
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	tm.call(&"_burn_out", p, TagManager.OUT_STORM)
	p.teleport(p.global_position + Vector3.UP * 2.0) # what the lava respawn does
	for i: int in 30: await physics_frame
	print("while out: state %s (frozen expected)" % p.get_state_name())
	tm.start_round()
	while tm.get_phase() != TagManager.PHASE_PLAYING: await physics_frame
	for i: int in 480: await physics_frame # past a fresh Torch's freeze too
	print("next round, 4 s in: state %s, freeze timer %.1f s (expected: not frozen, 0)" % [p.get_state_name(), p.get(&"_frozen_timer")])
	quit()
