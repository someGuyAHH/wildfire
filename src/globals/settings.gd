"""
Player-facing settings (look sensitivity, FOV, graphics), persisted to user://settings.cfg.
Autoloaded as STG. Read with get_value(), change with set_value(), listen to settings_changed.
Graphics settings apply themselves; call apply_graphics() after loading a map.
Toggles are stored as 0.0 / 1.0 so everything fits one typed dictionary.
"""

extends Node

signal settings_changed(key: StringName)

const PATH    := "user://settings.cfg"
const SECTION := "player"

# keys
const MOUSE_SENS   := &"mouse_sensitivity"
const FOV          := &"fov"
const RENDER_SCALE := &"render_scale"
const SSAO         := &"ssao"
const GLOW         := &"glow"
const MSAA         := &"msaa"
const FXAA         := &"fxaa"
const VSYNC        := &"vsync"   # 0 off, 1 adaptive (tears a late frame), 2 on (never tears)
const SHADOWS      := &"shadows" # 0 low, 1 medium, 2 high (see _SHADOW_PRESETS)
const LIGHTING     := &"lighting" # 0 low, 1 high: baked bounce light (a map's VoxelGI) + volumetric fog
const LEAF_SHADOWS := &"leaf_shadows" # 0 off, 1 low, 2 medium, 3 high (see _apply_leaf_shadows)
const FAST_SHADOWS := &"fast_shadows" # on: the sun's shadows cheaper and harder-edged (see _apply_shadows)
const THIRD_PERSON := &"third_person"
const PERF_HUD     := &"perf_hud" # 0 off, 1 FPS, 2 full (see perf_hud.gd)
const CAMERA_SHAKE := &"camera_shake" # the slam-jump's jolt: 0 off, 1 low (half), 2 full (see player_camera.gd)
const SPEED_FX     := &"speed_fx" # the overlays when you're fast: 0 off, 1 low, 2 medium, 3 high (see player_hud.gd)
# volumes, percent 0..100, one per audio bus (SFX applies them: src/audio/sfx.gd)
const VOL_MASTER   := &"vol_master"
const VOL_MUSIC    := &"vol_music"
const VOL_SFX      := &"vol_sfx"
const VOL_UI       := &"vol_ui"
const VOL_AMBIENCE := &"vol_ambience"
# premium effects (off by default: for strong GPUs; ULTRA turns them all on, all but LIVE_GI)
const SSR          := &"ssr"          # screen-space reflections (lava, pools, the river)
const SSIL         := &"ssil"         # screen-space indirect light (colour bleeding: lava on walls)
const TAA          := &"taa"          # temporal anti-aliasing (no shimmer on leaves; smooths soft shadows)
const SOFT_SHADOWS := &"soft_shadows" # contact-hardening sun shadows: sharp where they touch, soft further off
const FOG_DETAIL   := &"fog_detail"   # volumetric fog at twice the resolution: crisper sun shafts
const AUTO_EXPOSURE := &"auto_exposure" # eye adaptation: dark halls and canopy brighten, the sky blooms on the way out
const GLOW_HQ      := &"glow_hq"      # smoother (bicubic) glow
const LIVE_GI      := &"live_gi"      # SDFGI: live bounce light everywhere (heavy, worst when moving fast)

const GRAPHICS_KEYS: Array[StringName] = [RENDER_SCALE, SSAO, GLOW, MSAA, FXAA, VSYNC, SHADOWS, LIGHTING, LEAF_SHADOWS, FAST_SHADOWS,
		SSR, SSIL, TAA, SOFT_SHADOWS, FOG_DETAIL, AUTO_EXPOSURE, GLOW_HQ, LIVE_GI]
## ULTRA: every premium effect and the top settings, for strong GPUs (owner, 2026-11-20). Live GI
## (SDFGI) isn't in it: it's its own switch, the one that sinks a frame rate on its own.
const ULTRA: Dictionary[StringName, float] = {
	RENDER_SCALE: 1.0, SSAO: 1.0, GLOW: 1.0, MSAA: 0.0, FXAA: 0.0, TAA: 1.0, SHADOWS: 2.0, LEAF_SHADOWS: 3.0,
	FAST_SHADOWS: 0.0, LIGHTING: 1.0, SPEED_FX: 3.0, SSR: 1.0, SSIL: 1.0, SOFT_SHADOWS: 1.0, FOG_DETAIL: 1.0,
	AUTO_EXPOSURE: 1.0, GLOW_HQ: 1.0,
}
## An Environment with this meta set to true gets volumetric fog on High lighting (its own fog
## numbers); others don't (Godot's default density would bury a map in fog).
const VOLUMETRIC_META := &"volumetric_fog"

