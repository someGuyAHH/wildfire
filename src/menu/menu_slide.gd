class_name MenuSlide
extends Resource
## How the title menu's screens slide in and out. Each screen comes in from its own side
## (and the title goes out the opposite one); going back reverses it.

## Seconds for a slide.
@export_range(0.05, 1.0, 0.01) var duration: float = 0.26
## Seconds clicks are swallowed at the start of a slide (a click or key after that skips to the end).
@export_range(0.0, 0.5, 0.01) var input_block: float = 0.08
## The title slides along by this share of what the incoming screen does (1 = pushed off together, 0 = stays put under it).
@export_range(0.0, 1.0, 0.05) var title_follow: float = 1.0
## Easing of the slide.
@export var easing: Tween.EaseType = Tween.EASE_OUT
@export var transition: Tween.TransitionType = Tween.TRANS_CUBIC
## Which side each screen comes in from: (1, 0) the right, (-1, 0) the left, (0, 1) below, (0, -1) above.
@export var from_modes := Vector2(1.0, 0.0)
@export var from_settings := Vector2(0.0, 1.0)
@export var from_howto := Vector2(-1.0, 0.0)


## The side a screen comes in from (zero for the title).
func side_of(screen: StringName) -> Vector2:
	match screen:
		&"modes": return from_modes
		&"settings": return from_settings
		&"howto": return from_howto
	return Vector2.ZERO


@export_group("Match setup pieces")
## Where each piece of the match setup comes from, as a direction off the screen (x: -1 left, 1 right;
## y: -1 above, 1 below; diagonals are corners). Keys: back, title, wheel, arrow_l, arrow_r, bots, map, diff, play.
@export var piece_from: Dictionary[StringName, Vector2] = {
	&"back": Vector2(-1.0, -1.0), &"title": Vector2(0.0, -1.0), &"wheel": Vector2(0.0, -1.0),
	&"arrow_l": Vector2(-1.0, 0.0), &"arrow_r": Vector2(1.0, 0.0),
	&"bots": Vector2(-1.0, 1.0), &"map": Vector2(0.0, 1.0), &"diff": Vector2(1.0, 1.0), &"play": Vector2(1.0, -1.0),
}
## Seconds one piece takes to slide into place.
@export_range(0.05, 1.0, 0.01) var piece_time: float = 0.3
## Seconds between one piece starting and the next (in the order above).
@export_range(0.0, 0.2, 0.005) var piece_stagger: float = 0.04
## Leaving: each piece pops up off its spot at this speed (px/s) ...
@export_range(0.0, 3000.0, 10.0) var pop_speed: float = 900.0
## ... and then falls under this gravity (px/s^2).
@export_range(500.0, 30000.0, 100.0) var gravity: float = 9000.0
## Each piece lets go up to this many seconds late (random).
@export_range(0.0, 0.5, 0.005) var fall_delay_max: float = 0.12
## Each piece tumbles up to this fast, either way (degrees / s), and drifts sideways up to this fast (px/s).
@export_range(0.0, 720.0, 5.0) var spin_max: float = 120.0
@export_range(0.0, 600.0, 5.0) var drift_max: float = 120.0
## Which side the title comes in from / goes out to when the setup leaves / arrives.
@export var title_from := Vector2(-1.0, 0.0)
## Seconds the title takes to slide.
@export_range(0.05, 1.0, 0.01) var title_time: float = 0.3
## A falling piece is kept until it is fully below the screen, but never longer than its
## fall should take plus this many seconds (a safety cap).
@export_range(0.0, 5.0, 0.1) var fall_cap_extra: float = 2.0
