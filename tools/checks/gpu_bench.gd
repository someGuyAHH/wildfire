extends SceneTree
# GPU cost per setting / feature on a map, measured on the real GPU: NOT headless (it renders), so
# only run it when the owner says so. Holds fixed cameras and switches one thing at a time from a
# baseline, averaging the GPU time per frame. Settings change in memory only, never saved.
#   MAPI=3 [TESTS="greybox materials,render scale 0.55"] timeout 300 godot --fixed-fps 60 -s res://tools/checks/gpu_bench.gd
# TESTS: only these (comma-separated names from the list below); default all.
# (--fixed-fps keeps physics in step; the GPU numbers come from the renderer's own timers.)
# Leave the machine alone while it runs: moving the window or playing video shares the GPU and
# wrecks the numbers. Each test is measured between two baselines (before and after), and
# reported against their mean, so the GPU clocking up or down mid-run cancels out; medians, not
# means, so a stray spike doesn't count.
const WARMUP := 45      # frames before measuring (SDFGI settles over time: it gets more)
const SAMPLES := 90
var _main: Node
var _stg: Node
var _map: Node3D
var _cam: Camera3D
var _vp: RID


func _initialize() -> void:
	_main = (load("res://scn/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _gpu_ms(frames: int) -> float:
	var t: Array[float] = []
	for i: int in frames:
		await process_frame
		t.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	t.sort()
	return t[t.size() / 2]


func _put(key: StringName, v: float) -> void:
	_stg.call(&"set_value", key, v, false) # never saved


func _swap_greybox(on: bool) -> void:
	for n: Node in _map.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.mesh: continue
		for s: int in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if on and m and m.resource_path.contains("/art/"):
				mi.set_surface_override_material(s, load(m.resource_path.replace("/art/", "/greybox/")))
			elif not on:
				mi.set_surface_override_material(s, null)


func _toggle(path: NodePath, on: bool) -> void: # maps without that node (no lava) just skip it
	var n := _map.get_node_or_null(path) as Node3D
	if n: n.visible = on


func _trees(prop: StringName, value: Variant) -> void: # every model MultiMesh (trees, crowns)
	for n: Node in _map.find_children("*", "MultiMeshInstance3D", true, false): n.set(prop, value)


var _saved_shadow := {}
func _tree_shadows(on: bool) -> void: # shadow-only twins hidden, the rest stop casting; then put back
	for n: Node in _map.find_children("*", "MultiMeshInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not on:
			_saved_shadow[g] = [g.cast_shadow, g.visible]
			if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: g.visible = false
			else: g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _saved_shadow.has(g):
			g.cast_shadow = _saved_shadow[g][0]
			g.visible = _saved_shadow[g][1]


func _water(on: bool) -> void: # every surface drawn with the water shader (river, pools)
	for n: Node in _map.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m and m.shader and m.shader.resource_path.ends_with("water.gdshader"): (n as Node3D).visible = on


var _terrain_saved: Shader
func _terrain_plain(on: bool) -> void: # the terrain on Terrain3D's own lightweight shader (no anti-tiling)
	var t := _map.get_node_or_null(^"Terrain3D")
	if not t: return
	var mat: Object = t.get(&"material")
	if on:
		_terrain_saved = mat.get(&"shader_override")
		mat.set(&"shader_override", load("res://addons/terrain_3d/extras/shaders/lightweight.gdshader"))
	elif _terrain_saved:
		mat.set(&"shader_override", _terrain_saved)


func _sun() -> DirectionalLight3D:
	return _map.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D


func _run() -> void:
	_stg = root.get_node(^"STG")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await create_timer(1.0).timeout
	_main.call(&"_start_match", 0, 7, 1, int(OS.get_environment("MAPI")))
	_map = _main.get(&"_map") as Node3D
	_main.call(&"toggle_cheat", &"freeze")
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	_cam.far = 3000.0
	root.add_child(_cam)
	var keys: Array[StringName] = [&"render_scale", &"ssao", &"glow", &"msaa", &"fxaa", &"vsync", &"shadows", &"lighting", &"leaf_shadows"]
	var saved := {}
	for k: StringName in keys: saved[k] = _stg.call(&"get_value", k)
	# the owner's settings from their screenshot (2026-11-19, an exported build) as the baseline
	# (vsync off here so the frame isn't held to the refresh)
	var base := {&"render_scale": 0.55, &"ssao": 0.0, &"glow": 0.0, &"msaa": 0.0, &"fxaa": 1.0, &"vsync": 0.0, &"shadows": 1.0, &"lighting": 0.0, &"leaf_shadows": 2.0}
	var tests: Array = [
		["baseline", func() -> void: pass, func() -> void: pass],
		["glow off", func() -> void: _put(&"glow", 0.0), func() -> void: _put(&"glow", 1.0)],
		["shadows Low", func() -> void: _put(&"shadows", 0.0), func() -> void: _put(&"shadows", 1.0)],
		["shadows High", func() -> void: _put(&"shadows", 2.0), func() -> void: _put(&"shadows", 1.0)],
		["sun shadows off", func() -> void: _sun().shadow_enabled = false, func() -> void: _sun().shadow_enabled = true],
		["lighting High", func() -> void: _put(&"lighting", 1.0), func() -> void: _put(&"lighting", 0.0)],
		["SSAO on", func() -> void: _put(&"ssao", 1.0), func() -> void: _put(&"ssao", 0.0)],
		["FXAA on", func() -> void: _put(&"fxaa", 1.0), func() -> void: _put(&"fxaa", 0.0)],
		["render scale 0.5", func() -> void: _put(&"render_scale", 0.5), func() -> void: _put(&"render_scale", 0.6)],
		["render scale 0.55", func() -> void: _put(&"render_scale", 0.55), func() -> void: _put(&"render_scale", 0.6)],
		["render scale 0.8", func() -> void: _put(&"render_scale", 0.8), func() -> void: _put(&"render_scale", 0.6)],
		["greybox materials", func() -> void: _swap_greybox(true), func() -> void: _swap_greybox(false)],
		["lava hidden", func() -> void: _toggle(^"Lava", false), func() -> void: _toggle(^"Lava", true)],
		["brazier lights off", func() -> void: _toggle(^"Lights", false), func() -> void: _toggle(^"Lights", true)],
		["trees hidden", func() -> void: _trees(&"visible", false), func() -> void: _trees(&"visible", true)],
		["leaf shadows Off", func() -> void: _put(&"leaf_shadows", 0.0), func() -> void: _put(&"leaf_shadows", 2.0)],
		["leaf shadows Low", func() -> void: _put(&"leaf_shadows", 1.0), func() -> void: _put(&"leaf_shadows", 2.0)],
		["leaf shadows High", func() -> void: _put(&"leaf_shadows", 3.0), func() -> void: _put(&"leaf_shadows", 2.0)],
		["tree shadows off", _tree_shadows.bind(false), _tree_shadows.bind(true)],
		["water hidden", func() -> void: _water(false), func() -> void: _water(true)],
		["LOD off", func() -> void: root.mesh_lod_threshold = 0.0, func() -> void: root.mesh_lod_threshold = 1.0],
		["occlusion culling off", func() -> void: root.use_occlusion_culling = false, func() -> void: root.use_occlusion_culling = true],
		["terrain plain shader", _terrain_plain.bind(true), _terrain_plain.bind(false)],
		["depth fog off", func() -> void: _env().fog_enabled = false, func() -> void: _env().fog_enabled = true],
	]
	var views_by_map := {
		1: [["Overworld aqueduct", Vector3(60, 20, -20), Vector3(150, 13, -55)], ["Overworld overview", Vector3(0, 120, 150), Vector3(0, 0, 0)], ["Overworld meadow", Vector3(0, 3, 40), Vector3(60, 2, -40)]],
		2: [["Jungle temple from the plaza", Vector3(0, 8, 60), Vector3(0, 15, -30)], ["Jungle forest floor", Vector3(-100, 6, 40), Vector3(-130, 8, 20)], ["Jungle river", Vector3(108, 5, -40), Vector3(124.4, -2, -24.4)]],
		3: [["Basilica nave", Vector3(0, 7, 96), Vector3(0, 3, 200)], ["map overview", Vector3(7, 161, 99), Vector3(0, 0, 0)]],
	}
	var views: Array = views_by_map.get(int(OS.get_environment("MAPI")), views_by_map[3])
	var size := root.get_visible_rect().size
	print("window %dx%d" % [size.x, size.y])
	for v: Array in views:
		_cam.global_position = v[1]
		_cam.look_at(v[2])
		_cam.make_current()
		for k: StringName in base: _put(k, base[k])
		print("== %s" % v[0])
		await _gpu_ms(WARMUP)
		var before: float = await _gpu_ms(SAMPLES)
		print("  %-20s %6.2f ms GPU" % ["baseline", before])
		var only := OS.get_environment("TESTS").split(",", false)
		for t: Array in tests:
			if t[0] == "baseline" or (not only.is_empty() and not only.has(t[0])): continue
			(t[1] as Callable).call()
			await _gpu_ms(WARMUP * (4 if t[0] == "lighting High" else 1))
			var ms: float = await _gpu_ms(SAMPLES)
			(t[2] as Callable).call()
			await _gpu_ms(WARMUP * (4 if t[0] == "lighting High" else 1))
			var after: float = await _gpu_ms(SAMPLES)
			var base_ms := (before + after) * 0.5
			print("  %-20s %6.2f ms GPU  (%+6.2f vs baseline %.2f)" % [t[0], ms, ms - base_ms, base_ms])
			before = after
	for k: StringName in saved: _put(k, saved[k])
	quit()


func _env() -> Environment:
	return (_map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
