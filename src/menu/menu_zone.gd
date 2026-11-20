class_name MenuZone
extends Control
## A section of the match setup (bots, map, difficulty): a slab panel with its name at the top.
## With the focus it lightens, its name brightens and an ember bar runs along its top; left / right (keys,
## d-pad, stick) change its value (step()), the mouse works its parts directly. Hovering it takes
## the focus, like the buttons.

signal changed

const PAD := Vector2(24.0, 18.0)

var title := ""


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS
	for s: Signal in [focus_entered, focus_exited]: s.connect(queue_redraw)
	mouse_entered.connect(func() -> void: if not has_focus(): grab_focus())


## Moves the value by one (left -1, right +1). For subclasses.
func step(_by: int) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"): step(-1)
	elif event.is_action_pressed(&"ui_right"): step(1)
	else: return
	accept_event()


func _draw() -> void:
	var lit := has_focus()
	UIKit.draw_slab(self, Vector2.ZERO, size.x, size.y, 14.0, false, 0.0, UIKit.SLAB_FOCUS if lit else UIKit.SLAB)
	if lit: draw_rect(Rect2(0.0, 0.0, size.x, 4.0), UIKit.EMBER)
	var x := PAD.x
	draw_string(UIKit.DISPLAY_BOLD, Vector2(x, PAD.y + 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			UIKit.TEXT if lit else UIKit.MUTED)
	_draw_content(lit)


## For subclasses: what's in the panel (under the name, from PAD.y + 36).
func _draw_content(_lit: bool) -> void:
	pass
