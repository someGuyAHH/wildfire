extends SceneTree
# On the title screen the tagline sits clear below the WILDFIRE heading (their rects don't touch).
#   timeout 60 godot --headless --fixed-fps 120 -s res://tools/checks/title_layout.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	for i: int in 40: await process_frame
	var menu: Node = main.get(&"_menu")
	var logo: Control
	var tag: Control
	for l: Node in menu.find_children("*", "Control", true, false):
		if l.get_class() == "Control" and l.get_script() and l.get(&"text") == "WILDFIRE": logo = l
		elif l is Label and (l as Label).text.begins_with("tag, but"): tag = l
	var a := Rect2(logo.global_position, logo.size)
	var b := Rect2(tag.global_position, tag.size)
	print("logo %s, tagline %s, gap %.0f px" % [a, b, b.position.y - a.end.y])
	print("title layout: ", "FAIL (overlap)" if a.intersects(b) else "OK")
	quit()
