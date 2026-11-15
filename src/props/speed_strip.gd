extends Area3D

## Horizontal speed (m/s) pushed along the strip's -Z while you're on it.
@export var boost_speed: float = 30.0

var _riders: Array[Character] = []


func _ready() -> void:
	body_entered.connect(on_body_entered)
	body_exited.connect(on_body_exited)


func _physics_process(_delta: float) -> void:
	var fwd := -global_basis.z
	for c: Character in _riders:
		c.boost(fwd, boost_speed)


func on_body_entered(body: Node3D) -> void:
	var c := body as Character
	if c and not _riders.has(c): _riders.append(c)


func on_body_exited(body: Node3D) -> void:
	var c := body as Character
	if c: _riders.erase(c)
