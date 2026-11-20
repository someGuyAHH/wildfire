class_name BotsZone
extends MenuZone
## How many bots: − / + either side of the number, then a pip per player (you in teal, a bot in
## off-white, the empty seats dim) and "You and 7 bots".

var count := 7
var lo := 1
var hi := 15
var _minus: Rect2
var _plus: Rect2


func _init() -> void:
	super()
	title = "BOTS"
	custom_minimum_size = Vector2(300.0, 232.0)


func step(by: int) -> void:
	var n := clampi(count + by, lo, hi)
	if n == count: return
	count = n
	queue_redraw()
	changed.emit()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _minus.has_point(mb.position): step(-1)
		elif _plus.has_point(mb.position): step(1)
		accept_event()
		return
	super(event)


func _draw_content(lit: bool) -> void:
	var y := PAD.y + 44.0
	var sq := 48.0
	_minus = Rect2(PAD.x, y + 8.0, sq, sq)
	_plus = Rect2(size.x - PAD.x - sq, y + 8.0, sq, sq)
	for r: Rect2 in [_minus, _plus]:
		var on := (r == _minus and count > lo) or (r == _plus and count < hi)
		UIKit.draw_slab(self, r.position, sq, sq, 6.0, false, 0.0, UIKit.KEY, false)
		var sign_ := "−" if r == _minus else "+"
		var w := UIKit.DISPLAY.get_string_size(sign_, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(UIKit.DISPLAY, Vector2(r.get_center().x - w * 0.5, r.position.y + 36.0), sign_,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UIKit.TEXT if on else Color(UIKit.TEXT, 0.3))
	var num := "%d" % count
	var nw := UIKit.DISPLAY.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
	draw_string(UIKit.DISPLAY, Vector2(size.x * 0.5 - nw * 0.5, y + 60.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 72,
			UIKit.EMBER if lit else UIKit.TEXT)
	# a pip per seat: you, the bots, the empty ones
	var seats := hi + 1
	var gap := 3.0
	var pw := (size.x - PAD.x * 2.0 - gap * (seats - 1)) / seats
	var py := y + 92.0
	for i: int in seats:
		var c := UIKit.TEAL if i == 0 else (UIKit.TEXT if i <= count else Color(UIKit.TEXT, 0.14))
		draw_rect(Rect2(PAD.x + i * (pw + gap), py, pw, 22.0), c)
	draw_string(UIKit.BODY, Vector2(PAD.x, py + 50.0), "You and %d bot%s" % [count, "" if count == 1 else "s"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIKit.MUTED)
