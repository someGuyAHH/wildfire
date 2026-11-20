class_name RunnerBody
extends Node3D
## The runner model on a character (tools/blender/runner.py): gives each role slot its material,
## colours this character's accent and visor (set_tint), and plays the clip for what the
## character is doing. Sits under the character's Visual (which turns to face the view), the model
## turned half round (it's made facing +Z, characters face -Z).

const _MODEL := preload("res://assets/models/characters/runner.glb")
const _MATS := {
	&"suit": preload("res://assets/tres/materials/characters/runner_suit.tres"),
	&"dark": preload("res://assets/tres/materials/characters/runner_dark.tres"),
	&"accent": preload("res://assets/tres/materials/characters/runner_accent.tres"),
	&"visor": preload("res://assets/tres/materials/characters/runner_visor.tres"),
	&"sole": preload("res://assets/tres/materials/characters/runner_sole.tres"),
}
## Clips held as loops though their names don't say so (single held poses).
const _HELD: Array[StringName] = [&"Dash", &"Slam"]
## Ground speed (m/s) each locomotion clip's stride is made for; it plays faster or slower to match.
const _JOG_SPEED := 4.0
const _SPRINT_SPEED := 9.0
const _IDLE_BELOW := 0.6    # m/s: slower than this stands
const _SPRINT_FROM := 7.0   # m/s: faster than this sprints
const _BLEND := 0.12        # s, crossfade between clips
const _DIZZY_FROM := 0.05   # get_dizziness() above this staggers (the whole time you're dizzy)
const _DIZZY_SPEED := 1.6   # m/s the stagger's steps are made for

@export var character: Character

var mesh: MeshInstance3D
var _anim: AnimationPlayer
var _accent: StandardMaterial3D
var _visor: StandardMaterial3D
var _one_shot := 0.0 # seconds left of a clip that plays out before the state's own (jump take-off, landing)


func _ready() -> void:
	var model := _MODEL.instantiate() as Node3D
	model.rotation.y = PI
	add_child(model)
	mesh = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_accent = _MATS[&"accent"].duplicate()
	_visor = _MATS[&"visor"].duplicate()
	for i: int in mesh.mesh.get_surface_count():
		var role := StringName(mesh.mesh.surface_get_material(i).resource_name)
		var m: Material = _accent if role == &"accent" else _visor if role == &"visor" else _MATS.get(role)
		if m: mesh.set_surface_override_material(i, m)
	for clip: StringName in _HELD:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Idle")
	if character:
		character.jumped.connect(_on_jumped)
		character.landed.connect(_on_landed)


## Straight to standing, nothing left over (a respawn, a new round).
func reset() -> void:
	if not _anim: return
	_one_shot = 0.0
	_anim.speed_scale = 1.0
	_anim.clear_queue()
	_anim.play(&"Idle", 0.0)
	_anim.advance(0.0)


## This character's colour on the accents and the visor; glow > 0 lights the accents (the Torch).
func set_tint(color: Color, glow: float = 0.0) -> void:
	if not _accent: return
	_accent.albedo_color = color
	_accent.emission_enabled = glow > 0.0
	_accent.emission = color
	_accent.emission_energy_multiplier = glow
	_visor.emission = color.lerp(Color.WHITE, 0.25)


func _process(delta: float) -> void:
	if not character: return
	var state := character.get_state()
	if state == Character.ST_FROZEN: # held still, mid-pose
		_anim.speed_scale = 0.0
		return
	_anim.speed_scale = 1.0
	_one_shot -= delta
	match state:
		Character.ST_SLIDING:
			if _anim.current_animation not in [&"Slide_Start", &"Slide"]:
				_play(&"Slide_Start")
				_anim.queue(&"Slide")
		Character.ST_DASHING: _play(&"Dash")
		Character.ST_SLAMMING: _play(&"Slam")
		Character.ST_AIRBORNE:
			if _one_shot <= 0.0: _play(&"Jump")
		_:
			if _anim.current_animation in [&"Slide_Start", &"Slide"]:
				_play(&"Slide_Exit")
				_one_shot = 0.3
			if _one_shot > 0.0: return
			var speed := character.get_horizontal_speed()
			if character.get_dizziness() > _DIZZY_FROM: # stumbling about for as long as it lasts
				_play(&"Dizzy")
				_anim.speed_scale = clampf(0.75 + speed / _DIZZY_SPEED * 0.5, 0.75, 1.6)
			elif speed < _IDLE_BELOW:
				_play(&"Idle")
			elif speed < _SPRINT_FROM:
				_play(&"Jog_Fwd")
				_anim.speed_scale = clampf(speed / _JOG_SPEED, 0.5, 1.8)
			else:
				_play(&"Sprint")
				_anim.speed_scale = clampf(speed / _SPRINT_SPEED, 0.8, 2.2)


func _play(clip: StringName) -> void:
	if _anim.current_animation != clip: _anim.play(clip, _BLEND)


func _on_jumped(kind: int) -> void:
	# a wall jump kicks off like a ninja jump; the rest take off and then hang in the jump loop
	_anim.play(&"NinjaJump_Start" if kind == Character.JUMP_WALL else &"Jump_Start", 0.06)
	_one_shot = 0.35


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 6.0 or character.get_horizontal_speed() > _SPRINT_FROM: return # running on through it
	_anim.play(&"Jump_Land", 0.06)
	_anim.seek(0.35, true) # (the clip's first third is still in the air)
	_one_shot = 0.4

