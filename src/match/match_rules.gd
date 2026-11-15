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
## The first It of a round waits this long so runners can scatter.
@export var first_it_freeze: float = 3.0
## Every new It is frozen this long after being tagged.
@export var it_freeze_time: float = 1.5
## The previous It can't be tagged straight back for this long.
@export var no_tagback_time: float = 3.0

@export_group("Body slam")
## Closing speed (from current velocities, no run-up needed) that stuns someone you run into.
## The It touching you is always just a tag.
@export var bump_speed: float = 20.0
## Bodies closer than this (horizontally) are touching. Never used below tag_radius.
@export var bump_radius: float = 1.3
@export var bump_stun: float = 1.5
## A stunned player can't be slammed again for this long.
@export var bump_immunity: float = 3.0
## The attacker bounces back this hard (and up a bit).
@export var bump_knockback: float = 9.0
@export var bump_attacker_disorient: float = 1.0

@export_group("It bonus")
@export var it_speed_mult: float = 1.06
@export var it_dash_regen_mult: float = 1.3
@export var it_color := Color(1.0, 0.22, 0.12)
@export var it_glow: float = 2.5
