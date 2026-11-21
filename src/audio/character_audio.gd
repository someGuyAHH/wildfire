class_name CharacterAudio
extends Node
## What one runner sounds like (the player and every bot the same, from where it stands): footsteps on the
## ground it runs on, jumps, landings, dashes, wall kicks and slides, the slam, the vault, skids and bonks,
## and the loops: sliding, wall-sliding, burning, kindling heating up, the Hot Potato fuse. The player also
## gets the wind of their own speed. Sounds are asked for through SFX, which keeps the voices down.
## A child of its Character; Main adds one to everybody in a match.

## Metres of ground covered per footstep at standstill speed; it grows with speed (long strides when fast).
const _STRIDE_BASE := 1.7
const _STRIDE_PER_SPEED := 0.11
const _STRIDE_MAX := 3.6
const _STEP_MIN_SPEED := 1.5
## Falling this fast (m/s) on landing is heard, and this fast is a heavy landing.
const _LAND_MIN := 4.0
const _LAND_HEAVY := 16.0
const _LEVEL_RATE := 9.0 # loop fade, 1/s

class Voice extends RefCounted:
	var id: StringName
	var p3: AudioStreamPlayer3D # in the world, or ...
	var p2: AudioStreamPlayer   # ... flat (the player's own wind)
	var level := 0.0 # 0..1 now
	var want := 0.0  # where it's heading

	func is_playing() -> bool:
		return p3.playing if p3 else p2.playing

	func stop() -> void:
		if p3: p3.stop()
		else: p2.stop()

	func start_and_set(db: float) -> void:
		if p3:
			p3.volume_db = db
			if not p3.playing:
				p3.play(randf() * p3.stream.get_length())
				SFX.note_loop(id)
		else:
			p2.volume_db = db
			if not p2.playing:
				p2.play(randf() * p2.stream.get_length())
				SFX.note_loop(id)

var _c: Character
var _tm: TagManager
var _is_player := false
var _stride := 0.0
var _slamming := false
var _slam_pending := false
var _voices: Dictionary[StringName, Voice] = {}
var _step_ids: Dictionary[StringName, StringName] = {}


func setup(c: Character, tm: TagManager, is_player: bool) -> void:
	_c = c
	_tm = tm
	_is_player = is_player
	c.jumped.connect(_on_jumped)
	c.landed.connect(_on_landed)
	c.dashed.connect(_on_dashed)
	c.braked.connect(_on_braked)
	c.wall_bonked.connect(_on_bonked)
	c.state_changed.connect(_on_state_changed)
	for id: StringName in [&"slide_loop", &"wall_slide_loop", &"torch_loop", &"smolder_loop", &"fuse_loop"]:
		_voices[id] = _make_voice(id, false)
	if is_player: _voices[&"wind_speed"] = _make_voice(&"wind_speed", true)


func _make_voice(id: StringName, flat: bool) -> Voice:
	var v := Voice.new()
	v.id = id
	if flat: v.p2 = SFX.loop_2d(id, self)
	else: v.p3 = SFX.loop_3d(id, _c)
	return v


func _physics_process(delta: float) -> void:
	if not _c or not is_instance_valid(_c): return
	if _slam_pending:
		_slam_pending = false
		SFX.play_at(&"slam_start", _c.global_position)
	var speed := _c.get_horizontal_speed()
	var running := _c.is_on_floor() and _c.get_state() == Character.ST_GROUNDED and speed >= _STEP_MIN_SPEED
	if not running:
		_stride = minf(_stride, _stride_len(speed) * 0.5) # the first step after landing doesn't come at once
		return
	_stride += speed * delta
	var stride := _stride_len(speed)
	if _stride >= stride:
		_stride = fmod(_stride, stride)
		_step(speed)


func _stride_len(speed: float) -> float:
	return clampf(_STRIDE_BASE + speed * _STRIDE_PER_SPEED, _STRIDE_BASE, _STRIDE_MAX)


func _step(speed: float) -> void:
	var kind := _surface()
	var id: StringName = _step_ids.get(kind, &"")
	if id == &"":
		id = StringName("step_" + kind)
		if not SFX.has_sound(id): id = &"step_concrete"
		_step_ids[kind] = id
	SFX.play_at(id, _c.global_position, linear_to_db(clampf(speed / 9.0, 0.35, 1.0)), 1.0 + clampf((speed - 8.0) * 0.012, -0.05, 0.2))


