class_name FireTrail
extends Ribbon
## The Torch's fire streaming behind it: a solid ribbon from its back unit back along where it ran,
## white-hot yellow at the runner through orange to red, fading. Under the flame puffs, so the
## trail stays one tongue of fire at any speed. Follows a TorchFX (its position) while it burns.

const _MAT := preload("res://assets/tres/vfx/fire_trail.tres")
const _GRADIENT := preload("res://assets/tres/vfx/fire_trail_gradient.tres")

var fx: Node3D
var burning := false


func _ready() -> void:
	super()
	material_override = _MAT
	gradient = _GRADIENT


func _sample() -> Variant:
	if burning and fx and fx.is_visible_in_tree(): return fx.global_position
	return null
