extends Node

# bot brain v1 (M3). perceives with line-of-sight rays plus a hearing radius, makes decisions
# every skill.reaction_time, paths on the navmesh and drives the same CharacterIntent a player does.
#   Torch:   picks the best target, intercepts where it's heading, goes direct + dashes up close.
#   runner:  once it notices the Torch, picks the best escape point on a ring around itself
#            (far from the Torch, not running past it, inside the arena) and jukes when it's close.
#   nothing: wanders between random navmesh points.
#   beef:    runners keep a suspicion meter on other runners hovering near them / staring at them /
#            dashing at them. full meter = "oh you're trying to slam me": the bot either charges
#            back to slam first or noped out of there, with a shout over its head.

const GOAL_WANDER := 0
const GOAL_CHASE  := 1
const GOAL_SEARCH := 2
const GOAL_FLEE   := 3

const _EYE           := Vector3(0.0, 1.5, 0.0)
const _WORLD_MASK    := 1
const _CORNER_REACH  := 1.4
const _DIRECT_RANGE  := 9.0    # chase straight at a visible target closer than this
const _JUKE_RANGE    := 4.5
const _JUKE_TIME     := 0.35
const _STUCK_SPEED   := 1.5
const _STUCK_TIME    := 0.6
const _FLEE_RING_MIN := 18.0
const _FLEE_RING_MAX := 45.0
const _FLEE_REPICK   := 1.2    # max age of an escape point before it's reconsidered
const _WANDER_RADIUS := 25.0
const _WANDER_SPEED  := 0.55
const _SLIDE_MAX     := 3.0    # slides decay below run speed after this
const _JUMP_HOLD     := 0.25
const _OFF_MESH      := 4.0    # sampled points snapping further than this were inside walls
const _UNREACH_DIST  := 2.5    # path ends this far from the target = target is up somewhere
const _UNREACH_TIME  := 4.0    # how long a target stays marked unreachable
# suspicion / beef
const _SUS_RANGE     := 9.0    # past this nobody looks suspicious
const _SUS_CLOSE     := 5.0
const _SUS_DASH_RANGE := 6.0   # a dash only reads as a slam attempt from this close...
const _SUS_DASH_AIM  := 20.0   # ...and aimed at us (28 m/s dash, >20 toward us = within ~45°)
const _SWITCH_CLOSE  := 6.0    # a committed Torch still swaps to someone this close...
const _SUS_DECAY     := 0.8    # per second, so just walking past never adds up
const _SUS_MAX       := 8.0
const _SWITCH_RATIO  := 0.5    # ...if they're under half as far as the current target
const _TEAM_SPREAD   := 12.0   # target score penalty per other Torch already chasing them
const _FLANK_OFFSET  := 9.0    # how wide a second hunter swings to come from the side
const _BEEF_MIN      := 4.0
const _BEEF_MAX      := 6.0
const _BEEF_TORCH_SAFE  := 20.0   # if the Torch is noticed closer than this, survival beats beef
const _DODGE_RANGE   := 6.0    # sidestep slam dashes coming from closer than this
const _DODGE_CLOSING := 15.0
const _DODGE_CHANCE  := 0.55   # times juke_skill: even a sharp bot doesn't always get out of the way
const _DODGE_VIEW    := 0.25   # cos of the half-angle a dash has to come from to be seen (~75°)
# hazards / snuffs
const _HEAT_FLEE     := 0.25   # heat above this: head back inside
const _HAZARD_SAFE   := 8.0    # ...unless the Torch is closer than this (running from it wins)
const _STILL_MOVE    := 0.55   # stillness above this: go somewhere else
const _RELOCATE_DIST := 14.0
const _SNUFF_CHANCE  := 0.3    # per decision, times aggression
const _SNUFF_RANGE   := 30.0
const _SNUFF_LEAD_MAX := 1.5   # seconds ahead of the Torch to aim the intercept
const _SNUFF_TIME    := 4.0
const _SNUFF_CD      := 6.0
const _SNUFF_MARGIN  := 2.0    # want the dash to land at bump_speed + this, not just scrape it
const _LINK_TIMEOUT  := 4.0    # give up on a pad/vault/climb that's taking this long
const _LINK_ARRIVE   := 2.0
const _RELAX_DIST    := 15.0   # a busy Torch further than this...
const _RELAX_CLOSING := 6.0    # ...and not coming at us faster than this doesn't need running from
const _SIGHT_MAX     := 160.0  # nobody further than this is visible
const _QUERIES_PER_TICK := 2   # path queries all bots together may run in one physics tick
const _SNUFF_LINES: Array[String] = ["snuff time", "watch this", "hold my beer", "incoming"]
const REACT_COUNTER  := 0
const REACT_NOPE     := 1
const _COUNTER_LINES: Array[String] = ["BRO", "1v1 me", "come here", "oh it's ON", "try me"]
const _NOPE_LINES: Array[String] = ["nope", "nah", "?!", "not today", "weirdo"]
const _WIN_LINES: Array[String] = ["gg", "ez", "stay down"]
const _HIT_LINES: Array[String] = ["ow", "rude", "hey!"]
const _COUNTER_COLOR := Color(1.0, 0.45, 0.3)
const _NOPE_COLOR    := Color(1.0, 0.9, 0.4)

@export var character: Character
@export var tag_manager: TagManager
@export var skill: BotSkill
@export var map: GameMap
## Debug: while this bot is the Torch, chase only this character (F6 "Torch hunts me").
var force_target: Character

