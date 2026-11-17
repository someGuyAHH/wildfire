"""
Shared body for players and bots. Something writes a @CharacterIntent into `intent` every
physics tick (before this node runs) and the character does the rest.
Movement is a small state machine (ST_* constants) kept in this one file on purpose:
it's a single hot loop, splitting it into state objects would just add hops.
"""

class_name Character
extends CharacterBody3D

signal state_changed(old: int, new: int)
signal jumped(kind: int)
signal landed(impact_speed: float)
signal dashed(dir: Vector3)
signal frozen_changed(is_frozen: bool)
## The auto-step lifted the body this much in one tick (cameras smooth exactly this, nothing else).
signal stepped_up(height: float)
## kind: BRAKE_AIR (brake slam) or BRAKE_GROUND (skid stop)
signal braked(kind: int)
signal dizzy_changed(is_dizzy: bool)
## Hit a wall hard enough to get disoriented. impact_speed = speed into the wall (m/s).
signal wall_bonked(impact_speed: float)
signal disoriented_changed(is_disoriented: bool)

# states
const ST_GROUNDED := 0
const ST_AIRBORNE := 1
const ST_SLIDING  := 2
const ST_DASHING  := 3
const ST_SLAMMING := 4
const ST_FROZEN   := 5

const STATE_NAMES: Array[String] = ["grounded", "airborne", "sliding", "dashing", "slamming", "frozen"]

# jump kinds (for jumped signal)
const JUMP_GROUND      := 0
const JUMP_WALL        := 1
const JUMP_SLAM_BOUNCE := 2
const JUMP_DASH        := 3
const JUMP_VAULT       := 4
const JUMP_LAUNCH      := 5

# smoke levels (set_smoke)
const SMOKE_NONE   := 0
const SMOKE_LIGHT  := 1   # smoldering on the dry edge
const SMOKE_COLUMN := 2   # hid too long: a tall column everyone can see

# brake kinds (for braked signal)
const BRAKE_AIR    := 0
const BRAKE_GROUND := 1

# misc
const _MIN_MOVE_SQ     := 0.000001
const _CEILING_NORMAL  := -0.7  # normal.y below this is a ceiling, not a wall
const _VISUAL_TURN     := 15.0
const _FROZEN_BRAKE    := 60.0
const _SLIDE_STOP      := 2.0   # slide speed below this ends the slide
const _VAULT_CLEARANCE := 0.15
const _VAULT_PUSH      := 4.0
const _STEP_MIN_PROBE  := 0.02
const _STEP_EDGE_REACH := 0.1
const _BONK_STOP_RATIO := 0.6   # covering more than this of the expected distance = not stopped
const _STEP_LIP_MARGIN := 0.05
const _STEP_PROBE      := 0.15

const _BODY_MAT    := preload("res://assets/tres/materials/character_body.tres")
const _FIRE_SCENE  := preload("res://scn/vfx/fire.tscn")
const _SMOKE_SCENE := preload("res://scn/vfx/smoke.tscn")
const _SPARKS_SCENE := preload("res://scn/vfx/sparks.tscn")
const _OUT_FREEZE      := 1.0e6
const _DIZZY_FADE      := 0.6   # last bit of dizziness fades the camera sway out
const _DISORIENT_FADE  := 1.0   # steering drift fades out over the last second
const _DRIFT_FREQ_A    := 2.1   # two detuned sines so the drift doesn't feel periodic
const _DRIFT_FREQ_B    := 0.77
# fixed_size labels are sized as if 1 m from the camera, so they need a tiny pixel size.
# 0.0012 * 48 px font ~ 22 px tall on a 1080p screen at fov 112.
const _TAG_FIXED_PIXEL := 0.0012
const _PROBE_DIRS: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(0.7071, 0, 0.7071), Vector3(-0.7071, 0, 0.7071),
	Vector3(0.7071, 0, -0.7071), Vector3(-0.7071, 0, -0.7071),
]

@export var config: MovementConfig
@export var collision_shape: CollisionShape3D
## Rotated to face look_dir and squashed while sliding. Placeholder art lives under it.
@export var visual: Node3D
## Gets a per-character material so it can be tinted (role colors).
@export var body_mesh: MeshInstance3D
## Floating name above the head.
@export var name_tag: Label3D

var intent := CharacterIntent.new()
## Shown in name tags, scoreboards and the feed.
var display_name := "Runner"
## The character's own color; match code tints on top of it and goes back to it.
var base_tint := Color(0.82, 0.84, 0.88)
## Multiplies max run/air speed. The match uses it for the Torch bonus.
var speed_mult := 1.0
## A timed slowdown on top of speed_mult (lava): slow().
var _slow_mult := 1.0
var _slow_timer := 0.0
var _launched := false # in the air off a pad / launcher (till landing)...
var _launch_target := Vector3.INF # ...where it lands you, if the launcher knows
## Multiplies dash recharge speed.
var dash_regen_mult := 1.0
## Off for title-screen bots: no name tag or shouts cluttering the menu.
var show_labels := true
## Who this character is hunting right now (bots set it), null if nobody.
## HUDs use it for the "you're being hunted" warning.
var chase_target: Character

var _body_mat: StandardMaterial3D
var _tag_world_pixel := 0.008 # read from the scene in _ready

