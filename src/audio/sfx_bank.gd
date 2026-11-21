class_name SfxBank
extends Resource
## Every game sound (SfxDef) and every map's ambience (MapAudio). assets/tres/audio/sfx_bank.tres.

@export var sounds: Array[SfxDef] = []
@export var maps: Array[MapAudio] = []

@export_group("Ear ring (a hard stop's dizziness)")
## How the ring's level falls with the dizziness left (1 = in step with it; above 1 it drops away faster at first).
@export_range(0.5, 4.0, 0.05) var ring_curve: float = 1.5
## Seconds the ring takes to rise to its peak (no click).
@export_range(0.005, 0.5, 0.005) var ring_attack: float = 0.04
## While it rings the SFX and Ambience buses are low-passed down to this (Hz) at the peak, easing back as it fades.
@export_range(200.0, 20000.0, 50.0) var ring_muffle_hz: float = 1800.0
