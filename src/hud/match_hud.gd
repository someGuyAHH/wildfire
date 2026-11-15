extends CanvasLayer

# match HUD: round timer / countdown, who's the Torch, red frame while you're the Torch, tag feed,
# scoreboard (hold Tab, and on the results screen). built in code, it's all text.

const _TORCH_COLOR    := Color(1.0, 0.3, 0.2)
const _YOU_COLOR   := Color(0.5, 0.8, 1.0)
const _FEED_LIFE   := 4.5
const _FEED_FADE   := 1.0
const _FEED_MAX    := 5
const _BOARD_EVERY := 0.25
const _VIGNETTE_SHADER := preload("res://assets/gdshaders/threat_vignette.gdshader")
## Hunted warning: full strength at this distance or closer, nothing past _THREAT_FAR.
const _THREAT_NEAR := 5.0
const _THREAT_FAR  := 45.0
const _ARROW_MARGIN := 70.0
const _HEAT_COLOR   := Color(1.0, 0.45, 0.05)
const _SMOKE_COLOR  := Color(0.78, 0.78, 0.82)
const _SNUFF_COLOR  := Color(0.5, 0.85, 1.0)
const _COZY_WARN    := 0.5 # stillness above this starts warning you

var _tm: TagManager
var _player: Character
var _frame: Panel
var _timer_label: Label
var _role_label: Label
var _feed: VBoxContainer
var _feed_life: Dictionary[Label, float] = {}
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
	_tm.combusted.connect(on_combusted)
	_tm.round_ended.connect(on_round_ended)
	_tm.phase_changed.connect(on_phase_changed)


func _process(delta: float) -> void:
	if not _tm: return
	_update_top()
	_update_feed(delta)
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


func on_tagged(tagger: Character, victim: Character) -> void:
	_push_feed("%s set %s alight" % [_who(tagger), _who(victim)],
			_TORCH_COLOR if victim == _player else (_YOU_COLOR if tagger == _player else Color.WHITE))


func on_bumped(attacker: Character, victim: Character) -> void:
	if victim == _tm.get_torch():
		_push_feed("%s snuffed the Torch!  (-%.0f s)" % [_who(attacker), _tm.rules.snuff_bonus],
				_YOU_COLOR if attacker == _player else _SNUFF_COLOR)
		return
	_push_feed("%s shoved %s" % [_who(attacker), _who(victim)],
			_TORCH_COLOR if victim == _player else (_YOU_COLOR if attacker == _player else Color(1, 0.85, 0.4)))


func on_smoking_started(c: Character) -> void:
	_push_feed("%s %s smoking" % [_who(c), "are" if c == _player else "is"], _SMOKE_COLOR)


func on_combusted(c: Character, _old_torch: Character) -> void:
	_push_feed("%s sat still too long and caught fire!" % _who(c), _TORCH_COLOR if c == _player else _HEAT_COLOR)


func on_smolder_changed(c: Character, smoldering: bool) -> void:
	if smoldering: _push_feed("%s %s smoldering" % [_who(c), "are" if c == _player else "is"], _HEAT_COLOR)


func on_round_ended(standings: Array[Character]) -> void:
	var winner := standings[0] if not standings.is_empty() else null
	_board_title.text = "ROUND OVER  ·  %s" % ("YOU WIN!" if winner == _player else "%s wins" % winner.display_name) \
			if winner else "ROUND OVER"
	_board_refresh = 0.0


func on_phase_changed(phase: int) -> void:
	if phase == TagManager.PHASE_COUNTDOWN:
		for l: Label in _feed_life.keys(): l.queue_free()
		_feed_life.clear()
	if phase != TagManager.PHASE_RESULTS: _board_title.text = "SCOREBOARD"


func _update_top() -> void:
	var t := _tm.get_time_left()
	var torch := _tm.get_torch()
	var you_torch := torch == _player
	_frame.visible = you_torch
	match _tm.get_phase():
		TagManager.PHASE_COUNTDOWN:
			_timer_label.text = "%d" % ceili(t)
			_role_label.text = "get ready"
			_role_label.modulate = Color.WHITE
		TagManager.PHASE_PLAYING:
			_timer_label.text = "%d:%02d" % [floori(t / 60.0), int(t) % 60]
			if you_torch:
				_role_label.text = "YOU'RE ON FIRE!" if not _player.is_frozen() else "YOU'RE ON FIRE!  (frozen)"
				_role_label.modulate = _TORCH_COLOR
			elif torch:
				var d := torch.global_position.distance_to(_player.global_position)
				_role_label.text = "%s is the Torch  ·  %d m%s" % [torch.display_name, int(d),
						"  ·  fireproof for a moment" if _tm.is_tag_immune(_player) else ""]
				_role_label.modulate = Color.WHITE
		TagManager.PHASE_RESULTS:
			_timer_label.text = "next round in %d" % ceili(t)
			_role_label.text = ""
		_:
			_timer_label.text = ""
			_role_label.text = ""


