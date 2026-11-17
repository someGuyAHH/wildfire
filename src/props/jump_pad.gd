extends Area3D

## Launch velocity in the pad's local space (rotate the pad to aim it).
@export var launch_velocity := Vector3(0.0, 24.0, 0.0)
## If > 0, the vertical launch speed is worked out from the character's gravity so you
## always peak this many metres up, no matter how gravity is tuned. Overrides launch_velocity.y.
@export var launch_height: float = 0.0
## Momentum pad: adds its horizontal push to your speed, never slows your climb, and turns a fast
## fall into a bigger bounce. Off = an aimed pad: its lob (launch_velocity) lands you on a spot,
## but it never slows you sideways: run onto it faster than the lob and you keep your own speed.
@export var keep_horizontal: bool = true
## Momentum pads only: share of your fall speed that comes back as upward speed (a slam onto the
## pad bounces you higher than walking on).
@export_range(0.0, 1.0) var fall_bounce: float = 0.7
## Aimed pads: where the lob lands (world), set by the map generator. Bots launched off the pad
## steer for it, whether they meant to take the pad or not. INF = unknown.
@export var landing := Vector3.INF


func _ready() -> void:
	body_entered.connect(on_body_entered)


# standing on it fires it too: someone who lands back on the pad (or got onto it without
# "entering", say frozen there) isn't left standing on a dead pad
func _physics_process(_delta: float) -> void:
	if not monitoring: return # parked with its map (asking anyway floods the log with errors)
	for body: Node3D in get_overlapping_bodies():
		var c := body as Character
		if c and c.is_on_floor() and not c.is_frozen(): on_body_entered(c)


func on_body_entered(body: Node3D) -> void:
	var c := body as Character
	if not c: return
	var vel := launch_velocity
	if launch_height > 0.0: vel.y = sqrt(2.0 * c.config.gravity * launch_height)
	var out := global_basis * vel
	if keep_horizontal:
		var vy := c.velocity.y
		out.y = maxf(out.y, maxf(vy, -vy * fall_bounce))
	elif Vector2(c.velocity.x, c.velocity.z).length() > Vector2(out.x, out.z).length():
		out.x = c.velocity.x # came in faster than the lob: keep it, steer the landing yourself
		out.z = c.velocity.z
	c.launch(out, keep_horizontal, landing if not keep_horizontal else Vector3.INF)
