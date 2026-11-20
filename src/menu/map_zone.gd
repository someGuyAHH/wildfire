class_name MapZone
extends MenuZone
## Which map: a picture of each (assets/images/ui/maps/<name>.png, baked by
## tools/mapgen/mode_art.gd) in a row, the chosen one lifted and outlined in ember; under them its
## name and a line about it. The live match behind the menu switches to it too (Main).

const THUMB := Vector2(150.0, 84.0)
const _GAP := 12.0
const _ABOUT := {
	"gym": "The test course: every move, one of each.",
	"overworld": "Open grass, the aqueduct, the mesa and the canyon.",
	"jungle": "Treetop decks round the temple. Shade, leaves, long drops.",
	"inferno": "Roofless cathedral halls over a sea of lava.",
}

var names := PackedStringArray()
var index := 0
var _pics: Array[Texture2D] = []


func _init() -> void:
	super()
	title = "MAP"


## The maps by name (in Main's order) and the one picked.
func setup(map_names: PackedStringArray, at: int) -> void:
	names = map_names
	index = clampi(at, 0, maxi(names.size() - 1, 0))
	_pics.clear()
	for n: String in names:
		var path := "res://assets/images/ui/maps/%s.png" % n.to_lower()
		_pics.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)
	custom_minimum_size = Vector2(PAD.x * 2.0 + names.size() * THUMB.x + (names.size() - 1) * _GAP, 232.0)
	queue_redraw()


func step(by: int) -> void:
	pick(posmod(index + by, names.size()))


func pick(i: int) -> void:
	if i == index or names.is_empty(): return
	index = i
	queue_redraw()
	changed.emit()


func _thumb_rect(i: int) -> Rect2:
	return Rect2(PAD.x + i * (THUMB.x + _GAP), PAD.y + 40.0, THUMB.x, THUMB.y)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for i: int in names.size():
			if _thumb_rect(i).grow(4.0).has_point(mb.position): pick(i)
		accept_event()
		return
	super(event)


func _draw_content(lit: bool) -> void:
	for i: int in names.size():
		var r := _thumb_rect(i)
		var cur := i == index
		if cur: r.position += Vector2(0.0, -6.0)
		draw_rect(Rect2(r.position + Vector2(0.0, 6.0 if not cur else 10.0), r.size), UIKit.SLAB_SIDE)
		if _pics[i]: draw_texture_rect(_pics[i], r, false, Color.WHITE if cur else Color(0.55, 0.55, 0.55))
		else: draw_rect(r, UIKit.KEY)
		if cur: draw_rect(r, UIKit.EMBER, false, 3.0)
		draw_string(UIKit.DISPLAY_BOLD, r.position + Vector2(8.0, r.size.y - 8.0), names[i].to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.TEXT if cur else Color(UIKit.TEXT, 0.7))
	if names.is_empty(): return
	var y := PAD.y + 40.0 + THUMB.y + 34.0
	draw_string(UIKit.DISPLAY, Vector2(PAD.x, y + 6.0), names[index].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
			UIKit.EMBER if lit else UIKit.TEXT)
	draw_multiline_string(UIKit.BODY, Vector2(PAD.x, y + 36.0), _ABOUT.get(names[index].to_lower(), ""),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD.x * 2.0, 17, 2, UIKit.MUTED)
