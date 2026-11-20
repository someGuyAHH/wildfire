class_name UIKit
## The UI's look in one place: the palette, the fonts, and the small widgets every menu and the HUD
## build from (the rest lives in the theme, assets/tres/ui/wildfire_theme.tres). Flat vector look:
## warm charcoal panels, off-white text, ember orange only for what matters right now, teal for
## runners and you. Slanted shapes, hard shadows, no blur.

const CHARCOAL := Color("14110f")
const PANEL    := Color(0.078, 0.067, 0.059, 0.9)  # charcoal, see-through a little
const SHADOW   := Color(0.0, 0.0, 0.0, 0.45)       # hard drop shadows
const TEXT     := Color("f3ece2")
const MUTED    := Color("a89e92")
const EMBER    := Color("ff6a1a")
const EMBER_DARK := Color("c2260f")
const GOLD     := Color("ffc23a")
const TEAL     := Color("3fd0c9")
const SKEW     := 0.3   # slant of panels and buttons, as a fraction of their height
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


## A screen's title, its letters burning (FlameTitle).
static func heading(text: String, font_size: int = 64) -> FlameTitle:
	var t := FlameTitle.new()
	t.setup(text, font_size)
	return t


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
