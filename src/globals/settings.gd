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
const LIGHTING     := &"lighting" # 0 low, 1 high: global illumination (SDFGI) + volumetric fog
const THIRD_PERSON := &"third_person"
const PERF_HUD     := &"perf_hud" # 0 off, 1 FPS, 2 full (see perf_hud.gd)

const GRAPHICS_KEYS: Array[StringName] = [RENDER_SCALE, SSAO, GLOW, MSAA, FXAA, VSYNC, SHADOWS, LIGHTING]
## An Environment with this meta set to true gets volumetric fog on High lighting (its own fog
## numbers); others don't (Godot's default density would bury a map in fog).
const VOLUMETRIC_META := &"volumetric_fog"

# the sun's shadow map: [splits, max distance m, atlas px, soft filter (RenderingServer.ShadowQuality)].
# One 4096 map over 160 m in 2 splits made everything past ~16 m staircase-jagged.
const _SHADOW_PRESETS: Array[Array] = [
	[2, 120.0, 4096, 2],
	[4, 180.0, 4096, 3],
	[4, 240.0, 8192, 4],
]

## Mouse sensitivity is stored as a friendly number; radians per pixel = value * this.
const MOUSE_SENS_TO_RAD := 0.001

# graphics defaults are picked for integrated GPUs on high-dpi screens. measured on Iris Xe at
# 3072x1602: ssao ~10 ms, msaa 2x ~9 ms, glow ~5 ms, fog/shadows/fxaa ~free. fsr upscaling is the big win.
var _defaults: Dictionary[StringName, float] = {
	MOUSE_SENS: 5.6,
	FOV: 112.0,
	THIRD_PERSON: 0.0,
	RENDER_SCALE: 0.6,
	SSAO: 0.0,
	GLOW: 1.0,
	MSAA: 0.0,
	FXAA: 1.0,
	VSYNC: 1.0,
	SHADOWS: 1.0,
	LIGHTING: 0.0,
	PERF_HUD: 0.0,
}
var _values: Dictionary[StringName, float] = {}


func _ready() -> void:
	_values = _defaults.duplicate()
	load_settings()
	apply_graphics()


## Returns the setting's value. Unknown keys push an error and return 0.
func get_value(key: StringName) -> float:
	if not _values.has(key):
		push_error("Unknown setting '%s'" % key)
		return 0.0
	return _values[key]


func get_default(key: StringName) -> float:
	return _defaults.get(key, 0.0)


## Changes a setting and emits settings_changed. Returns true on success, false on fail.
## save=false is for slider drags; call save_settings() when you're done.
func set_value(key: StringName, value: float, save: bool = true) -> bool:
	if not _values.has(key):
		push_error("Unknown setting '%s', add it to _defaults first" % key)
		return false
	_values[key] = value
	if key in GRAPHICS_KEYS: apply_graphics()
	settings_changed.emit(key)
	if save: return save_settings()
	return true


## Puts every setting back to its default, applies graphics and saves.
## Returns true on success, false if saving failed.
func reset_to_defaults() -> bool:
	_values = _defaults.duplicate()
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
	# adaptive: a late frame tears instead of halving to 30 fps; on: never tears, but a late frame waits
	var vsync := [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_ENABLED]
	DisplayServer.window_set_vsync_mode(vsync[clampi(roundi(get_value(VSYNC)), 0, 2)])
	_apply_shadows()
	var world := vp.find_world_3d()
	var env := world.environment if world else null
	if not env: return
	env.ssao_enabled = is_on(SSAO)
	env.glow_enabled = is_on(GLOW)
	var rich := is_on(LIGHTING)
	env.sdfgi_enabled = rich
	env.volumetric_fog_enabled = rich and env.get_meta(VOLUMETRIC_META, false)


## The shadow preset onto the shadow atlas and every sun in the scene (maps bring their own).
func _apply_shadows() -> void:
	var p: Array = _SHADOW_PRESETS[clampi(roundi(get_value(SHADOWS)), 0, _SHADOW_PRESETS.size() - 1)]
	RenderingServer.directional_shadow_atlas_set_size(p[2], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p[3])
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun := n as DirectionalLight3D
		if not sun.shadow_enabled: continue
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if p[0] == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = p[1]
		sun.directional_shadow_blend_splits = p[0] == 4
		sun.directional_shadow_pancake_size = 40.0 # big casters behind the camera's slice don't get cut off
		sun.shadow_bias = 0.08
		sun.shadow_normal_bias = 1.5
		sun.shadow_blur = 1.0


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
	return true


## Returns true on success, false on fail.
func save_settings() -> bool:
	var cfg := ConfigFile.new()
	for key: StringName in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Couldn't write %s: %s" % [PATH, error_string(err)])
		return false
	return true