## Red edges + an arrow toward the closest bot that's actually hunting you.
func _update_threat(delta: float) -> void:
	var hunter: Character
	var best := INF
	for c: Character in _tm.get_participants():
		if c.chase_target != _player: continue
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
	var playing := _tm.get_phase() == TagManager.PHASE_PLAYING and _tm.get_torch() != _player
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
			text = "SMOLDERING  ·  get off the dry edge!"
			color = _HEAT_COLOR
		elif heat > 0.01:
			var on_edge := _tm.get_edge_distance(_player) < 0.0
			text = ("dry ground  ·  heating up %d%%" if on_edge else "cooling off  ·  %d%%") % int(heat * 100.0)
			color = _HEAT_COLOR if on_edge else Color(1.0, 0.8, 0.6)
		elif still > _COZY_WARN:
			text = "getting cozy...  keep moving or you'll start smoking"
			color = _SMOKE_COLOR
	_status_label.text = text
	_status_label.modulate = color


func _update_feed(delta: float) -> void:
	for l: Label in _feed_life.keys():
		var life := _feed_life[l] - delta
		if life <= 0.0:
			_feed_life.erase(l)
			l.queue_free()
			continue
		_feed_life[l] = life
		l.modulate.a = clampf(life / _FEED_FADE, 0.0, 1.0)


func _push_feed(text: String, color: Color) -> void:
	var l := _label(text, 22, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	_feed_life[l] = _FEED_LIFE
	while _feed.get_child_count() > _FEED_MAX:
		var old := _feed.get_child(0) as Label
		_feed_life.erase(old)
		_feed.remove_child(old)
		old.queue_free()


func _fill_board() -> void:
	for child: Node in _board_grid.get_children(): child.queue_free()
	for h: String in ["#", "player", "time burning", "snuffs", "shoves", "set alight", "score"]:
		_board_grid.add_child(_label(h, 20, Color(1, 1, 1, 0.6)))
	var standings := _tm.get_standings()
	for i: int in standings.size():
		var c := standings[i]
		var col := _YOU_COLOR if c == _player else (_TORCH_COLOR if c == _tm.get_torch() else Color.WHITE)
		_board_grid.add_child(_label("%d" % (i + 1), 22, col))
		_board_grid.add_child(_label(c.display_name, 22, col))
		_board_grid.add_child(_label("%.1f s" % _tm.get_torch_time(c), 22, col))
		_board_grid.add_child(_label("%d" % _tm.get_snuffs(c), 22, col))
		_board_grid.add_child(_label("%d" % _tm.get_shoves(c), 22, col))
		_board_grid.add_child(_label("%d" % _tm.get_tags_made(c), 22, col))
		_board_grid.add_child(_label("%.1f" % _tm.get_score(c), 22, col))


func _who(c: Character) -> String:
	return "You" if c == _player else c.display_name


func _build() -> void:
	_vignette = ColorRect.new()
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = _VIGNETTE_SHADER
	_vignette.material = _vignette_mat
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)
	_heat_vignette = ColorRect.new()
	_heat_mat = ShaderMaterial.new()
	_heat_mat.shader = _VIGNETTE_SHADER
	_heat_mat.set_shader_parameter(&"color", _HEAT_COLOR)
	_heat_mat.set_shader_parameter(&"max_alpha", 0.45)
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
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = Color(_TORCH_COLOR, 0.55)
	frame_style.set_border_width_all(10)
	_frame.add_theme_stylebox_override(&"panel", frame_style)
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 14.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_timer_label = _label("", 46, Color.WHITE)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label = _label("", 26, Color.WHITE)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label = _label("", 22, Color.WHITE)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_timer_label)
	top.add_child(_role_label)
	top.add_child(_status_label)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_top = 16.0
	_feed.offset_right = -20.0
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	_board = PanelContainer.new()
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	board_style.set_content_margin_all(24.0)
	_board.add_theme_stylebox_override(&"panel", board_style)
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	add_child(_board)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	_board.add_child(box)
	_board_title = _label("SCOREBOARD", 30, Color(1.0, 0.62, 0.2))
	box.add_child(_board_title)
	_board_grid = GridContainer.new()
	_board_grid.columns = 7
	_board_grid.add_theme_constant_override(&"h_separation", 36)
	box.add_child(_board_grid)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_constant_override(&"outline_size", 6)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	return l
