extends SceneTree
# RESTART ROUND and BACK TO TITLE ask first: picking one shows "are you sure?" (NO focused) and
# changes nothing; NO (or Esc) goes back to the buttons, still paused; YES does it. Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/pause_confirm.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 1)
	for i: int in 600: await physics_frame # into the round
	var pm := _main.get_node(^"PauseMenu")
	var tm := _main.get(&"tag_manager") as TagManager
	var ok := true
	pm.call(&"set_paused", true)
	var phase_before: int = tm.get(&"_phase")
	# restart: asks, NO changes nothing
	pm.call(&"on_restart_pressed")
	await process_frame
	var asking: bool = (pm.get(&"_confirm") as Control).visible and (pm.get(&"_confirm_no") as Button).has_focus()
	var unchanged: bool = paused and tm.get(&"_phase") == phase_before
	pm.call(&"_cancel_confirm")
	await process_frame
	var back: bool = paused and (pm.get(&"_buttons") as Control).visible and not (pm.get(&"_confirm") as Control).visible
	print("restart: asks %s (NO focused), nothing changed %s, NO -> back to the buttons %s" % [asking, unchanged, back])
	ok = ok and asking and unchanged and back
	# Esc cancels too
	pm.call(&"on_title_pressed")
	await process_frame
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	pm.call(&"_unhandled_input", esc)
	await process_frame
	var esc_ok: bool = paused and not (pm.get(&"_confirm") as Control).visible
	print("title: Esc cancels, still paused %s" % esc_ok)
	ok = ok and esc_ok
	# YES restarts
	pm.call(&"on_restart_pressed")
	await process_frame
	pm.call(&"_on_confirm_yes")
	await process_frame
	var restarted: bool = not paused and tm.get(&"_phase") == TagManager.PHASE_COUNTDOWN
	print("restart YES: unpaused, round restarting (countdown) %s" % restarted)
	ok = ok and restarted
	print("pause confirm: %s" % ("OK" if ok else "FAILED"))
	quit()
