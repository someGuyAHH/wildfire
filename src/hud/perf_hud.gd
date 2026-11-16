extends CanvasLayer

## Performance HUD (Settings > Performance HUD), in every build, menus and matches alike.
##   FPS:  frames per second
##   Full: + frame time (average / worst of the last second), GPU and render-CPU time per
##         frame, draw calls, and the 3D render resolution (render scale applied)
## Refreshes 4 times a second so the numbers are readable.

const _REFRESH := 0.25
const _WINDOW := 1.0 # seconds of frame times the average / worst cover

var _label: Label
var _mode := 0
var _times: Array[float] = []
var _since := 0.0


func _ready() -> void:
	layer = 20 # over the menus and the pause screen
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_right = -16.0
	_label.offset_bottom = -12.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_label)
	STG.settings_changed.connect(on_settings_changed)
	_apply()


func on_settings_changed(key: StringName) -> void:
	if key == STG.PERF_HUD: _apply()


func _apply() -> void:
	_mode = clampi(roundi(STG.get_value(STG.PERF_HUD)), 0, 2)
	visible = _mode > 0
	set_process(_mode > 0)
	_times.clear()
	# GPU time is only measured while asked for (it costs a query per frame)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _mode == 2)


func _process(delta: float) -> void:
	_times.append(delta)
	var total := 0.0
	for t: float in _times: total += t
	while _times.size() > 1 and total - _times[0] > _WINDOW:
		total -= _times[0]
		_times.pop_front()
	_since += delta
	if _since < _REFRESH: return
	_since = 0.0
	var fps := Engine.get_frames_per_second()
	if _mode == 1:
		_label.text = "%d FPS" % fps
		return
	var worst := 0.0
	for t: float in _times: worst = maxf(worst, t)
	var rid := get_viewport().get_viewport_rid()
	var vp := get_tree().root
	var res := Vector2(vp.size) * vp.scaling_3d_scale
	_label.text = "\n".join(PackedStringArray([
		"%d FPS" % fps,
		"frame %.1f ms  (worst %.1f)" % [total / _times.size() * 1000.0, worst * 1000.0],
		"GPU %.1f ms   render CPU %.1f ms" % [RenderingServer.viewport_get_measured_render_time_gpu(rid),
				RenderingServer.viewport_get_measured_render_time_cpu(rid)],
		"%d draw calls" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"3D %d×%d" % [roundi(res.x), roundi(res.y)],
	]))
