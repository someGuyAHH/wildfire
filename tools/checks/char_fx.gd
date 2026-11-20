extends SceneTree
# A character's own effects load and switch: smoke (soft round puffs: light wisps and the column) and
# the overdrive sparks (round glowing dots); every effect emitter pre-simulates its lifetime (a
# not-yet-spawned slot draws black at the emitter: the blob on a smoker's head) and casts no shadow.
# Headless.
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
		var root_fx := p.get(&"_smoke_fx") as Node3D
		var light := root_fx.get_node(^"Light") as CPUParticles3D
		var column := root_fx.get_node(^"Column") as CPUParticles3D
		var tex := ((column.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
		# each emitter keeps its own amount (changing it mid-run drew a black blob): only on/off
		var good := light.emitting == (level == Character.SMOKE_LIGHT) and column.emitting == (level == Character.SMOKE_COLUMN) \
				and light.amount == 14 and column.amount == 60 and tex is GradientTexture2D \
				and column.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and light.layers == p.body_mesh.layers \
				and light.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and column.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ok = ok and good
		print("smoke %d: light %s, column %s, %s  %s" % [level, light.emitting, column.emitting, "soft round puff" if tex is GradientTexture2D else "no texture", "ok" if good else "WRONG"])
	var sparks := (load("res://scn/vfx/sparks.tscn") as PackedScene).instantiate() as CPUParticles3D
	var stex := ((sparks.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
	print("sparks: %s" % (stex.resource_path.get_file() if stex else "no texture (squares)"))
	ok = ok and stex != null
	sparks.free()
	for path: String in ["res://scn/vfx/fire.tscn", "res://scn/vfx/smoke.tscn", "res://scn/vfx/sparks.tscn", "res://scn/vfx/tag_flash.tscn"]:
		var n := (load(path) as PackedScene).instantiate()
		var parts := ([n] + n.find_children("*", "CPUParticles3D", true, false)).filter(func(x: Node) -> bool: return x is CPUParticles3D)
		for x: CPUParticles3D in parts:
			# a slot not yet spawned draws as a black, opaque particle at the emitter: every emitter
			# switched on mid-game pre-simulates its whole lifetime (one-shots spawn all at once)
			if x.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or (not x.one_shot and x.preprocess < x.lifetime):
				print("%s/%s: shadow %s, preprocess %.2f of lifetime %.2f" % [path.get_file(), x.name, x.cast_shadow, x.preprocess, x.lifetime])
				ok = false
		n.free()
	print("character fx: %s" % ("OK" if ok else "CHECK"))
	quit()
