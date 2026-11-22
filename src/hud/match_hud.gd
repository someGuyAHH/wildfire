extends CanvasLayer

# match HUD: round timer / countdown, who's the Torch, red frame while you're the Torch, tag feed,
# scoreboard (hold Tab, and on the results screen). built in code, in the menus' look (UIKit): the
# clock on a slanted plate, under it a pill saying what you are (TORCH in ember, RUNNER in teal).

const _TORCH_COLOR := UIKit.EMBER
const _YOU_COLOR   := UIKit.TEAL
const _CLOCK_WARN  := 30.0 # the clock turns ember under this many seconds
const _FEED_LIFE   := 4.5
const _FEED_FADE   := 1.0
const _FEED_MAX    := 5
const _BOARD_EVERY := 0.25
const _MARKER_CONFIG := preload("res://assets/tres/match/marker_config.tres")
const _THREAT_MAT := preload("res://assets/tres/materials/threat_vignette.tres")
const _HEAT_MAT   := preload("res://assets/tres/materials/heat_vignette.tres")
## Hunted warning: full strength at this distance or closer, nothing past _THREAT_FAR.
const _THREAT_NEAR := 5.0
const _THREAT_FAR  := 45.0
const _ARROW_MARGIN := 70.0
const _HEAT_COLOR   := Color(1.0, 0.45, 0.05)
const _SMOKE_COLOR  := Color(0.78, 0.78, 0.82)
const _SNUFF_COLOR  := Color(0.5, 0.85, 1.0)
const _COZY_WARN    := 0.5 # stillness above this starts warning you
const _FUSE_WARN    := 5.0 # fuse turns red below this many seconds
const _STORM_WARN   := 20.0 # mention the storm wall when it's this close
const _HEADS_CLASSIC: Array[String] = ["#", "player", "time burning", "snuffs", "shoves", "set alight", "score"]
const _HEADS_FREEZE: Array[String] = ["#", "player", "time free", "thaws", "freezes", "score"]
const _HEADS_SURVIVAL: Array[String] = ["#", "player", "survived", "best streak", "snuffs", "shoves", "score"]

var _tm: TagManager
var _player: Character
var _frame: Panel
var _timer_label: Label
var _role_label: Label # the line under the pill (who's the Torch, how far)
var _pill: PanelContainer
var _pill_style: StyleBoxFlat
var _pill_icon: TextureRect
var _pill_text: Label
var _feed: VBoxContainer
var _feed_life: Dictionary[Control, float] = {}
var _board: PanelContainer
var _board_title: Label
var _board_grid: GridContainer
var _board_refresh := 0.0
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _arrow: Polygon2D
var _threat := 0.0
var _heat_vignette: ColorRect
var _heat_mat: ShaderMaterial
var _status_label: Label
var _mode_label: Label
# aiming at someone shows their name (names aren't floating over heads any more)
var _aim_label: Label
var _aim_target: Character
var _aim_timer := 0.0
var _aim_ray := PhysicsRayQueryParameters3D.new()


## Hooks the HUD to a match and to the local player. Call once after adding it to the tree.
func setup(tag_manager: TagManager, player: Character) -> void:
	if not tag_manager or not player:
		push_error("MatchHud.setup() needs a TagManager and the player")
		return
	_tm = tag_manager
	_player = player
	_build()
	_tm.tagged.connect(on_tagged)
	_tm.bumped.connect(on_bumped)
	_tm.smoking_started.connect(on_smoking_started)
	_tm.smolder_changed.connect(on_smolder_changed)
	_tm.burned_out.connect(on_burned_out)
	_tm.combusted.connect(on_combusted)
	_tm.round_ended.connect(on_round_ended)
	_tm.thawed.connect(on_thawed)
	_tm.sensed.connect(on_sensed)
	_tm.phase_changed.connect(on_phase_changed)


func _process(delta: float) -> void:
	if not _tm: return
	_update_top()
	_update_feed(delta)
	_update_aim(delta)
	_update_threat(delta)
	_update_hazards()
	var show_board := _tm.get_phase() == TagManager.PHASE_RESULTS or Input.is_action_pressed(&"scoreboard")
	_board.visible = show_board
	_board_refresh = maxf(_board_refresh - delta, 0.0)
	if show_board and not _board_refresh:
		_board_refresh = _BOARD_EVERY
		_fill_board()


