extends CanvasLayer

const _ITUNE := preload("res://src/hud/tuning_panel.gd")
const _IHELP := preload("res://src/hud/help_overlay.gd")

@export var character: Character
## Screen warp while dizzy (stun or wall-bonk). First child so it only warps the 3D view.
@export var dizzy_fx: ColorRect
@export var speed_lines: ColorRect
@export var debug_label: Label
@export var tuning_panel: _ITUNE
@export var help_overlay: _IHELP
## Speed (m/s) where speed lines start / reach full strength.
@export var lines_speed_min: float = 15.0
@export var lines_speed_max: float = 34.0

var _lines_mat: ShaderMaterial
var _dizzy_mat: ShaderMaterial


func _ready() -> void:
	if not character or not speed_lines or not debug_label:
		push_error("PlayerHud is missing references")
		set_process(false)
		return
	_lines_mat = speed_lines.material as ShaderMaterial
	if dizzy_fx: _dizzy_mat = dizzy_fx.material as ShaderMaterial
	debug_label.visible = OS.is_debug_build()
	# call down: the panels need the character to read/tune its config
	if tuning_panel: tuning_panel.setup(character)
	if help_overlay: help_overlay.setup(character)


func _process(_delta: float) -> void:
	var speed := character.get_horizontal_speed()
	if _dizzy_mat:
		var d := character.get_dizziness()
		dizzy_fx.visible = d > 0.001 # hidden = zero cost when you're fine
		if dizzy_fx.visible: _dizzy_mat.set_shader_parameter(&"strength", d)
	if _lines_mat:
		var t := clampf(inverse_lerp(lines_speed_min, lines_speed_max, speed), 0.0, 1.0)
		_lines_mat.set_shader_parameter(&"intensity", t)
	if not debug_label.visible: return
	debug_label.text = "%5.1f m/s  (%3.0f km/h)\nvert  %5.1f m/s\nstate %s\ndash  %.2f / %d\nwalls %d\ndizzy %3.0f%%  disor %.1fs\npos   %s\nfps   %d%s" % [
		speed, speed * 3.6, character.velocity.y, character.get_state_name(),
		character.get_dash_charges(), character.config.dash_charges,
		character.get_wall_jumps_left(), character.get_dizzy_meter() * 100.0, character.get_disorient_time(),
		character.global_position.snappedf(0.1),
		Engine.get_frames_per_second(), "  [slowmo]" if Engine.time_scale < 1.0 else ""]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_hud"): debug_label.visible = not debug_label.visible
