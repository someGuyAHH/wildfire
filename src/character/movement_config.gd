"""
Every movement tuning number in one place, shared by players and bots.
Edit the .tres in the inspector while the game runs to tune live.
Units are metres, seconds, m/s and m/s^2 unless the name says otherwise.
"""

class_name MovementConfig
extends Resource

# groups are worth it here, this thing has ~50 knobs
@export_group("Ground")
@export var max_speed: float = 14.0
@export var ground_accel: float = 90.0
## Deceleration with no input on the ground.
@export var ground_decel: float = 70.0
## How fast speed above max_speed bleeds off on the ground.
@export var ground_overspeed_drag: float = 10.0
## How fast an overspeed velocity can be turned on the ground, in rad/s.
@export var ground_turn_rate: float = 9.0
## After landing, overspeed drag is skipped for this long (keeps bhops and slide-jumps alive).
@export var landing_grace: float = 0.15
## Anything steeper is a wall (and wall-jumpable).
@export var floor_max_angle_deg: float = 62.0
@export var floor_snap: float = 0.55

@export_group("Air")
@export var air_accel: float = 45.0
@export var air_decel: float = 2.0
@export var air_overspeed_drag: float = 0.0
@export var air_turn_rate: float = 2.8

@export_group("Gravity")
@export var gravity: float = 18.0
@export var fall_gravity_mult: float = 1.35
@export var terminal_velocity: float = 65.0
## Above this horizontal speed, quadratic drag kicks in. Soft cap, not a clamp.
@export var soft_speed_cap: float = 32.0
@export var soft_cap_drag: float = 0.015

@export_group("Jump")
@export var jump_velocity: float = 9.5
## Vertical speed multiplier when jump is released early while rising.
@export var jump_cut_mult: float = 0.5
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12

@export_group("Slide")
@export var slide_boost: float = 5.0
## Slide never drops below this on flat ground while held.
@export var slide_min_speed: float = 11.0
@export var slide_friction: float = 1.0
@export var slide_steer_rate: float = 2.2
@export var slide_slope_accel: float = 1.0
## Minimum time between two slide boosts (anti spam).
@export var slide_boost_cooldown: float = 0.6
## Holding crouch when a slide runs out (or slows below this going uphill) keeps you low,
## walking at this speed until you let go.
@export var crouch_speed: float = 7.0

@export_group("Dash")
@export var dash_speed: float = 28.0
@export var dash_time: float = 0.14
@export var dash_charges: int = 3
## Seconds to regenerate one charge.
@export var dash_regen: float = 1.2
## Horizontal speed after a dash ends is max(speed before the dash, this).
@export var dash_exit_speed: float = 16.0
## Jumping out of a grounded dash keeps this fraction of the dash speed...
@export var dash_jump_keep: float = 0.85
## ...or, going faster than that already, adds this to your speed going into the dash. Chained
## dash-jumps level off where the soft cap's drag eats it (~38 m/s at one per charge refill).
@export var dash_jump_boost: float = 4.0

@export_group("Walls")
@export var wall_jumps_max: int = 3
@export var wall_jump_up: float = 10.5
@export var wall_jump_push: float = 9.0
## Fraction of along-the-wall speed kept through a wall-jump.
@export var wall_jump_keep: float = 0.9
@export var wall_probe_dist: float = 0.55
@export var wall_slide_speed: float = 3.0
## A wall touched this recently still counts for wall-jumps.
@export var wall_coyote: float = 0.15

@export_group("Slam")
@export var slam_speed: float = 48.0
@export var slam_horizontal_keep: float = 0.15
## Jumping this soon after a slam lands gives a bounce.
@export var slam_bounce_window: float = 0.25
## Slam-bounce apex = base + fall_ratio * (how far you fell), capped at max. Heights in metres.
## fall_ratio < 1 so chained bounces on flat ground level off (at base / (1 - ratio)).
@export var slam_bounce_base_height: float = 4.0
@export var slam_bounce_fall_ratio: float = 0.6
@export var slam_bounce_max_height: float = 20.0

@export_group("Brake (Q)")
## Air: how fast horizontal speed eases toward zero during a brake slam.
@export var brake_air_decel: float = 75.0
## Air: you keep this fraction of max_speed as steering, to line up a landing.
@export var brake_air_steer: float = 0.3
## Ground: skid-stop deceleration and how long it holds.
@export var brake_ground_decel: float = 160.0
@export var brake_ground_time: float = 0.2
## A ground brake from at least overdrive_speed is a crash stop: stunned this long...
@export var hard_stop_stun: float = 0.5
## ...then disoriented (steering drift, stumbling) this long.
@export var hard_stop_disorient: float = 1.8

@export_group("Overdrive")
## Above this horizontal speed: violet speed flames, sparks off your body, and braking to a dead
## stop on the ground stuns you (see hard_stop_*).
@export var overdrive_speed: float = 30.0

@export_group("Dizziness")
## Each ground brake adds 1; reaching the threshold stuns you.
@export var dizzy_threshold: float = 4.0
## Meter drain per second, so only rapid spam counts.
@export var dizzy_decay: float = 1.2
## Stun length; the camera sways for the same time.
@export var dizzy_duration: float = 2.0

@export_group("Wall bonk")
## Speed into a wall (m/s, the part going straight at it) that disorients you.
@export var wall_bonk_speed: float = 20.0
## Disorientation length at exactly wall_bonk_speed...
@export var bonk_duration: float = 2.5
## ...plus this many seconds per m/s above it...
@export var bonk_duration_per_mps: float = 0.1
## ...capped here.
@export var bonk_max_duration: float = 4.5
## Max steering drift while disoriented, in radians.
@export var bonk_steer_wobble: float = 0.55
## Impact speed is how fast you *actually* closed in on the wall over this window, not just
## your velocity, so dashing from point-blank (wall-jump setups) never counts.
@export var bonk_runup_time: float = 0.1
## Min time between two bonks, so one impact only counts once.
@export var bonk_cooldown: float = 0.4
## While disoriented you lurch around by yourself at up to this fraction of max_speed,
## even with no input (it mixes with your input when you do press keys).
@export var bonk_stumble: float = 0.3

@export_group("Step & vault")
## Auto-step height as a fraction of body height (0.42 * 1.8 m = 0.756 m).
@export var step_height_ratio: float = 0.42
## Auto-step height in metres. Derived, change step_height_ratio or height instead.
var step_height: float:
	get:
		return height * step_height_ratio
@export var vault_height: float = 1.5
@export var vault_probe_dist: float = 0.7
@export var vault_cooldown: float = 0.3

@export_group("Body")
@export var height: float = 1.8
@export var radius: float = 0.4
@export var eye_height: float = 1.62
@export var slide_height: float = 1.0
@export var slide_eye_height: float = 0.8


## How big a slam-jump launch is, 0..1: the apex a launch with this upward speed reaches, from the base
## bounce (0) to the highest (1). The audio reads it to choose how destructive the launch sounds.
func slam_jump_intensity(launch_speed_y: float) -> float:
	var apex := launch_speed_y * launch_speed_y / (2.0 * gravity)
	return clampf(inverse_lerp(slam_bounce_base_height, slam_bounce_max_height, apex), 0.0, 1.0)
