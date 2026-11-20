extends SceneTree
# GPU cost per setting / feature on a map, measured on the real GPU: NOT headless (it renders), so
# only run it when the owner says so. Holds fixed cameras and switches one thing at a time from a
# baseline, averaging the GPU time per frame. Settings change in memory only, never saved.
#   MAPI=3 [DEFAULTS=1] [FULL=1] [VIEWS="forest"] [TESTS="greybox materials,render scale 0.55"] timeout 300 godot --fixed-fps 60 -s res://tools/checks/gpu_bench.gd
# VoxelGI tests: GI_DATA=res://assets/gi/<map>_voxelgi.res GI_CENTER="x,y,z" GI_SIZE="x,y,z" (as baked).
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


var _path: PackedVector2Array = [] # a fly-through view: the camera follows this (xz) every measurement
const PATH_SAMPLES := 480 # frames to fly the whole path (8 s at 60 fps)
const PATH_HEIGHT := 3.5  # metres over the ground, about a third-person camera's


var _wall := 0.0 # the last measurement's whole-frame time (ms, wall clock): includes GPU work outside the viewport's own timer (e.g. VoxelGI re-lighting its cells)
func _gpu_ms(frames: int) -> float:
	var t: Array[float] = []
	var w: Array[float] = []
	var last := Time.get_ticks_usec()
	if not _path.is_empty(): frames = PATH_SAMPLES if frames == SAMPLES else frames
	for i: int in frames:
		if not _path.is_empty(): _fly(float(i) / frames if frames == PATH_SAMPLES else 0.0)
		await process_frame
		t.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
		var now := Time.get_ticks_usec()
		w.append((now - last) / 1000.0)
		last = now
	t.sort()
	w.sort()
	_wall = w[w.size() / 2]
	return t[t.size() / 2]


## The camera at fraction f of the path, PATH_HEIGHT over the ground, looking along it.
func _fly(f: float) -> void:
	var total := 0.0
	for i: int in _path.size() - 1: total += _path[i].distance_to(_path[i + 1])
	var at := _along(f * total)
	var ahead := _along(minf(f * total + 10.0, total + 10.0))
	_cam.global_position = Vector3(at.x, _ground(at) + PATH_HEIGHT, at.y)
	var look := Vector3(ahead.x, _ground(ahead) + PATH_HEIGHT - 1.0, ahead.y)
	if look.distance_to(_cam.global_position) > 0.5: _cam.look_at(look)


func _along(d: float) -> Vector2:
	for i: int in _path.size() - 1:
		var seg := _path[i].distance_to(_path[i + 1])
		if d <= seg: return _path[i].lerp(_path[i + 1], d / seg)
		d -= seg
	var last := _path[_path.size() - 1]
	return last + (last - _path[_path.size() - 2]).normalized() * d


func _ground(p: Vector2) -> float: # the terrain's own height (a ray would land on tree trunks and decks)
	var t := _map.get_node_or_null(^"Terrain3D")
	if not t: return 0.0
	var h: float = (t.get(&"data") as Object).call(&"get_height", Vector3(p.x, 0.0, p.y))
	return h if not is_nan(h) else 0.0


func _v(s: String) -> Vector3:
	var f := s.split_floats(",")
	return Vector3(f[0], f[1], f[2])


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


func _terrain_param(key: StringName, value: Variant) -> void: # one of terrain_art.gdshader's switches
	var t := _map.get_node_or_null(^"Terrain3D")
	if not t: return
	var mat := t.get(&"material") as Object
	mat.call(&"set_shader_param", key, value)
	if key == &"side_start": mat.call(&"set_shader_param", &"side_full", 0.0 if value < 0.5 else 0.62) # side-on off: both edges at 0


var _terrain_art: Shader
func _terrain_variant(drop: Array) -> void: # terrain_art.gdshader compiled without those features ([] = back)
	var t := _map.get_node_or_null(^"Terrain3D")
	if not t: return
	var mat := t.get(&"material") as Object
	if not _terrain_art: _terrain_art = mat.get(&"shader_override")
	if drop.is_empty():
		mat.set(&"shader_override", _terrain_art)
		return
	var sh := Shader.new()
	var code := _terrain_art.code
	for line: String in drop: code = code.replace(line, "")
	sh.code = code
	mat.set(&"shader_override", sh)


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