var _goal := GOAL_WANDER
var _goal_point := Vector3.ZERO
var _goal_age := 0.0
var _target: Character
var _target_visible := false
var _last_seen := Vector3.ZERO
var _path := PackedVector3Array()
var _path_i := 0
var _think := 0.0
var _repath := 0.0
var _stuck := 0.0
var _steer_noise := 0.0
var _juke_dir := Vector3.ZERO
var _dash_aim := Vector3.ZERO # one-tick steering override for an aimed dash
var _juke_timer := 0.0
var _jump_hold := 0.0
var _slide_wanted := false
var _slide_time := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
# targets the navmesh can't get to (perched on pillars etc), seconds left on the mark
var _unreachable: Dictionary[Character, float] = {}
var _camping := false
# runner perception
var _aware := false
var _memory := 0.0
var _alert_delay := 0.0
var _glance := 0.0
# beef
var _sus: Dictionary[Character, float] = {}
var _beef: Character
var _beef_mode := REACT_NOPE
var _beef_timer := 0.0
var _since_think := 0.0
var _dodged: Dictionary[Character, bool] = {}
static var _query_tick := -1
static var _queries_this_tick := 0
var _dodge_wait: Dictionary[Character, float] = {} # dasher -> seconds left before we react to it
var _commit := 0.0 # seconds the Torch keeps chasing its current target no matter what
# nav links: per path point, the GameMap.LINK_* kind of the link that starts there (0 = none)
var _path_kinds := PackedInt32Array()
var _link_timer := 0.0
var _wj_lean := Vector3.ZERO # wall-jump link: which way to lean (into a wall, then across to the next)
var _query := NavigationPathQueryParameters3D.new()
var _query_result := NavigationPathQueryResult3D.new()
var _snuff_timer := 0.0
var _snuff_cd := 0.0


func _ready() -> void:
	if not character:
		push_error("BotBrain needs a character")
		set_physics_process(false)
		return
	if not skill: skill = BotSkill.new()
	# write the intent before the character reads it
	process_physics_priority = character.process_physics_priority - 10
	_think = randf() * skill.reaction_time # stagger bots so they don't all think on one frame
	_ray.collision_mask = _WORLD_MASK
	_goal_point = character.global_position
	if tag_manager: tag_manager.bumped.connect(on_bumped)


func _physics_process(delta: float) -> void:
	var intent := character.intent
	if tag_manager and tag_manager.is_out(character):
		# burned out: sit the round out
		intent.set_wish(Vector3.ZERO)
		character.chase_target = null
		return
	_think = maxf(_think - delta, 0.0)
	_repath = maxf(_repath - delta, 0.0)
	_juke_timer = maxf(_juke_timer - delta, 0.0)
	_jump_hold = maxf(_jump_hold - delta, 0.0)
	_goal_age += delta
	_memory = maxf(_memory - delta, 0.0)
	_alert_delay = maxf(_alert_delay - delta, 0.0)
	_glance = maxf(_glance - delta, 0.0)
	_beef_timer = maxf(_beef_timer - delta, 0.0)
	_commit = maxf(_commit - delta, 0.0)
	_snuff_timer = maxf(_snuff_timer - delta, 0.0)
	_snuff_cd = maxf(_snuff_cd - delta, 0.0)
	if not _beef_timer: _beef = null
	_since_think += delta
	_check_incoming_dash()
	for c: Character in _unreachable.keys():
		_unreachable[c] -= delta
		if _unreachable[c] <= 0.0: _unreachable.erase(c)
	if not _think:
		_think = skill.reaction_time * randf_range(0.8, 1.2)
		_decide()
		_since_think = 0.0
	if not _repath: _repath_now()
	var wish := _steer()
	_handle_stuck(wish, delta)
	if _slide_wanted:
		_slide_time += delta
		if _slide_time > _SLIDE_MAX: _slide_wanted = false
	intent.slide_held = _slide_wanted
	intent.jump_held = _jump_hold > 0.0
	intent.set_wish(wish)
	if wish.length_squared() > 0.01: intent.set_look(wish)


## What the bot is doing (GOAL_* constants), for debugging.
func get_goal() -> int:
	return _goal


## Who the bot currently has beef with (null if nobody), and how (REACT_*), for debugging/tests.
func get_beef() -> Character:
	return _beef


func get_beef_mode() -> int:
	return _beef_mode


func on_bumped(attacker: Character, victim: Character) -> void:
	if victim == character:
		character.emote(_HIT_LINES.pick_random(), _COUNTER_COLOR, 1.2)
	elif attacker == character and tag_manager and tag_manager.is_torch(victim):
		# snuffed the Torch, that's the dream
		character.emote(_WIN_LINES.pick_random(), _COUNTER_COLOR, 1.6)
		_snuff_timer = 0.0
		_snuff_cd = _SNUFF_CD
	elif attacker == character and victim == _beef and _beef_mode == REACT_COUNTER:
		# got 'em, beef settled
		character.emote(_WIN_LINES.pick_random(), _COUNTER_COLOR, 1.6)
		_beef = null
		_beef_timer = 0.0


#region decisions

func _decide() -> void:
	_steer_noise = deg_to_rad(randf_range(-1.0, 1.0) * skill.steer_error_deg)
	var playing := tag_manager and tag_manager.get_phase() == TagManager.PHASE_PLAYING
	if playing and tag_manager.is_torch(character):
		_beef = null # a Torch has bigger things to do
		_decide_chaser()
		return
	# runners deal with the closest fire (Spread can have lots of Torches)
	var torch := tag_manager.nearest_torch(character.global_position) if playing else null
	if not torch:
		character.chase_target = null
		_wander()
		return
	_decide_runner(torch)


