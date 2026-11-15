"""
Numbers for one tag mode. Classic tag lives in assets/tres/match/classic_rules.tres.
"""

class_name MatchRules
extends Resource

@export_group("Round")
@export var round_time: float = 180.0
## Everyone is frozen in place while the countdown runs.
@export var countdown_time: float = 3.0
## Standings stay on screen this long, then a new round starts.
@export var results_time: float = 8.0

@export_group("Tagging")
## Max horizontal distance between body centers that counts as a touch (bodies are 0.8 wide).
@export var tag_radius: float = 1.3
## Max height difference that still counts (bodies are 1.8 tall).
@export var tag_height: float = 1.9
## The first Torch of a round waits this long so runners can scatter.
@export var first_torch_freeze: float = 3.0
## Every new Torch is frozen this long after being tagged.
@export var torch_freeze_time: float = 1.5
## The previous Torch can't be tagged straight back for this long.
@export var no_tagback_time: float = 3.0

@export_group("Body slam")
## Closing speed (from current velocities, no run-up needed) that stuns someone you run into.
## The Torch touching you is always just a tag.
@export var bump_speed: float = 20.0
## Bodies closer than this (horizontally) are touching. Never used below tag_radius.
@export var bump_radius: float = 1.3
@export var bump_stun: float = 1.5
## A stunned player can't be slammed again for this long.
@export var bump_immunity: float = 3.0
## The attacker bounces back this hard (and up a bit).
@export var bump_knockback: float = 9.0
@export var bump_attacker_disorient: float = 1.0

@export_group("Scoring")
## Score = time burning - snuffs * snuff_bonus - shoves * shove_bonus. Lowest score wins.
## A snuff is shoving the Torch, a shove is shoving another kindling (both seconds off).
@export var snuff_bonus: float = 3.0
@export var shove_bonus: float = 1.0

@export_group("Dry edge")
## The outer part of the arena (past this fraction of the map's arena_radius) is dry ground:
## kindling standing there heats up.
@export var edge_start: float = 0.85
## Heat gained per second on the dry edge (1.0 = full) and lost per second off it.
@export var heat_rate: float = 0.35
@export var heat_drain: float = 0.5
## Fully heated kindling smolders: time burning goes up at this rate (per second) without
## being the Torch, until they cool off back inside.
@export var smolder_score_rate: float = 0.5

@export_group("Smoke (hiding)")
## Kindling that stays within still_distance of one spot for still_time starts smoking...
@export var still_time: float = 6.0
@export var still_distance: float = 8.0
## ...and if it's still there when the smoke runs out (this long), it catches fire and becomes
## the Torch. Moving away puts the smoke out.
@export var smoke_time: float = 4.0

@export_group("Torch bonus")
@export var torch_speed_mult: float = 1.06
@export var torch_dash_regen_mult: float = 1.3
@export var torch_color := Color(1.0, 0.22, 0.12)
@export var torch_glow: float = 2.5
