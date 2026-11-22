class_name MatchAudio
extends Node
## The round's own sounds, from the TagManager's events: catching fire and going out, shoves, the smoke
## column's warning (cooling off, in Freeze), Hot Potato's fuse and its explosion, the storm closing in,
## the countdown and the round's win or lose; Freeze's freezing and melting, hunter's sense's ping. Where there is a place for it, it sounds there (the player hears it from
## where they are); the countdown, the storm and the verdict are flat. Main adds one per match.

const _FUSE_TICK_FAR := 8.0 # seconds left when the ticking starts, slow
const _TICK_SLOW := 0.8
const _TICK_FAST := 0.11

var _tm: TagManager
var _player: Character
var _count_shown := -1
var _tick_in := 0.0
var _storm_on := false
var _storm_loop: AudioStreamPlayer
var _storm_level := 0.0


func setup(tm: TagManager, player: Character) -> void:
	_tm = tm
	_player = player
	tm.phase_changed.connect(_on_phase_changed)
	tm.torch_added.connect(_on_torch_added)
	tm.torch_removed.connect(_on_torch_removed)
	tm.bumped.connect(_on_bumped)
	tm.smoking_started.connect(_on_smoking_started)
	tm.burned_out.connect(_on_burned_out)
	tm.round_ended.connect(_on_round_ended)
	tm.tagged.connect(_on_tagged)
	tm.thawed.connect(_on_thawed)
	tm.cooled.connect(_on_cooled)
	tm.sensed.connect(_on_sensed)
	_storm_loop = SFX.loop_2d(&"storm_loop", self)


func _process(delta: float) -> void:
	if not _tm: return
	if _tm.get_phase() == TagManager.PHASE_COUNTDOWN: _tick_countdown()
	else: _count_shown = -1
	_tick_fuse(delta)
	_tick_storm(delta)


# 3, 2, 1 as the seconds turn over
func _tick_countdown() -> void:
	var n := ceili(_tm.get_time_left())
	if n == _count_shown or n <= 0: return
	_count_shown = n
	SFX.play(&"countdown_beep", 0.0, 1.0 + (3 - mini(n, 3)) * 0.06)


# Hot Potato: the Torch's fuse ticks, faster as it burns down
func _tick_fuse(delta: float) -> void:
	if _tm.rules.mode != MatchRules.MODE_HOT_POTATO or _tm.get_phase() != TagManager.PHASE_PLAYING: return
	var left := _tm.get_fuse_left()
	var holder := _tm.get_torch()
	if left <= 0.0 or left > _FUSE_TICK_FAR or not holder: return
	_tick_in -= delta
	if _tick_in > 0.0: return
	var urgency := 1.0 - left / _FUSE_TICK_FAR
	_tick_in = lerpf(_TICK_SLOW, _TICK_FAST, urgency * urgency)
	SFX.play_at(&"fuse_tick", holder.global_position + Vector3.UP, urgency * 3.0, 1.0 + urgency * 0.35)


# the storm: a rumble that swells as you get caught outside it
func _tick_storm(delta: float) -> void:
	var on := _tm.storm_active() and _tm.get_phase() == TagManager.PHASE_PLAYING \
			and _tm.rules.round_time - _tm.get_time_left() >= _tm.rules.storm_delay # (it starts closing in after its delay)
	if on and not _storm_on: SFX.play(&"storm_start")
	_storm_on = on
	var heat := _tm.get_heat(_player) if _player and is_instance_valid(_player) else 0.0
	var want := (0.25 + 0.75 * heat) if on else 0.0
	_storm_level = move_toward(_storm_level, want, delta * 0.5)
	if _storm_level <= 0.001:
		if _storm_loop.playing: _storm_loop.stop()
		return
	_storm_loop.volume_db = SFX.get_def(&"storm_loop").volume_db + linear_to_db(_storm_level)
	_storm_loop.pitch_scale = 0.9 + 0.3 * _storm_level
	if not _storm_loop.playing:
		_storm_loop.play()
		SFX.note_loop(&"storm_loop")


func _on_phase_changed(phase: int) -> void:
	if phase == TagManager.PHASE_PLAYING: SFX.play(&"countdown_go")


func _on_torch_added(c: Character) -> void:
	SFX.play_at(&"ignite", c.global_position + Vector3.UP)


func _on_torch_removed(c: Character) -> void:
	SFX.play_at(&"extinguish", c.global_position + Vector3.UP)


func _on_bumped(_attacker: Character, victim: Character) -> void:
	SFX.play_at(&"shove", victim.global_position + Vector3.UP)


func _on_smoking_started(c: Character) -> void:
	var id := &"cooling_warn" if _tm.rules.mode == MatchRules.MODE_FREEZE else &"smoke_warn"
	SFX.play_at(id, c.global_position + Vector3.UP * 2.0)


# Freeze: a Torch's touch freezes the runner solid (in the other modes it's the ignite, from torch_added)
func _on_tagged(_tagger: Character, victim: Character) -> void:
	if _tm.rules.mode == MatchRules.MODE_FREEZE: _freeze_sound(victim)


func _on_cooled(c: Character) -> void:
	_freeze_sound(c)


# You (or whoever you're watching) freezing: the spectate view moves the camera, the listener, off to
# someone else right away, and a crack placed at the victim would fade out mid-sound with the distance.
# It's happening to you: flat, in your ears. Anyone else's freeze sounds where it is.
func _freeze_sound(c: Character) -> void:
	if _watching(c): SFX.play(&"freeze")
	else: SFX.play_at(&"freeze", c.global_position + Vector3.UP)


func _watching(c: Character) -> bool:
	if not _player or not is_instance_valid(_player): return false
	if c == _player: return true
	var rig := _player.get_node_or_null(^"CameraRig")
	return rig != null and rig.get(&"spectating") == c


func _on_thawed(_thawer: Character, c: Character) -> void:
	SFX.play_at(&"thaw_done", c.global_position + Vector3.UP)


# hunter's sense: the ping is for the Torches (it's their hint), flat
func _on_sensed(_c: Character) -> void:
	if _player and is_instance_valid(_player) and _tm.is_torch(_player): SFX.play(&"sense_ping")


func _on_burned_out(c: Character, reason: int) -> void:
	var at := c.global_position + Vector3.UP
	if reason == TagManager.OUT_FUSE: SFX.play_at(&"explosion", at)
	else: SFX.play_at(&"explosion", at, -7.0, 1.25) # the storm got them: a smaller bang


func _on_round_ended(standings: Array[Character]) -> void:
	if not _player or standings.is_empty(): return
	SFX.play(&"win" if standings[0] == _player else &"lose")