func _decide_chaser() -> void:
	if is_instance_valid(force_target) and force_target != character:
		_target_visible = _has_los(force_target)
		_camping = false
		_chase(force_target)
		return
	if _commit and _committed_still_valid():
		_target_visible = _has_los(_target)
		_chase(_target)
		return
	var best := _pick_target()
	if best and best != _target: _commit = skill.commit_time
	if not best:
		character.chase_target = null
		_target_visible = false
		# lost everyone: check where the last one was, then roam
		if _target and _goal != GOAL_WANDER and _flat(_last_seen - character.global_position).length() > 3.0:
			_set_goal(GOAL_SEARCH, _last_seen)
		else:
			_target = null
			_wander()
		return
	_chase(best)


## Goes after `best`: intercepts where it's heading, finishing dash when it'd land.
## Used by the Torch for tagging and by runners counter-slamming someone they have beef with.
func _chase(best: Character) -> void:
	_target = best
	_last_seen = best.global_position
	character.chase_target = best
	var to := best.global_position - character.global_position
	var dist := _flat(to).length()
	_camping = _unreachable.has(best)
	if _camping:
		# nobody else to chase: wait at the closest reachable spot under them and pounce later
		_set_goal(GOAL_CHASE, _snap(best.global_position))
		return
	# intercept: aim where they'll be by the time we get there
	var t := clampf(dist / maxf(character.get_horizontal_speed(), 8.0), 0.0, 1.5) * skill.prediction
	var goal := best.global_position + _flat(best.velocity) * t
	# a teammate's already closer behind them: swing wide and come from the side (pinch them)
	if _closer_hunter(best, dist):
		var heading := _flat(best.velocity)
		if heading.length() < 2.0: heading = _flat(to)
		var side_dir := heading.normalized().cross(Vector3.UP)
		var side := signf(_flat(character.global_position - best.global_position).dot(side_dir))
		if side == 0.0: side = 1.0
		goal += side_dir * side * _FLANK_OFFSET * clampf(dist / 20.0, 0.0, 1.0)
	_set_goal(GOAL_CHASE, _snap(goal))
	# finishing dash: aim at where they'll be when the dash lands, only if it can reach
	# (tags count anywhere along the dash, so reach = dash length + tag radius-ish)
	if _target_visible and absf(to.y) < 1.5 and character.get_dash_charges() >= 1.0:
		var cfg := character.config
		var aim := best.global_position + _flat(best.velocity) * (dist / cfg.dash_speed) * skill.prediction
		var aim_d := _flat(aim - character.global_position).length()
		var reach := cfg.dash_speed * cfg.dash_time + 1.0
		# not mid-climb (a dash at the top of a vault jump flattens it into the wall), and only
		# along a clear line: level with them over a ledge still means a wall in between
		if aim_d > 1.0 and aim_d < reach and _active_link() == 0 and _dash_clear(aim, aim_d) \
				and randf() < skill.dash_skill:
			_dash_aim = _flat(aim - character.global_position).normalized()
			character.intent.dash_pressed = true
	_maybe_slide(dist > 15.0)


func _decide_runner(torch: Character) -> void:
	character.chase_target = null
	var me := character.global_position
	var d := _flat(torch.global_position - me).length()
	var torch_noticed := _perceive_threat(torch, d)
	_update_suspicion(_since_think)
	if _avoid_hazards(d): return
	if _try_snuff(torch, d, torch_noticed): return
	if _beef and _beef != torch and not (torch_noticed and d < _BEEF_TORCH_SAFE):
		_do_beef()
		return
	if not torch_noticed:
		_wander()
		return
	# a Torch that's busy with someone else, not close and not heading our way isn't worth a
	# full sprint: stay loose (that's also what gives aggressive bots a shot at a snuff)
	var heading_at_us := _flat(torch.velocity).dot(_flat(me - torch.global_position).normalized()) > _RELAX_CLOSING
	if torch.chase_target and torch.chase_target != character and d > _RELAX_DIST and not heading_at_us:
		_wander()
		return
	var reached := _flat(_goal_point - me).length() < 4.0
	var torch_closer := _goal_point.distance_to(torch.global_position) < _goal_point.distance_to(me)
	if _goal != GOAL_FLEE or reached or torch_closer or _goal_age > _FLEE_REPICK:
		_set_goal(GOAL_FLEE, _pick_escape(torch))
	# juke: sidestep (and dash) when the Torch is about to touch us
	var away := _flat(me - torch.global_position).normalized()
	var closing := _flat(torch.velocity - character.velocity).dot(away)
	if d < _JUKE_RANGE and closing > 2.0 and not _juke_timer and randf() < skill.juke_skill:
		var side := 1.0 if randf() < 0.5 else -1.0
		_juke_dir = (away.cross(Vector3.UP) * side + away * 0.4).normalized()
		_juke_timer = _JUKE_TIME
		if character.get_dash_charges() >= 1.0: character.intent.dash_pressed = true
	_maybe_slide(d > 15.0)


## Someone hanging around close, staring at us, closing in, or dashing at us fills their meter.
## A full meter turns into beef: counter-slam or nope out, depending on aggression.
func _update_suspicion(dt: float) -> void:
	var me := character.global_position
	for o: Character in tag_manager.get_participants():
		if o == character or tag_manager.is_torch(o) or tag_manager.is_out(o): continue # nobody beefs with a burned-out body
		var to_me := _flat(me - o.global_position)
		var d := to_me.length()
		var rate := -_SUS_DECAY
		if d < _SUS_RANGE and d > 0.01:
			var dir := to_me / d
			var facing := o.intent.look_dir.dot(dir)
			var closing := _flat(o.velocity).dot(dir)
			var sus := 1.0 if d < _SUS_CLOSE else 0.4
			if facing > 0.95: sus += 1.0
			elif facing < 0.3: sus *= 0.3
			if closing > 10.0: sus += 1.0
			# dashing around near us isn't a slam attempt; dashing *at* us from close is
			if o.get_state() == Character.ST_DASHING and d < _SUS_DASH_RANGE and closing > _SUS_DASH_AIM:
				sus += 4.0
			rate += sus
		var meter := clampf(_sus.get(o, 0.0) + rate * dt, 0.0, _SUS_MAX)
		if meter <= 0.0:
			_sus.erase(o)
			continue
		_sus[o] = meter
		if meter >= skill.suspicion and not _beef: _realise(o)


