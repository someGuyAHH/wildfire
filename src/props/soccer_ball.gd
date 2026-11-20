class_name SoccerBall
extends RigidBody3D
## A giant inflatable soccer ball to knock about (the Overworld's crater). It rolls and bounces on
## the world, but characters pass through it (it isn't on their collision mask: running into it
## at speed mustn't stop you dead or bonk you); instead its Kick area feels them coming and knocks
## it away along the line from them to its middle, as hard as they hit it, a bit up and spinning.
## Anyone standing still in it nudges it off. Back home at the start of every round, and if it
## falls out of the world. Parked with its map (the map stops processing: out of the simulation).

const _MATS := {
	&"white": preload("res://assets/tres/materials/props/ball_white.tres"),
	&"black": preload("res://assets/tres/materials/props/ball_black.tres"),
	&"seam": preload("res://assets/tres/materials/props/ball_seam.tres"),
}

## How much of a character's closing speed the ball comes away with (over 1: it's light).
@export var kick_mult: float = 1.35
## Share of the kick that goes up as well, so it lofts.
@export var kick_lift: float = 0.35
## The least kick (m/s), for someone walking or standing into it.
@export var nudge: float = 3.0
## Seconds before the same character can kick it again (they're still inside it after a kick).
@export var kick_cooldown: float = 0.3
@export var max_speed: float = 45.0
## Fell this far below home: put back.
@export var fall_reset: float = 60.0

@onready var _kick: Area3D = $Kick
var _home: Transform3D
var _cool: Dictionary[Character, float] = {}
var _tm: Node # the TagManager, found once in the tree (rounds put the ball back home)


func _ready() -> void:
	_home = global_transform
	var mesh := find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	for i: int in mesh.mesh.get_surface_count():
		var m: Material = _MATS.get(StringName(mesh.mesh.surface_get_material(i).resource_name))
		if m: mesh.set_surface_override_material(i, m)


func _physics_process(delta: float) -> void:
	if not _kick.monitoring: return # parked with its map
	_watch_rounds()
	for c: Character in _cool.keys():
		_cool[c] -= delta
		if _cool[c] <= 0.0 or not is_instance_valid(c): _cool.erase(c)
	var me := global_position
	for body: Node3D in _kick.get_overlapping_bodies():
		var c := body as Character
		if not c or c.is_frozen() or _cool.has(c): continue
		var n := (me - (c.global_position + Vector3.UP * 0.9)).normalized()
		var closing := (c.velocity - linear_velocity).dot(n)
		var hit := maxf(closing * kick_mult, nudge)
		linear_velocity += n * hit + Vector3.UP * hit * kick_lift
		angular_velocity += n.cross(Vector3.UP) * -hit * 0.25
		_cool[c] = kick_cooldown
	if linear_velocity.length() > max_speed: linear_velocity = linear_velocity.normalized() * max_speed
	if me.y < _home.origin.y - fall_reset: go_home()


## Back to where the map put it, still.
func go_home() -> void:
	global_transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _watch_rounds() -> void:
	if _tm: return
	_tm = get_tree().root.find_child("TagManager", true, false)
	if _tm and _tm.has_signal(&"phase_changed"):
		_tm.connect(&"phase_changed", func(phase: int) -> void: if phase == TagManager.PHASE_COUNTDOWN: go_home())
