"""
Runs classic tag rounds: countdown -> play -> results -> next round.
Hand it participants and spawn points with set_participants(), then start_round().
Lowest score wins: time burning, minus bonuses for shoving the Torch (snuffs) and kindling (shoves). Everything else (HUD, bots) listens to the signals.
"""

class_name TagManager
extends Node

signal phase_changed(phase: int)
## old_it is null at the start of a round.
signal torch_changed(new_torch: Character, old_torch: Character)
signal tagged(tagger: Character, victim: Character)
signal round_ended(standings: Array[Character])
## Someone ran into someone else hard enough to stun them.
signal bumped(attacker: Character, victim: Character)
## Kindling hid in one spot too long and started smoking (a warning: move or catch fire).
signal smoking_started(c: Character)
## Kindling ignored the smoke and caught fire: it's the Torch now. old_torch is who it took over from.
signal combusted(c: Character, old_torch: Character)
## Kindling heated up fully on the dry edge (or cooled back off).
signal smolder_changed(c: Character, smoldering: bool)

# phases
const PHASE_IDLE      := 0
const PHASE_COUNTDOWN := 1
const PHASE_PLAYING   := 2
const PHASE_RESULTS   := 3

const _NAME_COLOR  := Color(1, 1, 1, 0.9)
const _SMOKE_COLOR := Color(0.75, 0.75, 0.8, 1.0)

@export var rules: MatchRules
## Starts a new round automatically after the results screen.
@export var auto_restart: bool = true
## Where the arena is (center + radius) for the dry edge. Without one the edge rule is off.
@export var map: GameMap

var _participants: Array[Character] = []
var _spawns: Array[Vector3] = []
var _torch: Character
var _no_tagback: Character
var _torch_time: Dictionary[Character, float] = {}
var _tags_made: Dictionary[Character, int] = {}
var _snuffs: Dictionary[Character, int] = {}
var _shoves: Dictionary[Character, int] = {}
var _phase := PHASE_IDLE
var _phase_timer := 0.0
var _no_tagback_timer := 0.0
var _bump_immune: Dictionary[Character, float] = {}
# dry edge / hiding
var _heat: Dictionary[Character, float] = {}
var _smoldering: Dictionary[Character, bool] = {}
var _anchor: Dictionary[Character, Vector3] = {}
var _still: Dictionary[Character, float] = {}
var _smoke: Dictionary[Character, float] = {}


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
			if _torch: _torch_time[_torch] += delta
			_tick_bump_immunity(delta)
			_tick_edge_and_hiding(delta)
			_check_bumps() # first: a stunned Torch can't tag this tick
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
	_set_torch(null)
	_no_tagback = null
	_no_tagback_timer = 0.0
	_torch_time.clear()
	_tags_made.clear()
	_snuffs.clear()
	_shoves.clear()
	_bump_immune.clear()
	_heat.clear()
	_anchor.clear()
	_still.clear()
	for c: Character in _participants: _clear_burn_marks(c)
	_smoldering.clear()
	_smoke.clear()
	var order := _participants.duplicate()
	order.shuffle()
	for i: int in order.size():
		var c: Character = order[i]
		_torch_time[c] = 0.0
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


func get_torch() -> Character:
	return _torch


func get_participants() -> Array[Character]:
	return _participants


func get_torch_time(c: Character) -> float:
	return _torch_time.get(c, 0.0)


func get_tags_made(c: Character) -> int:
	return _tags_made.get(c, 0)


## Times c shoved the Torch this round.
func get_snuffs(c: Character) -> int:
	return _snuffs.get(c, 0)


## Times c shoved another kindling this round.
func get_shoves(c: Character) -> int:
	return _shoves.get(c, 0)


## Ranking score: time burning minus shove bonuses. Lower is better, can go negative.
func get_score(c: Character) -> float:
	return get_torch_time(c) - get_snuffs(c) * rules.snuff_bonus - get_shoves(c) * rules.shove_bonus


## 0..1, how heated up c is from standing on the dry edge.
func get_heat(c: Character) -> float:
	return _heat.get(c, 0.0)


func is_smoldering(c: Character) -> bool:
	return _smoldering.get(c, false)


## 0..1, how close c is to smoking from staying in one spot.
func get_stillness(c: Character) -> float:
	return clampf(_still.get(c, 0.0) / maxf(rules.still_time, 0.01), 0.0, 1.0)


## True while c is smoking (revealed after hiding too long).
func is_smoking(c: Character) -> bool:
	return _smoke.get(c, 0.0) > 0.0


## Seconds until a smoking c catches fire (0 if not smoking).
func get_smoke_left(c: Character) -> float:
	return _smoke.get(c, 0.0)


## Distance from c to the start of the dry edge (negative = already on it). INF without a map.
func get_edge_distance(c: Character) -> float:
	if not map: return INF
	var off := c.global_position - map.arena_center
	return map.arena_radius * rules.edge_start - Vector2(off.x, off.z).length()


## True if c can't be tagged right now (the previous Torch, during no-tag-back).
func is_tag_immune(c: Character) -> bool:
	return c == _no_tagback and _no_tagback_timer > 0.0


## Participants sorted best first (least time burning, then most tags).
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
	_set_torch(first)
	if rules.first_torch_freeze > 0.0: first.freeze(rules.first_torch_freeze)


func _end_round() -> void:
	var standings := get_standings()
	_set_torch(null)
	_set_phase(PHASE_RESULTS, rules.results_time)
	round_ended.emit(standings)


