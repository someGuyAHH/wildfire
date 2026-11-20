extends SceneTree
# A character's own effects load and switch: smoke (the cloud puff, light wisps and the column) and
# the overdrive sparks (round glowing dots). Headless.
#   timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/char_fx.gd
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	_main.call(&"_start_match", 0, 3, 1, 1)
	_main.call(&"toggle_cheat", &"alone")
	for i: int in 300: await physics_frame
	var p := _main.get(&"_player") as Character
	var ok := true
	for level: int in [Character.SMOKE_LIGHT, Character.SMOKE_COLUMN, Character.SMOKE_NONE]:
		p.set_smoke(level)
		await process_frame
		var fx := p.get(&"_smoke_fx") as CPUParticles3D
		var tex := ((fx.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
		var good := fx.emitting == (level != Character.SMOKE_NONE) and tex and tex.resource_path.ends_with("smoke_puff.png") and fx.gi_mode == GeometryInstance3D.GI_MODE_DISABLED
		ok = ok and good
		print("smoke %d: emitting %s, %d puffs, %s  %s" % [level, fx.emitting, fx.amount, tex.resource_path.get_file() if tex else "no texture", "ok" if good else "WRONG"])
	var sparks := (load("res://scn/vfx/sparks.tscn") as PackedScene).instantiate() as CPUParticles3D
	var stex := ((sparks.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
	print("sparks: %s" % (stex.resource_path.get_file() if stex else "no texture (squares)"))
	ok = ok and stex != null
	sparks.free()
	print("character fx: %s" % ("OK" if ok else "CHECK"))
	quit()
