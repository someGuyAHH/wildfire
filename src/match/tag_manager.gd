"""
Runs WILDFIRE rounds: countdown -> play -> results -> next round.
Hand it participants and spawn points with set_participants(), then start_round().
The mode lives in rules.mode:
  CLASSIC  one Torch, touching someone passes the fire. Lowest score (time burning - bonuses) wins.
  SPREAD   whoever you light becomes another Torch. Ends when everyone burns or time runs out.
           Highest score (time survived + bonuses) wins.
  HUNTED   you (`focus`) vs the swarm: every bot acts as one player. They start on fire and
           hunt you; any bot lighting you puts them all out and sets you on fire; you lighting
           any bot sets the whole swarm on fire again. Score = your time not burning.
  HOT POTATO  classic passing on a fuse: whoever holds the fire when it runs out burns out
           (eliminated). A storm wall closes in; full storm heat burns you out too. Last one wins.
Everything else (HUD, bots) listens to the signals.
"""

class_name TagManager
extends Node

signal phase_changed(phase: int)
signal torch_added(c: Character)
signal torch_removed(c: Character)
signal tagged(tagger: Character, victim: Character)
signal round_ended(standings: Array[Character])
## Someone ran into someone else hard enough to stun them.
signal bumped(attacker: Character, victim: Character)
## Kindling hid in one spot too long and started smoking (a warning: move or catch fire).
signal smoking_started(c: Character)
## Kindling ignored the smoke and caught fire. old_torch is who it took the fire from (classic/hunted).
signal combusted(c: Character, old_torch: Character)
## Kindling heated up fully on the dry edge (or cooled back off).
signal smolder_changed(c: Character, smoldering: bool)
## Hot Potato: c is out of the round. reason = OUT_FUSE or OUT_STORM.
signal burned_out(c: Character, reason: int)

# phases
const PHASE_IDLE      := 0
const PHASE_COUNTDOWN := 1
const PHASE_PLAYING   := 2
const PHASE_RESULTS   := 3

# burn-out reasons
const OUT_FUSE  := 0
const OUT_STORM := 1

# hunted: which side just lost the fire
const _IMMUNE_NONE  := 0
const _IMMUNE_YOU   := 1
const _IMMUNE_SWARM := 2

const _NAME_COLOR  := Color(1, 1, 1, 0.9)
const _SMOKE_COLOR := Color(0.75, 0.75, 0.8, 1.0)

@export var rules: MatchRules
## Starts a new round automatically after the results screen.
@export var auto_restart: bool = true
## Where the arena is (center + radius) for the dry edge. Without one the edge rule is off.
@export var map: GameMap
## Hunted mode's prey (the player). Never the first Torch in Hunted.
var focus: Character

var _participants: Array[Character] = []
var _spawns: Array[Vector3] = []
## [DEBUG] This one can't be lit (tags, smoke, the edge, the storm), but is still chased.
var untaggable: Character
var _torches: Array[Character] = []
var _no_tagback: Character
var _elapsed := 0.0
var _torch_time: Dictionary[Character, float] = {}
var _tags_made: Dictionary[Character, int] = {}
var _snuffs: Dictionary[Character, int] = {}
var _shoves: Dictionary[Character, int] = {}
var _streak: Dictionary[Character, float] = {}
var _best_streak: Dictionary[Character, float] = {}
var _phase := PHASE_IDLE
var _phase_timer := 0.0
var _no_tagback_timer := 0.0
# hunted: which side just lost the fire and can't take it straight back (0 none, 1 you, 2 swarm)
var _hunted_immune := 0
var _bump_immune: Dictionary[Character, float] = {}
# dry edge / hiding
var _heat: Dictionary[Character, float] = {}
var _outside: Dictionary[Character, float] = {} # how long each has been out on the edge / in the storm, for the grace
var _smoldering: Dictionary[Character, bool] = {}
var _smolder_time: Dictionary[Character, float] = {} # how long each has smoldered on the edge, toward igniting
var _anchor: Dictionary[Character, Vector3] = {}
var _still: Dictionary[Character, float] = {}
var _smoke: Dictionary[Character, float] = {}
# hot potato / storm
var _out: Dictionary[Character, float] = {} # eliminated -> round time they went out
var _fuse := 0.0
var _storm_radius := 0.0


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
			_elapsed += delta
			_tick_scores(delta)
			_tick_fuse(delta)
			_tick_storm(delta)
			_tick_bump_immunity(delta)
			_tick_edge_and_hiding(delta)
			_check_bumps() # first: a stunned Torch can't tag this tick
			_check_tags()
			var over := rules.mode == MatchRules.MODE_SPREAD and _kindling_left() == 0
			over = over or (rules.mode == MatchRules.MODE_HOT_POTATO and alive_count() <= 1)
			if not _phase_timer or over:
				_end_round()
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
	_clear_torches()
	_no_tagback = null
	_no_tagback_timer = 0.0
	_hunted_immune = _IMMUNE_NONE
	_elapsed = 0.0
	for d: Dictionary in [_torch_time, _tags_made, _snuffs, _shoves, _streak, _best_streak,
						  _bump_immune, _heat, _outside, _anchor, _still]:
		d.clear()
	for c: Character in _participants: _clear_burn_marks(c)
	_smoldering.clear()
	_smolder_time.clear()
	_smoke.clear()
	for c: Character in _out.keys(): c.set_out(false)
	_out.clear()
	_fuse = 0.0
	_storm_radius = map.arena_radius if map else 0.0
	if map: map.set_storm(_storm_radius, false)
	var order := _participants.duplicate()
	order.shuffle()
	_pick_spawn_room(order.size()) # every mode, Spread too: its first Torch's freeze is the head start
	for i: int in order.size():
		var c: Character = order[i]
		_torch_time[c] = 0.0
		_tags_made[c] = 0
		c.teleport(_spawns[i % _spawns.size()])
		c.freeze(rules.countdown_time)
		c.set_name_tag(c.display_name, _NAME_COLOR)
	_set_phase(PHASE_COUNTDOWN, rules.countdown_time)


