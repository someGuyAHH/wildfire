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
const VSYNC        := &"vsync"
const THIRD_PERSON := &"third_person"
const PERF_HUD     := &"perf_hud" # 0 off, 1 FPS, 2 full (see perf_hud.gd)

const GRAPHICS_KEYS: Array[StringName] = [RENDER_SCALE, SSAO, GLOW, MSAA, FXAA, VSYNC]

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
	# adaptive: a late frame tears a little instead of halving to 30 fps (plain fifo vsync does that)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE if is_on(VSYNC) else DisplayServer.VSYNC_DISABLED)
	var world := vp.find_world_3d()
	var env := world.environment if world else null
	if not env: return
	env.ssao_enabled = is_on(SSAO)
	env.glow_enabled = is_on(GLOW)


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
