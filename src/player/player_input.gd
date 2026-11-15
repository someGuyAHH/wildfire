extends Node

signal respawn_requested

const _IPCAM := preload("res://src/player/player_camera.gd")

const _SLOWMO_SCALE := 0.25

@export var character: Character
@export var camera_rig: _IPCAM
## Debug/tests only: read input even when the mouse isn't captured (headless can't capture it).
@export var require_capture: bool = true

# cruise / free look (hold middle mouse): everything held at the click (movement keys, slide,
# jump) stays held until middle mouse is released, movement in the world direction it had then,
# while the camera turns freely. keys pressed during cruise stack on top like real held keys.
var _cruise := false
var _cruise_keys := Vector2.ZERO
var _cruise_fwd := Vector3.FORWARD
var _cruise_slide := false
var _cruise_jump := false


func _ready() -> void:
	if not character or not camera_rig:
		push_error("PlayerInput needs character and camera_rig assigned")
		set_physics_process(false)
		return
	# must write the intent before the character reads it this tick
	process_physics_priority = character.process_physics_priority - 10
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	var intent := character.intent
	var cam_fwd := camera_rig.get_forward()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_capture
	if captured and Input.is_action_just_pressed(&"freelook"):
		_cruise = true
		_cruise_keys = _move_keys()
		_cruise_fwd = cam_fwd
		_cruise_slide = Input.is_action_pressed(&"slide")
		_cruise_jump = Input.is_action_pressed(&"jump")
	if _cruise and (not captured or not Input.is_action_pressed(&"freelook")): _cruise = false
	# while cruising, the body keeps facing (and dashing toward) the latched direction
	var fwd := _cruise_fwd if _cruise else cam_fwd
	intent.set_look(fwd)
	if not captured:
		# window not focused / paused: let go of everything
		intent.set_wish(Vector3.ZERO)
		intent.jump_held = false
		intent.slide_held = false
		return
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	# latched W + live A = diagonal, latched W + live S = cancel, like holding both for real
	var iv := (_cruise_keys + _move_keys()).limit_length(1.0) if _cruise else _move_keys()
	intent.set_wish(right * iv.x - fwd * iv.y)
	intent.jump_pressed = intent.jump_pressed or Input.is_action_just_pressed(&"jump")
	intent.jump_held = Input.is_action_pressed(&"jump") or (_cruise and _cruise_jump)
	intent.slide_pressed = intent.slide_pressed or Input.is_action_just_pressed(&"slide")
	intent.slide_held = Input.is_action_pressed(&"slide") or (_cruise and _cruise_slide)
	intent.dash_pressed = intent.dash_pressed or Input.is_action_just_pressed(&"dash")
	intent.brake_pressed = intent.brake_pressed or Input.is_action_just_pressed(&"brake")


## True while middle mouse cruise / free look is held.
func is_cruising() -> bool:
	return _cruise


func _move_keys() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


func _unhandled_input(event: InputEvent) -> void:
	# Esc / pause lives in the pause menu now
	if event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"respawn"):
		respawn_requested.emit()
	elif event.is_action_pressed(&"debug_slowmo"):
		Engine.time_scale = 1.0 if Engine.time_scale < 1.0 else _SLOWMO_SCALE