## Maps with several start rooms: this round starts in a random one (respawns too, till the
## next round). Fewer markers than people: topped up with a ring around the room's middle.
func _pick_spawn_room(people: int) -> void:
	if not map: return
	# Spread: spots all over the room (`spawn_spread` markers, if the map has them), as far apart as
	# they go; its first Torch walks into a crowd otherwise
	var wide: Array[PackedVector3Array] = []
	if rules.mode == MatchRules.MODE_SPREAD: wide = map.spawn_rooms(&"spawn_spread")
	if wide.size() >= 2:
		var pool: PackedVector3Array = wide.pick_random()
		if pool.size() >= people:
			_spawns = _far_apart(pool, people)
			return
	var rooms := map.spawn_rooms()
	if rooms.size() < 2: return
	var room: PackedVector3Array = rooms.pick_random()
	if room.is_empty(): return
	var spots: Array[Vector3] = []
	var mid := Vector3.ZERO
	for p: Vector3 in room:
		spots.append(p)
		mid += p
	mid /= room.size()
	var missing := people - spots.size()
	for i: int in missing:
		var a := TAU * (i + 0.5) / missing
		spots.append(mid + Vector3(cos(a), 0.0, sin(a)) * 3.5)
	_spawns = spots


# `count` of `pool`, picked so each is as far as it can be from those already picked
func _far_apart(pool: PackedVector3Array, count: int) -> Array[Vector3]:
	var left := Array(pool)
	left.shuffle()
	var out: Array[Vector3] = [left.pop_back()]
	while out.size() < count and not left.is_empty():
		var best := 0
		var best_d := -1.0
		for k: int in left.size():
			var d := INF
			for q: Vector3 in out: d = minf(d, (left[k] as Vector3).distance_squared_to(q))
			if d > best_d:
				best_d = d
				best = k
		out.append(left[best])
		left.remove_at(best)
	return out


func get_phase() -> int:
	return _phase


## Seconds left in the current phase (countdown, round or results).
func get_time_left() -> float:
	return _phase_timer


## The Torch (classic/hunted), or the first of them (spread). Null between rounds.
func get_torch() -> Character:
	return _torches[0] if not _torches.is_empty() else null


func get_torches() -> Array[Character]:
	return _torches


func is_torch(c: Character) -> bool:
	return c in _torches


## Closest burning character to `pos` (null if none). What runners run from.
func nearest_torch(pos: Vector3) -> Character:
	var best: Character
	var best_d := INF
	for t: Character in _torches:
		var d := t.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = t
	return best


func get_participants() -> Array[Character]:
	return _participants


func get_torch_time(c: Character) -> float:
	return _torch_time.get(c, 0.0)


