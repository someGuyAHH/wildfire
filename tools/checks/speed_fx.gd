extends SceneTree
# The Speed effects setting: Off hides both speed overlays even at full speed; Low / Medium / High
# show them and set the momentum shader's detail (1-3). Headless; the player is pushed to full
# speed by hand; the setting changes in memory only (never saved).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/speed_fx.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var stg := root.get_node(^"STG")
	var saved: float = stg.call(&"get_value", &"speed_fx")
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 2)
	_main.call(&"toggle_cheat", &"alone")
	var player := _main.get_node(^"Player") as CharacterBody3D
	var hud := _main.get_node(^"Player/Hud")
	var fx := hud.get_node(^"MomentumFX") as CanvasItem
	var lines := hud.get_node(^"SpeedLines") as CanvasItem
	var mat := fx.material as ShaderMaterial
	var ok := true
	for level: int in [3, 0, 1, 2, 3]:
		stg.call(&"set_value", &"speed_fx", float(level), false)
		for i: int in 30:
			player.velocity = Vector3(40.0, 0.0, 0.0)
			await physics_frame
		var shown := fx.visible and lines.visible
		var detail: int = mat.get_shader_parameter(&"detail")
		var good := shown == (level > 0) and (level == 0 or detail == level)
		ok = ok and good
		print("level %d: momentum %s, lines %s, detail %d  %s" % [level, fx.visible, lines.visible, detail, "ok" if good else "WRONG"])
	stg.call(&"set_value", &"speed_fx", saved, false)
	print("speed effects: %s" % ("OK" if ok else "FAILED"))
	quit()