## Puts a line in the top-right feed (debug toggles and the like).
func notify(text: String, color: Color = Color.WHITE) -> void:
	_push_feed(text, color)


func on_thawed(thawer: Character, c: Character) -> void:
	_push_feed("%s melted %s free" % [_who(thawer), _who(c)], _YOU_COLOR if thawer == _player or c == _player else _tm.rules.ice_color)


func on_sensed(c: Character) -> void:
	if _tm.is_torch(_player): _push_feed("Hunter's sense: %s shows through walls" % _who(c), UIKit.GOLD)


func on_tagged(tagger: Character, victim: Character) -> void:
	if _tm.rules.mode == MatchRules.MODE_FREEZE:
		_push_feed("%s froze %s" % [_who(tagger), _who(victim)],
				_TORCH_COLOR if victim == _player else (_YOU_COLOR if tagger == _player else _tm.rules.ice_color))
		return
	_push_feed("%s set %s alight" % [_who(tagger), _who(victim)],
			_TORCH_COLOR if victim == _player else (_YOU_COLOR if tagger == _player else Color.WHITE))


func on_bumped(attacker: Character, victim: Character) -> void:
	if _tm.is_torch(victim):
		_push_feed("%s snuffed the Torch!  (-%.0f s)" % [_who(attacker), _tm.rules.snuff_bonus],
				_YOU_COLOR if attacker == _player else _SNUFF_COLOR)
		return
	_push_feed("%s shoved %s" % [_who(attacker), _who(victim)],
			_TORCH_COLOR if victim == _player else (_YOU_COLOR if attacker == _player else Color(1, 0.85, 0.4)))


func on_smoking_started(c: Character) -> void:
	_push_feed("%s %s smoking" % [_who(c), "are" if c == _player else "is"], _SMOKE_COLOR)


func on_burned_out(c: Character, reason: int) -> void:
	var text := "%s %s" % [_who(c), "burned out" if reason == TagManager.OUT_FUSE else "got caught in the storm"]
	_push_feed(text, _TORCH_COLOR if c == _player else _HEAT_COLOR)


func on_combusted(c: Character, _old_torch: Character) -> void:
	_push_feed("%s sat still too long and caught fire!" % _who(c), _TORCH_COLOR if c == _player else _HEAT_COLOR)


func on_smolder_changed(c: Character, smoldering: bool) -> void:
	if smoldering: _push_feed("%s %s smoldering" % [_who(c), "are" if c == _player else "is"], _HEAT_COLOR)


func on_round_ended(standings: Array[Character]) -> void:
	if _tm.rules.mode == MatchRules.MODE_FREEZE: # a side wins, not one player
		var runners := _tm.runners_won()
		_board_title.text = "ROUND OVER  ·  %s" % ("THE RUNNERS HELD OUT" if runners else "EVERYONE'S FROZEN")
		_board_refresh = 0.0
		return
	var winner := standings[0] if not standings.is_empty() else null
	_board_title.text = "ROUND OVER  ·  %s" % ("YOU WIN!" if winner == _player else "%s wins" % winner.display_name) \
			if winner else "ROUND OVER"
	_board_refresh = 0.0


func on_phase_changed(phase: int) -> void:
	if phase == TagManager.PHASE_COUNTDOWN:
		for l: Control in _feed_life.keys(): l.queue_free()
		_feed_life.clear()
	if phase != TagManager.PHASE_RESULTS: _board_title.text = "SCOREBOARD"


