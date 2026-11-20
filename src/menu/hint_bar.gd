class_name HintBar
extends Control
## The strip along the bottom of a menu screen: a quiet line on the left, and on the right what
## the keys do here, as keycaps ("Esc  Back"). Set it with set_hints().

const _GAP := 28.0   # between hints
const _KEY_GAP := 6.0
const _LABEL_GAP := 10.0
const _LABEL_SIZE := 17

var left_text := ""
var _hints: Array = [] # [[keys: PackedStringArray, label: String], ...]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 96.0
	offset_right = -96.0
	offset_top = -76.0
	offset_bottom = -24.0


## hints: [[["Esc"], "Back"], [["←", "→"], "Change"], ...]
func set_hints(hints: Array) -> void:
	_hints = hints
	queue_redraw()


func _draw() -> void:
	var font := UIKit.BODY
	var y := size.y - 8.0 - 44.0
	var base := y + 6.0 + (32.0 + font.get_ascent(_LABEL_SIZE) - font.get_descent(_LABEL_SIZE)) * 0.5
	if left_text != "":
		draw_string(font, Vector2(0.0, base), left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, Color(UIKit.MUTED, 0.7))
	var x := size.x
	for i: int in range(_hints.size() - 1, -1, -1):
		var keys: PackedStringArray = _hints[i][0]
		var label: String = _hints[i][1]
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE).x
		x -= lw
		draw_string(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, UIKit.MUTED)
		x -= _LABEL_GAP
		for k: int in range(keys.size() - 1, -1, -1):
			var kw := UIKit.key_width(keys[k])
			x -= kw
			UIKit.draw_key(self, Vector2(x, y), kw, keys[k], false, 32.0)
			x -= _KEY_GAP
		x -= _GAP