## The ground under foot: a floor collider can name its own surface (meta "surface"), else the map's.
func _surface() -> StringName:
	for i: int in _c.get_slide_collision_count():
		var col := _c.get_slide_collision(i)
		if col.get_normal().y < 0.7: continue
		var body := col.get_collider() as Node
		if body and body.has_meta(&"surface"): return StringName(body.get_meta(&"surface"))
	return SFX.surface


func _on_jumped(kind: int) -> void:
	var at := _c.global_position
	match kind:
		Character.JUMP_GROUND, Character.JUMP_DASH: SFX.play_at(&"jump", at)
		Character.JUMP_WALL: SFX.play_at(&"wall_jump", at)
		Character.JUMP_SLAM_BOUNCE: SFX.play_layers(&"slam_jump", at, _c.config.slam_jump_intensity(_c.velocity.y))
		Character.JUMP_VAULT: SFX.play_at(&"vault", at)
		Character.JUMP_LAUNCH: SFX.play_at(&"pad_launch", at)


func _on_landed(impact_speed: float) -> void:
	var at := _c.global_position
	if _slamming:
		_slamming = false
		SFX.play_at(&"slam_land", at, linear_to_db(clampf(impact_speed / 40.0, 0.5, 1.0)))
		return
	if impact_speed < _LAND_MIN: return
	var vol := linear_to_db(clampf(impact_speed / _LAND_HEAVY, 0.4, 1.0))
	SFX.play_at(&"land_heavy" if impact_speed >= _LAND_HEAVY else &"land_light", at, vol)


func _on_dashed(_dir: Vector3) -> void:
	SFX.play_at(&"dash", _c.global_position)


func _on_braked(kind: int) -> void:
	if kind == Character.BRAKE_AIR:
		_slam_pending = false # the brake slam has its own whoosh, not the slam's
		SFX.play_at(&"brake_air", _c.global_position)
	# (a ground brake is silent: a hard stop's dizziness has its own ear ring, see EarRing)


func _on_bonked(impact_speed: float) -> void:
	SFX.play_at(&"bonk", _c.global_position, linear_to_db(clampf(impact_speed / 30.0, 0.85, 1.0)))


# the slam's whoosh waits one tick: a brake slam (Q in the air) says so right after, with its own sound
func _on_state_changed(old: int, new: int) -> void:
	if new == Character.ST_SLAMMING:
		_slamming = true
		_slam_pending = true
	elif old == Character.ST_SLAMMING and (new == Character.ST_DASHING or new == Character.ST_FROZEN):
		_slamming = false # cut short: its landing is an ordinary one


func _process(delta: float) -> void:
	if not _c or not is_instance_valid(_c): return
	var out := _tm != null and _tm.is_out(_c)
	var speed := _c.get_horizontal_speed()
	var dist := SFX.listener_distance(_c.global_position)
	_want(&"slide_loop", 0.0 if out or _c.get_state() != Character.ST_SLIDING or not _c.is_on_floor() \
			else clampf(speed / 10.0, 0.25, 1.0), dist)
	_want(&"wall_slide_loop", 1.0 if _c.is_wall_sliding() and not out else 0.0, dist)
	var torch := _tm != null and not out and _tm.is_torch(_c)
	_want(&"torch_loop", 1.0 if torch else 0.0, dist)
	var heat := 0.0
	if _tm and not out: heat = 1.0 if _tm.is_smoldering(_c) else clampf(_tm.get_heat(_c) * 1.5, 0.0, 1.0)
	_want(&"smolder_loop", heat, dist)
	_want(&"fuse_loop", 1.0 if torch and _tm.rules.mode == MatchRules.MODE_HOT_POTATO and _tm.get_fuse_left() > 0.0 else 0.0, dist)
	if _is_player:
		var wind := clampf((speed - 10.0) / 32.0, 0.0, 1.0)
		var v := _voices[&"wind_speed"]
		v.want = wind * wind
		v.p2.pitch_scale = lerpf(0.8, 1.35, wind)
	for v: Voice in _voices.values(): _fade(v, delta)


# the nearest few of each loop get to play: ask, and the grant arrives a frame later
func _want(id: StringName, level: float, dist: float) -> void:
	var v := _voices[id]
	if level > 0.0:
		SFX.loop_wanted(id, self, dist)
		v.want = level if SFX.loop_granted(id, self) else 0.0
	else:
		v.want = 0.0


func _fade(v: Voice, delta: float) -> void:
	v.level = move_toward(v.level, v.want, delta * _LEVEL_RATE)
	if v.level <= 0.001:
		if v.is_playing(): v.stop()
		return
	v.start_and_set(SFX.get_def(v.id).volume_db + linear_to_db(v.level))