func _check_tags() -> void:
	if not _torch or _torch.is_frozen(): return # a frozen Torch can't tag
	var p := _torch.global_position
	for c: Character in _participants:
		if c == _torch or is_tag_immune(c): continue
		var d := c.global_position - p
		if absf(d.y) > rules.tag_height: continue
		if Vector2(d.x, d.z).length_squared() > rules.tag_radius * rules.tag_radius: continue
		_tag(c)
		return # one tag per tick, the new Torch is frozen anyway


## Dry edge heats kindling up (full heat = smolder = burning time without being the Torch);
## staying in one spot too long makes kindling smoke (revealed). The Torch is exempt from both.
func _tick_edge_and_hiding(delta: float) -> void:
	for c: Character in _participants:
		if c == _torch:
			_clear_burn_marks(c)
			continue
		# dry edge
		var on_edge := get_edge_distance(c) < 0.0
		var heat := clampf(_heat.get(c, 0.0) + (rules.heat_rate if on_edge else -rules.heat_drain) * delta, 0.0, 1.0)
		_heat[c] = heat
		var was_smoldering: bool = _smoldering.get(c, false)
		var smolder := heat >= 1.0 or (was_smoldering and heat > 0.5) # cool off a bit before it stops
		if smolder != was_smoldering:
			_smoldering[c] = smolder
			smolder_changed.emit(c, smolder)
		if smolder: _torch_time[c] += delta * rules.smolder_score_rate
		# hiding: frozen time doesn't count; moving away from the anchor resets it and puts the smoke out
		if not _anchor.has(c) or c.global_position.distance_to(_anchor[c]) > rules.still_distance:
			_anchor[c] = c.global_position
			_still[c] = 0.0
			_smoke[c] = 0.0
		elif not c.is_frozen():
			_still[c] += delta
		var smoke: float = _smoke.get(c, 0.0)
		if smoke > 0.0:
			smoke = maxf(smoke - delta, 0.0)
			_smoke[c] = smoke
			if not smoke:
				_combust(c)
				continue
		elif _still[c] >= rules.still_time:
			_smoke[c] = rules.smoke_time
			smoking_started.emit(c)
		_apply_burn_marks(c)


# smoke / name tag show the state to everyone
func _apply_burn_marks(c: Character) -> void:
	var level := Character.SMOKE_COLUMN if is_smoking(c) else (Character.SMOKE_LIGHT if is_smoldering(c) else Character.SMOKE_NONE)
	if c.get_smoke() == level: return
	c.set_smoke(level)
	if level == Character.SMOKE_COLUMN: c.set_name_tag("SMOKING  %s" % c.display_name, _SMOKE_COLOR)
	else: c.set_name_tag(c.display_name, _NAME_COLOR)


func _clear_burn_marks(c: Character) -> void:
	if c.get_smoke() != Character.SMOKE_NONE:
		c.set_smoke(Character.SMOKE_NONE)
		if c != _torch: c.set_name_tag(c.display_name, _NAME_COLOR)
	_smoke.erase(c)
	_still.erase(c)
	_anchor.erase(c)


## Kindling that sat through its whole smoke warning catches fire: it becomes the Torch, and the
## old Torch can't be lit straight back (same as a normal pass).
func _combust(c: Character) -> void:
	var old := _torch
	_clear_burn_marks(c)
	_no_tagback = old
	_no_tagback_timer = rules.no_tagback_time
	_set_torch(c)
	if rules.torch_freeze_time > 0.0: c.freeze(rules.torch_freeze_time)
	combusted.emit(c, old)


func _check_bumps() -> void:
	var n := _participants.size()
	# never shorter than the tag reach, or a slam into the Torch always loses to its tag
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
			if attacker == _torch: continue # the Torch touching you is a tag, not a slam
			if _bump_immune.has(victim) or victim.is_frozen(): continue
			_bump(attacker, victim, dir if attacker == a else -dir)


func _bump(attacker: Character, victim: Character, dir: Vector3) -> void:
	# points: shoving the Torch is a snuff, shoving kindling is a plain shove
	if victim == _torch: _snuffs[attacker] = get_snuffs(attacker) + 1
	else: _shoves[attacker] = get_shoves(attacker) + 1
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
	var tagger := _torch
	_tags_made[tagger] += 1
	_no_tagback = tagger
	_no_tagback_timer = rules.no_tagback_time
	_set_torch(victim)
	victim.freeze(rules.torch_freeze_time)
	tagged.emit(tagger, victim)


func _set_torch(c: Character) -> void:
	var old := _torch
	if old:
		old.speed_mult = 1.0
		old.dash_regen_mult = 1.0
		old.set_tint(old.base_tint)
		old.set_name_tag(old.display_name, _NAME_COLOR)
		old.set_burning(false)
	_torch = c
	if c:
		c.speed_mult = rules.torch_speed_mult
		c.dash_regen_mult = rules.torch_dash_regen_mult
		c.set_tint(rules.torch_color, rules.torch_glow)
		c.set_name_tag("TORCH  %s" % c.display_name, rules.torch_color, true)
		c.set_burning(true)
	if old != c: torch_changed.emit(c, old)


func _set_phase(phase: int, time: float) -> void:
	_phase = phase
	_phase_timer = time
	phase_changed.emit(phase)


func _better_than(a: Character, b: Character) -> bool:
	var sa := get_score(a)
	var sb := get_score(b)
	if not is_equal_approx(sa, sb): return sa < sb
	return get_tags_made(a) > get_tags_made(b)
