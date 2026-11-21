class_name EarRing
extends Node
## The ringing in the player's ears after a hard stop or a wall bonk, like a flashbang but soft: a steady
## high tone (about 3.2 kHz, gently beating) that rings for as long as they are dizzy or disoriented. It
## starts at its peak and fades away with what is left of the dizziness, and while it rings the SFX and
## Ambience buses are muffled (low-passed) by the same amount. Local player only, flat. It stops at once on
## burning out, the round ending, leaving the match and pausing, and always puts the muffle back.
## Peak level: the `tinnitus` sound's volume_db in the bank; the curve, attack and muffle: SfxBank.ring_*.

var _c: Character
var _tm: TagManager
var _player: AudioStreamPlayer
var _t := 0.0                 # own clock (seconds)
var _dis_total := 0.01        # the disorientation's length when it began, for its share left
var _dis_prev := 0.0
var _dizzy_end := 0.0         # when the brake-spam dizziness ends on _t
var _dizzy_total := 0.01
var _level := 0.0             # 0..1 now (rises over the attack, then follows what is left)


func setup(c: Character, tm: TagManager) -> void:
	_c = c
	_tm = tm
	_player = SFX.loop_ring(&"tinnitus", self)
	c.dizzy_changed.connect(_on_dizzy_changed)
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _exit_tree() -> void:
	SFX.set_muffle(0.0, 20500.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED: _silence() # a pause cuts it, and the muffle with it


func _on_dizzy_changed(on: bool) -> void:
	if on:
		_dizzy_total = maxf(_c.config.dizzy_duration, 0.01)
		_dizzy_end = _t + _dizzy_total


## The share of the dizziness left now, 0..1 (1 at the moment it begins).
func share_left() -> float:
	var left := _c.get_disorient_time()
	if left > _dis_prev + 0.001: _dis_total = left # (a new or longer disorientation)
	_dis_prev = left
	var dis := clampf(left / _dis_total, 0.0, 1.0) if left > 0.0 else 0.0
	var dizzy := clampf((_dizzy_end - _t) / _dizzy_total, 0.0, 1.0)
	return maxf(dis, dizzy)


func _process(delta: float) -> void:
	_t += delta
	if not _c or not is_instance_valid(_c): return
	var raw := share_left()
	var over := _tm != null and (_tm.is_out(_c) or _tm.get_phase() != TagManager.PHASE_PLAYING)
	if over:
		_silence()
		return
	var bank := SFX.BANK
	var want := pow(raw, bank.ring_curve)
	# up over the attack (no click), down exactly with what is left
	_level = minf(_level + delta / bank.ring_attack, want) if want > _level else want
	_apply(bank)


func _apply(bank: SfxBank) -> void:
	if _level <= 0.001:
		_silence()
		return
	_player.volume_db = SFX.get_def(&"tinnitus").volume_db + linear_to_db(_level)
	if not _player.playing:
		_player.play()
		SFX.note_loop(&"tinnitus")
	SFX.set_muffle(_level, bank.ring_muffle_hz)


func _silence() -> void:
	_level = 0.0
	_dizzy_end = 0.0
	_dis_prev = 0.0
	if _player and _player.playing: _player.stop()
	SFX.set_muffle(0.0, 20500.0)


## The ring's level now, 0..1 (for checks).
func get_level() -> float:
	return _level