## Dry edge and hiding rules apply to bots too, and they know it: heating up sends them back
## inside, staying in one spot too long makes them relocate. A close Torch still comes first.
## Returns true if it set a goal.
func _avoid_hazards(torch_dist: float) -> bool:
	# about to combust is worse than almost anything; otherwise a close Torch comes first
	var smoking := tag_manager.is_smoking(character)
	if torch_dist < _HAZARD_SAFE and not (smoking and torch_dist > 3.0): return false
	var me := character.global_position
	var inward := _flat(tag_manager.get_safe_center() - me).normalized() # the storm drifts: run for its centre
	if tag_manager.get_heat(character) > _HEAT_FLEE or tag_manager.get_edge_distance(character) < 0.0:
		_set_goal(GOAL_FLEE, _snap(me + inward * _RELOCATE_DIST * 2.0))
		return true
	if tag_manager.get_stillness(character) > _STILL_MOVE or smoking:
		var dir := inward.rotated(Vector3.UP, randf_range(-1.2, 1.2))
		_set_goal(GOAL_FLEE, _snap(me + dir * _RELOCATE_DIST))
		return true
	return false


## Aggressive runners sneak up on a Torch that's busy chasing someone else and dash-shove it
## (a snuff). Only dashes in if the hit would land hard enough; a slow touch just gets you lit.
## Returns true while an attempt is running.
func _try_snuff(torch: Character, d: float, noticed: bool) -> bool:
	var busy := torch.chase_target != character and not torch.is_frozen()
	if _snuff_timer:
		if not busy or d > _SNUFF_RANGE * 1.5:
			_snuff_timer = 0.0 # it turned on us (or got snuffed already): bail
			_snuff_cd = _SNUFF_CD
			return false
	else:
		if _snuff_cd or not noticed or not busy or d > _SNUFF_RANGE or d < 4.0: return false
		if character.get_dash_charges() < 1.0 or randf() > skill.aggression * _SNUFF_CHANCE: return false
		_snuff_timer = _SNUFF_TIME
		character.emote(_SNUFF_LINES.pick_random(), _COUNTER_COLOR)
	var me := character.global_position
	var tv := _flat(torch.velocity)
	_target = torch
	_target_visible = _has_los(torch)
	_camping = false
	# intercept: cut across where it's heading (further ahead the further away it is). chasing it
	# from behind never closes fast enough for a snuff
	var cfg := character.config
	var to := _flat(torch.global_position - me)
	var dist := to.length()
	var lead := clampf(dist / cfg.max_speed, 0.3, _SNUFF_LEAD_MAX)
	_set_goal(GOAL_CHASE, _snap(torch.global_position + tv * lead))
	if dist < 0.01: return true
	var closing := cfg.dash_speed - tv.dot(to / dist) # our dash speed minus how fast it runs away
	var aim := torch.global_position + tv * (dist / cfg.dash_speed)
	var aim_d := _flat(aim - me).length()
	if _target_visible and character.get_dash_charges() >= 1.0 and aim_d < cfg.dash_speed * cfg.dash_time + 1.0 \
			and closing >= tag_manager.rules.bump_speed + _SNUFF_MARGIN:
		_dash_aim = _flat(aim - me).normalized()
		character.intent.dash_pressed = true
	elif dist < 2.5:
		# too close without a good shot: abort before it lights us
		_snuff_timer = 0.0
		_snuff_cd = _SNUFF_CD
		return false
	return true


func _realise(o: Character) -> void:
	_sus.erase(o)
	_beef = o
	_beef_timer = randf_range(_BEEF_MIN, _BEEF_MAX)
	_beef_mode = REACT_COUNTER if randf() < skill.aggression else REACT_NOPE
	if _beef_mode == REACT_COUNTER: character.emote(_COUNTER_LINES.pick_random(), _COUNTER_COLOR)
	else: character.emote(_NOPE_LINES.pick_random(), _NOPE_COLOR)


func _do_beef() -> void:
	if _beef_mode == REACT_COUNTER:
		_target_visible = _has_los(_beef)
		_camping = false
		_chase(_beef)
		return
	var me := character.global_position
	var reached := _flat(_goal_point - me).length() < 4.0
	if _goal != GOAL_FLEE or reached or _goal_age > _FLEE_REPICK:
		_set_goal(GOAL_FLEE, _pick_escape(_beef))
	_maybe_slide(true)


