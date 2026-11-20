extends SceneTree
# Fast shadows: on, every shadowed sun stops blending its cascades; off, they blend again (4-split
# presets). The map size and filter are RenderingServer-wide and can't be read back, so only the
# sun's own switch is checked. Headless; the setting changes in memory only (never saved).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/fast_shadows.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var stg := root.get_node(^"STG")
	var saved: float = stg.call(&"get_value", &"fast_shadows")
	var saved_q: float = stg.call(&"get_value", &"shadows")
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 2)
	await create_timer(0.3).timeout
	stg.call(&"set_value", &"shadows", 1.0, false) # Medium: 4 cascades
	var ok := true
	for on: bool in [true, false]:
		stg.call(&"set_value", &"fast_shadows", 1.0 if on else 0.0, false)
		for n: Node in root.find_children("*", "DirectionalLight3D", true, false):
			var sun := n as DirectionalLight3D
			if not sun.shadow_enabled or not sun.is_inside_tree(): continue
			var good := sun.directional_shadow_blend_splits == (not on)
			ok = ok and good
			print("fast %s: %s blends cascades %s  %s" % [on, sun.get_path(), sun.directional_shadow_blend_splits, "ok" if good else "WRONG"])
	stg.call(&"set_value", &"fast_shadows", saved, false)
	stg.call(&"set_value", &"shadows", saved_q, false)
	print("fast shadows: %s" % ("OK" if ok else "FAILED"))
	quit()
