class_name SlamFxConfig
extends Resource
## Tuning for the slam-jump impact (SlamFx): every size, count and strength from intensity 0 (the base 4 m
## bounce) to 1 (the 20 m top bounce), the same intensity the launch sound uses
## (MovementConfig.slam_jump_intensity). Each pair is a min (intensity 0) and a max (intensity 1); the max is
## the hard cap: intensity is clamped to 0..1, so nothing ever grows past it. Live: assets/tres/vfx/slam_fx.tres.

## How intensity becomes "how big" (0..1 in, 0..1 out). Unset = straight. Bent up, the small bounces stay small
## and only the big ones open up.
@export var response: Curve

@export_group("Cracks")
## Radius of the crack decal on the ground, metres.
@export var crack_radius_min: float = 0.9
@export var crack_radius_max: float = 3.0
## How far the decal reaches above and below the hit point (slopes, steps), metres.
@export var crack_depth: float = 1.4
## From this response the medium crack pattern (more cracks, branches) is used, and from the next the heavy one.
@export var crack_medium_from: float = 0.3
@export var crack_heavy_from: float = 0.7
## Seconds the cracks stay at full strength, then the seconds they fade over.
@export var crack_hold: float = 2.5
@export var crack_fade: float = 1.5
## Embers in the cracks: from this response on, glowing up to ember_energy at the top, cooling over ember_time s.
@export var ember_from: float = 0.5
@export var ember_energy: float = 4.0
@export var ember_time: float = 1.6

@export_group("Dust")
## Share of the dust ring's puffs that are emitted (of SlamFx.DUST_AMOUNT).
@export var dust_ratio_min: float = 0.4
@export var dust_ratio_max: float = 1.0
## Ring the puffs start on, and how fast they're thrown outward, along the ground.
@export var dust_radius_min: float = 0.35
@export var dust_radius_max: float = 1.0
@export var dust_speed_min: float = 4.0
@export var dust_speed_max: float = 10.0
## Puff size multiplier.
@export var dust_size_min: float = 0.7
@export var dust_size_max: float = 1.5
## Lingering dust (slow, wide, fading over seconds) from this response on, all of it at the top.
@export var linger_from: float = 0.3

@export_group("Debris")
## Rock chunks kicked up from this response on, all of SlamFx.DEBRIS_AMOUNT at the top.
@export var debris_from: float = 0.2
@export var debris_speed_min: float = 5.0
@export var debris_speed_max: float = 10.5
@export var debris_size_min: float = 0.8
@export var debris_size_max: float = 1.4

@export_group("Shockwave")
## A pale ring of dust racing out along the ground, radius it reaches (m), over shock_time s.
@export var shock_radius_min: float = 1.8
@export var shock_radius_max: float = 6.0
@export var shock_time: float = 0.35
@export var shock_alpha: float = 0.55

@export_group("Camera shake")
## Shake ("trauma" 0..1; the camera squares it) for your own slam-jump. Settings > Camera shake scales it.
@export var shake_min: float = 0.12
@export var shake_max: float = 0.55
## Someone else's slam-jump this close shakes your camera too, fading out with distance.
@export var shake_radius: float = 14.0

@export_group("Budget")
## Impacts on screen at once (each is two decals and three particle emitters). A new one past this takes over
## the oldest (a bot's before yours).
@export_range(1, 16) var pool_size: int = 6
## Impacts further than this from the camera aren't shown at all (yours always are).
@export var cull_distance: float = 60.0

@export_group("Colours")
## Dust colour per map (by scene name); debris is the same, darker.
@export var map_dust: Dictionary[StringName, Color] = {}
## A floor collider with a "surface" meta (wood, grass, concrete) picks its dust colour here first.
@export var surface_dust: Dictionary[StringName, Color] = {}
@export var default_dust: Color = Color(0.6, 0.57, 0.52)
## Debris colour = dust colour times this.
@export var debris_shade: float = 0.55


## Intensity (any value: clamped to 0..1) through the response curve.
func amount(intensity: float) -> float:
	var i := clampf(intensity, 0.0, 1.0)
	return clampf(response.sample_baked(i), 0.0, 1.0) if response else i


## 0 below `from`, rising to 1 at the top.
static func ramp_from(t: float, from: float) -> float:
	return clampf(inverse_lerp(from, 1.0, t), 0.0, 1.0) if from < 1.0 else 0.0


func dust_colour(map_name: StringName, surface: StringName) -> Color:
	if surface != &"" and surface_dust.has(surface): return surface_dust[surface]
	return map_dust.get(map_name, default_dust)
