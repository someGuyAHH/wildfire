extends SceneTree
# In-game screenshots from fixed cameras (renders: a window opens, only when the owner allows).
# Starts a Classic match on MAPI with the bots lifted out and the clock frozen, then for each
# camera in CAMS ("x,y,z>lx,ly,lz;..."; the camera at x,y,z looking at lx,ly,lz) waits for the
# picture to settle and saves OUT/<n>.png. HUD hidden. Settings untouched (never saved).
#   MAPI=2 CAMS="0,8,60>0,15,-30" OUT=/some/dir [HIDE=Shadow] timeout 120 godot -s res://tools/checks/shot.gd
# LIVE=1: the bots stay in and play (no cheats); a camera "@i" sits 3.5 m to the side of bot i
# (i = -1: you), at chest height, looking at it ("@t" the Torch, "@tb" behind it, for its trail);
# "@<i>d": bot i (or -1, you) made to dash just before; "@<i>b": from behind (third person).
# SMOKE=1/2: you smoke; FREEZE=1: you're frozen by a hit. TORCH_BOT=1: the Torch is bot 0 (running). GAP seconds (default 1.5) between shots.
# LEAN_SHADOWS=1: the sun's shadows with the bench's three savings (2048 map, no cascade blending,
# the low soft filter), to compare against the same cameras without.
var _main: Node


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 3, 1, int(OS.get_environment("MAPI")))
	var live := OS.get_environment("LIVE") == "1"
	if not live:
		_main.call(&"toggle_cheat", &"alone")
		_main.call(&"toggle_cheat", &"freeze")
	else:
		await create_timer(6.0).timeout # through the countdown, everyone off and running
		var me := _main.get(&"_player") as Character
		if OS.get_environment("SMOKE") != "": me.set_smoke(int(OS.get_environment("SMOKE"))) # SMOKE=1/2: you smoulder / smoke
		if OS.get_environment("BOT_SMOKE") != "": _who(0).set_smoke(int(OS.get_environment("BOT_SMOKE"))) # bot 0 smokes
		if OS.get_environment("SMOKE_LAYER") != "": # (probe) your smoke on another render layer
			for p: Node in (me.get(&"_smoke_fx") as Node).get_children(): (p as VisualInstance3D).layers = int(OS.get_environment("SMOKE_LAYER"))
		if OS.get_environment("FREEZE") == "1": me.freeze(60.0) # FREEZE=1: you're frozen by a hit (the flinch)
		if OS.get_environment("TORCH_BOT") == "1": # the Torch handed to a bot (you stand still: no input)
			var tm: Node = _main.get(&"tag_manager")
			for c: Character in tm.call(&"get_participants"):
				if tm.call(&"is_torch", c): tm.call(&"_remove_torch", c)
			tm.call(&"_add_torch", _who(0))
			_main.call(&"toggle_cheat", &"no_tag") # or it tags you (standing still) straight back
			await create_timer(1.5).timeout
	for n: Node in root.find_children("*", "CanvasLayer", true, false): (n as CanvasLayer).visible = false
	if OS.get_environment("LEAN_SHADOWS") == "1":
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(1)
		for n: Node in root.find_children("*", "DirectionalLight3D", true, false): (n as DirectionalLight3D).directional_shadow_blend_splits = false
	for key: String in ["volumetric_fog_gi_inject", "volumetric_fog_density"]: # FOG_GI_INJECT / FOG_DENSITY: try other fog
		var v := OS.get_environment(key.replace("volumetric_", "").to_upper())
		if v != "":
			for w: Node in root.find_children("*", "WorldEnvironment", true, false): (w as WorldEnvironment).environment.set(key, float(v))
	if OS.get_environment("LIGHTING") != "": # the Lighting setting, in memory only (never saved)
		root.get_node(^"STG").call(&"set_value", &"lighting", float(OS.get_environment("LIGHTING")), false)
		if OS.get_environment("GI_ENERGY") != "": # try another bounce strength on the map's baked GI
			for n: Node in get_nodes_in_group(&"baked_gi"): (n as VoxelGI).data.energy = float(OS.get_environment("GI_ENERGY"))
		await create_timer(1.0).timeout
	# GI=none / sdfgi / voxel (GI_DATA, GI_CENTER, GI_SIZE as baked by bake_gi.gd; low quality, half res)
	var gi_mode := OS.get_environment("GI")
	if gi_mode != "":
		var env := (root.find_children("*", "WorldEnvironment", true, false)[-1] as WorldEnvironment).environment
		env.sdfgi_enabled = gi_mode == "sdfgi"
		if gi_mode == "voxel":
			RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW)
			RenderingServer.gi_set_use_half_resolution(true)
			var vg := VoxelGI.new()
			vg.data = load(OS.get_environment("GI_DATA"))
			if OS.get_environment("GI_ENERGY") != "": vg.data.energy = float(OS.get_environment("GI_ENERGY"))
			vg.size = _v(OS.get_environment("GI_SIZE"))
			(_main.get(&"_map") as Node3D).add_child(vg)
			vg.global_position = _v(OS.get_environment("GI_CENTER"))
		await create_timer(2.0).timeout # (SDFGI settles over time)
	var hide := OS.get_environment("HIDE") # nodes whose name ends with this are hidden (compare with / without)
	if hide != "":
		for n: Node in root.find_children("*" + hide, "Node3D", true, false): (n as Node3D).visible = false
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 3000.0
	root.add_child(cam)
	var out := OS.get_environment("OUT")
	# VARIANTS="base:;taa:taa=1;ultra:ULTRA": each a settings change (in memory only, from the
	# defaults; "ULTRA" the preset) and every camera shot again: OUT/<variant>_<n>.png
	var variants := OS.get_environment("VARIANTS").split(";", false)
	if variants.is_empty(): variants = PackedStringArray([":"])
	var stg := root.get_node(^"STG")
	for variant: String in variants:
		var vname := variant.get_slice(":", 0)
		var change := variant.get_slice(":", 1)
		if vname != "":
			for k: StringName in stg.get(&"_values"): if k in stg.GRAPHICS_KEYS or k == &"speed_fx": stg.call(&"set_value", k, stg.call(&"get_default", k), false)
			if change == "ULTRA": stg.call(&"apply_ultra", false)
			else:
				for kv: String in change.split(",", false): stg.call(&"set_value", StringName(kv.get_slice("=", 0)), float(kv.get_slice("=", 1)), false)
			for f: int in 90: await process_frame # (eye adaptation, TAA and the fog settle)
		await _shoot_all(cam, out, vname)
	print("saved %d variant(s) to %s" % [variants.size(), out])
	quit()


