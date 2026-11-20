class_name DifficultyZone
extends MenuZone
## How good the bots are: a segmented bar of the four choices, a hot block sliding to the chosen
## one, and a line on what it means.

const OPTIONS: Array[String] = ["Easy", "Normal", "Hard", "Mixed"]
const _ABOUT: Array[String] = [
	"Slow to react and easy to lose behind cover.",
	"They read the map and cut corners. Fair.",
	"They head you off where you're going. No mercy.",
	"Every bot rolls its own skill, like a public lobby.",
]
const _BAR_H := 52.0
const _SLIDE_TIME := 0.2

var index := 3
var _block_x := -1.0 # the hot block's left edge (eases to the chosen segment)
var _tween: Tween


func _init() -> void:
	super()
	title = "DIFFICULTY"
	custom_minimum_size = Vector2(400.0, 232.0)
	resized.connect(func() -> void: _block_x = -1.0) # (re-placed at the next draw)


func step(by: int) -> void:
	pick(clampi(index + by, 0, OPTIONS.size() - 1))


func pick(i: int) -> void:
	if i == index: return
	index = i
	if _tween: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v: float) -> void: _block_x = v; queue_redraw(), _block_x, _seg(i).position.x, _SLIDE_TIME)
	queue_redraw()
	changed.emit()


func _seg(i: int) -> Rect2:
	var w := (size.x - PAD.x * 2.0) / OPTIONS.size()
	return Rect2(PAD.x + i * w, PAD.y + 44.0, w, _BAR_H)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for i: int in OPTIONS.size():
			if _seg(i).has_point(mb.position): pick(i)
		accept_event()
		return
	super(event)


func _draw_content(_lit: bool) -> void:
	var bar := Rect2(_seg(0).position, Vector2(size.x - PAD.x * 2.0, _BAR_H))
	draw_rect(bar, UIKit.SLAB_SIDE)
	if _block_x < 0.0: _block_x = _seg(index).position.x
	var s := _seg(index)
	UIKit.draw_slab(self, Vector2(_block_x, s.position.y - 4.0), s.size.x, s.size.y, 6.0, true, 0.0, UIKit.EMBER, false)
	for i: int in OPTIONS.size():
		var r := _seg(i)
		var t := OPTIONS[i].to_upper()
		var w := UIKit.DISPLAY_BOLD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var on := i == index and absf(_block_x - r.position.x) < 4.0
		draw_string(UIKit.DISPLAY_BOLD, Vector2(r.get_center().x - w * 0.5, r.position.y + 33.0 - (4.0 if i == index else 0.0)), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.CHARCOAL if on else UIKit.TEXT)
	draw_multiline_string(UIKit.BODY, Vector2(PAD.x, bar.end.y + 36.0), _ABOUT[index], HORIZONTAL_ALIGNMENT_LEFT,
			size.x - PAD.x * 2.0, 17, 3, UIKit.MUTED)
