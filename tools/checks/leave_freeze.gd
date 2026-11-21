extends SceneTree
# BACK TO TITLE (and menu PLAY): the burn plays over a frozen picture, not the live match. During the
# burn the tree is paused (bots, physics, particles, world sounds), the 3D view is off (disable_3d), the
# Freeze rect holds a static texture and the burn shader samples no screen texture; afterwards
# the title is back, unpaused, 3D on, and nothing is left over. Headless: no GPU time is measured, and
# the picture is a 2x2 stand-in (nothing renders here).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/leave_freeze.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _snap() -> Dictionary:
	var tm := _main.get(&"tag_manager") as TagManager
	var parts: Array = _main.get(&"_participants")
	var pos := PackedVector3Array()
	for c: Character in parts: pos.append(c.global_position)
	return {"game_time": _main.get(&"_game_time"), "pos": pos, "tm_time": tm.get(&"_elapsed")}


func _run() -> void:
	await create_timer(0.5).timeout
	var ok := true
	var shader_src := ((_main.get(&"_burn_mat") as ShaderMaterial).shader as Shader).code
	var samples_screen := shader_src.contains("hint_screen_texture") or shader_src.contains("SCREEN_TEXTURE")
	print("burn shader samples a screen texture: %s" % samples_screen)
	ok = ok and not samples_screen
	_main.call(&"_start_match", 0, 3, 1, 1)
	for i: int in 600: await physics_frame
	var base_orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var pm := _main.get_node(^"PauseMenu")
	pm.call(&"set_paused", true)
	pm.call(&"on_title_pressed")
	await process_frame
	var before := _snap()
	pm.call(&"_on_confirm_yes") # -> Main.return_to_title
	await process_frame
	var freeze := _main.get(&"_freeze") as TextureRect
	for i: int in 3: await process_frame
	for i: int in 12: await physics_frame # (the burn-in is 0.45 s, 54 frames: still going)
	var mid := _snap()
	var frozen: bool = paused and root.disable_3d and freeze.visible and freeze.texture != null
	print("during the burn: tree paused %s, 3D off %s, frozen picture %s (%s)" % [paused, root.disable_3d, freeze.visible, freeze.texture])
	var halted: bool = mid.game_time == before.game_time and mid.pos == before.pos and mid.tm_time == before.tm_time
	print("simulation halted (game time, positions, match clock unchanged): %s" % halted)
	var tex_a := freeze.texture
	for i: int in 8: await physics_frame
	var static_tex: bool = freeze.texture == tex_a and (_main.get(&"_burn_mat") as ShaderMaterial).shader.code == shader_src
	print("picture unchanged while burning: %s" % static_tex)
	ok = ok and frozen and halted and static_tex
	# the pause menu can't be talked into unpausing mid-burn
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	pm.call(&"_unhandled_input", esc)
	ok = ok and paused
	print("Esc during the burn leaves it paused: %s" % paused)
	await create_timer(1.5).timeout
	var back: bool = not paused and not root.disable_3d and not freeze.visible and freeze.texture == null \
			and not (_main.get(&"_in_match") as bool) and not (_main.get(&"_switching") as bool) \
			and (_main.get(&"_participants") as Array).size() == 8
	print("back at the title: unpaused, 3D on, picture gone, attract running: %s" % back)
	ok = ok and back
	# menu PLAY does the same, and the match comes up unpaused
	_main.call(&"on_start_requested", 0, 3, 1, 1)
	for i: int in 10: await process_frame
	var play_frozen: bool = paused and root.disable_3d and freeze.visible
	print("PLAY burn: paused %s, 3D off %s, picture %s" % [paused, root.disable_3d, freeze.visible])
	await create_timer(1.6).timeout
	var play_done: bool = not paused and not root.disable_3d and not freeze.visible and (_main.get(&"_in_match") as bool)
	print("PLAY done: in the match, unpaused, 3D on: %s" % play_done)
	ok = ok and play_frozen and play_done
	# the match freed and re-made leaves no extra orphans
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("orphan nodes: %d -> %d" % [base_orphans, orphans])
	ok = ok and orphans <= base_orphans + 5
	print("leave freeze: %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