## Per tick: someone (not the Torch, whose dashes are tags) dashing straight at us up close is a
## slam attempt. Roll once per dash to sidestep it.
func _check_incoming_dash() -> void:
	if not tag_manager or character.is_frozen(): return
	var me := character.global_position
	var i_burn := tag_manager.is_torch(character)
	var look := _flat(character.intent.look_dir).normalized()
	for o: Character in tag_manager.get_participants():
		if o == character: continue
		if o.get_state() != Character.ST_DASHING:
			_dodged.erase(o)
			_dodge_wait.erase(o)
			continue
		if tag_manager.is_torch(o) and not i_burn: continue # runners juke a Torch's tag dash at think rate
		if _dodged.has(o): continue
		var to_me := _flat(me - o.global_position)
		var d := to_me.length()
		if d > _DODGE_RANGE or d < 0.01: continue
		if _flat(o.velocity).dot(to_me / d) < _DODGE_CLOSING: continue
		# only a dash it can see coming (in front of it, nothing in the way), and only after its
		# reaction time: a 28 m/s dash crosses 6 m in ~0.2 s, so slow bots never make it
		if look.dot(-to_me / d) < _DODGE_VIEW or not _has_los(o): continue
		if not _dodge_wait.has(o):
			_dodge_wait[o] = skill.reaction_time * randf_range(0.9, 1.3)
			continue
		_dodge_wait[o] -= get_physics_process_delta_time()
		if _dodge_wait[o] > 0.0: continue
		_dodged[o] = true
		if randf() > skill.juke_skill * _DODGE_CHANCE: continue
		var side := 1.0 if randf() < 0.5 else -1.0
		_juke_dir = to_me / d
		_juke_dir = _juke_dir.cross(Vector3.UP) * side
		_juke_timer = _JUKE_TIME
		if character.get_dash_charges() >= 1.0: character.intent.dash_pressed = true


## Runners aren't omniscient: they hear the Torch nearby, see it only inside their view cone
## (plus the odd glance back), react a beat late to a surprise, and remember it for a while.
## Returns true once the runner is aware AND has reacted.
func _perceive_threat(torch: Character, d: float) -> bool:
	var sees := d < skill.hearing_radius
	if not sees and d < skill.awareness_radius and _has_los(torch):
		var glancing := not _glance
		if glancing: _glance = skill.glance_interval * randf_range(0.7, 1.3)
		var facing := _flat(character.velocity)
		if facing.length() < 2.0: facing = character.intent.look_dir
		var to := _flat(torch.global_position - character.global_position)
		sees = glancing or rad_to_deg(facing.angle_to(to)) < skill.view_half_angle
	if sees:
		if not _aware and not _memory: _alert_delay = skill.reaction_time * 1.5 # "wait, what"
		_aware = true
		_memory = skill.memory_time
	elif not _memory:
		_aware = false
	return _aware and not _alert_delay


func _wander() -> void:
	var me := character.global_position
	if _goal == GOAL_WANDER and _flat(_goal_point - me).length() > 3.0 and _goal_age < 6.0: return
	var a := randf() * TAU
	var p := me + Vector3(cos(a), 0.0, sin(a)) * randf_range(8.0, _WANDER_RADIUS)
	if map: p = p.lerp(map.arena_center, 0.25) # drift back toward the middle over time
	_set_goal(GOAL_WANDER, _snap(p))
	_slide_wanted = false


## How many other Torches are chasing c right now.
func _hunters_of(c: Character) -> int:
	var n := 0
	for t: Character in tag_manager.get_torches():
		if t != character and t.chase_target == c: n += 1
	return n


## True if another Torch chasing `target` is closer to it than we are (dist).
func _closer_hunter(target: Character, dist: float) -> bool:
	for t: Character in tag_manager.get_torches():
		if t == character or t.chase_target != target: continue
		if _flat(t.global_position - target.global_position).length() < dist: return true
	return false


## A committed target stays the target unless it's untaggable, unreachable, out of sight and far,
## or someone else is right on top of us (much closer than the target).
func _committed_still_valid() -> bool:
	if not is_instance_valid(_target) or tag_manager.is_tag_immune(_target) or tag_manager.is_torch(_target): return false
	if _unreachable.has(_target): return false
	var me := character.global_position
	var d := _flat(_target.global_position - me).length()
	if d > skill.awareness_radius * 1.5 and not _has_los(_target): return false
	for c: Character in tag_manager.get_participants():
		if c == character or c == _target or tag_manager.is_torch(c) or tag_manager.is_tag_immune(c): continue
		var dc := _flat(c.global_position - me).length()
		if dc < _SWITCH_CLOSE and dc < d * _SWITCH_RATIO: return false
	return true


## Best thing to chase: close, reachable-looking, preferring the current target (no flip-flopping)
## and anyone out of dashes.
func _pick_target() -> Character:
	var me := character.global_position
	var best: Character
	var best_score := INF
	var best_visible := false
	for c: Character in tag_manager.get_participants():
		if c == character or tag_manager.is_torch(c) or tag_manager.is_tag_immune(c): continue
		var to := c.global_position - me
		var d := _flat(to).length()
		var visible := _has_los(c)
		if not visible and d > skill.awareness_radius * 1.5: continue
		var score := d + absf(to.y) * 3.0
		if to.y > 2.5: score += 25.0 # up a tower, probably can't get there
		if c == _target: score -= 8.0
		if _unreachable.has(c): score += 40.0 # only picked if there's nobody else
		# team play: spread out over the kindling instead of all chasing one
		score += _hunters_of(c) * _TEAM_SPREAD
		if c.get_dash_charges() < 1.0: score -= 4.0
		# someone sprinting straight away is a long chase; someone wandering or coming closer isn't
		var running_away := _flat(c.velocity).dot(_flat(to).normalized() if d > 0.1 else Vector3.ZERO)
		score += clampf(running_away, 0.0, 15.0) * 1.5
		if not visible: score += 10.0
		if score < best_score:
			best_score = score
			best = c
			best_visible = visible
	_target_visible = best_visible
	return best


