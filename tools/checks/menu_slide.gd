extends SceneTree
# The title menu's screens slide (MenuSlide): each comes in from its own side, goes back the same
# way, ends exactly in place with only itself visible, and a key press skips a slide to its end.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/menu_slide.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _report(menu: Node, label: String, frames: int) -> void:
	var screens: Dictionary = menu.get(&"_screens")
	var parts := PackedStringArray()
	for key: StringName in screens.keys():
		var s := screens[key] as Control
		if s.visible: parts.append("%s@%s" % [key, s.position])
	print("%s (+%d frames): %s" % [label, frames, ", ".join(parts)])


func _pieces(menu: Node, label: String) -> void:
	var pieces: Dictionary = menu.get(&"_pieces")
	var parts := PackedStringArray()
	for key: StringName in pieces.keys():
		var c := pieces[key] as Control
		parts.append("%s %s r%.2f" % [key, c.global_position.round(), c.rotation])
	print("  ", label, ": ", "; ".join(parts))


func _run(main: Node) -> void:
	for i: int in 30: await process_frame
	var menu: Node = main.get(&"_menu")
	var ok := true
	for screen: StringName in [&"modes", &"settings", &"howto"]:
		menu.call(&"show_screen", screen)
		for i: int in 8: await process_frame
		_report(menu, "-> %s mid" % screen, 8)
		if screen == &"modes": _pieces(menu, "pieces mid")
		for i: int in 60: await process_frame
		_report(menu, "-> %s done" % screen, 68)
		if screen == &"modes": _pieces(menu, "pieces done")
		menu.call(&"show_screen", &"title")
		for i: int in 8: await process_frame
		_report(menu, "-> title mid", 8)
		if screen == &"modes": _pieces(menu, "pieces falling")
		for i: int in 20: await process_frame
		if screen == &"modes": _pieces(menu, "pieces falling later")
		for i: int in 40: await process_frame
		_report(menu, "-> title done", 68)
		if screen == &"modes": _pieces(menu, "pieces after")
	# skipping: a key press mid-slide finishes it
	menu.call(&"show_screen", &"modes")
	for i: int in 60: await process_frame
	menu.call(&"show_screen", &"title")
	for i: int in 4: await process_frame
	var press := InputEventKey.new()
	press.keycode = KEY_SHIFT
	press.pressed = true
	menu.call(&"_input", press)
	_report(menu, "skipped", 4)
	_pieces(menu, "skipped pieces")
	quit()
