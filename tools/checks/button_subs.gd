extends SceneTree
# A slab button's side description sits along the bottom: in the lower half of the button, inside
# the slanted right edge, and clear of the main label (title menu, settings tabs, pause menu).
#   timeout 90 godot --headless --fixed-fps 120 -s res://tools/checks/button_subs.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	for i: int in 40: await process_frame
	var menu: Node = main.get(&"_menu")
	menu.call(&"show_screen", &"settings", false)
	for i: int in 10: await process_frame
	var fail := false
	var n := 0
	for owner: Node in [menu]:
		for b: FireButton in owner.find_children("*", "FireButton", true, false):
			if b.sub == "" or b.centered: continue
			n += 1
			var l := b.label_rect()
			var s := b.sub_rect()
			var lower := s.position.y >= b.size.y * 0.5
			var inside := s.end.x <= b.size.x - UIKit.SLAB_SKEW * s.end.y and s.end.y <= b.size.y
			var clear := not l.intersects(s)
			if not (lower and inside and clear):
				fail = true
				print("  FAIL '%s' (%s): label %s sub %s lower %s inside %s clear %s" % [b.text, b.size, l, s, lower, inside, clear])
	# and at other heights / widths
	for h: float in [52.0, 66.0, 96.0, 140.0]:
		var b := FireButton.new()
		b.text = "HOW TO PLAY"
		b.sub = "The keys, and the rules of each mode"
		b.text_size = 30 if h < 100.0 else 56
		b.custom_minimum_size = Vector2(560.0, h)
		root.add_child(b)
		await process_frame
		b.size = Vector2(560.0, h)
		var l := b.label_rect()
		var s := b.sub_rect()
		var ok := s.position.y >= h * 0.5 and not l.intersects(s)
		print("  height %.0f: label %s sub %s %s" % [h, l, s, "ok" if ok else "FAIL"])
		if not ok: fail = true
		b.queue_free()
	print("button descriptions (%d buttons): %s" % [n, "FAIL" if fail else "OK"])
	quit()
