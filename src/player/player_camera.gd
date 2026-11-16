extends Node3D

# render layer 2 = "first_person_hidden" (see project settings)
const _HIDDEN_LAYER := 2
const _WORLD_MASK   := 1
const _TP_MIN_DIST  := 0.35
const _STEP_EASE_RATE := 20.0
const _SNAP_RATE      := 35.0   # free-look snap-back: ~0.1 s to get there
const _SNAP_DONE      := 0.002  # radians

@export var character: Character
@export var camera: Camera3D
# mouse sensitivity and base FOV live in STG (user settings)
## Radians per second at full stick tilt.
@export var stick_sensitivity: float = 3.6
@export var max_fov_add: float = 16.0
## Speed range (m/s) mapped onto 0..max_fov_add.
@export var fov_speed_min: float = 13.0
@export var fov_speed_max: float = 34.0
@export var dash_fov_kick: float = 7.0
@export var wall_tilt_deg: float = 7.0
@export var strafe_tilt_deg: float = 1.6
@export var landing_dip_max: float = 0.35
## Camera sway while dizzy-stunned (radians at full dizziness).
@export var dizzy_sway: float = 0.14
## Zoom punch (negative FOV kick) and dip when you bonk a wall.
@export var bonk_fov_punch: float = -10.0
@export var bonk_dip: float = 0.25

@export_group("Third person")
@export var tp_distance: float = 4.2
## Height above the eye pivot.
@export var tp_height: float = 0.5
## Sideways offset, positive = over the right shoulder.
@export var tp_shoulder: float = 0.45
## Radius of the sphere swept toward the camera so it never ends up inside a wall.
@export var tp_probe_radius: float = 0.25
## How fast the boom extends back out after being pushed in by a wall.
@export var tp_return_speed: float = 6.0

var _yaw := 0.0
var _pitch := 0.0
var _roll := 0.0
var _eye := 0.0
var _step_ease := 0.0 # negative right after a step-up, eases back to 0
# free look: where the view pointed when it started, and whether we're easing back there
var _free_yaw := 0.0
var _free_pitch := 0.0
var _snapping := false
# a step pop is spread over one physics tick by physics interpolation, so it's only cancelled as
# fast as it actually shows up on screen (cancelling it all at once dips the view for a frame)
var _step_pending := 0.0
var _step_tick := 0
var _dip := 0.0
var _fov_kick := 0.0
var _sway_t := 0.0
var _mouse_sens := 0.0
var _base_fov := 0.0
var _third_person := false
var _tp_dist := 0.0
var _tp_probe := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	if not character or not camera:
		push_error("PlayerCamera needs character and camera assigned")
		set_process(false)
		return
	# we follow the interpolated transform by hand every frame, so no engine interpolation here
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply_settings()
	STG.settings_changed.connect(on_settings_changed)
	camera.fov = _base_fov
	_hide_body(character.visual)
	# your own name tag is useless to you, and as the Torch it renders huge on top of the view
	if character.name_tag: character.name_tag.visible = false
	var sphere := SphereShape3D.new()
	sphere.radius = tp_probe_radius
	_tp_probe.shape = sphere
	_tp_probe.collision_mask = _WORLD_MASK
	_tp_probe.exclude = [character.get_rid()]
	_tp_dist = tp_distance
	_yaw = character.visual.rotation.y if character.visual else 0.0
	_eye = character.get_eye_height()
	character.landed.connect(on_character_landed)
	character.dashed.connect(on_character_dashed)
	character.stepped_up.connect(on_character_stepped_up)
	character.wall_bonked.connect(on_character_wall_bonked)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_camera"):
		STG.set_value(STG.THIRD_PERSON, 0.0 if _third_person else 1.0)
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var motion := event as InputEventMouseMotion
	if not motion: return
	_snapping = false # looking around yourself wins over the snap-back
	_yaw -= motion.screen_relative.x * _mouse_sens
	_pitch = clampf(_pitch - motion.screen_relative.y * _mouse_sens, -PI * 0.495, PI * 0.495)