## Seconds of this round c has spent not on fire (smoldering counts against it).
## Hot Potato: how long c lasted before burning out (still alive = the whole round so far).
func get_survived(c: Character) -> float:
	if rules.mode == MatchRules.MODE_HOT_POTATO: return _out.get(c, _elapsed)
	return maxf(_elapsed - get_torch_time(c), 0.0)


## Hot Potato: c burned out and is sitting out the rest of the round.
func is_out(c: Character) -> bool:
	return _out.has(c)


func alive_count() -> int:
	return _participants.size() - _out.size()


## Hot Potato: seconds until whoever holds the fire burns out (0 in other modes).
func get_fuse_left() -> float:
	return _fuse


func storm_active() -> bool:
	return rules.storm_enabled and map != null


## Current safe-zone radius (metres around the arena center) while the storm is on.
func get_storm_radius() -> float:
	return _storm_radius


## Longest unbroken stretch c went without being on fire this round.
func get_best_streak(c: Character) -> float:
	return _best_streak.get(c, 0.0)


func get_tags_made(c: Character) -> int:
	return _tags_made.get(c, 0)


## Times c shoved a Torch this round.
func get_snuffs(c: Character) -> int:
	return _snuffs.get(c, 0)


## Times c shoved another kindling this round.
func get_shoves(c: Character) -> int:
	return _shoves.get(c, 0)


## Ranking score. Classic: time burning minus shove bonuses (lower is better, can go negative).
## Spread/Hunted: time survived plus shove bonuses (higher is better).
func get_score(c: Character) -> float:
	var bonus := get_snuffs(c) * rules.snuff_bonus + get_shoves(c) * rules.shove_bonus
	if lower_score_wins(): return get_torch_time(c) - bonus
	return get_survived(c) + bonus


func lower_score_wins() -> bool:
	return rules.mode == MatchRules.MODE_CLASSIC


## 0..1, how heated up c is from standing on the dry edge.
func get_heat(c: Character) -> float:
	return _heat.get(c, 0.0)


func is_smoldering(c: Character) -> bool:
	return _smoldering.get(c, false)


## Seconds until smoldering c catches fire if they stay on the dry edge (INF if they won't).
func get_ignite_left(c: Character) -> float:
	if not is_smoldering(c) or rules.smolder_ignite_time <= 0.0: return INF
	return maxf(rules.smolder_ignite_time - _smolder_time.get(c, 0.0), 0.0)


## 0..1, how close c is to smoking from staying in one spot.
func get_stillness(c: Character) -> float:
	return clampf(_still.get(c, 0.0) / maxf(rules.still_time, 0.01), 0.0, 1.0)


## True while c is smoking (move or catch fire).
func is_smoking(c: Character) -> bool:
	return _smoke.get(c, 0.0) > 0.0


## Seconds until a smoking c catches fire (0 if not smoking).
func get_smoke_left(c: Character) -> float:
	return _smoke.get(c, 0.0)


## Distance from c to the start of the dry edge, or to the storm wall when the storm is on
## (negative = already past it). INF without a map.
func get_edge_distance(c: Character) -> float:
	if not map: return INF
	var off := c.global_position - map.arena_center
	var edge := _storm_radius if storm_active() else map.get_dry_edge(rules.edge_start)
	return edge - Vector2(off.x, off.z).length()


## True if c can't be lit right now (the previous Torch, during no-tag-back; in Hunted the
## whole side that just lost the fire).
func is_tag_immune(c: Character) -> bool:
	if c == untaggable: return true
	if _no_tagback_timer <= 0.0: return false
	if _hunted():
		return (_hunted_immune == _IMMUNE_YOU and c == focus) or (_hunted_immune == _IMMUNE_SWARM and c != focus)
	return c == _no_tagback


func _hunted() -> bool:
	return rules.mode == MatchRules.MODE_HUNTED and focus != null and focus in _participants


## Hunted: the swarm catches fire (everyone but you) or goes out and you catch fire.
func _hunted_set(swarm_burning: bool) -> void:
	_clear_torches()
	if swarm_burning:
		for c: Character in _participants:
			if c != focus and not is_out(c):
				_add_torch(c)
				if rules.torch_freeze_time > 0.0: c.freeze(rules.torch_freeze_time)
		_hunted_immune = _IMMUNE_YOU
	else:
		_add_torch(focus)
		if rules.torch_freeze_time > 0.0: focus.freeze(rules.torch_freeze_time)
		_hunted_immune = _IMMUNE_SWARM
	_no_tagback_timer = rules.no_tagback_time