# the sun's shadow map: [splits, max distance m, atlas px, soft filter (RenderingServer.ShadowQuality)].
# One 4096 map over 160 m in 2 splits made everything past ~16 m staircase-jagged.
# Low was [2, 120 m, 4096, soft 2] and measured 1.5-4.3 ms SLOWER than Medium on the Jungle (two
# splits each spanning far more of the trees' alpha-cut cards): now a smaller, shorter, harder map.
# Every preset uses the cheapest soft filter (1): the softer ones (Medium had 3, High 4) blur the
# edge with a per-pixel noise pattern that Godot leaves to TAA to smooth out; at render scale 0.55
# with FXAA it showed as a pixelly grain over every shadow (owner, 2026-11-20: "looks worse than
# Low"), and cost 0.7-1.2 ms more in the forest. Medium and High keep their bigger maps and reach.
const _SHADOW_PRESETS: Array[Array] = [
	[2, 90.0, 2048, 1],
	[4, 180.0, 4096, 1],
	[4, 240.0, 8192, 1],
]

## Mouse sensitivity is stored as a friendly number; radians per pixel = value * this.
const MOUSE_SENS_TO_RAD := 0.001

# graphics defaults: the owner's pick (2026-11-20), a starting point for an integrated GPU (Iris Xe
# at 3072 x 1728): render scale 0.55, FXAA, adaptive VSync, Medium shadows and leaf shadows, Lighting
# Low, Medium speed effects; SSAO, glow, MSAA and the premium effects off. (Older notes: ssao ~10 ms, msaa 2x ~9 ms, glow 1.4-3 ms; fsr upscaling is the big win.)
var _defaults: Dictionary[StringName, float] = {
	MOUSE_SENS: 5.6,
	FOV: 112.0,
	THIRD_PERSON: 0.0,
	RENDER_SCALE: 0.55, # 0.6 -> 0.55 (2026-11-18): Iris Xe ran ~22 ms at 0.6 once it clocked down
	SSAO: 0.0,
	GLOW: 0.0,
	MSAA: 0.0,
	FXAA: 1.0,
	VSYNC: 1.0,
	SHADOWS: 1.0,
	LIGHTING: 0.0,
	LEAF_SHADOWS: 2.0,
	FAST_SHADOWS: 0.0, # (on saves ~3.6-4.1 ms in the Jungle's forest, but up close the edges go jagged)
	PERF_HUD: 0.0,
	CAMERA_SHAKE: 2.0,
	SPEED_FX: 2.0, # Medium ~2.3 ms at full speed on Iris Xe (High ~3.1-3.6, Low ~1.0-1.3)
	SSR: 0.0,
	SSIL: 0.0,
	TAA: 0.0,
	SOFT_SHADOWS: 0.0,
	FOG_DETAIL: 0.0,
	AUTO_EXPOSURE: 0.0,
	GLOW_HQ: 0.0,
	LIVE_GI: 0.0,
	VOL_MASTER: 80.0,
	VOL_MUSIC: 70.0,
	VOL_SFX: 100.0,
	VOL_UI: 80.0,
	VOL_AMBIENCE: 80.0,
}
var _values: Dictionary[StringName, float] = {}
# Per-map defaults: a map can bring its own defaults for some settings (GameMap.graphics_defaults:
# the Jungle's shadows are lighter). While it's loaded those keys read the player's own choice for
# that map, or failing one, the map's default; changing them there is remembered for that map only
# (cfg section "map_<name>"). Everything else is global.
var _map_name := ""
var _map_defaults: Dictionary = {}               # key -> the current map's default
var _map_values: Dictionary[String, Dictionary] = {} # map name -> {key: the player's choice there}


func _ready() -> void:
	_values = _defaults.duplicate()
	load_settings()
	apply_graphics()


## Returns the setting's value. Unknown keys push an error and return 0.
func get_value(key: StringName) -> float:
	if not _values.has(key):
		push_error("Unknown setting '%s'" % key)
		return 0.0
	if _map_defaults.has(key): return float(_map_values.get(_map_name, {}).get(key, _map_defaults[key]))
	return _values[key]


## The default this setting has here (the current map's own, if it brings one).
func get_default(key: StringName) -> float:
	if _map_defaults.has(key): return float(_map_defaults[key])
	return _defaults.get(key, 0.0)


## The map now loaded and its own defaults (GameMap.graphics_defaults); applies graphics.
func set_map(map_name: String, defaults: Dictionary) -> void:
	_map_name = map_name
	_map_defaults = {}
	for k: Variant in defaults: if _values.has(StringName(k)): _map_defaults[StringName(k)] = float(defaults[k])
	apply_graphics()
	for k: StringName in _map_defaults: settings_changed.emit(k)