func _process(delta: float) -> void:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO: _snapping = false
	if _snapping:
		var k := 1.0 - exp(-_SNAP_RATE * delta)
		_yaw = lerp_angle(_yaw, _free_yaw, k)
		_pitch = lerpf(_pitch, _free_pitch, k)
		if absf(angle_difference(_yaw, _free_yaw)) < _SNAP_DONE and absf(_pitch - _free_pitch) < _SNAP_DONE:
			_yaw = _free_yaw
			_pitch = _free_pitch
			_snapping = false
	_yaw -= stick.x * stick_sensitivity * delta
	_pitch = clampf(_pitch - stick.y * stick_sensitivity * delta, -PI * 0.495, PI * 0.495)

	var origin := character.get_global_transform_interpolated().origin
	# follow the body exactly; only real auto-step pops (announced by the character) get eased.
	# guessing steps from "rising fast while grounded" saw-toothed on steep slopes and pad launches
	_step_ease = lerpf(_step_ease, 0.0, 1.0 - exp(-_STEP_EASE_RATE * delta))
	var step_partial := 0.0
	if _step_pending:
		if Engine.get_physics_frames() > _step_tick:
			_step_ease -= _step_pending # fully on screen now, ease it from here
			_step_pending = 0.0
		else:
			step_partial = -_step_pending * Engine.get_physics_interpolation_fraction()
	_eye = lerpf(_eye, character.get_eye_height(), 1.0 - exp(-14.0 * delta))
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-9.0 * delta))
	global_position = Vector3(origin.x, origin.y + _step_ease + step_partial + _eye + _dip, origin.z)
	# dizzy sway: detuned sines on every axis so it feels drunk, not periodic
	var dizzy := character.get_dizziness()
	_sway_t = _sway_t + delta if dizzy > 0.0 else 0.0
	var sway := Vector3(sin(_sway_t * 2.3) * 0.5, sin(_sway_t * 1.7), sin(_sway_t * 3.1 + 1.0)) \
			* dizzy_sway * dizzy
	rotation = Vector3(0.0, _yaw + sway.y, 0.0)

	_roll = lerpf(_roll, _target_roll(), 1.0 - exp(-10.0 * delta))
	camera.rotation = Vector3(_pitch + sway.x, 0.0, _roll + sway.z)
	camera.position = _boom(delta) if _third_person else Vector3.ZERO

	var t := clampf(inverse_lerp(fov_speed_min, fov_speed_max, character.get_horizontal_speed()), 0.0, 1.0)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-6.0 * delta))
	var target_fov := _base_fov + max_fov_add * t + _fov_kick + sin(_sway_t * 2.6) * 5.0 * dizzy
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-8.0 * delta))


## Horizontal forward of the view (-Z rotated by yaw).
func get_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Free look started: remember where the view points now.
func begin_free_look() -> void:
	_free_yaw = _yaw
	_free_pitch = _pitch
	_snapping = false


## Free look ended: snap (fast ease) back to where the view pointed when it started.
func end_free_look() -> void:
	_snapping = true


func on_settings_changed(_key: StringName) -> void:
	_apply_settings()


func on_character_landed(impact_speed: float) -> void:
	_dip = -clampf(impact_speed * 0.012, 0.0, landing_dip_max)


func on_character_stepped_up(height: float) -> void:
	# cancel the pop, then ease it back in over ~0.15 s (see _process for the interpolation dance)
	_step_pending += height
	_step_tick = Engine.get_physics_frames()


func on_character_dashed(_dir: Vector3) -> void:
	_fov_kick = dash_fov_kick


func on_character_wall_bonked(_impact_speed: float) -> void:
	_fov_kick = bonk_fov_punch
	_dip = -bonk_dip


func _apply_settings() -> void:
	_mouse_sens = STG.get_value(STG.MOUSE_SENS) * STG.MOUSE_SENS_TO_RAD
	_base_fov = STG.get_value(STG.FOV)
	_third_person = STG.is_on(STG.THIRD_PERSON)
	# own body only shows up in third person (shadow shows in both)
	if _third_person: camera.cull_mask |= _HIDDEN_LAYER
	else: camera.cull_mask &= ~_HIDDEN_LAYER


## Third-person camera offset in rig space. Orbits the eye pivot with pitch and sweeps a
## sphere out to it; walls pull the camera in instantly, it eases back out after.
func _boom(delta: float) -> Vector3:
	var local := Basis(Vector3.RIGHT, _pitch) * Vector3(tp_shoulder, tp_height, tp_distance)
	var motion := global_basis * local
	_tp_probe.transform = Transform3D(Basis.IDENTITY, global_position)
	_tp_probe.motion = motion
	var frac := get_world_3d().direct_space_state.cast_motion(_tp_probe)
	var want := maxf(local.length() * frac[0], _TP_MIN_DIST)
	if want < _tp_dist: _tp_dist = want
	else: _tp_dist = lerpf(_tp_dist, want, 1.0 - exp(-tp_return_speed * delta))
	return local.normalized() * _tp_dist


func _target_roll() -> float:
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	if character.is_wall_sliding():
		# lean away from the wall
		return deg_to_rad(wall_tilt_deg) * signf(character.get_last_wall_normal().dot(right))
	var side := character.velocity.dot(right) / maxf(character.config.max_speed, 0.01)
	return -deg_to_rad(strafe_tilt_deg) * clampf(side, -1.0, 1.0)


func _hide_body(root: Node) -> void:
	if not root: return
	for child: Node in root.get_children():
		_hide_body(child)
	var vi := root as VisualInstance3D
	if vi: vi.layers = _HIDDEN_LAYER
