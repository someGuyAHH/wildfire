"""
Runs classic tag rounds: countdown -> play -> results -> next round.
Hand it participants and spawn points with set_participants(), then start_round().
Lowest total time as It wins. Everything else (HUD, bots) listens to the signals.
"""

class_name TagManager
extends Node

signal phase_changed(phase: int)
## old_it is null at the start of a round.
signal it_changed(new_it: Character, old_it: Character)
signal tagged(tagger: Character, victim: Character)
signal round_ended(standings: Array[Character])
## Someone ran into someone else hard enough to stun them.
signal bumped(attacker: Character, victim: Character)

# phases
const PHASE_IDLE      := 0
const PHASE_COUNTDOWN := 1
const PHASE_PLAYING   := 2
const PHASE_RESULTS   := 3

const _NAME_COLOR := Color(1, 1, 1, 0.9)

@export var rules: MatchRules
## Starts a new round automatically after the results screen.
@export var auto_restart: bool = true

var _participants: Array[Character] = []
var _spawns: Array[Vector3] = []
var _it: Character
var _no_tagback: Character
var _it_time: Dictionary[Character, float] = {}
var _tags_made: Dictionary[Character, int] = {}
var _phase := PHASE_IDLE
var _phase_timer := 0.0
var _no_tagback_timer := 0.0
var _bump_immune: Dictionary[Character, float] = {}


func _ready() -> void:
	if not rules:
		push_error("TagManager has no MatchRules, using defaults")
		rules = MatchRules.new()


func _physics_process(delta: float) -> void:
	match _phase:
		PHASE_COUNTDOWN:
			_phase_timer = maxf(_phase_timer - delta, 0.0)
			if not _phase_timer: _begin_play()
		PHASE_PLAYING:
			_phase_timer = maxf(_phase_timer - delta, 0.0)
			_no_tagback_timer = maxf(_no_tagback_timer - delta, 0.0)
			if _it: _it_time[_it] += delta
			_tick_bump_immunity(delta)
			_check_bumps() # first: a stunned It can't tag this tick
			_check_tags()
			if not _phase_timer: _end_round()
		PHASE_RESULTS:
			_phase_timer = maxf(_phase_timer - delta, 0.0)
			if not _phase_timer and auto_restart: start_round()


## Sets who plays and where they spawn (cycled if there are fewer spawns than players).
## Returns true on success, false on fail.
func set_participants(list: Array[Character], spawns: Array[Vector3]) -> bool:
	if list.size() < 2:
		push_error("Tag needs at least 2 participants, got %d" % list.size())
		return false
	if spawns.is_empty():
		push_error("set_participants() needs at least one spawn point")
		return false
	_participants = list.duplicate()
	_spawns = spawns.duplicate()
	return true


## Resets scores, puts everyone on a spawn and starts the countdown.
func start_round() -> void:
	if _participants.size() < 2:
		push_error("Call set_participants() before start_round()")
		return
	_set_it(null)
	_no_tagback = null
	_no_tagback_timer = 0.0
	_it_time.clear()
	_tags_made.clear()
	_bump_immune.clear()
	var order := _participants.duplicate()
	order.shuffle()
	for i: int in order.size():
		var c: Character = order[i]
		_it_time[c] = 0.0
		_tags_made[c] = 0
		c.teleport(_spawns[i % _spawns.size()])
		c.freeze(rules.countdown_time)
		c.set_name_tag(c.display_name, _NAME_COLOR)
	_set_phase(PHASE_COUNTDOWN, rules.countdown_time)


func get_phase() -> int:
	return _phase


## Seconds left in the current phase (countdown, round or results).
func get_time_left() -> float:
	return _phase_timer


func get_it() -> Character:
	return _it


func get_participants() -> Array[Character]:
	return _participants


func get_it_time(c: Character) -> float:
	return _it_time.get(c, 0.0)


func get_tags_made(c: Character) -> int:
	return _tags_made.get(c, 0)


## True if c can't be tagged right now (the previous It, during no-tag-back).
func is_tag_immune(c: Character) -> bool:
	return c == _no_tagback and _no_tagback_timer > 0.0


## Participants sorted best first (least time as It, then most tags).
func get_standings() -> Array[Character]:
	var out := _participants.duplicate()
	out.sort_custom(_better_than)
	return out


