extends Node

signal respawn_requested

const _IPCAM := preload("res://src/player/player_camera.gd")

const _SLOWMO_SCALE := 0.25

@export var character: Character
@export var camera_rig: _IPCAM


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
	var fwd := camera_rig.get_forward()
	intent.set_look(fwd)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# window not focused / paused: let go of everything
		intent.set_wish(Vector3.ZERO)
		intent.jump_held = false
		intent.slide_held = false
		return
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var iv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	intent.set_wish(right * iv.x - fwd * iv.y)
	intent.jump_pressed = intent.jump_pressed or Input.is_action_just_pressed(&"jump")
	intent.jump_held = Input.is_action_pressed(&"jump")
	intent.slide_pressed = intent.slide_pressed or Input.is_action_just_pressed(&"slide")
	intent.slide_held = Input.is_action_pressed(&"slide")
	intent.dash_pressed = intent.dash_pressed or Input.is_action_just_pressed(&"dash")
	intent.brake_pressed = intent.brake_pressed or Input.is_action_just_pressed(&"brake")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"respawn"):
		respawn_requested.emit()
	elif event.is_action_pressed(&"debug_slowmo"):
		Engine.time_scale = 1.0 if Engine.time_scale < 1.0 else _SLOWMO_SCALE