## Samples escape points on a ring around the bot and keeps the best one. Candidates are scored
## raw first and only the best few get snapped to the navmesh (snaps are the expensive part).
func _pick_escape(torch: Character) -> Vector3:
	const SNAPS := 3
	var me := character.global_position
	var threat := torch.global_position
	var away := _flat(me - threat).normalized()
	var n := maxi(skill.flee_samples, 4)
	var cands: Array[Vector3] = []
	var raw: Array[float] = []
	for i: int in n:
		var a := TAU * (i + randf()) / n
		var cand := me + Vector3(cos(a), 0.0, sin(a)) * randf_range(_FLEE_RING_MIN, _FLEE_RING_MAX)
		cands.append(cand)
		raw.append(_escape_score(cand, me, threat, away))
	var order := range(n)
	order.sort_custom(func(x: int, y: int) -> bool: return raw[x] > raw[y])
	var best := me + away * 20.0
	var best_score := -INF
	var snaps := 0
	for i: int in order:
		if snaps >= SNAPS: break
		var cand := cands[i]
		var p := _snap(cand)
		snaps += 1
		if _flat(p - cand).length() > _OFF_MESH: continue
		var score := _escape_score(p, me, threat, away) - absf(p.y - me.y) * 0.8
		if score > best_score:
			best_score = score
			best = p
		# blunder: settle for whatever decent-ish option came up instead of the best
		if score > 0.0 and randf() < skill.blunder: return p
	return best


func _escape_score(p: Vector3, me: Vector3, threat: Vector3, away: Vector3) -> float:
	var score := p.distance_to(threat) - p.distance_to(me) * 0.35
	score += _flat(p - me).normalized().dot(away) * 12.0
	# never pick a route that runs past the Torch
	if Geometry3D.get_closest_point_to_segment(threat, me, p).distance_to(threat) < 7.0: score -= 30.0
	# several Torches (Spread): don't run from one straight into another
	if tag_manager and tag_manager.rules.mode == MatchRules.MODE_SPREAD:
		for t: Character in tag_manager.get_torches():
			var tp := t.global_position
			if tp.distance_to(threat) < 1.0 or tp.distance_to(me) > 45.0: continue
			score -= maxf(0.0, 28.0 - p.distance_to(tp)) * 1.5
			if Geometry3D.get_closest_point_to_segment(tp, me, p).distance_to(tp) < 7.0: score -= 20.0
	if map:
		var edge := _flat(p - map.arena_center).length() - map.arena_radius * 0.8
		if edge > 0.0: score -= edge * 2.0
	return score


func _maybe_slide(far: bool) -> void:
	if _slide_wanted:
		if not far or _corner_dist() < 5.0: _slide_wanted = false
		return
	if not far or character.get_horizontal_speed() < 10.0 or not character.is_on_floor(): return
	if _corner_dist() < 12.0 or randf() > skill.slide_use: return
	_slide_wanted = true
	_slide_time = 0.0
	character.intent.slide_pressed = true

#endregion


#region movement

func _steer() -> Vector3:
	var pos := character.global_position
	var wish := Vector3.ZERO
	var direct := _goal == GOAL_CHASE and _target and _target_visible \
			and _flat(_target.global_position - pos).length() < _DIRECT_RANGE \
			and absf(_target.global_position.y - pos.y) < 1.5
	# off an aimed pad, planned or walked over: steer for where it lands you (not the path, which
	# may lie elsewhere: fighting a long lob drops you short, into the lava on the Inferno)
	var launch_to := character.get_launch_target()
	if launch_to != Vector3.INF and not character.is_on_floor():
		var to_land := _flat(launch_to - pos)
		return to_land.normalized() if to_land.length() > 0.5 else Vector3.ZERO
	if direct:
		var lead := _target.global_position + _flat(_target.velocity) * 0.15 * skill.prediction
		wish = _flat(lead - pos).normalized()
	elif _active_link():
		return _steer_link(_active_link(), pos) # precise, no steering noise
	elif _path_i < _path.size():
		while _path_i < _path.size() - 1 and _flat(_path[_path_i] - pos).length() < _CORNER_REACH:
			_path_i += 1
			if _active_link(): return _steer_link(_active_link(), pos) # just reached a link start
		var corner := _path[_path_i]
		wish = _flat(corner - pos)
		wish = wish.normalized() if wish.length() > 0.5 else Vector3.ZERO
		if corner.y - pos.y > 0.9 and _flat(corner - pos).length() < 3.0: _jump()
	else:
		wish = _flat(_goal_point - pos)
		wish = wish.normalized() if wish.length() > 1.0 else Vector3.ZERO
	if _juke_timer: wish = _juke_dir
	if _dash_aim != Vector3.ZERO:
		# aimed dash: exact, no steering noise
		var aim := _dash_aim
		_dash_aim = Vector3.ZERO
		return aim
	# camping under a perched target: stand still once there instead of jumping at the pillar
	# (the goal snaps onto the pillar top, so "there" means the end of the walkable path)
	if _camping and not _path.is_empty() and _path_i >= _path.size() - 1 \
			and _flat(_path[_path.size() - 1] - pos).length() < 1.5:
		wish = Vector3.ZERO
	if _goal == GOAL_WANDER: wish *= _WANDER_SPEED
	return wish.rotated(Vector3.UP, _steer_noise)


## Pushing but not moving: hop, re-path. A wall right in front: hop over it.
func _handle_stuck(wish: Vector3, delta: float) -> void:
	if character.is_frozen():
		_stuck = 0.0
		return
	if wish.length_squared() > 0.04 and character.get_horizontal_speed() < _STUCK_SPEED: _stuck += delta
	else: _stuck = 0.0
	if _stuck > _STUCK_TIME:
		_stuck = 0.0
		_jump()
		_repath = 0.0
	var n := character.get_last_wall_normal()
	if n != Vector3.ZERO and wish.dot(n) < -0.5 and character.is_on_floor(): _jump()