func _update_top() -> void:
	var t := _tm.get_time_left()
	var you_torch := _tm.is_torch(_player)
	var torch := _tm.nearest_torch(_player.global_position)
	var torches := _tm.get_torches().size()
	_frame.visible = you_torch
	_mode_label.text = _tm.rules.mode_name.to_upper()
	match _tm.get_phase():
		TagManager.PHASE_COUNTDOWN:
			_timer_label.text = "%d" % ceili(t)
			_timer_label.modulate = UIKit.TEXT
			_set_pill("GET READY", UIKit.TEXT, null)
			_role_label.text = ""
		TagManager.PHASE_PLAYING:
			var potato := _tm.rules.mode == MatchRules.MODE_HOT_POTATO
			_timer_label.text = "%d:%02d" % [floori(t / 60.0), int(t) % 60]
			if potato:
				# the fuse is the clock that matters; it turns red in the last few seconds
				var fuse := _tm.get_fuse_left()
				_timer_label.text = "FUSE  %.1f" % fuse
				_timer_label.modulate = _TORCH_COLOR if fuse < _FUSE_WARN else UIKit.TEXT
			else:
				_timer_label.modulate = _TORCH_COLOR if t < _CLOCK_WARN else UIKit.TEXT
			_role_label.text = ""
			if _tm.is_out(_player):
				var rig := _player.get_node_or_null(^"CameraRig")
				var watched: Character = rig.get(&"spectating") if rig else null
				_set_pill("BURNED OUT", UIKit.MUTED, null)
				_role_label.text = "%d left standing" % _tm.alive_count()
				if is_instance_valid(watched) and not _tm.is_out(watched):
					_role_label.text += "  ·  watching %s  (jump: next)" % watched.display_name
			elif _tm.is_iced(_player):
				_set_pill("FROZEN SOLID", _tm.rules.ice_color, UIKit.ICON_FROZEN)
				_role_label.text = "Wait for a free runner to melt you  ·  %d%%  ·  jump: watch someone else" % int(_tm.get_thaw_progress(_player) * 100.0)
			elif you_torch:
				if _player.is_frozen(): _set_pill("TORCH  ·  FROZEN", _TORCH_COLOR, UIKit.ICON_FROZEN)
				else: _set_pill("YOU'RE THE TORCH", _TORCH_COLOR, UIKit.ICON_FIRE)
				if potato: _role_label.text = "%d left" % _tm.alive_count()
				if _freeze_mode(): _role_label.text = "%d runner%s still free" % [_tm.free_runner_count(), "" if _tm.free_runner_count() == 1 else "s"]
			else:
				_set_pill("RUNNER", _YOU_COLOR, UIKit.ICON_RUN)
				if torch:
					var d := torch.global_position.distance_to(_player.global_position)
					var who := "%s is the Torch" % torch.display_name if torches == 1 \
							else "%d Torches  ·  nearest" % torches
					_role_label.text = "%s  ·  %d m%s%s" % [who, int(d),
							"  ·  fireproof for a moment" if _tm.is_tag_immune(_player) else "",
							"  ·  %d left" % _tm.alive_count() if potato else ""]
				if _freeze_mode(): _role_label.text = "%d free  ·  freeze them all, or melt your friends" % _tm.free_runner_count()
		TagManager.PHASE_RESULTS:
			_timer_label.modulate = UIKit.TEXT
			_timer_label.text = "NEXT ROUND  %d" % ceili(t)
			_pill.visible = false
			_role_label.text = ""
		_:
			_timer_label.text = ""
			_pill.visible = false
			_role_label.text = ""


## The pill under the clock: what you are, in its colour (dark text on it), with an icon.
func _set_pill(text: String, color: Color, icon: Texture2D) -> void:
	_pill.visible = true
	_pill_text.text = text
	_pill_style.bg_color = color
	_pill_icon.texture = icon
	_pill_icon.visible = icon != null


## Red edges + an arrow toward the closest bot that's actually hunting you.
func _update_threat(delta: float) -> void:
	var hunter: Character
	var best := INF
	for c: Character in _tm.get_participants():
		if c.chase_target != _player or c.is_frozen(): continue
		var d := c.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			hunter = c
	var target := 0.0
	if hunter and _tm.get_phase() == TagManager.PHASE_PLAYING:
		target = clampf(1.0 - (best - _THREAT_NEAR) / (_THREAT_FAR - _THREAT_NEAR), 0.0, 1.0)
	_threat = lerpf(_threat, target, 1.0 - exp(-6.0 * delta))
	_vignette.visible = _threat > 0.01
	if _vignette.visible: _vignette_mat.set_shader_parameter(&"strength", _threat)
	_arrow.visible = false
	if not hunter or target <= 0.0: return
	var cam := get_viewport().get_camera_3d()
	if not cam: return
	var size := get_viewport().get_visible_rect().size
	var p := hunter.global_position + Vector3.UP
	var behind := cam.is_position_behind(p)
	var sp := cam.unproject_position(p)
	if not behind and Rect2(Vector2.ZERO, size).grow(-_ARROW_MARGIN).has_point(sp): return # on screen
	# point from the screen center toward it (mirrored when it's behind the camera)
	var dir := (sp - size * 0.5) * (-1.0 if behind else 1.0)
	if dir.length_squared() < 1.0: dir = Vector2.DOWN
	dir = dir.normalized()
	var half := size * 0.5 - Vector2(_ARROW_MARGIN, _ARROW_MARGIN)
	var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	_arrow.position = size * 0.5 + dir * reach
	_arrow.rotation = dir.angle()
	_arrow.modulate.a = clampf(0.4 + _threat, 0.0, 1.0)
	_arrow.visible = true