## Participants sorted best first (by score, then most people set alight).
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
	var pool := _participants.duplicate()
	# the player never starts on fire in Hunted (it's about being chased) or Spread (you'd
	# start the whole wildfire yourself)
	var spare_focus := rules.mode == MatchRules.MODE_HUNTED or rules.mode == MatchRules.MODE_SPREAD
	if spare_focus and focus and pool.size() > 1: pool.erase(focus)
	if _hunted():
		# the swarm starts on fire, you get a head start
		for c: Character in _participants:
			if c != focus:
				_add_torch(c)
				if rules.first_torch_freeze > 0.0: c.freeze(rules.first_torch_freeze)
		return
	var first: Character = pool.pick_random()
	_add_torch(first)
	if rules.first_torch_freeze > 0.0: first.freeze(rules.first_torch_freeze)
	if rules.mode == MatchRules.MODE_HOT_POTATO: _light_fuse()


func _light_fuse() -> void:
	_fuse = maxf(rules.fuse_time + randf_range(-rules.fuse_jitter, rules.fuse_jitter), 3.0)


func _tick_fuse(delta: float) -> void:
	if rules.mode != MatchRules.MODE_HOT_POTATO or not _fuse: return
	_fuse = maxf(_fuse - delta, 0.0)
	if _fuse: return
	var holder := get_torch()
	if holder: _burn_out(holder, OUT_FUSE)


## The storm wall closes in; anyone alive outside it heats up (Torch included) and burns out
## at full heat. Inside, heat drains.
func _tick_storm(delta: float) -> void:
	if not storm_active(): return
	var t := clampf((_elapsed - rules.storm_delay) / maxf(rules.storm_shrink_time, 0.01), 0.0, 1.0)
	_storm_radius = lerpf(map.arena_radius, minf(rules.storm_end_radius, map.arena_radius), t)
	map.set_storm(_storm_radius, true)
	for c: Character in _participants:
		if is_out(c): continue
		var outside := _exposed(c, get_edge_distance(c) < 0.0, delta)
		var heat := clampf(_heat.get(c, 0.0) + (rules.storm_heat_rate if outside else -rules.heat_drain) * delta, 0.0, 1.0)
		_heat[c] = heat
		if heat >= 1.0 and c != untaggable: _burn_out(c, OUT_STORM)


# out past the line for longer than the grace? (Tracks the time; back inside resets it.)
func _exposed(c: Character, out: bool, delta: float) -> bool:
	if not out:
		_outside.erase(c)
		return false
	_outside[c] = _outside.get(c, 0.0) + delta
	return _outside[c] > rules.hazard_grace


## Hot Potato elimination. If it was the fire holder, the fire jumps to a random survivor
## (frozen for a moment so everyone can scatter) and a new fuse is lit.
func _burn_out(c: Character, reason: int) -> void:
	if is_out(c): return
	var was_torch := is_torch(c)
	_out[c] = _elapsed
	_remove_torch(c)
	_clear_burn_marks(c)
	c.set_out(true)
	burned_out.emit(c, reason)
	if not was_torch or alive_count() <= 1: return
	var alive: Array[Character] = []
	for p: Character in _participants:
		if not is_out(p): alive.append(p)
	var next: Character = alive.pick_random()
	_add_torch(next)
	if rules.first_torch_freeze > 0.0: next.freeze(rules.first_torch_freeze)
	_light_fuse()


func _end_round() -> void:
	var standings := get_standings()
	_clear_torches()
	if map: map.set_storm(0.0, false)
	_set_phase(PHASE_RESULTS, rules.results_time)
	round_ended.emit(standings)


func _tick_scores(delta: float) -> void:
	for c: Character in _participants:
		if is_out(c): continue
		if is_torch(c):
			_torch_time[c] += delta
			_streak[c] = 0.0
		else:
			var s: float = _streak.get(c, 0.0) + delta
			_streak[c] = s
			if s > _best_streak.get(c, 0.0): _best_streak[c] = s


func _kindling_left() -> int:
	return _participants.size() - _torches.size()


func _check_tags() -> void:
	# iterate a copy: lighting someone changes the list
	for t: Character in _torches.duplicate():
		if t.is_frozen() or not is_torch(t): continue # a frozen Torch can't light anyone
		var p := t.global_position
		for c: Character in _participants:
			if is_torch(c) or is_tag_immune(c) or is_out(c): continue
			var d := c.global_position - p
			if absf(d.y) > rules.tag_height: continue
			if Vector2(d.x, d.z).length_squared() > rules.tag_radius * rules.tag_radius: continue
			_tag(t, c)
			break # one per Torch per tick (the newly lit one is frozen anyway)