func _jump() -> void:
	character.intent.jump_pressed = true
	_jump_hold = _JUMP_HOLD


func _set_goal(goal: int, point: Vector3) -> void:
	var changed := goal != _goal or point.distance_to(_goal_point) > 2.0
	_goal = goal
	_goal_point = point
	if changed:
		_goal_age = 0.0
		_repath = 0.0


func _repath_now() -> void:
	# path queries cost 1-4 ms on a big map: cap them per physics tick across all bots, so a moment
	# when everyone repaths at once (a new Torch) is spread over a few ticks instead of one hitch
	var tick := Engine.get_physics_frames()
	if tick != _query_tick:
		_query_tick = tick
		_queries_this_tick = 0
	if _queries_this_tick >= _QUERIES_PER_TICK and not _path.is_empty():
		_repath = randf_range(0.01, 0.03) # keep the current path a moment longer
		return
	_queries_this_tick += 1
	_repath = 0.25 if _goal == GOAL_CHASE else 0.6
	# never throw a path away mid-pad-flight or mid-climb
	if _active_link() and not character.is_on_floor():
		_repath = 0.1
		return
	if not _nav_ready():
		_path.clear()
		_path_kinds.clear()
		return
	_query.map = _nav_map()
	_query.start_position = character.global_position
	_query.target_position = _goal_point
	_query.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES \
			| NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_OWNERS
	NavigationServer3D.query_path(_query, _query_result)
	_path = _query_result.path
	_path_kinds.resize(_path.size())
	var types := _query_result.path_types
	var owners := _query_result.path_owner_ids
	# a link's start point carries the link (its end point belongs to the region it lands on)
	for i: int in _path.size():
		_path_kinds[i] = 0
		if i < types.size() and types[i] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK and i < owners.size():
			var link := instance_from_id(owners[i])
			if link: _path_kinds[i] = link.get_meta(GameMap.LINK_KIND, 0)
	_path_i = 1 if _path.size() > 1 else 0
	_link_timer = 0.0
	# a chase path that stops short of its goal, or a target standing off the navmesh (a pillar top),
	# means we can't walk to them. measured against the goal, not the target: the goal is an
	# intercept point ahead of / beside them, so a moving target is never at the path's end
	if _goal == GOAL_CHASE and _target and not _path.is_empty():
		var short := _path[_path.size() - 1].distance_to(_goal_point) > _UNREACH_DIST
		if short or _off_mesh(_target): _unreachable[_target] = _UNREACH_TIME


## Standing somewhere the navmesh doesn't reach. Airborne doesn't count (jumps, pad flights).
func _off_mesh(c: Character) -> bool:
	if not c.is_on_floor() or not _nav_ready(): return false
	var gap := c.global_position - _snap(c.global_position)
	return _flat(gap).length() > _UNREACH_DIST or gap.y > 1.5


## The link we're currently on (heading from its start to its end), GameMap.LINK_*; 0 if none.
func _active_link() -> int:
	if _path_i < 1 or _path_i >= _path.size() or _path_i - 1 >= _path_kinds.size(): return 0
	return _path_kinds[_path_i - 1]


## Moves along a nav link: pad -> fly to the end, vault -> run in with jump held, drop -> walk off,
## wall-jump -> jump and keep wall-jumping (jump held, so the vault finishes it at the top),
## jump -> take off at the start edge and fly at the end.
func _steer_link(kind: int, pos: Vector3) -> Vector3:
	var start := _path[_path_i - 1]
	var end := _path[_path_i]
	var to_end := _flat(end - pos)
	var on_floor := character.is_on_floor()
	_link_timer += get_physics_process_delta_time()
	if (on_floor and to_end.length() < _LINK_ARRIVE and absf(end.y - pos.y) < 1.2) or _link_timer > _LINK_TIMEOUT:
		if _link_timer > _LINK_TIMEOUT: _repath = 0.0 # didn't work out, find another way
		_path_i += 1
		_link_timer = 0.0
		return to_end.normalized()
	var dir := to_end.normalized() if to_end.length() > 0.1 else Vector3.ZERO
	# airborne on a jump or climb: brake against the landing instead of sailing past a narrow ledge
	if not on_floor and (kind == GameMap.LINK_JUMP or kind == GameMap.LINK_VAULT):
		var hv := _flat(character.velocity)
		var along := hv.dot(dir)
		var fall_time := 0.35 if character.velocity.y < 0.0 else 0.6
		if along * fall_time > to_end.length() + 0.5: return -dir
	match kind:
		GameMap.LINK_PAD:
			if on_floor:
				# get onto the pad, it does the rest. ease off the last few metres: an aimed pad only
				# lobs you exactly onto its spot if you arrive slower than the lob
				var to_start := _flat(start - pos)
				if to_start.length() > 0.5: return to_start.normalized() * clampf(to_start.length() / 6.0, 0.15, 1.0)
			return dir * (1.0 if to_end.length() > 1.5 else 0.3)
		GameMap.LINK_VAULT:
			_jump_hold = maxf(_jump_hold, _JUMP_HOLD)
			if on_floor:
				# right under a floating ledge: jumping just bonks its underside, back out first
				if to_end.length() < 1.3 and end.y - pos.y > 1.5: return _flat(start - end).normalized()
				if to_end.length() < 3.5: _jump()
		GameMap.LINK_JUMP:
			_jump_hold = maxf(_jump_hold, _JUMP_HOLD)
			if on_floor:
				var to_start := _flat(start - pos)
				var span := _flat(end - start).length()
				# still short of the edge: run to it (lined up with the jump), then take off. short
				# hops don't need a sprint, and a sprint overshoots a 2 m ledge
				var pace := clampf(span / 5.0, 0.45, 1.0)
				if to_start.length() > 0.8 and to_start.dot(_flat(end - start)) > 0.0: return to_start.normalized() * pace
				_jump()
				return dir * pace
		GameMap.LINK_WALLJUMP:
			_jump_hold = maxf(_jump_hold, _JUMP_HOLD)
			if on_floor:
				# arrive at the foot slowly and jump from right there: a running jump sails out of
				# the gap past the walls
				_wj_lean = Vector3.ZERO
				var to_start := _flat(start - pos)
				var speed := _flat(character.velocity).length()
				if to_start.length() > 0.8: return to_start.normalized() * clampf(to_start.length() / 4.0, 0.25, 0.6)
				if speed > 4.0: return -_flat(character.velocity).normalized()
				_jump()
				return Vector3.ZERO
			else:
				if character.get_last_wall_normal() != Vector3.ZERO and character.velocity.y < 2.0:
					character.intent.jump_pressed = true
				# lean into a wall (you only wall-jump off one you're touching) and keep leaning into
				# the one you're on: each wall-jump pushes you off, leaning brings you back for the
				# next (one wall or a gap between two, either works); level with the top, over onto it
				if character.is_on_wall(): _wj_lean = -_flat(character.get_wall_normal()).normalized()
				if pos.y < end.y - 0.3:
					if _flat(start - pos).length() > 1.5: return _flat(start - pos).normalized() # drifted out
					if _wj_lean == Vector3.ZERO: _wj_lean = _nearest_wall(pos)
					return _wj_lean if _wj_lean != Vector3.ZERO else _flat(start - pos).limit_length(1.0)
	return dir