## Heat haze from the dry edge, and a status line for heat / hiding (kindling only).
func _update_hazards() -> void:
	var storm := _tm.storm_active()
	# the storm burns everyone (Torch too); the dry edge only kindling
	var playing := _tm.get_phase() == TagManager.PHASE_PLAYING and not _tm.is_out(_player) \
			and (storm or not _tm.is_torch(_player))
	var heat := _tm.get_heat(_player) if playing else 0.0
	_heat_vignette.visible = heat > 0.01
	if _heat_vignette.visible:
		_heat_mat.set_shader_parameter(&"strength", heat)
		_heat_mat.set_shader_parameter(&"pulse_rate", 9.0 if _tm.is_smoldering(_player) else 2.0)
	var text := ""
	var color := Color.WHITE
	if playing:
		var still := _tm.get_stillness(_player)
		if _tm.is_smoking(_player):
			text = "SMOKING  ·  move or you'll catch fire!  (%.1f s)" % _tm.get_smoke_left(_player)
			color = _HEAT_COLOR
		elif _tm.is_smoldering(_player):
			var left := _tm.get_ignite_left(_player)
			text = "SMOLDERING  ·  get off the dry edge!" if left == INF else "SMOLDERING  ·  get off the dry edge!  catching fire in %.1f s" % left
			color = _HEAT_COLOR
		elif heat > 0.01:
			var on_edge := _tm.get_edge_distance(_player) < 0.0
			if on_edge:
				text = ("IN THE STORM  ·  get inside!  %d%%" if storm else "dry ground  ·  heating up %d%%") % int(heat * 100.0)
			else:
				text = "cooling off  ·  %d%%" % int(heat * 100.0)
			color = _HEAT_COLOR if on_edge else Color(1.0, 0.8, 0.6)
		elif _tm.get_edge_distance(_player) < 0.0: # out there, still in the grace
			text = "IN THE STORM  ·  get inside!" if storm else "dry ground  ·  get back inside"
			color = _HEAT_COLOR
		elif storm and _tm.get_edge_distance(_player) < _STORM_WARN:
			text = "storm wall  ·  %d m away" % int(_tm.get_edge_distance(_player))
			color = _HEAT_COLOR
		elif still > _COZY_WARN:
			text = "getting cozy...  keep moving or you'll start smoking"
			color = _SMOKE_COLOR
	_status_label.text = text
	_status_label.modulate = color


func _update_feed(delta: float) -> void:
	for l: Control in _feed_life.keys():
		var life := _feed_life[l] - delta
		if life <= 0.0:
			_feed_life.erase(l)
			l.queue_free()
			continue
		_feed_life[l] = life
		l.modulate.a = clampf(life / _FEED_FADE, 0.0, 1.0)


# a slanted strip, its edge bar and text in the line's colour
func _push_feed(text: String, color: Color) -> void:
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"SlantPanel"
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := strip.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	style.border_color = color
	style.content_margin_left = 28.0
	style.content_margin_right = 20.0
	strip.add_theme_stylebox_override(&"panel", style)
	var l := _label(text, 20, color)
	l.theme_type_variation = &"" # on the strip, no outline needed
	strip.add_child(l)
	_feed.add_child(strip)
	_feed_life[strip] = _FEED_LIFE
	while _feed.get_child_count() > _FEED_MAX:
		var old := _feed.get_child(0) as Control
		_feed_life.erase(old)
		_feed.remove_child(old)
		old.queue_free()


