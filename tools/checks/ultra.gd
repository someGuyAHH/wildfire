extends SceneTree
# The ULTRA preset turns every premium effect on (reflections, coloured bounce light, TAA, soft
# shadows, eye adaptation, smooth glow) and live GI stays its own switch; back to the defaults
# turns them off again. Headless; settings change in memory only (never saved).
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/ultra.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _state(stg: Node) -> Dictionary:
	var map := _main.get(&"_map") as Node3D
	var we := map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
	var env := we.environment
	var sun := map.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	return {"ssr": env.ssr_enabled, "ssil": env.ssil_enabled, "taa": root.use_taa, "sdfgi": env.sdfgi_enabled,
			"soft": sun.light_angular_distance > 0.0, "exposure": we.camera_attributes != null,
			"smooth glow": stg.call(&"is_on", &"glow_hq"), "scale": root.scaling_3d_scale} # (bicubic glow is renderer-wide: no read-back)


func _run() -> void:
	var stg := root.get_node(^"STG")
	var saved := {}
	for k: StringName in stg.get(&"_values"): saved[k] = stg.call(&"get_value", k)
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 2)
	await create_timer(0.3).timeout
	var ok := true
	stg.call(&"apply_ultra", false)
	var u := _state(stg)
	print("ultra: %s" % u)
	ok = ok and u.ssr and u.ssil and u.taa and u.soft and u.exposure and u["smooth glow"] and not u.sdfgi and is_equal_approx(u.scale, 1.0)
	stg.call(&"set_value", &"live_gi", 1.0, false)
	var g := _state(stg)
	print("live GI on: sdfgi %s" % g.sdfgi)
	ok = ok and g.sdfgi
	for k: StringName in saved: stg.call(&"set_value", k, stg.call(&"get_default", k), false)
	var d := _state(stg)
	print("defaults: %s" % d)
	ok = ok and not (d.ssr or d.ssil or d.taa or d.soft or d.exposure or d["smooth glow"] or d.sdfgi)
	for k: StringName in saved: stg.call(&"set_value", k, saved[k], false)
	print("ultra preset: %s" % ("OK" if ok else "FAILED"))
	quit()