## Dry edge heats kindling up (full heat = smolder = burning time without being a Torch);
## staying in one spot too long makes kindling smoke, then combust. Torches are exempt.
func _tick_edge_and_hiding(delta: float) -> void:
	for c: Character in _participants:
		if is_out(c): continue
		if is_torch(c):
			_clear_burn_marks(c)
			continue
		# dry edge (the storm takes over heat when it's on)
		if storm_active():
			_tick_hiding(c, delta)
			continue
		var on_edge := get_edge_distance(c) < 0.0
		var heats := _exposed(c, on_edge, delta)
		var heat: float = _heat.get(c, 0.0)
		if heats: heat += rules.heat_rate * delta
		elif not on_edge: heat -= rules.heat_drain * delta # in the grace: it holds, neither builds nor cools
		heat = clampf(heat, 0.0, 1.0)
		_heat[c] = heat
		var was_smoldering: bool = _smoldering.get(c, false)
		var smolder := heat >= 1.0 or (was_smoldering and heat > 0.5) # cool off a bit before it stops
		if smolder != was_smoldering:
			_smoldering[c] = smolder
			smolder_changed.emit(c, smolder)
		if smolder: _torch_time[c] += delta * rules.smolder_score_rate
		# smoldering out on the edge long enough: it catches (back inside, it just smolders off)
		if smolder and on_edge and rules.smolder_ignite_time > 0.0:
			_smolder_time[c] = _smolder_time.get(c, 0.0) + delta
			if _smolder_time[c] >= rules.smolder_ignite_time:
				_smolder_time.erase(c)
				_heat[c] = 0.0
				_smoldering[c] = false
				smolder_changed.emit(c, false)
				_combust(c)
				continue
		elif not smolder: _smolder_time.erase(c)
		_tick_hiding(c, delta)


func _tick_hiding(c: Character, delta: float) -> void:
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
			return
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
		if not is_torch(c): c.set_name_tag(c.display_name, _NAME_COLOR)
	_smoke.erase(c)
	_still.erase(c)
	_anchor.erase(c)


## Kindling that sat through its whole smoke warning catches fire. Classic/Hunted: it takes the
## fire over (the old Torch can't be lit straight back). Spread: it's just one more Torch.
func _combust(c: Character) -> void:
	_clear_burn_marks(c)
	if c == untaggable: return # [DEBUG] no-tag: smoke and the edge can't light you either
	if _hunted():
		# you sat still: you're on fire and the swarm goes out. a bot sat still: the swarm burns
		var was := get_torch()
		_hunted_set(c != focus)
		combusted.emit(c, was)
		return
	var old: Character = null
	if rules.mode != MatchRules.MODE_SPREAD:
		old = get_torch()
		if old:
			_remove_torch(old)
			_no_tagback = old
			_no_tagback_timer = rules.no_tagback_time
	_add_torch(c)
	if rules.torch_freeze_time > 0.0 and rules.mode != MatchRules.MODE_SPREAD: c.freeze(rules.torch_freeze_time)
	combusted.emit(c, old)


func _check_bumps() -> void:
	var n := _participants.size()
	for i: int in n:
		var a := _participants[i]
		if is_out(a): continue
		var sa := a.get_capsule_segment()
		var ra := a.get_body_radius()
		for j: int in range(i + 1, n):
			var b := _participants[j]
			if is_out(b): continue
			# touching = the real capsules (crouching shrinks them) within reach of each other.
			# never shorter than the tag reach, or a slam into a Torch always loses to its tag
			var rb := b.get_body_radius()
			var reach := maxf(rules.bump_margin, rules.tag_radius - ra - rb)
			if _capsule_gap(sa, ra, b.get_capsule_segment(), rb) > reach: continue
			if _try_stomp(a, b) or _try_stomp(b, a): continue
			var d := b.global_position - a.global_position
			var flat := Vector3(d.x, 0.0, d.z)
			if flat.length_squared() < 0.0001: continue
			var dir := flat.normalized() # a -> b
			# plain velocity on purpose: a point-blank dash into someone counts (no run-up needed)
			var va := Vector3(a.velocity.x, 0.0, a.velocity.z).dot(dir)   # a moving toward b
			var vb := -Vector3(b.velocity.x, 0.0, b.velocity.z).dot(dir)  # b moving toward a
			if va + vb < rules.bump_speed: continue
			# whoever brought more of the speed is the one doing the slamming
			var attacker := a if va >= vb else b
			var victim := b if attacker == a else a
			if is_torch(attacker): continue # a Torch touching you lights you, it's not a shove
			if _bump_immune.has(victim) or victim.is_frozen(): continue
			_bump(attacker, victim, dir if attacker == a else -dir)