func _store(key: StringName, value: float) -> void:
	if _map_defaults.has(key):
		if not _map_values.has(_map_name): _map_values[_map_name] = {}
		_map_values[_map_name][key] = value
	else:
		_values[key] = value


## Changes a setting and emits settings_changed. Returns true on success, false on fail.
## save=false is for slider drags; call save_settings() when you're done.
func set_value(key: StringName, value: float, save: bool = true) -> bool:
	if not _values.has(key):
		push_error("Unknown setting '%s', add it to _defaults first" % key)
		return false
	_store(key, value)
	if key in GRAPHICS_KEYS: apply_graphics()
	settings_changed.emit(key)
	if save: return save_settings()
	return true


## The ULTRA preset: every premium effect and the top settings (see ULTRA), applied and saved.
## save=false: in memory only (checks).
func apply_ultra(save: bool = true) -> bool:
	for key: StringName in ULTRA: _store(key, ULTRA[key])
	apply_graphics()
	for key: StringName in ULTRA: settings_changed.emit(key)
	return save_settings() if save else true


## Puts every setting back to its default, applies graphics and saves.
## Returns true on success, false if saving failed.
func reset_to_defaults() -> bool:
	_values = _defaults.duplicate()
	_map_values.erase(_map_name) # this map's own choices too (back to its defaults)
	apply_graphics()
	for key: StringName in _values.keys(): settings_changed.emit(key)
	return save_settings()


func is_on(key: StringName) -> bool:
	return get_value(key) > 0.5


## Pushes graphics settings onto the root viewport, the window and the active 3D environment.
## Call it again after a map loads, since that brings a new WorldEnvironment.
func apply_graphics() -> void:
	var vp := get_tree().root
	var scale := clampf(get_value(RENDER_SCALE), 0.25, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.msaa_3d = Viewport.MSAA_2X if is_on(MSAA) else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if is_on(FXAA) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = is_on(TAA)
	# fog detail: the froxel grid the volumetric fog is computed on (64 x 64 x 64 by default)
	var fog_res := 128 if is_on(FOG_DETAIL) else 64
	RenderingServer.environment_set_volumetric_fog_volume_size(fog_res, fog_res)
	# adaptive: a late frame tears instead of halving to 30 fps; on: never tears, but a late frame waits
	var vsync := [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_ENABLED]
	DisplayServer.window_set_vsync_mode(vsync[clampi(roundi(get_value(VSYNC)), 0, 2)])
	_apply_shadows()
	_apply_leaf_shadows()
	var world := vp.find_world_3d()
	var env := world.environment if world else null
	if not env: return
	env.ssao_enabled = is_on(SSAO)
	if env.ssao_enabled: _tune_ssao(env)
	env.glow_enabled = is_on(GLOW)
	var rich := is_on(LIGHTING)
	# High: the map's baked bounce light (VoxelGI, tools/mapgen/bake_gi.gd). It used to be SDFGI,
	# which rebuilds round the camera as it moves: +12 ms standing, +31 ms flying through the
	# Inferno, 80 ms frames at full speed, for a barely visible change. Baked: +1.7-2.9 ms.
	# Live GI (SDFGI): its own switch (heavy, worst moving fast), apart from Lighting High
	env.sdfgi_enabled = is_on(LIVE_GI)
	for n: Node in get_tree().get_nodes_in_group(&"baked_gi"): n.set(&"enabled", rich) # (BakedGI: may show only near it)
	env.volumetric_fog_enabled = rich and env.get_meta(VOLUMETRIC_META, false)
	env.ssr_enabled = is_on(SSR)
	if env.ssr_enabled:
		env.ssr_max_steps = 96
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
	env.ssil_enabled = is_on(SSIL)
	if env.ssil_enabled:
		env.ssil_radius = 4.0
		env.ssil_intensity = 1.0
	RenderingServer.environment_glow_set_use_bicubic_upscale(is_on(GLOW_HQ)) # (renderer-wide)
	_apply_exposure(vp)


## Eye adaptation: the scene's exposure follows how bright the view is (dark halls and canopy brighten
## after a moment, the sky blooms on the way out). A practical CameraAttributes on the map's
## WorldEnvironment, kept on its meta so it's only ours to take away.
func _apply_exposure(vp: Viewport) -> void:
	for n: Node in vp.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if is_on(AUTO_EXPOSURE):
			if not we.camera_attributes:
				var ca := CameraAttributesPractical.new()
				ca.auto_exposure_enabled = true
				ca.auto_exposure_scale = 0.2
				ca.auto_exposure_speed = 0.6
				ca.auto_exposure_min_sensitivity = 50.0
				ca.auto_exposure_max_sensitivity = 120.0 # (400 brightened the Jungle ~50% and blew out the Inferno's lit floors: owner)
				we.camera_attributes = ca
				we.set_meta(&"auto_exposure_ours", true)
		elif we.get_meta(&"auto_exposure_ours", false):
			we.camera_attributes = null
			we.remove_meta(&"auto_exposure_ours")


## Ambient occlusion that darkens where things meet (corners, under ledges, round feet), not
## the whole ground: Godot's defaults reach 300 m out and read every bump in the ground textures'
## normal maps as a crevice, so an open field went dark and blotchy. No fine detail pass, a
## gentler, wider occlusion, and none past ~90 m.
func _tune_ssao(env: Environment) -> void:
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.ssao_power = 1.8
	env.ssao_detail = 0.0
	env.ssao_horizon = 0.08
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.0
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 30.0, 90.0)