var _hidden_layers: Array[CanvasLayer] = []
func _hud(on: bool) -> void: # every UI layer (HUD overlays: momentum, dizzy, speed lines, minimap)
	if not on:
		for n: Node in root.find_children("*", "CanvasLayer", true, false):
			if (n as CanvasLayer).visible:
				(n as CanvasLayer).visible = false
				_hidden_layers.append(n)
	else:
		for cl: CanvasLayer in _hidden_layers: cl.visible = true
		_hidden_layers.clear()


var _hud_node: Node
func _overlay(which: Array, on: bool, params: Dictionary = {}) -> void: # the speed overlays at full speed (the frozen player's HUD would hide them)
	if not _hud_node: _hud_node = _main.get_node(^"Player/Hud")
	_hud_node.set_process(not on)
	for name: String in which:
		var r := _hud_node.get_node(name) as CanvasItem
		r.visible = on
		var m := (r as CanvasItem).material as ShaderMaterial
		if not on:
			for k: StringName in params: m.set_shader_parameter(k, _overlay_saved.get(k))
			continue
		if name == "MomentumFX": m.set_shader_parameter(&"speed", 1.0)
		if name == "SpeedLines": m.set_shader_parameter(&"intensity", 1.0)
		for k: StringName in params:
			if not _overlay_saved.has(k): _overlay_saved[k] = m.get_shader_parameter(k)
			m.set_shader_parameter(k, params[k])
var _overlay_saved := {}


var _trunk_saved := {}
func _trunk_shadows(on: bool) -> void: # tree trunks (Trunk*, Tree*Wood) stop casting; then put back
	for n: Node in _map.find_children("*", "MultiMeshInstance3D", true, false):
		if not (n.name.begins_with("Trunk") or n.name.ends_with("Wood")): continue
		var g := n as GeometryInstance3D
		if not on:
			_trunk_saved[g] = g.cast_shadow
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _trunk_saved.has(g):
			g.cast_shadow = _trunk_saved[g]
	if on: _trunk_saved.clear()


func _sun_knob(prop: StringName, value: Variant) -> void: # one sun-shadow property; settings put it all back
	if prop == &"atlas": RenderingServer.directional_shadow_atlas_set_size(int(value), true)
	elif prop == &"filter": RenderingServer.directional_soft_shadow_filter_set_quality(int(value))
	else: _sun().set(prop, value)


var _lump_ends := {}
func _lumps_end(metres: float) -> void: # the far crowns' stand-in shadow lumps stop at this distance (0 = back to their own)
	for n: Node in get_nodes_in_group(&"shadow_far"):
		var g := n as GeometryInstance3D
		if not _lump_ends.has(g): _lump_ends[g] = g.visibility_range_end
		g.visibility_range_end = metres if metres > 0.0 else _lump_ends[g]


func _sun_combo(lumps: float) -> void: # the three wins together: 2048 map, no cascade blend, low filter (+ lump range)
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(1)
	_sun().directional_shadow_blend_splits = false
	if lumps > 0.0: _lumps_end(lumps)


func _sun_combo_back() -> void:
	_lumps_end(0.0)
	_stg.call(&"apply_graphics")


var _voxel: VoxelGI
func _voxel_gi(on: bool, fog: bool = false) -> void: # the baked VoxelGI (assets/gi/<map>_voxelgi.res) instead of SDFGI
	if on:
		_voxel = VoxelGI.new()
		_voxel.data = load(OS.get_environment("GI_DATA"))
		_voxel.size = _v(OS.get_environment("GI_SIZE")) # where and how big it was baked (bake_gi.gd's CENTER, SIZE)
		_map.add_child(_voxel)
		_voxel.global_position = _v(OS.get_environment("GI_CENTER"))
		_env().sdfgi_enabled = false
		_env().volumetric_fog_enabled = fog
	elif _voxel:
		_voxel.queue_free()
		_voxel = null
		_env().volumetric_fog_enabled = false


