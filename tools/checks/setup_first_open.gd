extends SceneTree
# First time the match setup is shown: per-frame wall time of the first frames, and how often the carousel's
# 3D viewport is asked to render while idle / hidden (headless: script, layout, scene-tree cost only; GPU time
# and shader compiles are not measured).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/setup_first_open.gd
func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var main := (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred(main)


# frames out of `frames` in which the carousel's 3D ring was asked to draw (ModeWheel.renders)
func _count_renders(wheel: Control, frames: int, times: Array[float]) -> int:
	var before: int = wheel.get(&"renders")
	var last := Time.get_ticks_usec()
	for i: int in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	return int(wheel.get(&"renders")) - before


func _run(main: Node) -> void:
	for i: int in 90: await process_frame
	var menu: Node = main.get(&"_menu")
	var wheel: Control = (menu.get(&"_pieces") as Dictionary)[&"wheel"]
	var bad: Array[String] = []
	var hidden := await _count_renders(wheel, 60, [] as Array[float])
	if hidden != 0: bad.append("hidden setup drew the carousel")
	print("title (setup hidden):   %d / 60 frames render the carousel" % hidden)
	menu.call(&"show_screen", &"modes")
	var first: Array[float] = []
	var building := await _count_renders(wheel, 60, first)
	print("first open, frames 1-8 (ms): ", first.slice(0, 8).map(func(t: float) -> String: return "%.1f" % t))
	print("first open: worst %.2f ms, renders in 60 frames %d" % [first.max(), building])
	for i: int in 90: await process_frame # (the build-in and the swing finish)
	var idle := await _count_renders(wheel, 120, [] as Array[float])
	print("setup idle:             %d / 120 frames render the carousel" % idle)
	wheel.call(&"step", 1)
	var turning := await _count_renders(wheel, 90, [] as Array[float])
	print("turning one card (90 f): %d frames render" % turning)
	var after := await _count_renders(wheel, 60, [] as Array[float])
	print("idle after the turn:    %d / 60" % after)
	if idle > 0 or after > 0: bad.append("idle setup drew the carousel (%d, %d)" % [idle, after])
	if turning < 30: bad.append("turning drew only %d frames" % turning)
	menu.call(&"show_screen", &"title")
	for i: int in 150: await process_frame
	var back := await _count_renders(wheel, 60, [] as Array[float])
	print("back on the title:      %d / 60" % back)
	if back > 0: bad.append("title drew the carousel")
	if first.max() > 12.0: bad.append("first open frame %.1f ms" % first.max())
	menu.call(&"show_screen", &"modes")
	var second: Array[float] = []
	await _count_renders(wheel, 30, second)
	print("second open worst %.2f ms" % second.max())
	print("FAIL: " + ", ".join(bad) if bad else "PASS")
	quit(1 if bad else 0)
