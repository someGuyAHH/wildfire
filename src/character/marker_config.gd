"""
Tuning for the role marker floating over every character (see RoleMarker).
Edit the .tres while the game runs to tune live.
"""

class_name MarkerConfig
extends Resource

@export_group("Shape")
## Marker size (m) at the reference distance: the width of the inverted pyramid's top.
@export var size: float = 0.34
## Height of the apex (the tip, pointing down) above the character's origin.
@export var height: float = 2.35
## How much the marker brightens itself so it reads in dark corners (0 = lit only by the scene).
@export_range(0.0, 1.0) var self_light: float = 0.3

@export_group("Motion")
## Spin around Y, radians per second.
@export var spin_speed: float = 1.6
## Bob up and down: amplitude (m) and angular speed.
@export var bob_amount: float = 0.07
@export var bob_speed: float = 2.4

@export_group("Constant size")
## At this distance the marker is exactly `size`. Nearer shrinks, farther grows, within the clamp,
## so it stays about the same size on screen.
@export var ref_distance: float = 12.0
@export var min_scale: float = 0.35
@export var max_scale: float = 6.0

@export_group("Roles")
## The Torch's emissive glow (energy), its colour comes from the match rules.
@export var torch_glow: float = 3.0
## Pop when a marker changes to or from the Torch: scale punch (added to 1) and how long it takes.
@export var pop_scale: float = 1.2
@export var pop_time: float = 0.35

@export_group("Aim name")
## Aiming at a character shows their name for this long (s) after you look away.
@export var name_show_time: float = 1.2
## How close (m, sideways) your view ray passes a character to count as aiming at them.
@export var aim_radius: float = 1.0
@export var aim_range: float = 120.0
