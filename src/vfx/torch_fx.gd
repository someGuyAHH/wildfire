class_name TorchFX
extends Node3D
## The Torch's fire: flames off the runner's back unit (a small white-hot core at their root),
## embers shed behind it, a flickering warm light, and scorch marks left on the ground every few
## steps, fading. The particles are in world
## space, so running stretches the flames and embers into a trail; running fast adds a second
## spray of embers (Trail). Follows its anchor (a point on the runner's back unit,
## RunnerBody.back_anchor()) every frame; without one, the character's chest.

const _SCORCH_TEX := preload("res://assets/tres/vfx/scorch.tres")
const _SCORCH_MAX := 24 # a ring of decals reused, per Torch

## Ground travelled (m) between scorch marks.
@export var scorch_spacing: float = 1.3
## Seconds a scorch mark takes to fade away.
@export var scorch_life: float = 6.0
## Faster than this (m/s), a second spray of embers streams off behind (the trail).
@export var trail_speed: float = 8.0

@onready var _flames: CPUParticles3D = $Flames
@onready var _core: CPUParticles3D = $Core
@onready var _embers: CPUParticles3D = $Embers
@onready var _trail: CPUParticles3D = $Trail
@onready var _light: OmniLight3D = $Light

var _character: Character
var _anchor: Node3D
var _on := false
var _marks: Array[Decal] = []
var _ages: Array[float] = []
var _next_mark := 0
var _last_mark := Vector3.INF
var _flicker := 0.0


func setup(character: Character, anchor: Node3D) -> void:
	_character = character
	_anchor = anchor


## Render layers for the particles (the local player's own fire is hidden in first person).
func set_layers(layers: int) -> void:
	_flames.layers = layers
	_core.layers = layers
	_embers.layers = layers
	_trail.layers = layers


func set_on(on: bool) -> void:
	_on = on
	_flames.emitting = on
	_core.emitting = on
	_embers.emitting = on
	_light.visible = on
	if not on:
		_trail.emitting = false
		_last_mark = Vector3.INF


func _process(delta: float) -> void:
	if not _character: return
	global_position = _anchor.global_position if is_instance_valid(_anchor) else _character.global_position + Vector3.UP * 1.3
	_age_marks(delta)
	if not _on: return
	var fast := _character.get_horizontal_speed() > trail_speed
	if _trail.emitting != fast: _trail.emitting = fast
	_flicker += delta * 17.0
	_light.light_energy = 1.6 + sin(_flicker) * 0.25 + sin(_flicker * 2.3) * 0.15
	if _character.is_on_floor():
		var at := _character.global_position
		if _last_mark == Vector3.INF or at.distance_to(_last_mark) >= scorch_spacing:
			_mark(at)
			_last_mark = at


func _mark(at: Vector3) -> void:
	var d: Decal
	if _marks.size() < _SCORCH_MAX:
		d = Decal.new()
		d.top_level = true
		d.texture_albedo = _SCORCH_TEX
		d.size = Vector3(1.4, 1.2, 1.4)
		d.cull_mask = 1 # the world (render layer 1); not your own hidden body
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		add_child(d)
		_marks.append(d)
		_ages.append(0.0)
	var i := _next_mark % _SCORCH_MAX
	_next_mark += 1
	d = _marks[i]
	d.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), at + Vector3.UP * 0.1)
	var s := randf_range(0.8, 1.2)
	d.size = Vector3(1.4 * s, 1.2, 1.4 * s)
	d.visible = true
	_ages[i] = 0.0


func _age_marks(delta: float) -> void:
	for i: int in _marks.size():
		if not _marks[i].visible: continue
		_ages[i] += delta
		var left := 1.0 - _ages[i] / scorch_life
		if left <= 0.0: _marks[i].visible = false
		else: _marks[i].modulate.a = minf(left * 2.0, 1.0) # holds, then fades over its last half