func _shoot_all(cam: Camera3D, out: String, vname: String) -> void:
	var live := OS.get_environment("LIVE") == "1"
	var i := 0
	for spec: String in OS.get_environment("CAMS").split(";", false):
		if spec.begins_with("@"):
			# "@t": the Torch from the side, "@tb": the Torch from behind and above (its trail)
			var torch := spec.begins_with("@t")
			var who := _torch() if torch else _who(int(spec.substr(1).trim_suffix("d").trim_suffix("b")))
			if spec.ends_with("d") and not torch:
				who.call(&"_try_dash")
				for f: int in 9: await process_frame # ~0.15 s into the dash
			var side := who.visual.global_basis.x if who.visual else Vector3.RIGHT
			cam.global_position = who.global_position + side * 3.5 + Vector3.UP * 1.3
			if spec.ends_with("d") and not torch: # "@<i>d": made to dash first; shot from the side, a little behind (the streak)
				cam.global_position = who.global_position + side * 4.0 + who.visual.global_basis.z * 2.5 + Vector3.UP * 1.6
			if spec.ends_with("b") and not torch: # "@<i>b": from behind and above, like the third-person camera
				cam.global_position = who.global_position + who.visual.global_basis.z * 3.6 + Vector3.UP * 2.3
			if spec == "@tb": cam.global_position = who.global_position + who.visual.global_basis.z * 6.0 + side * 1.5 + Vector3.UP * 2.6
			cam.look_at(who.global_position + Vector3.UP * 1.0)
			cam.fov = 45.0
		else:
			var parts := spec.split(">")
			cam.global_position = _v(parts[0])
			cam.look_at(_v(parts[1]))
			cam.fov = 80.0
		cam.make_current()
		for f: int in (2 if live else 40): await process_frame # let shadows, fog and fades settle (live: they have; the bot would run out of frame)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s%d.png" % [out, (vname + "_") if vname != "" else "", i])
		i += 1
		if live: await create_timer(float(OS.get_environment("GAP")) if OS.get_environment("GAP") != "" else 1.5).timeout


## The first Torch of the match (or the player if there's none yet).
func _torch() -> Character:
	var tm: Node = _main.get(&"tag_manager")
	for c: Character in tm.call(&"get_participants"):
		if tm.call(&"is_torch", c): return c
	return _main.get(&"_player") as Character


## Bot i of the match (-1: the player).
func _who(i: int) -> Character:
	var player := _main.get(&"_player") as Character
	if i < 0: return player
	var tm: Node = _main.get(&"tag_manager")
	var others: Array = tm.call(&"get_participants").filter(func(c: Character) -> bool: return c != player)
	return others[i % others.size()]
