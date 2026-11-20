class_name DashTrail
extends Ribbon
## A streak left behind a dash: a glowing ribbon through the points the runner's chest passed,
## in the character's own colour. Records while the character dashes (and a moment after, so the
## tail eases out).

const _MAT := preload("res://assets/tres/vfx/dash_trail.tres")

## Height (m) of the streak over the character's feet.
@export var height: float = 1.05
## Seconds it keeps recording after the dash ends.
@export var tail_time: float = 0.08

var character: Character
var _tail := 0.0


func _ready() -> void:
	super()
	material_override = _MAT


func _sample() -> Variant:
	if not character: return null
	if character.body_mesh: layers = character.body_mesh.layers # your own stays out of your first-person view
	var dashing := character.get_state() == Character.ST_DASHING
	_tail = tail_time if dashing else _tail - get_process_delta_time()
	if _tail <= 0.0 or not character.visible: return null
	return character.get_global_transform_interpolated().origin + Vector3.UP * height