var _state := ST_AIRBORNE
var _capsule: CapsuleShape3D
var _stand_query := PhysicsShapeQueryParameters3D.new()
var _col := KinematicCollision3D.new() # reused by every test_move probe, read only right after a hit
var _crouched := false
var _was_on_floor := false
var _can_cut_jump := false
var _wall_sliding := false
var _wall_normal := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _pre_dash_speed := 0.0
var _dash_charges := 0.0
var _wall_jumps_left := 0
# timers, all clamped at 0 so truthiness works
var _coyote := 0.0
var _jump_buffer := 0.0
var _wall_timer := 0.0
var _landing_grace := 0.0
var _slam_bounce := 0.0
var _slide_boost_cd := 0.0
var _vault_cd := 0.0
var _dash_timer := 0.0
var _frozen_timer := 0.0
var _brake_timer := 0.0
var _dizzy_timer := 0.0
var _dizzy_meter := 0.0 # drains on its own, not a timer but same clamping
var _slam_brake := false
var _air_peak_y := 0.0      # highest point since leaving the ground (slam-bounce scaling)
var _bounce_height := 0.0   # apex the next slam-bounce will reach
var _disorient_timer := 0.0
var _disorient_phase := 0.0
var _stumble_seed := 0.0
var _bonk_cd := 0.0
var _emote_label: Label3D
var _out_hidden: Array[Node3D] = []
var _fire: CPUParticles3D
var _fire_light: OmniLight3D
var _smoke_fx: CPUParticles3D
var _sparks: CPUParticles3D
var _smoke_level := SMOKE_NONE
var _emote_timer := 0.0
# ring buffer of recent positions, for measuring real run-up speed into walls
var _pos_history := PackedVector3Array()
var _pos_head := 0


func _ready() -> void:
	if not config:
		push_error("%s has no MovementConfig, using defaults" % name)
		config = MovementConfig.new()
	if name_tag:
		_tag_world_pixel = name_tag.pixel_size
		name_tag.visible = show_labels
	if body_mesh:
		_body_mat = _BODY_MAT.duplicate() # own copy: set_tint() colors only this character
		body_mesh.material_override = _body_mat
		set_tint(base_tint)
	if not collision_shape or not (collision_shape.shape is CapsuleShape3D):
		push_error("%s needs a CollisionShape3D with a CapsuleShape3D" % name)
		return
	# shape gets resized for slides, so every character needs its own copy
	_capsule = collision_shape.shape.duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule
	_capsule.radius = config.radius
	_apply_body_height(config.height)

	var stand_shape := CapsuleShape3D.new()
	stand_shape.radius = config.radius - 0.05
	stand_shape.height = config.height - 0.1
	_stand_query.shape = stand_shape
	_stand_query.collision_mask = collision_mask
	_stand_query.exclude = [get_rid()]

	floor_max_angle = deg_to_rad(config.floor_max_angle_deg)
	floor_snap_length = config.floor_snap
	floor_constant_speed = true
	floor_block_on_wall = false
	max_slides = 6
	_dash_charges = float(config.dash_charges)
	_wall_jumps_left = config.wall_jumps_max
	_reset_pos_history()


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if intent.jump_pressed: _jump_buffer = config.jump_buffer
	if intent.dash_pressed and _state != ST_FROZEN: _try_dash()
	if intent.brake_pressed and _state != ST_FROZEN: _brake()
	# disorientation bends the wish for this tick only, the controller's value is put back after
	var raw_wish := intent.wish_dir
	if _disorient_timer:
		intent.wish_dir = (raw_wish.rotated(Vector3.UP, _drift_angle()) + _stumble()).limit_length(1.0)

	match _state:
		ST_FROZEN:   _move_frozen(delta)
		ST_DASHING:  _move_dash(delta)
		ST_SLAMMING: _move_slam(delta)
		ST_SLIDING:  _move_slide(delta)
		ST_GROUNDED: _move_ground(delta)
		ST_AIRBORNE: _move_air(delta)

	_apply_soft_cap(delta)
	var pre_vel := velocity
	# dashes too: dashing at stairs used to stop you dead on the first step (and bonk you)
	if _state == ST_GROUNDED or _state == ST_SLIDING or _state == ST_DASHING: _try_step_up(delta)
	var pre_pos := global_position
	move_and_slide()
	_after_move(pre_vel, pre_pos, delta)
	_turn_visual(delta)
	_update_sparks()
	intent.wish_dir = raw_wish
	intent.clear_edges()


#region public api

## Replaces velocity (jump pads, launchers). keep_horizontal adds vel's horizontal part to the current one instead.
## target: where the launcher means you to land (for bots), INF if it doesn't say.
func launch(vel: Vector3, keep_horizontal: bool = false, target: Vector3 = Vector3.INF) -> void:
	if _state == ST_FROZEN: return
	if keep_horizontal:
		velocity = Vector3(velocity.x + vel.x, vel.y, velocity.z + vel.z)
	else:
		velocity = vel
	_try_stand()
	_coyote = 0.0
	_can_cut_jump = false
	_wall_jumps_left = config.wall_jumps_max
	_launched = true
	_launch_target = target
	_set_state(ST_AIRBORNE)
	jumped.emit(JUMP_LAUNCH)


## In the air off a pad or launcher (cleared on landing).
func is_launched() -> bool:
	return _launched


## Where the pad that launched you means you to land (INF if not launched, or it didn't say).
func get_launch_target() -> Vector3:
	return _launch_target if _launched else Vector3.INF


