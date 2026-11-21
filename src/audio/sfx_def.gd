class_name SfxDef
extends Resource
## One game sound: its recorded variants and how it is played. Edit the numbers in assets/tres/audio/sfx_bank.tres.

## What the game asks for it by ("step_grass", "ui_click").
@export var id: StringName = &""
## The recordings. A one-shot picks one at random (never the same twice in a row).
@export var streams: Array[AudioStream] = []
## The bus it plays on (Buses.* in sfx.gd).
@export var bus: StringName = &"SFX"
## Balance against the rest, dB. (The files are all normalised to the same loudness.)
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0
## Each play is this much louder or quieter, either way (dB).
@export_range(0.0, 6.0, 0.1) var volume_jitter_db: float = 1.0
## Each play is pitched somewhere in this range (1 = as recorded).
@export_range(0.5, 2.0, 0.01) var pitch_min: float = 0.95
@export_range(0.5, 2.0, 0.01) var pitch_max: float = 1.05
## At most this many of it sound at once (it is a loop: this many loops across the whole game).
## A new one steals the oldest, or is dropped when it's further away than all of them.
@export_range(1, 32) var max_voices: int = 4
## Least seconds between two plays of it.
@export_range(0.0, 2.0, 0.01) var min_interval: float = 0.0
## In the world (3D, fading with distance) or flat (menus, the round's stingers).
@export var positional: bool = true
## 3D: the distance at which it is at full volume, and the distance past which it isn't played at all.
@export_range(0.5, 100.0, 0.5) var unit_size: float = 6.0
@export_range(5.0, 400.0, 1.0) var max_distance: float = 60.0
## A loop (its stream gets looped; the owner starts and stops it).
@export var loop: bool = false


## A random recording, not the one `last` was if there is a choice.
func pick(last: AudioStream = null) -> AudioStream:
	if streams.is_empty(): return null
	if streams.size() == 1: return streams[0]
	var s := streams.pick_random() as AudioStream
	if s == last: s = streams[(streams.find(s) + 1) % streams.size()]
	return s

@export_group("Layered by intensity")
## Sounds of one group are one event played together (SFX.play_layers), each gated by an intensity 0..1:
## silent below gate_from, fading in up to gate_full (from gate_from on, when they're equal), full above.
@export var layer_group: StringName = &""
@export_range(0.0, 1.0, 0.01) var gate_from: float = 0.0
@export_range(0.0, 1.0, 0.01) var gate_full: float = 0.0
## At intensity 1 this much louder (dB), and pitched to this (1 = unchanged; lower = deeper); scaled by the intensity.
@export_range(-12.0, 12.0, 0.5) var intensity_db: float = 0.0
@export_range(0.5, 1.5, 0.01) var intensity_pitch: float = 1.0