## Horizontal direction to the closest wall within 4 m (8 rays at chest height), or ZERO.
func _nearest_wall(pos: Vector3) -> Vector3:
	var space := character.get_world_3d().direct_space_state
	var best := Vector3.ZERO
	var best_d := INF
	for k: int in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8.0)
		_ray.from = pos + Vector3.UP * 0.9
		_ray.to = _ray.from + d * 4.0
		var hit := space.intersect_ray(_ray)
		if hit and _ray.from.distance_to(hit.position) < best_d:
			best_d = _ray.from.distance_to(hit.position)
			best = d
	return best


func _corner_dist() -> float:
	if _path_i >= _path.size(): return 0.0
	return _flat(_path[_path_i] - character.global_position).length()

#endregion


#region helpers

func _has_los(c: Character) -> bool:
	# past this nobody's seen, and the ray (long ones across terrain collision are costly) is skipped
	if character.global_position.distance_squared_to(c.global_position) > _SIGHT_MAX * _SIGHT_MAX: return false
	_ray.from = character.global_position + _EYE
	_ray.to = c.global_position + _EYE
	return character.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Nothing solid along a dash toward aim (waist height, the dash's length or aim_d if shorter)?
func _dash_clear(aim: Vector3, aim_d: float) -> bool:
	var dir := _flat(aim - character.global_position).normalized()
	_ray.from = character.global_position + Vector3.UP * 0.9
	_ray.to = _ray.from + dir * aim_d
	return character.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _nav_map() -> RID:
	return character.get_world_3d().navigation_map


func _nav_ready() -> bool:
	if map and not map.is_nav_ready(): return false
	return NavigationServer3D.map_get_iteration_id(_nav_map()) > 0


func _snap(p: Vector3) -> Vector3:
	if not _nav_ready(): return p
	return map.nav_snap(p) if map else NavigationServer3D.map_get_closest_point(_nav_map(), p)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

#endregion


#region debug

const _GOAL_NAMES: Array[String] = ["WANDER", "CHASE", "SEARCH", "FLEE"]
const _LINK_NAMES: Array[String] = ["walk", "PAD", "CLIMB", "DROP", "WALL-JUMP", "JUMP"]


## [DEBUG] What the bot's up to, a few short lines for the F5 overlay.
func debug_text() -> String:
	var lines := PackedStringArray()
	lines.append("%s  ·  %s  ·  %.0f m/s" % [character.display_name, character.get_state_name(), character.get_horizontal_speed()])
	var goal := _GOAL_NAMES[_goal] if _goal < _GOAL_NAMES.size() else str(_goal)
	var what := goal
	if is_instance_valid(_target) and (_goal == GOAL_CHASE or _goal == GOAL_SEARCH):
		what += "  %s %.0f m%s" % [_target.display_name, character.global_position.distance_to(_target.global_position), "" if _target_visible else " (unseen)"]
	if _camping: what += "  camping"
	if _commit > 0.0: what += "  commit %.1f" % _commit
	if is_instance_valid(force_target): what += "  forced"
	lines.append(what)
	var move := "%s  %d/%d" % [_LINK_NAMES[_active_link()] if _active_link() < _LINK_NAMES.size() else "?", _path_i, _path.size()]
	if _path.is_empty(): move = "no path" if _nav_ready() else "nav not ready"
	if _stuck > 0.0: move += "  stuck %.1f" % _stuck
	if _juke_timer > 0.0: move += "  juke"
	if _link_timer > 0.0: move += "  link %.1f s" % _link_timer
	lines.append(move)
	return "\n".join(lines)


## [DEBUG] The path still ahead (from the last corner passed), with each segment's link kind.
func debug_path() -> Array:
	var pts := PackedVector3Array([character.global_position])
	var kinds := PackedInt32Array()
	for i: int in range(_path_i, _path.size()):
		pts.append(_path[i])
		kinds.append(_path_kinds[i - 1] if i >= 1 and i - 1 < _path_kinds.size() else 0)
	return [pts, kinds, _goal_point]

#endregion
