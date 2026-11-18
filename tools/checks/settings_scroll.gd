extends SceneTree
# The settings list scrolls when the screen is too short for it, on the title screen and in the
# pause menu: the scroller ends above the screen's bottom, and focusing the last row (BACK)
# scrolls it into view.
#   timeout 120 godot --headless --fixed-fps 60 -s res://tools/checks/settings_scroll.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP # headless windows are square: lay out exactly 1920 x 1080
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _check(label: String, owner: Node) -> void:
	var sc := owner.find_children("*", "ScrollContainer", true, false)
	if sc.is_empty():
		print(label, ": no scroller")
		return
	var s := sc[0] as ScrollContainer
	var list := s.get_child(0) as Control
	var buttons := list.find_children("*", "FireButton", true, false)
	(buttons[buttons.size() - 1] as Control).grab_focus()
	for i: int in 10: await process_frame
	var back := buttons[buttons.size() - 1] as Control
	var visible_back := back.global_position.y + back.size.y <= s.global_position.y + s.size.y + 1.0
	print("%s: scroller %.0f px, list %.0f px, ends at %.0f of %.0f; BACK focused -> scrolled %d, in view %s" % [
		label, s.size.y, list.size.y, s.global_position.y + s.size.y, root.get_visible_rect().size.y, s.scroll_vertical, visible_back])


func _run(main: Node) -> void:
	for i: int in 30: await process_frame
	var menu: Node = main.get(&"_menu")
	menu.call(&"show_screen", &"settings")
	for i: int in 40: await process_frame
	await _check("title settings", menu)
	main.call(&"_start_match", 0, 3, 1, 0)
	for i: int in 30: await process_frame
	var pause: Node = main.get(&"_pause")
	pause.call(&"set_paused", true)
	pause.call(&"show_settings", true)
	for i: int in 10: await process_frame
	await _check("pause settings", pause)
	pause.call(&"set_paused", false)
	quit()
