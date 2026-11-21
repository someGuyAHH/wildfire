extends SceneTree
# Per-frame wall time of the menu's idle, setup build-in and setup exit (headless: script, layout and
# scene-tree cost only; no GPU work or shader compiles are measured here).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/menu_exit_perf.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _measure(label: String, frames: int) -> void:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i: int in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var sum := 0.0
	var worst := 0.0
	for t: float in times:
		sum += t
		worst = maxf(worst, t)
	var sorted := times.duplicate()
	sorted.sort()
	print("%-22s %3d frames: mean %.2f ms, median %.2f, p95 %.2f, worst %.2f" % [label, frames, sum / frames, sorted[frames / 2], sorted[int(frames * 0.95)], worst])


func _run(main: Node) -> void:
	for i: int in 60: await process_frame
	var menu: Node = main.get(&"_menu")
	var wheel: Control = (menu.get(&"_pieces") as Dictionary)[&"wheel"]
	var vp: SubViewport = wheel.get(&"_vp")
	var counts := {&"wheel resized": 0, &"3D viewport resized": 0}
	wheel.resized.connect(func() -> void: counts[&"wheel resized"] += 1)
	vp.size_changed.connect(func() -> void: counts[&"3D viewport resized"] += 1)
	await _measure("title idle", 120)
	menu.call(&"show_screen", &"modes")
	await _measure("build-in", 60)
	await _measure("setup idle", 120)
	counts[&"wheel resized"] = 0
	counts[&"3D viewport resized"] = 0
	menu.call(&"show_screen", &"title")
	await _measure("exit", 120)
	print("during the exit: ", counts)
	await _measure("title idle after", 60)
	quit()
