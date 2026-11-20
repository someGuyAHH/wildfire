extends SceneTree
# Screenshots of the UI (renders: a window opens, only when the owner allows): the title screen,
# mode select, settings and how-to-play over the live attract match, then a Classic match with
# bots playing: the HUD, the scoreboard (Tab) and the pause menu. Settings untouched (never saved).
#   OUT=/some/dir [MAPI=1] [ONLY="title,hud"] timeout 180 godot --fixed-fps 120 -s res://tools/checks/ui_shot.gd
# Saves OUT/<name>.png. ONLY: just these shots (title, modes, settings, howto, hud, torch, board, pause).
# modes also saves modes_turn (the carousel mid-turn, going back a mode) and modes_back (after).
var _main: Node
var _out := ""
var _only := PackedStringArray()


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_out = OS.get_environment("OUT")
	_only = OS.get_environment("ONLY").split(",", false)
	_run.call_deferred()


func _want(name: String) -> bool:
	return _only.is_empty() or name in _only


func _shot(name: String, frames: int = 30) -> void:
	for f: int in frames: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await create_timer(2.5).timeout
	var menu: Node = _main.get(&"_menu")
	if _want("title"): await _shot("title", 60)
	for screen: String in ["modes", "settings", "howto"]:
		if not _want(screen): continue
		menu.call(&"show_screen", StringName(screen))
		await _shot(screen, 90)
		if screen == "modes": # the carousel mid-turn (going back) and after
			var wheel: Node = menu.get(&"_wheel")
			wheel.call(&"step", -1)
			await _shot("modes_turn", 10)
			await _shot("modes_turn2", 12)
			await _shot("modes_back", 90)
	if _want("hud") or _want("torch") or _want("board") or _want("pause"):
		var mapi := int(OS.get_environment("MAPI")) if OS.get_environment("MAPI") != "" else 1
		_main.call(&"_start_match", 0, 7, 1, mapi)
		await create_timer(1.5).timeout
		if _want("countdown"): await _shot("countdown", 2)
		await create_timer(6.0).timeout # past the countdown, everyone running
		if _want("hud"): await _shot("hud", 2)
		if _want("torch"):
			var tm: Node = _main.get(&"tag_manager")
			var me := _main.get(&"_player") as Character
			for c: Character in tm.call(&"get_participants"):
				if tm.call(&"is_torch", c) and c != me: tm.call(&"_remove_torch", c)
			if not tm.call(&"is_torch", me): tm.call(&"_add_torch", me)
			await create_timer(1.0).timeout
			await _shot("torch", 2)
		if _want("board"):
			Input.action_press(&"scoreboard")
			await _shot("board", 20)
			Input.action_release(&"scoreboard")
			for f: int in 5: await process_frame
		if _want("pause"):
			var pause: Node = _main.get(&"_pause")
			pause.call(&"set_paused", true)
			await _shot("pause", 40)
			pause.call(&"set_paused", false)
	quit()