## Gap between two upright capsules (core segments + radii); negative when they overlap.
static func _capsule_gap(sa: PackedVector3Array, ra: float, sb: PackedVector3Array, rb: float) -> float:
	var flat := Vector2(sb[0].x - sa[0].x, sb[0].z - sa[0].z).length()
	var gap_y := maxf(0.0, maxf(sb[0].y - sa[1].y, sa[0].y - sb[1].y))
	return Vector2(flat, gap_y).length() - ra - rb


## Slamming down onto someone from high enough: they're stunned like a shove, you bounce off.
## Returns true if it was a stomp (handled, so it isn't also checked as a shove).
func _try_stomp(attacker: Character, victim: Character) -> bool:
	if not attacker.is_slamming() or is_torch(attacker): return false
	if attacker.get_drop_height() < rules.stomp_min_drop: return false
	# coming down on top of them, not dropping past their side
	if attacker.global_position.y < victim.get_capsule_segment()[1].y: return false
	if _bump_immune.has(victim) or victim.is_frozen(): return true
	if is_torch(victim): _snuffs[attacker] = get_snuffs(attacker) + 1
	else: _shoves[attacker] = get_shoves(attacker) + 1
	victim.freeze(rules.bump_stun)
	_bump_immune[victim] = rules.bump_immunity
	_bump_immune[attacker] = rules.bump_immunity
	attacker.launch(Vector3.UP * rules.stomp_bounce, true)
	bumped.emit(attacker, victim)
	return true


func _bump(attacker: Character, victim: Character, dir: Vector3) -> void:
	# points: shoving a Torch is a snuff, shoving kindling is a plain shove
	if is_torch(victim): _snuffs[attacker] = get_snuffs(attacker) + 1
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


func _tag(tagger: Character, victim: Character) -> void:
	_tags_made[tagger] += 1
	if _hunted():
		_hunted_set(victim != focus) # lit a bot: the whole swarm burns. lit you: they all go out
		tagged.emit(tagger, victim)
		return
	if rules.mode != MatchRules.MODE_SPREAD:
		# pass the fire: the tagger goes out and can't be lit straight back
		_remove_torch(tagger)
		_no_tagback = tagger
		_no_tagback_timer = rules.no_tagback_time
	_add_torch(victim)
	# a fresh Torch freezes so the one who lit it can get away; in Spread nobody's getting away
	# (the tagger stays a Torch too), so no freeze there
	if rules.mode != MatchRules.MODE_SPREAD: victim.freeze(rules.torch_freeze_time)
	tagged.emit(tagger, victim)


func _add_torch(c: Character) -> void:
	if is_torch(c): return
	_torches.append(c)
	c.speed_mult = rules.torch_speed_mult
	c.dash_regen_mult = rules.torch_dash_regen_mult
	c.set_tint(rules.torch_color, rules.torch_glow)
	c.set_name_tag("TORCH  %s" % c.display_name, rules.torch_color, true)
	c.set_burning(true)
	torch_added.emit(c)


func _remove_torch(c: Character) -> void:
	if not is_torch(c): return
	_torches.erase(c)
	c.speed_mult = 1.0
	c.dash_regen_mult = 1.0
	c.set_tint(c.base_tint)
	c.set_name_tag(c.display_name, _NAME_COLOR)
	c.set_burning(false)
	torch_removed.emit(c)


func _clear_torches() -> void:
	for t: Character in _torches.duplicate(): _remove_torch(t)


func _set_phase(phase: int, time: float) -> void:
	_phase = phase
	_phase_timer = time
	phase_changed.emit(phase)


func _better_than(a: Character, b: Character) -> bool:
	var sa := get_score(a)
	var sb := get_score(b)
	if not is_equal_approx(sa, sb): return sa < sb if lower_score_wins() else sa > sb
	return get_tags_made(a) > get_tags_made(b)