## The shadow preset onto the shadow atlas and every sun in the scene (maps bring their own).
func _apply_shadows() -> void:
	var p: Array = _SHADOW_PRESETS[clampi(roundi(get_value(SHADOWS)), 0, _SHADOW_PRESETS.size() - 1)]
	# Fast shadows: a map no bigger than 2048 and no blending between the cascades (the filter is
	# already the cheapest). Measured 2026-11-20 on Iris Xe at 3072 x 1728 (Jungle forest, defaults otherwise):
	# -4.1 ms flying through with bots about, -3.6 / -4.0 ms in fixed views. Up close shadow edges
	# turn hard and stair-stepped, so it's a choice, not the default.
	var fast := is_on(FAST_SHADOWS)
	# soft shadows: contact-hardening (the sun gets a size in the sky: PCSS) with a smooth filter.
	# The smooth filter's noise wants TAA to settle it (without, it showed as grain at 0.55 scale)
	var soft := is_on(SOFT_SHADOWS) and not fast
	RenderingServer.directional_shadow_atlas_set_size(mini(p[2], 2048) if fast else p[2], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(4 if soft else (mini(p[3], 1) if fast else p[3]))
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun := n as DirectionalLight3D
		if not sun.shadow_enabled: continue
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if p[0] == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = p[1]
		sun.directional_shadow_blend_splits = p[0] == 4 and not fast
		sun.directional_shadow_pancake_size = 40.0 # big casters behind the camera's slice don't get cut off
		sun.shadow_bias = 0.08
		sun.shadow_normal_bias = 1.5
		sun.shadow_blur = 1.0
		sun.light_angular_distance = 1.2 if soft else 0.0 # degrees across: how fast the penumbra widens


## Tree crowns cast detailed, dappled shadows from their leaf cards up close (the "shadow_near"
## group) and blobby ones from cheap stand-in lumps further out ("shadow_far"); both hand over at
## the map's own distance (meta "shadow_distance"). Off: neither. Low: lumps only, everywhere.
## Medium: the map's distance. High: twice as far. (Maps without trees have neither group.)
func _apply_leaf_shadows() -> void:
	var level := clampi(roundi(get_value(LEAF_SHADOWS)), 0, 3)
	var scale: float = [0.0, 0.0, 1.0, 2.0][level]
	for n: Node in get_tree().get_nodes_in_group(&"shadow_near"):
		var g := n as GeometryInstance3D
		g.visible = level >= 2
		g.visibility_range_end = float(g.get_meta(&"shadow_distance", 45.0)) * scale
	for n: Node in get_tree().get_nodes_in_group(&"shadow_far"):
		var g := n as GeometryInstance3D
		g.visible = level >= 1
		g.visibility_range_begin = float(g.get_meta(&"shadow_distance", 45.0)) * scale


## Returns true on success, false on fail. A missing file isn't a fail, you just get defaults.
func load_settings() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err == ERR_FILE_NOT_FOUND: return true
	if err != OK:
		push_error("Couldn't read %s: %s" % [PATH, error_string(err)])
		return false
	for key: StringName in _values.keys():
		_values[key] = float(cfg.get_value(SECTION, key, _values[key]))
	for section: String in cfg.get_sections():
		if not section.begins_with("map_"): continue
		var mine := {}
		for key: String in cfg.get_section_keys(section): mine[StringName(key)] = float(cfg.get_value(section, key))
		_map_values[section.trim_prefix("map_")] = mine
	return true


## Returns true on success, false on fail.
func save_settings() -> bool:
	var cfg := ConfigFile.new()
	for key: StringName in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	for map_name: String in _map_values:
		for key: StringName in _map_values[map_name]: cfg.set_value("map_" + map_name, key, _map_values[map_name][key])
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Couldn't write %s: %s" % [PATH, error_string(err)])
		return false
	return true
