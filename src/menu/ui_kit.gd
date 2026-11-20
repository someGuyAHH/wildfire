class_name UIKit
## The UI's look in one place: the palette, the fonts, and the small widgets every menu and the HUD
## build from (the rest lives in the theme, assets/tres/ui/wildfire_theme.tres). Flat vector look:
## warm charcoal slabs with a visible thickness, off-white text, ember orange only for what matters
## right now (the chosen thing turns into a hot slab and lifts toward you), teal
## for runners and you.

const CHARCOAL := Color("14110f")
const PANEL    := Color(0.078, 0.067, 0.059, 0.9)  # charcoal, see-through a little
const SHADOW   := Color(0.0, 0.0, 0.0, 0.45)       # hard drop shadows
const TEXT     := Color("f3ece2")
const MUTED    := Color("a89e92")
const EMBER    := Color("ff6a1a")
const EMBER_DARK := Color("c2260f")
const GOLD     := Color("ffc23a")
const TEAL     := Color("3fd0c9")
const SKEW     := 0.3   # slant of the HUD's plates, as a fraction of their height
const SLAB_SKEW := 0.16 # slant of menu buttons and tabs (big panels stand straight)
# a slab's faces: the front, its lit top lip and its thickness below
const SLAB := Color("1d1916")
const SLAB_TOP := Color("2c2622")
const SLAB_SIDE := Color("0c0a09")
const SLAB_FOCUS := Color("2a2420")  # a row or zone with focus
const HOT_TOP := Color("ff9a5c")
const HOT_SIDE := Color("a8340c")
const KEY := Color("2c2622")         # keycaps
const KEY_SIDE := Color("120f0d")
const SHADOW_OFFSET := Vector2(5.0, 5.0)

## Titles, numbers and the timer.
const DISPLAY := preload("res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
const DISPLAY_BOLD := preload("res://assets/fonts/BarlowCondensed-BoldItalic.ttf")
## Body text (the theme's default font).
const BODY := preload("res://assets/fonts/Barlow-SemiBold.ttf")
const BODY_BOLD := preload("res://assets/fonts/Barlow-Bold.ttf")

const ICON_FIRE := preload("res://assets/images/ui/fire.svg")
const ICON_RUN := preload("res://assets/images/ui/person-simple-run.svg")
const ICON_FROZEN := preload("res://assets/images/ui/snowflake.svg")


## A menu label (hard shadow, from the theme's MenuLabel). font: null keeps the body font.
static func label(text: String, font_size: int, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"MenuLabel"
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	if font: l.add_theme_font_override(&"font", font)
	return l


## A screen's title: the display font, off-white, a hard shadow (only the logo burns: FlameTitle).
static func heading(text: String, font_size: int = 64) -> Label:
	var l := label(text, font_size, TEXT, DISPLAY)
	l.add_theme_constant_override(&"shadow_offset_x", 4)
	l.add_theme_constant_override(&"shadow_offset_y", 4)
	return l


## Empty space in a box (an 8 px grid: pass multiples of 8).
static func gap(px: float, horizontal: bool = false) -> Control:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.custom_minimum_size = Vector2(px, 0.0) if horizontal else Vector2(0.0, px)
	return g


## The slanted panel shape (a parallelogram leaning right) filling w x h at `at`.
static func slant(at: Vector2, w: float, h: float) -> PackedVector2Array:
	var s := h * SKEW
	return PackedVector2Array([at + Vector2(s, 0.0), at + Vector2(w, 0.0), at + Vector2(w - s, h), at + Vector2(0.0, h)])


## Draws a slanted plate on `ci`: hard shadow, fill, and an accent bar on its left edge.
static func draw_plate(ci: CanvasItem, at: Vector2, w: float, h: float, fill: Color, bar: Color, bar_w: float = 6.0) -> void:
	ci.draw_colored_polygon(slant(at + SHADOW_OFFSET, w, h), Color(SHADOW, SHADOW.a * fill.a))
	ci.draw_colored_polygon(slant(at, w, h), fill)
	if bar.a > 0.0: ci.draw_colored_polygon(slant(at, bar_w + h * SKEW, h), bar)


## A slab: a slanted (skew, of its height) block, `depth` px thick below, with a lit top lip and a
## hard shadow; `at` is its front's top-left. hot: the ember version.
static func draw_slab(ci: CanvasItem, at: Vector2, w: float, h: float, depth: float, hot: bool = false,
		skew: float = SLAB_SKEW, face: Color = SLAB, shadow: bool = true) -> void:
	var s := h * skew
	var d := Vector2(0.0, depth)
	# the block's outline seen from above: the front plus its sides down to the bottom face
	var hull := PackedVector2Array([at + Vector2(s, 0.0), at + Vector2(w, 0.0), at + Vector2(w, 0.0) + d,
			at + Vector2(w - s, h) + d, at + Vector2(0.0, h) + d, at + Vector2(0.0, h)])
	if shadow:
		var sh := hull.duplicate()
		for i: int in sh.size(): sh[i] += Vector2(6.0, 6.0)
		ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.32))
	ci.draw_colored_polygon(hull, HOT_SIDE if hot else SLAB_SIDE)
	ci.draw_colored_polygon(slant_k(at, w, h, skew), EMBER if hot else face)
	var lip := minf(3.0, h * 0.08)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(s, 0.0), at + Vector2(w, 0.0),
			at + Vector2(w - lip * skew, lip), at + Vector2(s - lip * skew, lip)]), HOT_TOP if hot else SLAB_TOP)


## The slanted shape with a given skew.
static func slant_k(at: Vector2, w: float, h: float, skew: float) -> PackedVector2Array:
	var s := h * skew
	return PackedVector2Array([at + Vector2(s, 0.0), at + Vector2(w, 0.0), at + Vector2(w - s, h), at + Vector2(0.0, h)])


## A keycap with its label (w: its width; pressed: sunk and hot).
static func draw_key(ci: CanvasItem, at: Vector2, w: float, label: String, pressed: bool = false, h: float = 44.0) -> void:
	var depth := 2.0 if pressed else 6.0
	var top := at + Vector2(0.0, 6.0 - depth)
	ci.draw_rect(Rect2(top + Vector2(0.0, depth), Vector2(w, h)), HOT_SIDE if pressed else KEY_SIDE)
	ci.draw_rect(Rect2(top, Vector2(w, h)), EMBER if pressed else KEY)
	var fs := 18 if label.length() > 1 else 20
	var tw := DISPLAY_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := top.y + (h + DISPLAY_BOLD.get_ascent(fs) - DISPLAY_BOLD.get_descent(fs)) * 0.5
	ci.draw_string(DISPLAY_BOLD, Vector2(top.x + (w - tw) * 0.5, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CHARCOAL if pressed else TEXT)


## Width of a keycap for this label.
static func key_width(label: String) -> float:
	return maxf(36.0, DISPLAY_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 22.0)