func _fill_board() -> void:
	for child: Node in _board_grid.get_children(): child.queue_free()
	var classic := _tm.lower_score_wins()
	# (a ternary of two array literals comes out untyped, so pick from typed consts instead)
	var heads := _HEADS_CLASSIC if classic else _HEADS_SURVIVAL
	if _freeze_mode(): heads = _HEADS_FREEZE
	_board_grid.columns = heads.size()
	for h: String in heads:
		var head := _label(h.to_upper(), 20, UIKit.MUTED)
		head.add_theme_font_override(&"font", UIKit.DISPLAY_BOLD)
		_board_grid.add_child(head)
	var standings := _tm.get_standings()
	for i: int in standings.size():
		var c := standings[i]
		var col := _YOU_COLOR if c == _player else (_TORCH_COLOR if _tm.is_torch(c) else UIKit.TEXT)
		var shown := c.display_name
		if _freeze_mode() and _tm.is_iced(c): # who's frozen solid: in ice blue, and it says so
			col = _tm.rules.ice_color
			shown += "  ·  FROZEN"
		_board_grid.add_child(_label("%d" % (i + 1), 22, col))
		_board_grid.add_child(_label(shown, 22, col))
		if _freeze_mode():
			_board_grid.add_child(_label("%.1f s" % _tm.get_survived(c), 22, col))
			_board_grid.add_child(_label("%d" % _tm.get_thaws(c), 22, col))
			_board_grid.add_child(_label("%d" % _tm.get_tags_made(c), 22, col))
			_board_grid.add_child(_label("%.1f" % _tm.get_score(c), 22, col))
			continue
		_board_grid.add_child(_label("%.1f s" % (_tm.get_torch_time(c) if classic else _tm.get_survived(c)), 22, col))
		if not classic: _board_grid.add_child(_label("%.1f s" % _tm.get_best_streak(c), 22, col))
		_board_grid.add_child(_label("%d" % _tm.get_snuffs(c), 22, col))
		_board_grid.add_child(_label("%d" % _tm.get_shoves(c), 22, col))
		if classic: _board_grid.add_child(_label("%d" % _tm.get_tags_made(c), 22, col))
		_board_grid.add_child(_label("%.1f" % _tm.get_score(c), 22, col))


func _freeze_mode() -> bool:
	return _tm.rules.mode == MatchRules.MODE_FREEZE


func _who(c: Character) -> String:
	return "You" if c == _player else c.display_name


