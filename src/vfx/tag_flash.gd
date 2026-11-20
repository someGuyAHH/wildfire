class_name TagFlash
extends Node3D
## The burst when someone is set alight: sparks flung out, a ring of fire swelling and fading, a
## flash of light. Plays once where it's put, then frees itself.

const LIFE := 1.0
const FLASH_ENERGY := 7.0
const FLASH_TIME := 0.35


func _ready() -> void:
	($Burst as CPUParticles3D).emitting = true
	($Ring as CPUParticles3D).emitting = true
	var light := $Light as OmniLight3D
	light.light_energy = FLASH_ENERGY
	create_tween().tween_property(light, ^"light_energy", 0.0, FLASH_TIME).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(LIFE, false).timeout.connect(queue_free)


## Render layers for the particles (your own flash stays out of your first-person face).
func set_layers(layers: int) -> void:
	($Burst as CPUParticles3D).layers = layers
	($Ring as CPUParticles3D).layers = layers
