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
