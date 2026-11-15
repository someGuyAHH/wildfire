"""
What a controller (player input or bot brain) wants a @Character to do this physics tick.
The character never reads Input directly, it only reads one of these.
Controllers overwrite every field each tick, so "pressed" flags are one-tick edges.
"""

class_name CharacterIntent
extends RefCounted

## World-space horizontal direction, length 0..1 (analogue scales speed).
var wish_dir := Vector3.ZERO
## World-space horizontal facing; used for dashes without input and for the visual.
var look_dir := Vector3.FORWARD

var jump_pressed := false
var jump_held    := false
var slide_pressed := false
var slide_held    := false
var dash_pressed  := false
## Brake slam in the air, skid stop on the ground.
var brake_pressed := false


## Resets one-tick edges. Held states are left alone.
func clear_edges() -> void:
	jump_pressed = false
	slide_pressed = false
	dash_pressed = false
	brake_pressed = false


## Writes a direction into wish_dir, flattened and clamped to length 1.
func set_wish(dir: Vector3) -> void:
	dir.y = 0.0
	wish_dir = dir.limit_length(1.0)


## Writes a facing into look_dir, flattened. Zero-ish input keeps the old facing.
func set_look(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001: return
	look_dir = dir.normalized()