func _build() -> void:
	_vignette = ColorRect.new()
	_vignette_mat = _THREAT_MAT
	_vignette.material = _vignette_mat
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)
	_heat_vignette = ColorRect.new()
	_heat_mat = _HEAT_MAT
	_heat_vignette.material = _heat_mat
	_heat_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heat_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heat_vignette.visible = false
	add_child(_heat_vignette)
	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(26, 0), Vector2(-14, -18), Vector2(-6, 0), Vector2(-14, 18)])
	_arrow.color = _TORCH_COLOR
	_arrow.visible = false
	add_child(_arrow)

	_frame = Panel.new()
	_frame.theme_type_variation = &"TorchFrame"
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	# top centre: the mode, the clock on its plate, the pill, the line under it, hazards
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 12.0
	top.add_theme_constant_override(&"separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_mode_label = _label("", 18, UIKit.MUTED)
	_mode_label.add_theme_font_override(&"font", UIKit.DISPLAY_BOLD)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_mode_label)
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"SlantPanel"
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size.x = 168.0
	top.add_child(plate)
	_timer_label = _label("", 52, UIKit.TEXT)
	_timer_label.theme_type_variation = &"HudNumber"
	_timer_label.add_theme_constant_override(&"outline_size", 0) # on its plate
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(_timer_label)
	_pill = PanelContainer.new()
	_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill_style = StyleBoxFlat.new()
	_pill_style.skew = Vector2(UIKit.SKEW, 0.0)
	_pill_style.set_content_margin_all(4.0)
	_pill_style.content_margin_left = 22.0
	_pill_style.content_margin_right = 22.0
	_pill_style.shadow_color = UIKit.SHADOW
	_pill_style.shadow_size = 1
	_pill_style.shadow_offset = Vector2(4.0, 4.0)
	_pill.add_theme_stylebox_override(&"panel", _pill_style)
	_pill.visible = false
	top.add_child(_pill)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override(&"separation", 8)
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(pill_row)
	_pill_icon = TextureRect.new()
	_pill_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pill_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pill_icon.custom_minimum_size = Vector2(26.0, 26.0)
	_pill_icon.modulate = UIKit.CHARCOAL
	_pill_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_row.add_child(_pill_icon)
	_pill_text = Label.new()
	_pill_text.add_theme_font_override(&"font", UIKit.DISPLAY)
	_pill_text.add_theme_font_size_override(&"font_size", 28)
	_pill_text.add_theme_color_override(&"font_color", UIKit.CHARCOAL)
	_pill_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_row.add_child(_pill_text)
	_role_label = _label("", 22, UIKit.TEXT)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_role_label)
	_status_label = _label("", 22, UIKit.TEXT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_status_label)

	_aim_label = _label("", 24, Color.WHITE)
	_aim_label.visible = false
	_aim_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_aim_label.add_theme_constant_override(&"outline_size", 8)
	add_child(_aim_label)
	_aim_ray.collision_mask = 1 # the world only

	# mini was taken by the minimum function for integers
	var minimap := Minimap.new()
	minimap.tag_manager = _tm
	minimap.player = _player
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -20.0 - Minimap.RADIUS * 2.0
	minimap.offset_right = -20.0
	minimap.offset_top = 16.0
	minimap.offset_bottom = 16.0 + Minimap.RADIUS * 2.0
	add_child(minimap)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_top = 16.0 + Minimap.RADIUS * 2.0 + 16.0 # under the minimap
	_feed.offset_right = -24.0
	_feed.add_theme_constant_override(&"separation", 8)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	_board = PanelContainer.new()
	_board.theme_type_variation = &"DarkPanel"
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	add_child(_board)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	_board.add_child(box)
	_board_title = _label("SCOREBOARD", 40, UIKit.TEXT)
	_board_title.add_theme_font_override(&"font", UIKit.DISPLAY)
	_board_title.theme_type_variation = &""
	box.add_child(_board_title)
	_board_grid = GridContainer.new()
	_board_grid.columns = 7
	_board_grid.add_theme_constant_override(&"h_separation", 40)
	_board_grid.add_theme_constant_override(&"v_separation", 6)
	box.add_child(_board_grid)


## The character your view ray passes closest to (within the marker config's aim radius and
## range) and that isn't behind a wall; null if none.
func _aimed_at(cam: Camera3D) -> Character:
	var cfg := _MARKER_CONFIG
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var best: Character = null
	var best_d := cfg.aim_range
	for c: Character in _tm.get_participants():
		if c == _player or not c.visible: continue
		var to := c.global_position + Vector3.UP * 1.0 - from
		var along := to.dot(fwd)
		if along <= 0.0 or along >= best_d: continue
		if (to - fwd * along).length() > cfg.aim_radius: continue
		_aim_ray.from = from
		_aim_ray.to = from + to
		if not _player.get_world_3d().direct_space_state.intersect_ray(_aim_ray).is_empty(): continue
		best = c
		best_d = along
	return best


func _update_aim(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam: return
	var hit := _aimed_at(cam)
	if hit:
		_aim_target = hit
		_aim_timer = _MARKER_CONFIG.name_show_time
		_aim_label.text = ("TORCH  " if _tm.is_torch(hit) else "") + hit.display_name
		_aim_label.modulate = (hit.marker.get_color() if hit.marker else hit.base_tint)
	else:
		_aim_timer = maxf(_aim_timer - delta, 0.0)
	var anchor := (_aim_target.get_global_transform_interpolated().origin + Vector3.UP * (_MARKER_CONFIG.height + 0.5)) \
			if is_instance_valid(_aim_target) else Vector3.ZERO
	var on_screen := _aim_timer > 0.0 and is_instance_valid(_aim_target) and not cam.is_position_behind(anchor)
	_aim_label.visible = on_screen
	if not on_screen: return
	_aim_label.modulate.a = clampf(_aim_timer / 0.3, 0.0, 1.0)
	var p := cam.unproject_position(anchor)
	_aim_label.position = p - Vector2(_aim_label.size.x * 0.5, _aim_label.size.y)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"HudLabel"
	l.add_theme_font_size_override(&"font_size", size)
	return l