## Puts a character back on a random spawn (fell off the map, pressed respawn).
func respawn(c: Character) -> void:
	if _spawns.is_empty(): return
	c.teleport(_spawns.pick_random())


func _begin_play() -> void:
	_set_phase(PHASE_PLAYING, rules.round_time)
	var first: Character = _participants.pick_random()
	_set_it(first)
	if rules.first_it_freeze > 0.0: first.freeze(rules.first_it_freeze)


func _end_round() -> void:
	var standings := get_standings()
	_set_it(null)
	_set_phase(PHASE_RESULTS, rules.results_time)
	round_ended.emit(standings)


func _check_tags() -> void:
	if not _it or _it.is_frozen(): return # a frozen It can't tag
	var p := _it.global_position
	for c: Character in _participants:
		if c == _it or is_tag_immune(c): continue
		var d := c.global_position - p
		if absf(d.y) > rules.tag_height: continue
		if Vector2(d.x, d.z).length_squared() > rules.tag_radius * rules.tag_radius: continue
		_tag(c)
		return # one tag per tick, the new It is frozen anyway


func _check_bumps() -> void:
	var n := _participants.size()
	# never shorter than the tag reach, or a slam into the It always loses to its tag
	var r := maxf(rules.bump_radius, rules.tag_radius)
	var r2 := r * r
	for i: int in n:
		var a := _participants[i]
		for j: int in range(i + 1, n):
			var b := _participants[j]
			var d := b.global_position - a.global_position
			if absf(d.y) > rules.tag_height: continue
			var flat := Vector3(d.x, 0.0, d.z)
			if flat.length_squared() > r2 or flat.length_squared() < 0.0001: continue
			var dir := flat.normalized() # a -> b
			# plain velocity on purpose: a point-blank dash into someone counts (no run-up needed)
			var va := Vector3(a.velocity.x, 0.0, a.velocity.z).dot(dir)   # a moving toward b
			var vb := -Vector3(b.velocity.x, 0.0, b.velocity.z).dot(dir)  # b moving toward a
			if va + vb < rules.bump_speed: continue
			# whoever brought more of the speed is the one doing the slamming
			var attacker := a if va >= vb else b
			var victim := b if attacker == a else a
			if attacker == _it: continue # the It touching you is a tag, not a slam
			if _bump_immune.has(victim) or victim.is_frozen(): continue
			_bump(attacker, victim, dir if attacker == a else -dir)


func _bump(attacker: Character, victim: Character, dir: Vector3) -> void:
	victim.freeze(rules.bump_stun)
	_bump_immune[victim] = rules.bump_immunity
	_bump_immune[attacker] = rules.bump_immunity # no instant counter-slam either
	attacker.knockback(-dir * rules.bump_knockback + Vector3.UP * rules.bump_knockback * 0.4)
	attacker.disorient(rules.bump_attacker_disorient)
	bumped.emit(attacker, victim)


func _tick_bump_immunity(delta: float) -> void:
	for c: Character in _bump_immune.keys():
		_bump_immune[c] -= delta
		if _bump_immune[c] <= 0.0: _bump_immune.erase(c)


func _tag(victim: Character) -> void:
	var tagger := _it
	_tags_made[tagger] += 1
	_no_tagback = tagger
	_no_tagback_timer = rules.no_tagback_time
	_set_it(victim)
	victim.freeze(rules.it_freeze_time)
	tagged.emit(tagger, victim)


func _set_it(c: Character) -> void:
	var old := _it
	if old:
		old.speed_mult = 1.0
		old.dash_regen_mult = 1.0
		old.set_tint(old.base_tint)
		old.set_name_tag(old.display_name, _NAME_COLOR)
	_it = c
	if c:
		c.speed_mult = rules.it_speed_mult
		c.dash_regen_mult = rules.it_dash_regen_mult
		c.set_tint(rules.it_color, rules.it_glow)
		c.set_name_tag("IT  %s" % c.display_name, rules.it_color, true)
	if old != c: it_changed.emit(c, old)


func _set_phase(phase: int, time: float) -> void:
	_phase = phase
	_phase_timer = time
	phase_changed.emit(phase)


func _better_than(a: Character, b: Character) -> bool:
	var ta := get_it_time(a)
	var tb := get_it_time(b)
	if not is_equal_approx(ta, tb): return ta < tb
	return get_tags_made(a) > get_tags_made(b)