## Pushes horizontal speed along dir up to at least `speed`. Never slows you down.
func boost(dir: Vector3, speed: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < _MIN_MOVE_SQ: return
	dir = dir.normalized()
	var hv := _horizontal()
	var along := hv.dot(dir)
	if along >= speed: return
	hv += dir * (speed - along)
	velocity.x = hv.x
	velocity.z = hv.z
	_landing_grace = maxf(_landing_grace, 0.3)


## Freezes the character in place (tag stun). Overlapping freezes keep the longer one.
func freeze(duration: float) -> void:
	if duration <= 0.0:
		push_error("freeze() wants a positive duration, got %s" % duration)
		return
	_frozen_timer = maxf(_frozen_timer, duration)
	if _state == ST_FROZEN: return
	_try_stand()
	_set_state(ST_FROZEN)
	frozen_changed.emit(true)


## Moves the character instantly, kills velocity and resets interpolation so it doesn't streak.
## Colors the body. glow > 0 makes it emissive (the Torch glows).
func set_tint(color: Color, glow: float = 0.0) -> void:
	if not _body_mat: return
	_body_mat.albedo_color = color
	_body_mat.emission_enabled = glow > 0.0
	_body_mat.emission = color
	_body_mat.emission_energy_multiplier = glow


## Sets the character on fire (the Torch): embers rising and trailing behind, plus a warm light.
## The embers use the body's render layers, so the local player doesn't see their own in first person.
func set_burning(on: bool) -> void:
	if on and not _fire: _build_fire()
	if not _fire: return
	_fire.emitting = on
	_fire_light.visible = on


## Smoke off the character: SMOKE_NONE, SMOKE_LIGHT (smoldering) or SMOKE_COLUMN (revealed).
func set_smoke(level: int) -> void:
	if level == _smoke_level: return
	_smoke_level = level
	if level != SMOKE_NONE and not _smoke_fx: _build_smoke()
	if not _smoke_fx: return
	_smoke_fx.emitting = level != SMOKE_NONE
	var column := level == SMOKE_COLUMN
	_smoke_fx.amount = 60 if column else 14 # (changing amount restarts it, fine here)
	_smoke_fx.lifetime = 5.0 if column else 1.6
	_smoke_fx.initial_velocity_min = 4.0 if column else 0.6
	_smoke_fx.initial_velocity_max = 6.5 if column else 1.4
	_smoke_fx.scale_amount_min = 1.2 if column else 0.5
	_smoke_fx.scale_amount_max = 2.2 if column else 0.9


func get_smoke() -> int:
	return _smoke_level


## Hot Potato burn-out: hides the body (and its fire, smoke and name) and freezes it until
## brought back. The node itself stays visible so a player's camera and HUD keep working.
func set_out(on: bool) -> void:
	if on:
		# only hide (and later restore) what's showing, e.g. a player's own name tag stays hidden
		_out_hidden.clear()
		for n: Node3D in [visual, name_tag, _fire, _fire_light, _smoke_fx, _emote_label]:
			if n and n.visible:
				n.visible = false
				_out_hidden.append(n)
		freeze(_OUT_FREEZE)
		return
	for n: Node3D in _out_hidden:
		if is_instance_valid(n): n.visible = true
	_out_hidden.clear()
	if _state == ST_FROZEN: _frozen_timer = 0.0 # thaws on the next tick


## Pops a short line over the head for a moment ("BRO", "nope"...). Bots use it to react.
func emote(text: String, color: Color = Color.WHITE, duration: float = 1.8) -> void:
	if not show_labels: return
	if not _emote_label:
		_emote_label = Label3D.new()
		_emote_label.name = "Emote"
		_emote_label.position.y = 2.75
		_emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_emote_label.font_size = 60
		_emote_label.outline_size = 16
		_emote_label.pixel_size = 0.01
		add_child(_emote_label)
	_emote_label.text = text
	_emote_label.modulate = color
	_emote_label.visible = true
	_emote_timer = duration


## Sets the floating name. through_walls draws it on top of everything (used for the Torch).
func set_name_tag(text: String, color: Color = Color.WHITE, through_walls: bool = false) -> void:
	if not name_tag: return
	name_tag.text = text
	name_tag.modulate = color
	name_tag.no_depth_test = through_walls
	name_tag.fixed_size = through_walls # readable at any distance when it matters
	name_tag.pixel_size = _TAG_FIXED_PIXEL if through_walls else _tag_world_pixel
	name_tag.render_priority = 10 if through_walls else 0


## The capsule's core segment in world space (bottom and top sphere centres). It follows crouching.
func get_capsule_segment() -> PackedVector3Array:
	var c := collision_shape.global_position if collision_shape else global_position
	var half := (_capsule.height * 0.5 - _capsule.radius) if _capsule else 0.5
	return PackedVector3Array([c - Vector3.UP * half, c + Vector3.UP * half])


func get_body_radius() -> float:
	return _capsule.radius if _capsule else config.radius


## True while slamming down (Ctrl or Q in the air).
func is_slamming() -> bool:
	return _state == ST_SLAMMING


## Metres dropped since the highest point of this airtime (0 on the ground).
func get_drop_height() -> float:
	return 0.0 if is_on_floor() else maxf(_air_peak_y - global_position.y, 0.0)


## Is the character frozen (tag stun, dizzy stun, countdown)?
func is_frozen() -> bool:
	return _state == ST_FROZEN


## Steering drift + stumbling + camera sway for `duration` s (wall bonks, body slams).
## Overlapping calls keep the longer time.
func disorient(duration: float) -> void:
	if duration <= 0.0: return
	if not _disorient_timer:
		_disorient_phase = 0.0
		_stumble_seed = randf() * TAU # lurch off in a different direction every time
		disoriented_changed.emit(true)
	_disorient_timer = maxf(_disorient_timer, duration)


## Adds a shove to the velocity. Anything with upward push puts you in the air.
func knockback(vel: Vector3) -> void:
	if _state == ST_FROZEN: return
	velocity += vel
	if vel.y > 0.0:
		_coyote = 0.0
		_can_cut_jump = false
		_try_stand()
		_set_state(ST_AIRBORNE)


## Top speed times `mult` for `duration` seconds (lava). A new one replaces the old.
func slow(duration: float, mult: float) -> void:
	_slow_timer = duration
	_slow_mult = mult


func is_slowed() -> bool:
	return _slow_timer > 0.0


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_was_on_floor = false
	_try_stand()
	_set_state(ST_AIRBORNE)
	_reset_pos_history() # or the teleport itself looks like a 1000 m/s run-up
	reset_physics_interpolation()


func get_state() -> int:
	return _state


func get_state_name() -> String:
	return STATE_NAMES[_state]


func get_horizontal_speed() -> float:
	return _horizontal().length()


func get_dash_charges() -> float:
	return _dash_charges


func get_wall_jumps_left() -> int:
	return _wall_jumps_left


func get_eye_height() -> float:
	return config.slide_eye_height if _crouched else config.eye_height


## 0..1, how dizzy the character is right now (fades out at the end). Cameras sway with this.
## Covers both the brake-spam stun and wall-bonk disorientation, whichever is stronger.
func get_dizziness() -> float:
	return maxf(clampf(_dizzy_timer / _DIZZY_FADE, 0.0, 1.0), get_disorientation())


## 0..1, wall-bonk disorientation (steering drift), fading out over its last second.
func get_disorientation() -> float:
	return clampf(_disorient_timer / _DISORIENT_FADE, 0.0, 1.0)


## Seconds of disorientation left.
func get_disorient_time() -> float:
	return _disorient_timer


## 0..1, how close ground-brake spam is to making you dizzy.
func get_dizzy_meter() -> float:
	return clampf(_dizzy_meter / maxf(config.dizzy_threshold, 0.01), 0.0, 1.0)


func is_wall_sliding() -> bool:
	return _wall_sliding


## Flattened normal of the last wall touched (zero if none recently).
## Not get_wall_normal(), that one's CharacterBody3D's (raw contact normal from the last move).
func get_last_wall_normal() -> Vector3:
	return _wall_normal if _wall_timer else Vector3.ZERO

#endregion


#region states

func _move_ground(delta: float) -> void:
	if _consume_jump(): return
	if intent.slide_pressed:
		_enter_slide()
		_move_slide(delta)
		return
	# crouch-walk while crouch is held (or there's no headroom), stand up otherwise
	if _crouched and not intent.slide_held: _try_stand()
	if _brake_timer:
		# skid stop, input ignored until it's done
		_set_horizontal(_horizontal().move_toward(Vector3.ZERO, config.brake_ground_decel * delta))
		velocity.y = 0.0
		return
	var drag := 0.0 if _landing_grace else config.ground_overspeed_drag
	var top := config.crouch_speed if _crouched else config.max_speed * speed_mult * _slow_mult
	_set_horizontal(_accelerate(_horizontal(), intent.wish_dir, top,
								config.ground_accel, config.ground_decel, drag,
								config.ground_turn_rate, delta))
	velocity.y = 0.0


func _move_air(delta: float) -> void:
	if _consume_jump(): return
	if intent.slide_pressed and not _coyote:
		_enter_slam()
		return
	if _crouched: _try_stand()
	_try_vault()
	_set_horizontal(_accelerate(_horizontal(), intent.wish_dir, config.max_speed * speed_mult * _slow_mult,
								config.air_accel, config.air_decel, config.air_overspeed_drag,
								config.air_turn_rate, delta))
	# variable jump height
	if _can_cut_jump and velocity.y > 0.0 and not intent.jump_held:
		velocity.y *= config.jump_cut_mult
		_can_cut_jump = false
	if velocity.y <= 0.0: _can_cut_jump = false
	_apply_gravity(delta)
	# wall slide: falling while pushing into a wall
	_wall_sliding = _wall_timer > 0.0 and velocity.y < 0.0 \
			and intent.wish_dir.dot(-_wall_normal) > 0.3
	if _wall_sliding and velocity.y < -config.wall_slide_speed:
		velocity.y = move_toward(velocity.y, -config.wall_slide_speed, config.gravity * 3.0 * delta)


func _move_slide(delta: float) -> void:
	if not intent.slide_held and _try_stand():
		_set_state(ST_GROUNDED)
		_move_ground(delta)
		return
	if _consume_jump(): return

	var hv := _horizontal()
	var speed := hv.length()
	var dir := hv / speed if speed > 0.01 else intent.look_dir
	if intent.wish_dir.length_squared() > 0.01:
		var want := intent.wish_dir.normalized()
		if dir.dot(want) > -0.5: dir = _rotate_toward(dir, want, config.slide_steer_rate * delta)

	# slopes: the floor normal's horizontal part points downhill
	var n := get_floor_normal()
	var downhill := Vector3(n.x, 0.0, n.z)
	hv = dir * speed + downhill * config.gravity * config.slide_slope_accel * delta
	speed = hv.length()
	if speed > 0.01: dir = hv / speed
	var uphill := downhill.dot(dir) < -0.02
	speed -= config.slide_friction * delta
	if not uphill: speed = maxf(speed, config.slide_min_speed)
	# slide ran out (or crawling up a slope slower than you'd crouch-walk): drop to a crouch-walk
	# if crouch is still held, otherwise stand up. never just stall at 2 m/s.
	if speed < _SLIDE_STOP or (uphill and speed < config.crouch_speed):
		if intent.slide_held or not _try_stand():
			_set_crouched(true)
			_set_state(ST_GROUNDED)
			_move_ground(delta)
			return
		_set_state(ST_GROUNDED)
	_set_horizontal(dir * maxf(speed, 0.0))
	velocity.y = 0.0


# constant velocity, delta not needed
func _move_dash(_delta: float) -> void:
	if _consume_jump(): return
	velocity = _dash_dir * config.dash_speed
	if not _dash_timer: _end_dash()


func _move_slam(delta: float) -> void:
	if _consume_jump(): return # wall-jump out of a slam is allowed
	velocity.y = -config.slam_speed
	if _slam_brake:
		# ease speed down to a small steerable amount instead of cutting it, less whiplash
		var target := intent.wish_dir * config.max_speed * config.brake_air_steer
		_set_horizontal(_horizontal().move_toward(target, config.brake_air_decel * delta))
		return
	# a little steering so you can aim the landing
	_set_horizontal(_accelerate(_horizontal(), intent.wish_dir, config.max_speed * 0.3,
								config.air_accel * 0.5, 0.0, 0.0, 0.0, delta))


func _move_frozen(delta: float) -> void:
	_set_horizontal(_horizontal().move_toward(Vector3.ZERO, _FROZEN_BRAKE * delta))
	if is_on_floor():
		velocity.y = 0.0
	else:
		_apply_gravity(delta)
	if _frozen_timer: return
	_set_state(ST_GROUNDED if is_on_floor() else ST_AIRBORNE)
	frozen_changed.emit(false)

#endregion


#region actions

## Returns true if a jump of some kind happened this tick.
func _consume_jump() -> bool:
	if not _jump_buffer: return false
	match _state:
		ST_GROUNDED, ST_SLIDING:
			_do_ground_jump(JUMP_GROUND)
			return true
		ST_DASHING:
			if is_on_floor() or _coyote:
				# already going faster than a dash-jump gives (pad, slide, bhop): it adds on top instead
				_set_horizontal(_dash_dir * maxf(config.dash_speed * config.dash_jump_keep, _pre_dash_speed + config.dash_jump_boost))
				_do_ground_jump(JUMP_DASH)
				return true
			return _do_wall_jump()
		ST_AIRBORNE:
			if _coyote:
				_do_ground_jump(JUMP_GROUND)
				return true
			return _do_wall_jump()
		ST_SLAMMING:
			return _do_wall_jump()
	return false


func _do_ground_jump(kind: int) -> void:
	var vy := config.jump_velocity
	if _slam_bounce and kind == JUMP_GROUND:
		# launch speed that peaks exactly at _bounce_height (never weaker than a normal jump)
		vy = maxf(sqrt(2.0 * config.gravity * _bounce_height), vy)
		kind = JUMP_SLAM_BOUNCE
	velocity.y = vy
	_jump_buffer = 0.0
	_coyote = 0.0
	_slam_bounce = 0.0
	_can_cut_jump = kind == JUMP_GROUND
	_try_stand()
	_set_state(ST_AIRBORNE)
	jumped.emit(kind)


func _do_wall_jump() -> bool:
	if _wall_jumps_left <= 0: return false
	var n := _find_wall()
	if n == Vector3.ZERO: return false
	var hv := _horizontal()
	var along := hv - n * hv.dot(n)
	# input can steer the kick, but not back into the wall
	var wish := intent.wish_dir - n * minf(intent.wish_dir.dot(n), 0.0)
	var out := along * config.wall_jump_keep + n * config.wall_jump_push + wish * 3.0
	velocity = Vector3(out.x, config.wall_jump_up, out.z)
	_wall_jumps_left -= 1
	_wall_timer = 0.0
	_jump_buffer = 0.0
	_can_cut_jump = false
	_try_stand()
	_set_state(ST_AIRBORNE)
	jumped.emit(JUMP_WALL)
	return true


func _try_dash() -> void:
	if _dash_charges < 1.0 or _state == ST_DASHING: return
	if _slow_timer: return # slowed (lava): no dashing out of it
	var dir := intent.wish_dir.normalized() if intent.wish_dir.length_squared() > 0.01 else intent.look_dir
	_pre_dash_speed = _horizontal().length()
	_dash_charges -= 1.0
	_dash_dir = dir
	_dash_timer = config.dash_time
	_can_cut_jump = false
	_try_stand()
	_set_state(ST_DASHING)
	dashed.emit(dir)


func _end_dash() -> void:
	_set_horizontal(_dash_dir * maxf(_pre_dash_speed, config.dash_exit_speed))
	velocity.y = 0.0
	if not is_on_floor():
		_set_state(ST_AIRBORNE)
	elif intent.slide_held:
		_enter_slide()
	else:
		_set_state(ST_GROUNDED)


## Q: brake slam in the air, skid stop on the ground. Ground spam fills the dizzy meter,
## and a full meter stuns you (same freeze as a tag stun) while the camera sways.
func _brake() -> void:
	if not is_on_floor():
		_enter_slam(true)
		braked.emit(BRAKE_AIR)
		return
	var crash := get_horizontal_speed() >= config.overdrive_speed
	match _state:
		ST_SLIDING: _try_stand()
		ST_DASHING: _dash_timer = 0.0
	_brake_timer = config.brake_ground_time
	_set_state(ST_GROUNDED)
	braked.emit(BRAKE_GROUND)
	if crash: # slamming the brakes from overdrive: stunned, then you stumble about
		freeze(config.hard_stop_stun)
		disorient(config.hard_stop_stun + config.hard_stop_disorient)
		return
	_dizzy_meter += 1.0
	if _dizzy_meter < config.dizzy_threshold: return
	_dizzy_meter = 0.0
	if not _dizzy_timer: dizzy_changed.emit(true)
	_dizzy_timer = config.dizzy_duration
	freeze(config.dizzy_duration)


## Speed going *into* a wall (not along it) above wall_bonk_speed disorients you.
## Harder hits last longer. No stun, just steering drift and camera sway.
func _check_wall_bonk(pre_vel: Vector3, pre_pos: Vector3, delta: float) -> void:
	if _pos_history.is_empty(): _reset_pos_history()
	# oldest sample is bonk_runup_time ago; swap in the current position
	var oldest := _pos_history[_pos_head]
	_pos_history[_pos_head] = global_position
	_pos_head = (_pos_head + 1) % _pos_history.size()
	var window := _pos_history.size() / float(Engine.physics_ticks_per_second)
	var runup := (global_position - oldest) / window
	runup.y = 0.0
	if _bonk_cd: return
	var flat_vel := Vector3(pre_vel.x, 0.0, pre_vel.z)
	var impact := 0.0
	for i: int in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if not _is_wall(n): continue # walkable slopes and ceilings don't count
		var flat_n := Vector3(n.x, 0.0, n.z).normalized()
		# both have to be fast: velocity alone lies on point-blank dashes (0 run-up),
		# run-up alone lies right after a wall-jump bounce
		var hit := minf(-flat_vel.dot(flat_n), -runup.dot(flat_n))
		# a step isn't a wall: only count it if there's still wall in front of us above step height.
		# probed last, it's two shape casts, and almost every wall contact is too slow to matter
		if hit <= impact or hit < config.wall_bonk_speed or not _wall_above_step(flat_n): continue
		impact = hit
	if impact < config.wall_bonk_speed: return
	# a real bonk *stops* you. slope crests, ledge lips and glancing hits barely slow you down
	# (they just redirect you), so if we still covered most of the distance it wasn't a bonk
	var speed := flat_vel.length()
	var moved := Vector3(global_position.x - pre_pos.x, 0.0, global_position.z - pre_pos.z)
	if speed > 0.01 and moved.dot(flat_vel / speed) > speed * delta * _BONK_STOP_RATIO: return
	_bonk_cd = config.bonk_cooldown
	disorient(minf(config.bonk_duration + (impact - config.wall_bonk_speed) * config.bonk_duration_per_mps,
				config.bonk_max_duration))
	wall_bonked.emit(impact)


## Involuntary lurch while disoriented: a slowly wandering direction with pulsing strength.
func _stumble() -> Vector3:
	var p := _disorient_phase
	var angle := _stumble_seed + p * 0.9 + sin(p * 1.7) * 1.5
	var strength := config.bonk_stumble * get_disorientation() * (0.6 + 0.4 * sin(p * 2.9))
	return Vector3(sin(angle), 0.0, cos(angle)) * strength


func _reset_pos_history() -> void:
	var ticks := maxi(1, roundi(config.bonk_runup_time * Engine.physics_ticks_per_second))
	_pos_history.resize(ticks)
	_pos_history.fill(global_position)
	_pos_head = 0


## True if, lifted by step_height (+ a lip), moving a bit into the wall still hits something.
func _wall_above_step(flat_n: Vector3) -> bool:
	var t := global_transform
	t.origin.y += config.step_height + _STEP_LIP_MARGIN
	if test_move(global_transform, Vector3.UP * (config.step_height + _STEP_LIP_MARGIN)): return true # low ceiling, call it a wall
	return test_move(t, -flat_n * _STEP_PROBE)


func _drift_angle() -> float:
	var wobble := sin(_disorient_phase * _DRIFT_FREQ_A) * 0.7 + sin(_disorient_phase * _DRIFT_FREQ_B * TAU) * 0.3
	return wobble * config.bonk_steer_wobble * get_disorientation()


func _enter_slide() -> void:
	var hv := _horizontal()
	var speed := hv.length()
	var dir: Vector3
	if speed > 1.0:
		dir = hv / speed
	elif intent.wish_dir.length_squared() > 0.01:
		dir = intent.wish_dir.normalized()
	else:
		dir = intent.look_dir
	if not _slide_boost_cd:
		speed = maxf(speed, minf(speed + config.slide_boost, config.max_speed + config.slide_boost))
		_slide_boost_cd = config.slide_boost_cooldown
	_set_horizontal(dir * maxf(speed, config.slide_min_speed))
	_set_crouched(true)
	_set_state(ST_SLIDING)


## brake=true is the Q slam: horizontal speed eases off instead of being cut instantly.
func _enter_slam(brake: bool = false) -> void:
	_slam_brake = brake
	if not brake: _set_horizontal(_horizontal() * config.slam_horizontal_keep)
	_try_stand()
	velocity.y = -config.slam_speed
	_can_cut_jump = false
	_set_state(ST_SLAMMING)


## Air-only ledge pop: pushing into a wall with jump held and a ledge within vault_height
## gives exactly enough upward speed to clear it. Physical, so it can't clip into stuff.
func _try_vault() -> void:
	if _vault_cd or not intent.jump_held or not _wall_timer: return
	var into := -_wall_normal
	if intent.wish_dir.dot(into) < 0.5: return
	var t := global_transform
	var up := Vector3.UP * config.vault_height
	if test_move(t, up): return # head blocked
	t.origin += up
	var fwd := into * config.vault_probe_dist
	if test_move(t, fwd): return # wall is taller than a vault
	t.origin += fwd
	var col := _col
	if not test_move(t, -up, col): return # nothing to land on
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle: return
	var rise := t.origin.y + col.get_travel().y - global_position.y + _VAULT_CLEARANCE
	if rise <= 0.0: return
	var need := sqrt(2.0 * config.gravity * rise)
	if velocity.y >= need: return
	velocity.y = need
	var hv := _horizontal()
	var into_speed := hv.dot(into)
	if into_speed < _VAULT_PUSH: _set_horizontal(hv + into * (_VAULT_PUSH - into_speed))
	_vault_cd = config.vault_cooldown
	_can_cut_jump = false
	jumped.emit(JUMP_VAULT)


## Lifts the body onto low steps before move_and_slide so they don't stop you.
func _try_step_up(delta: float) -> void:
	if not is_on_floor(): return
	var hv := _horizontal()
	# move_and_slide zeroes velocity into the step, so fall back to where we *want* to go
	var dir := hv if hv.length_squared() > 0.01 else intent.wish_dir
	if dir.length_squared() < _MIN_MOVE_SQ: return
	dir = dir.normalized()
	var motion := dir * maxf(hv.length() * delta, _STEP_MIN_PROBE)
	var t := global_transform
	var col := _col
	if not test_move(t, motion, col): return
	if col.get_normal().angle_to(Vector3.UP) <= floor_max_angle: return # walkable slope, not a step
	var up := Vector3.UP * config.step_height
	if test_move(t, up): return
	t.origin += up
	# reach a radius past the edge, otherwise the round capsule bottom lands on the corner
	var probe := motion + dir * (config.radius + _STEP_EDGE_REACH)
	if test_move(t, probe): return # still blocked up there, it's a wall
	t.origin += probe
	if not test_move(t, -up, col): return
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle: return
	var step := up.y + col.get_travel().y
	if step <= 0.01: return
	global_position.y += step
	stepped_up.emit(step)

#endregion


#region helpers

func _after_move(pre_vel: Vector3, pre_pos: Vector3, delta: float) -> void:
	var fall_speed := -pre_vel.y
	_check_wall_bonk(pre_vel, pre_pos, delta)
	if is_on_wall():
		var n := _wall_normal_flat()
		if n != Vector3.ZERO:
			_wall_normal = n
			_wall_timer = config.wall_coyote
	var on_floor := is_on_floor()
	if not on_floor: _air_peak_y = maxf(_air_peak_y, global_position.y)
	if on_floor and not _was_on_floor:
		_on_land(fall_speed)
	elif not on_floor and _was_on_floor:
		_on_leave_floor()
	_was_on_floor = on_floor
	if on_floor: _air_peak_y = global_position.y


func _on_land(impact_speed: float) -> void:
	_launched = false
	_wall_jumps_left = config.wall_jumps_max
	_landing_grace = config.landing_grace
	_can_cut_jump = false
	_wall_sliding = false
	match _state:
		ST_SLAMMING:
			_slam_bounce = config.slam_bounce_window
			var fall := maxf(_air_peak_y - global_position.y, 0.0)
			_bounce_height = clampf(config.slam_bounce_base_height + fall * config.slam_bounce_fall_ratio,
									config.slam_bounce_base_height, config.slam_bounce_max_height)
			velocity.y = 0.0
			if _slam_brake:
				# stick the landing: whatever speed is left gets skidded off
				_brake_timer = config.brake_ground_time
				_set_state(ST_GROUNDED)
			elif intent.slide_held: _enter_slide()
			else: _set_state(ST_GROUNDED)
			_slam_brake = false
		ST_AIRBORNE:
			if intent.slide_held: _enter_slide()
			else: _set_state(ST_GROUNDED)
	landed.emit(impact_speed)


func _on_leave_floor() -> void:
	match _state:
		ST_GROUNDED, ST_SLIDING:
			_coyote = config.coyote_time
			_set_state(ST_AIRBORNE)
		ST_DASHING:
			_coyote = config.coyote_time


func _tick_timers(delta: float) -> void:
	if _slow_timer:
		_slow_timer = maxf(_slow_timer - delta, 0.0)
		if not _slow_timer: _slow_mult = 1.0
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_wall_timer = maxf(_wall_timer - delta, 0.0)
	_landing_grace = maxf(_landing_grace - delta, 0.0)
	_slam_bounce = maxf(_slam_bounce - delta, 0.0)
	_slide_boost_cd = maxf(_slide_boost_cd - delta, 0.0)
	_vault_cd = maxf(_vault_cd - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	_frozen_timer = maxf(_frozen_timer - delta, 0.0)
	if _emote_timer:
		_emote_timer = maxf(_emote_timer - delta, 0.0)
		if not _emote_timer: _emote_label.visible = false
	_brake_timer = maxf(_brake_timer - delta, 0.0)
	_dizzy_meter = maxf(_dizzy_meter - config.dizzy_decay * delta, 0.0)
	if _dizzy_timer:
		_dizzy_timer = maxf(_dizzy_timer - delta, 0.0)
		if not _dizzy_timer: dizzy_changed.emit(false)
	_bonk_cd = maxf(_bonk_cd - delta, 0.0)
	if _disorient_timer:
		_disorient_phase += delta
		_disorient_timer = maxf(_disorient_timer - delta, 0.0)
		if not _disorient_timer: disoriented_changed.emit(false)
	if _state != ST_DASHING:
		_dash_charges = minf(_dash_charges + delta * dash_regen_mult / config.dash_regen, float(config.dash_charges))
	if _state != ST_AIRBORNE: _wall_sliding = false


## Ground/air acceleration. Under max speed it's a plain move_toward; above it, momentum
## is kept and steered (turn_rate rad/s) while bleeding overspeed_drag. Pulling hard
## against your momentum brakes at full accel.
func _accelerate(hv: Vector3, wish: Vector3, max_speed: float, accel: float, decel: float,
				overspeed_drag: float, turn_rate: float, delta: float) -> Vector3:
	var wish_len := wish.length()
	if wish_len < 0.01: return hv.move_toward(Vector3.ZERO, decel * delta)
	var target_speed := max_speed * wish_len
	var speed := hv.length()
	if speed <= target_speed + 0.01: return hv.move_toward(wish * max_speed, accel * delta)
	var dir := hv / speed
	var want := wish / wish_len
	if dir.dot(want) < -0.2: return hv.move_toward(wish * max_speed, accel * delta)
	dir = _rotate_toward(dir, want, turn_rate * delta)
	return dir * maxf(speed - overspeed_drag * delta, target_speed)


func _apply_gravity(delta: float) -> void:
	var g := config.gravity * (config.fall_gravity_mult if velocity.y < 0.0 else 1.0)
	velocity.y = maxf(velocity.y - g * delta, -config.terminal_velocity)


func _apply_soft_cap(delta: float) -> void:
	var hv := _horizontal()
	var speed := hv.length()
	if speed <= config.soft_speed_cap: return
	var drag := config.soft_cap_drag * speed * (speed - config.soft_speed_cap)
	_set_horizontal(hv / speed * maxf(speed - drag * delta, config.soft_speed_cap))


## Wall normal from contact, or from probing 8 directions if we're just near one.
func _find_wall() -> Vector3:
	if _wall_timer: return _wall_normal
	var col := _col
	for dir: Vector3 in _PROBE_DIRS:
		if not test_move(global_transform, dir * config.wall_probe_dist, col): continue
		var n := col.get_normal()
		if _is_wall(n): return Vector3(n.x, 0.0, n.z).normalized()
	return Vector3.ZERO


func _wall_normal_flat() -> Vector3:
	var n := get_wall_normal()
	if not _is_wall(n): return Vector3.ZERO
	return Vector3(n.x, 0.0, n.z).normalized()


func _set_crouched(c: bool) -> void:
	if c == _crouched: return
	_crouched = c
	_apply_body_height(config.slide_height if c else config.height)


func _apply_body_height(h: float) -> void:
	if not _capsule: return
	_capsule.height = h
	collision_shape.position.y = h * 0.5
	if visual: visual.scale.y = h / config.height


## Stands up if there's headroom. Returns true if standing afterwards.
func _try_stand() -> bool:
	if not _crouched: return true
	var t := global_transform
	t.origin.y += config.height * 0.5 + 0.05
	_stand_query.transform = t
	if not get_world_3d().direct_space_state.intersect_shape(_stand_query, 1).is_empty(): return false
	_set_crouched(false)
	return true


func _turn_visual(delta: float) -> void:
	if not visual: return
	var look := intent.look_dir
	var target := atan2(-look.x, -look.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target, 1.0 - exp(-_VISUAL_TURN * delta))


func _set_state(s: int) -> void:
	if s == _state: return
	var old := _state
	_state = s
	state_changed.emit(old, s)


func _horizontal() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _set_horizontal(hv: Vector3) -> void:
	velocity.x = hv.x
	velocity.z = hv.z


## One definition of "wall" for bonks, wall-jumps and wall-slides: steeper than you can walk
## on (floor_max_angle), but not a ceiling.
func _is_wall(n: Vector3) -> bool:
	return n.angle_to(Vector3.UP) > floor_max_angle and n.y > _CEILING_NORMAL


func _build_fire() -> void:
	_fire = _FIRE_SCENE.instantiate() as CPUParticles3D
	_fire_light = _fire.get_node(^"Light") as OmniLight3D
	if body_mesh: _fire.layers = body_mesh.layers # hidden from your own first-person camera
	add_child(_fire)


## Electric sparks while you're in overdrive (over overdrive_speed), so everyone can see it.
func _update_sparks() -> void:
	var on := get_horizontal_speed() >= config.overdrive_speed and _state != ST_FROZEN and visual and visual.visible
	if on and not _sparks:
		_sparks = _SPARKS_SCENE.instantiate() as CPUParticles3D
		if body_mesh: _sparks.layers = body_mesh.layers # not in your own first-person view
		add_child(_sparks)
	if _sparks and _sparks.emitting != on: _sparks.emitting = on


func _build_smoke() -> void:
	_smoke_fx = _SMOKE_SCENE.instantiate() as CPUParticles3D
	if body_mesh: _smoke_fx.layers = body_mesh.layers # your own smoke stays out of your face
	add_child(_smoke_fx)


static func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(angle, -max_angle, max_angle))

#endregion
