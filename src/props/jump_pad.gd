extends Area3D

## Launch velocity in the pad's local space (rotate the pad to aim it).
@export var launch_velocity := Vector3(0.0, 24.0, 0.0)
## If > 0, the vertical launch speed is worked out from the character's gravity so you
## always peak this many metres up, no matter how gravity is tuned. Overrides launch_velocity.y.
@export var launch_height: float = 0.0
## Adds the pad's horizontal push to your current momentum instead of replacing it.
@export var keep_horizontal: bool = true


func _ready() -> void:
	body_entered.connect(on_body_entered)


func on_body_entered(body: Node3D) -> void:
	var c := body as Character
	if not c: return
	var vel := launch_velocity
	if launch_height > 0.0: vel.y = sqrt(2.0 * c.config.gravity * launch_height)
	c.launch(global_basis * vel, keep_horizontal)
