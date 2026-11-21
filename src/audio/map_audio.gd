class_name MapAudio
extends Resource
## What a map sounds like: the ground under foot and the ambience loops that run under everything.

## The map scene's file name without the extension ("overworld").
@export var map_name: StringName = &""
## "concrete", "grass" or "wood": which footsteps (step_<surface>). A floor collider can say otherwise with a "surface" meta.
@export var surface: StringName = &"concrete"
## Ambience loops (ids of looping sounds in the bank) and each one's level (dB), side by side.
@export var ambience: Array[StringName] = []
@export var ambience_db: Array[float] = []