func _chars_out_of_gi(out: bool) -> void: # every character's meshes, particles and lights out of the GI
	for c: Node in root.find_children("*", "CharacterBody3D", true, false):
		for n: Node in c.find_children("*", "", true, false):
			if n is GeometryInstance3D: (n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED if out else GeometryInstance3D.GI_MODE_STATIC
			elif n is Light3D: (n as Light3D).light_bake_mode = Light3D.BAKE_DISABLED if out else Light3D.BAKE_DYNAMIC


func _map_lights_static(on: bool) -> void: # the map's own lights not re-lit into the GI every frame
	for n: Node in _map.find_children("*", "Light3D", true, false):
		(n as Light3D).light_bake_mode = Light3D.BAKE_STATIC if on else Light3D.BAKE_DYNAMIC


func _ultra_off(base: Dictionary) -> void: # back from ULTRA to the run's baseline, premium effects off
	for k: StringName in [&"taa", &"ssr", &"ssil", &"soft_shadows", &"fog_detail", &"auto_exposure", &"glow_hq"]: _put(k, 0.0)
	for k: StringName in base: _put(k, base[k])


func _hide_named(suffix: String, hide: bool) -> void: # model MultiMeshes whose name ends with suffix (Leaves, Wood, Shadow, LeavesShadow)
	for n: Node in _map.find_children("*", "MultiMeshInstance3D", true, false):
		if String(n.name).ends_with(suffix): (n as Node3D).visible = not hide


func _group_hidden(group: StringName, hide: bool) -> void:
	for n: Node in get_nodes_in_group(group): (n as Node3D).visible = not hide


func _sun_restore() -> void:
	_stg.call(&"apply_graphics")


func _sun() -> DirectionalLight3D:
	return _map.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D


func _run() -> void:
	_stg = root.get_node(^"STG")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	if OS.get_environment("FULL") == "1": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN) # the overlays cost per screen pixel
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
	var keys: Array[StringName] = [&"render_scale", &"ssao", &"glow", &"msaa", &"fxaa", &"vsync", &"shadows", &"lighting", &"leaf_shadows",
			&"taa", &"ssr", &"ssil", &"soft_shadows", &"fog_detail", &"auto_exposure", &"glow_hq", &"live_gi", &"fast_shadows", &"speed_fx"]
	var saved := {}
	for k: StringName in keys: saved[k] = _stg.call(&"get_value", k)
	# the owner's settings from their screenshot (2026-11-19, an exported build) as the baseline
	# (vsync off here so the frame isn't held to the refresh)
	var base := {&"render_scale": 0.55, &"ssao": 0.0, &"glow": 0.0, &"msaa": 0.0, &"fxaa": 1.0, &"vsync": 0.0, &"shadows": 1.0, &"lighting": 0.0, &"leaf_shadows": 2.0}
	if OS.get_environment("DEFAULTS") == "1": # the game's defaults instead (vsync still off)
		for k: StringName in base: base[k] = _stg.call(&"get_default", k)
		base[&"vsync"] = 0.0
	for kv: String in OS.get_environment("SETTINGS").split(",", false): # e.g. SETTINGS="glow=0,lighting=1": on top of the baseline
		base[StringName(kv.get_slice("=", 0))] = float(kv.get_slice("=", 1))
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
		["HUD hidden", _hud.bind(false), _hud.bind(true)],
		["LOD off", func() -> void: root.mesh_lod_threshold = 0.0, func() -> void: root.mesh_lod_threshold = 1.0],
		["occlusion culling off", func() -> void: root.use_occlusion_culling = false, func() -> void: root.use_occlusion_culling = true],
		["terrain no anti-tiling", _terrain_param.bind(&"detile_enabled", false), _terrain_param.bind(&"detile_enabled", true)],
		["terrain no side-on rock", _terrain_param.bind(&"side_start", 0.001), _terrain_param.bind(&"side_start", 0.78)],
		["terrain no macro variation", _terrain_param.bind(&"macro_variation_enabled", false), _terrain_param.bind(&"macro_variation_enabled", true)],
		["terrain built w/o anti-tiling", _terrain_variant.bind(["#define TERRAIN_DETILE"]), _terrain_variant.bind([])],
		["terrain built w/o side-on rock", _terrain_variant.bind(["#define TERRAIN_SIDE"]), _terrain_variant.bind([])],
		["terrain built w/o both", _terrain_variant.bind(["#define TERRAIN_DETILE", "#define TERRAIN_SIDE"]), _terrain_variant.bind([])],
		["terrain plain shader", _terrain_plain.bind(true), _terrain_plain.bind(false)],
		["momentum overlay", _overlay.bind(["MomentumFX"], true), _overlay.bind(["MomentumFX"], false)],
		["momentum overdrive", _overlay.bind(["MomentumFX"], true, {&"overdrive": 1.0}), _overlay.bind(["MomentumFX"], false, {&"overdrive": 1.0})],
		["momentum blur 3", _overlay.bind(["MomentumFX"], true, {&"blur_samples": 3}), _overlay.bind(["MomentumFX"], false, {&"blur_samples": 3})],
		["momentum blur 1", _overlay.bind(["MomentumFX"], true, {&"blur_samples": 1}), _overlay.bind(["MomentumFX"], false, {&"blur_samples": 1})],
		["momentum Medium", _overlay.bind(["MomentumFX"], true, {&"detail": 2}), _overlay.bind(["MomentumFX"], false, {&"detail": 2})],
		["momentum Low", _overlay.bind(["MomentumFX"], true, {&"detail": 1}), _overlay.bind(["MomentumFX"], false, {&"detail": 1})],
		["speed lines", _overlay.bind(["SpeedLines"], true), _overlay.bind(["SpeedLines"], false)],
		["screen copy off", func() -> void: _main.get_node(^"Player/Hud/MomentumCopy").visible = false, func() -> void: _main.get_node(^"Player/Hud/MomentumCopy").visible = true],
		["both overlays", _overlay.bind(["MomentumFX", "SpeedLines"], true), _overlay.bind(["MomentumFX", "SpeedLines"], false)],
		["trunk shadows off", _trunk_shadows.bind(false), _trunk_shadows.bind(true)],
		["sun reach 120 m", _sun_knob.bind(&"directional_shadow_max_distance", 120.0), _sun_restore],
		["sun reach 90 m", _sun_knob.bind(&"directional_shadow_max_distance", 90.0), _sun_restore],
		["sun 2 cascades", _sun_knob.bind(&"directional_shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS), _sun_restore],
		["sun map 2048", _sun_knob.bind(&"atlas", 2048), _sun_restore],
		["sun filter low", _sun_knob.bind(&"filter", 1), _sun_restore],
		["sun filter hard", _sun_knob.bind(&"filter", 0), _sun_restore],
		["sun no cascade blend", _sun_knob.bind(&"directional_shadow_blend_splits", false), _sun_restore],
		["lumps end 120 m", _lumps_end.bind(120.0), _lumps_end.bind(0.0)],
		["lumps end 90 m", _lumps_end.bind(90.0), _lumps_end.bind(0.0)],
		["three sun wins", _sun_combo.bind(0.0), _sun_combo_back],
		["three wins + lumps 120", _sun_combo.bind(120.0), _sun_combo_back],
		["VoxelGI", _voxel_gi.bind(true), _voxel_gi.bind(false)],
		["VoxelGI + vol. fog", _voxel_gi.bind(true, true), _voxel_gi.bind(false)],
		["VoxelGI low quality", func() -> void: RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW); _voxel_gi(true), func() -> void: _voxel_gi(false); RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_HIGH)],
		["VoxelGI half res", func() -> void: RenderingServer.gi_set_use_half_resolution(true); _voxel_gi(true), func() -> void: _voxel_gi(false); RenderingServer.gi_set_use_half_resolution(false)],
		["VoxelGI low + half", func() -> void: RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW); RenderingServer.gi_set_use_half_resolution(true); _voxel_gi(true), func() -> void: _voxel_gi(false); RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_HIGH); RenderingServer.gi_set_use_half_resolution(false)],
		["lighting High one bounce", func() -> void: _put(&"lighting", 1.0); for n: Node in get_nodes_in_group(&"baked_gi"): (n as VoxelGI).data.use_two_bounces = false, func() -> void: _put(&"lighting", 0.0); for n: Node in get_nodes_in_group(&"baked_gi"): (n as VoxelGI).data.use_two_bounces = true],
		["lighting High GI hidden", func() -> void: _put(&"lighting", 1.0); for n: Node in get_nodes_in_group(&"baked_gi"): (n as VoxelGI).visible = false, func() -> void: _put(&"lighting", 0.0)],
		["lighting Low", func() -> void: _put(&"lighting", 0.0), func() -> void: _put(&"lighting", 1.0)],
		["characters out of GI", _chars_out_of_gi.bind(true), _chars_out_of_gi.bind(false)],
		["map lights static", _map_lights_static.bind(true), _map_lights_static.bind(false)],
		["lighting High lights static", func() -> void: _map_lights_static(true); _put(&"lighting", 1.0), func() -> void: _put(&"lighting", 0.0); _map_lights_static(false)],
		["both out of GI", func() -> void: _chars_out_of_gi(true); _map_lights_static(true), func() -> void: _chars_out_of_gi(false); _map_lights_static(false)],
		["map effects hidden", func() -> void: for n: Node in _map.find_children("*", "Node3D", true, false): if n is LavaSparks or n is WaterfallSpray: (n as Node3D).visible = false, func() -> void: for n: Node in _map.find_children("*", "Node3D", true, false): if n is LavaSparks or n is WaterfallSpray: (n as Node3D).visible = true],
		["TAA", func() -> void: _put(&"taa", 1.0); _put(&"fxaa", 0.0), func() -> void: _put(&"taa", 0.0); _put(&"fxaa", 1.0)],
		["reflections", func() -> void: _put(&"ssr", 1.0), func() -> void: _put(&"ssr", 0.0)],
		["coloured bounce", func() -> void: _put(&"ssil", 1.0), func() -> void: _put(&"ssil", 0.0)],
		["soft shadows", func() -> void: _put(&"soft_shadows", 1.0), func() -> void: _put(&"soft_shadows", 0.0)],
		["detailed shafts", func() -> void: _put(&"lighting", 1.0); _put(&"fog_detail", 1.0), func() -> void: _put(&"fog_detail", 0.0); _put(&"lighting", 0.0)],
		["eye adaptation", func() -> void: _put(&"auto_exposure", 1.0), func() -> void: _put(&"auto_exposure", 0.0)],
		["smooth glow", func() -> void: _put(&"glow_hq", 1.0), func() -> void: _put(&"glow_hq", 0.0)],
		["live GI", func() -> void: _put(&"live_gi", 1.0), func() -> void: _put(&"live_gi", 0.0)],
		["ULTRA", func() -> void: _stg.call(&"apply_ultra", false), _ultra_off.bind(base)],
		["leaves hidden", _hide_named.bind("Leaves", true), _hide_named.bind("Leaves", false)],
		["trunks hidden", _hide_named.bind("Wood", true), _hide_named.bind("Wood", false)],
		["near leaf shadows off", _group_hidden.bind(&"shadow_near", true), _group_hidden.bind(&"shadow_near", false)],
		["far lump shadows off", _group_hidden.bind(&"shadow_far", true), _group_hidden.bind(&"shadow_far", false)],
		["global shadow defaults", func() -> void: _put(&"leaf_shadows", 2.0); _put(&"fast_shadows", 0.0), func() -> void: _put(&"leaf_shadows", _stg.call(&"get_default", &"leaf_shadows")); _put(&"fast_shadows", _stg.call(&"get_default", &"fast_shadows"))],
		["depth fog off", func() -> void: _env().fog_enabled = false, func() -> void: _env().fog_enabled = true],
	]
	var views_by_map := {
		1: [["Overworld fly-through (bots live)", PackedVector2Array([Vector2(0, 60), Vector2(60, -40), Vector2(120, -60), Vector2(40, -150), Vector2(-80, -120), Vector2(-130, 150)]), null], ["Overworld aqueduct", Vector3(60, 20, -20), Vector3(150, 13, -55)], ["Overworld overview", Vector3(0, 120, 150), Vector3(0, 0, 0)], ["Overworld meadow", Vector3(0, 3, 40), Vector3(60, 2, -40)]],
		2: [["Jungle forest fly-through (bots live)", PackedVector2Array([Vector2(70, 72), Vector2(-20, 82), Vector2(-95, 52), Vector2(-135, 0), Vector2(-120, -60), Vector2(-60, -100)]), null], ["Jungle forest, owner's 3rd person", Vector3(2, 5, 43), Vector3(-60, 2, 22)], ["Jungle temple from the plaza", Vector3(0, 8, 60), Vector3(0, 15, -30)], ["Jungle forest floor", Vector3(-100, 6, 40), Vector3(-130, 8, 20)], ["Jungle river", Vector3(108, 5, -40), Vector3(124.4, -2, -24.4)], ["Jungle waterfall", Vector3(-48, 6, -132), Vector3(-55, 0, -158)], ["Jungle temple far through leaves", Vector3(-150, 5, 110), Vector3(0, 15, -30)], ["Jungle temple hall", Vector3(10, 4, -36), Vector3(-15, 4, -30)]],
		3: [["Inferno fly-through (bots live)", PackedVector2Array([Vector2(0, 95), Vector2(0, 215), Vector2(45, 190), Vector2(-40, 130), Vector2(-120, 30), Vector2(-200, 0)]), null], ["Basilica nave", Vector3(0, 7, 96), Vector3(0, 3, 200)], ["map overview", Vector3(7, 161, 99), Vector3(0, 0, 0)]],
	}
	var views: Array = views_by_map.get(int(OS.get_environment("MAPI")), views_by_map[3])
	print("window %dx%d (3D renders at that times the render scale; the UI's logical size is %s)" % [root.size.x, root.size.y, root.get_visible_rect().size])
	var only_views := OS.get_environment("VIEWS")
	for v: Array in views:
		if only_views != "" and not (v[0] as String).contains(only_views): continue
		var flying: bool = v[1] is PackedVector2Array
		_path = v[1] if flying else PackedVector2Array()
		if flying:
			_main.call(&"toggle_cheat", &"freeze") # bots off and running for the fly-through
			_fly(0.0)
		else:
			_cam.global_position = v[1]
			_cam.look_at(v[2])
		_cam.make_current()
		for k: StringName in base: _put(k, base[k])
		print("== %s" % v[0])
		await _gpu_ms(WARMUP)
		var before: float = await _gpu_ms(SAMPLES)
		print("  %-20s %6.2f ms GPU   frame %6.2f ms" % ["baseline", before, _wall])
		var only := OS.get_environment("TESTS").split(",", false)
		for t: Array in tests:
			if t[0] == "baseline" or (not only.is_empty() and not only.has(t[0])): continue
			(t[1] as Callable).call()
			await _gpu_ms(WARMUP * (4 if t[0] == "lighting High" else 1))
			var ms: float = await _gpu_ms(SAMPLES)
			var wall_ms := _wall
			(t[2] as Callable).call()
			await _gpu_ms(WARMUP * (4 if t[0] == "lighting High" else 1))
			var after: float = await _gpu_ms(SAMPLES)
			var base_ms := (before + after) * 0.5
			print("  %-20s %6.2f ms GPU  (%+6.2f vs baseline %.2f)   frame %6.2f ms (baseline %.2f)" % [t[0], ms, ms - base_ms, base_ms, wall_ms, _wall])
			before = after
		if flying: _main.call(&"toggle_cheat", &"freeze") # back to frozen for the fixed views
	for k: StringName in saved: _put(k, saved[k])
	quit()


func _env() -> Environment:
	return (_map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
