extends CanvasLayer

const _ITUNE := preload("res://src/hud/tuning_panel.gd")
const _IHELP := preload("res://src/hud/help_overlay.gd")

@export var character: Character
## Screen warp while dizzy (stun or wall-bonk). First child so it only warps the 3D view.
@export var dizzy_fx: ColorRect
## Blue edges, flames + motion blur over 20 m/s (fast enough to body-slam someone).
@export var momentum_fx: ColorRect
## Re-copies the screen so momentum stacks on top of the dizzy warp. Only on when both show.
@export var momentum_copy: BackBufferCopy
## Turns cyan while you're fast enough to body-slam.
@export var crosshair: ColorRect
@export var speed_lines: ColorRect
@export var debug_label: Label
@export var tuning_panel: _ITUNE
@export var help_overlay: _IHELP
## Speed (m/s) where speed lines start / reach full strength.
@export var lines_speed_min: float = 15.0
@export var lines_speed_max: float = 34.0
## Speed where the momentum effect is at full strength (it snaps in at the slam threshold).
@export var momentum_full_speed: float = 32.0
@export var charged_crosshair := Color(0.45, 0.95, 1.0)

var _lines_mat: ShaderMaterial
var _dizzy_mat: ShaderMaterial
var _momentum_mat: ShaderMaterial
var _speed_fx := 0.0
var _crosshair_color := Color.WHITE


func _ready() -> void:
	if not character or not speed_lines or not debug_label:
		push_error("PlayerHud is missing references")
		set_process(false)
		return
	_lines_mat = speed_lines.material as ShaderMaterial
	if dizzy_fx: _dizzy_mat = dizzy_fx.material as ShaderMaterial
	if momentum_fx: _momentum_mat = momentum_fx.material as ShaderMaterial
	if crosshair: _crosshair_color = crosshair.color
	debug_label.visible = OS.is_debug_build()
	# call down: the panels need the character to read/tune its config
	if tuning_panel: tuning_panel.setup(character)
	if help_overlay: help_overlay.setup(character)


func _process(delta: float) -> void:
	var speed := character.get_horizontal_speed()
	_update_momentum(speed, delta)
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


## Snaps in at the slam threshold (20 m/s), grows to momentum_full_speed.
func _update_momentum(speed: float, delta: float) -> void:
	if not _momentum_mat: return
	var threshold := character.config.wall_bonk_speed
	var speed_target := 0.0
	if speed >= threshold:
		speed_target = lerpf(0.55, 1.0, clampf(inverse_lerp(threshold, momentum_full_speed, speed), 0.0, 1.0))
	# fast in, slower out so it doesn't flicker on the edge
	_speed_fx = move_toward(_speed_fx, speed_target, delta * (8.0 if speed_target > _speed_fx else 3.0))
	momentum_fx.visible = _speed_fx > 0.005 # hidden = zero cost
	if momentum_fx.visible: _momentum_mat.set_shader_parameter(&"speed", _speed_fx)
	if momentum_copy: momentum_copy.visible = momentum_fx.visible and dizzy_fx and dizzy_fx.visible
	if crosshair: crosshair.color = _crosshair_color.lerp(charged_crosshair, clampf(_speed_fx / 0.55, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_hud"): debug_label.visible = not debug_label.visible
