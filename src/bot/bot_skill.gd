"""
How good a bot is. Presets live in assets/tres/bot/. Difficulty comes from decisions and
reaction time, never from movement cheats: bots use the same MovementConfig as you.
"""

class_name BotSkill
extends Resource

## Seconds between decisions (target picks, flee routes, noticing the Torch). Lower = sharper.
@export var reaction_time: float = 0.22
## 0..1, how well chasers lead a moving target instead of running at where it is.
@export var prediction: float = 0.7
## How far a runner can *see* the Torch (still needs line of sight and to be looking that way).
@export var awareness_radius: float = 45.0
## Within this distance a runner hears the Torch from any direction, through walls.
@export var hearing_radius: float = 10.0
## Half-angle of the runner's view cone, degrees, around the way it's moving.
@export var view_half_angle: float = 60.0
## Seconds between glances over the shoulder (one 360° check each).
@export var glance_interval: float = 2.0
## After losing sight of the Torch, keep fleeing from where it was seen for this long.
@export var memory_time: float = 3.0
## 0..1, chance a runner picks a mediocre escape route instead of the best one.
@export var blunder: float = 0.12
## How much "this guy keeps hovering around / staring at me / dashing at me" it takes before
## the bot realises it's being targeted for a body slam. Lower = catches on quicker.
@export var suspicion: float = 2.5
## Once the Torch picks a target it sticks with it this long (seconds) before reconsidering,
## unless the target becomes untaggable/unreachable or someone else is right on top of it.
@export var commit_time: float = 5.0
## 0..1, chance the bot fights back (charges you to slam you first) instead of running off.
@export var aggression: float = 0.5
## 0..1, chance to use a dash when a good moment comes up.
@export var dash_skill: float = 0.6
## 0..1, chance a runner jukes (sideways dash/swerve) when the Torch is about to touch it.
@export var juke_skill: float = 0.5
## 0..1, chance to slide on long straights for the speed boost.
@export var slide_use: float = 0.5
## How many escape points a runner considers each decision.
@export var flee_samples: int = 16
## Random steering error, degrees.
@export var steer_error_deg: float = 8.0
