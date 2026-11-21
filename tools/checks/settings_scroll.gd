extends SceneTree
# Every tab of the settings (title screen and pause menu) fits the screen: rows, buttons and the
# last row when focused all end above the bottom edge.
#   timeout 120 godot --headless --fixed-fps 60 -s res://tools/checks/settings_scroll.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP # headless windows are square: lay out exactly 1920 x 1080
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _check(label: String, owner: Node) -> void:
	# the settings are tabs, not a scrolling list: on every tab the rows, the detail panel's
	# actions and the focused last row must all sit inside the screen
	var screen: Node = owner if owner.has_method(&"open_tab") else null
	if not screen:
		for n: Node in owner.find_children("*", "Control", true, false):
			if n.has_method(&"open_tab"): screen = n
		if not screen:
			print(label, ": FAIL no settings screen")
			return
	var height := root.get_visible_rect().size.y
	var tabs: Array = screen.get(&"_tab_defs")
	for t: int in tabs.size():
		screen.call(&"open_tab", t)
		for i: int in 6: await process_frame
		var rows: Array = screen.get(&"_rows")
		var last := rows[rows.size() - 1] as Control
		last.grab_focus()
		for i: int in 4: await process_frame
		var low := last.global_position.y + last.size.y
		for b: Control in screen.find_children("*", "FireButton", true, false):
			if b.is_visible_in_tree(): low = maxf(low, b.global_position.y + b.size.y)
		print("%s, tab %s: %d rows, lowest edge %.0f of %.0f, in view %s" % [label, tabs[t][0], rows.size(), low, height, low <= height])


func _run(main: Node) -> void:
	for i: int in 30: await process_frame
	var menu: Node = main.get(&"_menu")
	menu.call(&"show_screen", &"settings")
	for i: int in 60: await process_frame
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
