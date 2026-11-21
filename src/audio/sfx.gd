"""
The game's sound: every sound effect, the ambience under each map and the music hook. Autoloaded as SFX.
Sounds are looked up by id in the SfxBank (assets/tres/audio/sfx_bank.tres), which says how each is played.

  SFX.play_at(&"dash", pos)        a sound in the world (fades with distance, dropped when too far)
  SFX.play(&"win")                 a flat sound (stingers, menus: SFX.ui() is the same for the UI ones)
  SFX.loop_3d / loop_2d            a looping player for its owner to start and stop; loop_wanted() and
                                   loop_granted() share the voices between many owners (the nearest win)
  SFX.set_map(&"jungle")           the ambience and the ground sound of a map
  SFX.play_music(stream)           the music (nothing plays yet: it only has a bus and this hook)

Voices are limited twice: each sound has its own max_voices, and the world has a fixed pool, so a room
of bots never turns into noise: the nearest voices win, the far ones are dropped. Volumes follow the
Audio settings (STG): one slider per bus.
"""

extends Node

const BANK: SfxBank = preload("res://assets/tres/audio/sfx_bank.tres")

const BUS_MASTER   := &"Master"
const BUS_MUSIC    := &"Music"
const BUS_SFX      := &"SFX"
const BUS_UI       := &"UI"
const BUS_AMBIENCE := &"Ambience"
## The bus of each volume setting (see Settings > Audio).
const VOLUME_BUSES: Dictionary[StringName, StringName] = {
	&"vol_master": BUS_MASTER, &"vol_music": BUS_MUSIC, &"vol_sfx": BUS_SFX, &"vol_ui": BUS_UI, &"vol_ambience": BUS_AMBIENCE,
}

const _WORLD_VOICES := 32
const _FLAT_VOICES := 16
const _AMBIENCE_FADE := 1.5

## How many times each sound was asked for this run (a hook that never fires shows up as missing: checks read it).
var requested: Dictionary[StringName, int] = {}
## How many times each loop was started by its owner.
var loops_started: Dictionary[StringName, int] = {}
## How many of those actually sounded (the rest were too far, too soon or out of voices).
var played: Dictionary[StringName, int] = {}
## The ground under foot on the current map (see surface_of).
var surface: StringName = &"concrete"

var _defs: Dictionary[StringName, SfxDef] = {}
var _maps: Dictionary[StringName, MapAudio] = {}
var _world: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _last_time: Dictionary[StringName, float] = {}
var _last_stream: Dictionary[StringName, AudioStream] = {}
var _clock := 0.0
var _ambience: Dictionary[StringName, AudioStreamPlayer] = {} # id -> its player, the current map's
var _music: AudioStreamPlayer
var _loop_requests: Dictionary[StringName, Array] = {} # id -> [[distance, owner], ...] this frame
var _loop_winners: Dictionary[StringName, Dictionary] = {} # id -> {source: true}, last frame's decision
var _map_name: StringName = &""
var _groups: Dictionary[StringName, Array] = {} # layer_group -> its SfxDefs
var _amb_db: Dictionary[StringName, float] = {} # id -> its level on this map (before the duck)
var _duck_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menus click while the game is paused
	for d: SfxDef in BANK.sounds:
		_defs[d.id] = d
		if d.layer_group != &"":
			if not _groups.has(d.layer_group): _groups[d.layer_group] = []
			_groups[d.layer_group].append(d)
		if d.loop:
			for s: AudioStream in d.streams:
				if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
				elif s is AudioStreamWAV: (s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	for m: MapAudio in BANK.maps: _maps[m.map_name] = m
	for i: int in _WORLD_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE # the world falls silent with the game paused
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_world.append(p)
	for i: int in _FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	add_child(_music)
	STG.settings_changed.connect(_on_setting_changed)
	apply_volumes()


func _process(delta: float) -> void:
	_clock += delta
	_decide_loops()


#region volumes

## Puts every Audio setting on its bus (0 is silent).
func apply_volumes() -> void:
	for key: StringName in VOLUME_BUSES: _set_bus_volume(VOLUME_BUSES[key], STG.get_value(key))


func _on_setting_changed(key: StringName) -> void:
	if VOLUME_BUSES.has(key): _set_bus_volume(VOLUME_BUSES[key], STG.get_value(key))


func _set_bus_volume(bus: StringName, percent: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0: return
	AudioServer.set_bus_mute(i, percent <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(percent, 0.01) / 100.0))

#endregion


#region one-shots

func has_sound(id: StringName) -> bool:
	return _defs.has(id)


func get_def(id: StringName) -> SfxDef:
	return _defs.get(id)


func get_ids() -> Array[StringName]:
	return _defs.keys()


## A sound in the world. vol_db and pitch are on top of the sound's own variation. Returns whether it sounded.
func play_at(id: StringName, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> bool:
	var d := _lookup(id)
	if not d: return false
	if not d.positional: return play(id, vol_db, pitch)
	var dist := _listener_distance(pos)
	if dist > d.max_distance or not _ready_to_play(d): return false
	var slot := _free_world_slot(d, dist)
	if not slot: return false
	slot.stream = _pick(d)
	slot.bus = d.bus
	slot.volume_db = d.volume_db + vol_db + randf_range(-d.volume_jitter_db, d.volume_jitter_db)
	slot.pitch_scale = pitch * randf_range(d.pitch_min, d.pitch_max)
	slot.unit_size = d.unit_size
	slot.max_distance = d.max_distance
	slot.set_meta(&"id", id)
	slot.set_meta(&"t0", _clock)
	slot.set_meta(&"dist", dist)
	slot.global_position = pos
	slot.play()
	_note(d)
	return true


## One event made of layers (the slam-jump's launch): every sound of the group whose gate the intensity (0..1)
## has opened, louder and deeper the higher it is. Returns how many layers were asked for.
func play_layers(group: StringName, pos: Vector3, intensity: float, vol_db: float = 0.0) -> int:
	intensity = clampf(intensity, 0.0, 1.0)
	var n := 0
	for d: SfxDef in _groups.get(group, []):
		var g := layer_gain(d, intensity)
		if g <= 0.01: continue
		n += 1
		play_at(d.id, pos, vol_db + linear_to_db(g) + d.intensity_db * intensity, lerpf(1.0, d.intensity_pitch, intensity))
	return n


## How open a layer's gate is at this intensity (0..1).
func layer_gain(d: SfxDef, intensity: float) -> float:
	if d.gate_full <= d.gate_from: return 1.0 if intensity >= d.gate_from else 0.0
	return smoothstep(d.gate_from, d.gate_full, intensity)


## A flat sound (no position): the round's stingers and the menus.
func play(id: StringName, vol_db: float = 0.0, pitch: float = 1.0) -> bool:
	var d := _lookup(id)
	if not d or not _ready_to_play(d): return false
	var slot := _free_flat_slot(d)
	if not slot: return false
	slot.stream = _pick(d)
	slot.bus = d.bus
	slot.volume_db = d.volume_db + vol_db + randf_range(-d.volume_jitter_db, d.volume_jitter_db)
	slot.pitch_scale = pitch * randf_range(d.pitch_min, d.pitch_max)
	slot.set_meta(&"id", id)
	slot.set_meta(&"t0", _clock)
	slot.play()
	_note(d)
	return true


## Menu sounds: the same as play() (their sounds sit on the UI bus).
func ui(id: StringName, vol_db: float = 0.0, pitch: float = 1.0) -> bool:
	return play(id, vol_db, pitch)


func _lookup(id: StringName) -> SfxDef:
	var d: SfxDef = _defs.get(id)
	if not d:
		push_error("SFX: no sound '%s'" % id)
		return null
	requested[id] = requested.get(id, 0) + 1
	return d


func _note(d: SfxDef) -> void:
	played[d.id] = played.get(d.id, 0) + 1
	_last_time[d.id] = _clock


func _ready_to_play(d: SfxDef) -> bool:
	return d.min_interval <= 0.0 or _clock - _last_time.get(d.id, -100.0) >= d.min_interval


func _pick(d: SfxDef) -> AudioStream:
	var s := d.pick(_last_stream.get(d.id))
	_last_stream[d.id] = s
	return s


## A free player, or the one of this sound playing furthest away when the new one is nearer. Null: drop it.
func _free_world_slot(d: SfxDef, dist: float) -> AudioStreamPlayer3D:
	var idle: AudioStreamPlayer3D = null
	var same := 0
	var far_same: AudioStreamPlayer3D = null
	var far_any: AudioStreamPlayer3D = null
	for p: AudioStreamPlayer3D in _world:
		if not p.playing:
			if not idle: idle = p
			continue
		if p.get_meta(&"id") == d.id:
			same += 1
			if not far_same or p.get_meta(&"dist") > far_same.get_meta(&"dist"): far_same = p
		if not far_any or p.get_meta(&"dist") > far_any.get_meta(&"dist"): far_any = p
	if same >= d.max_voices:
		return far_same if far_same.get_meta(&"dist") > dist else null
	if idle: return idle
	return far_any if far_any and far_any.get_meta(&"dist") > dist else null


func _free_flat_slot(d: SfxDef) -> AudioStreamPlayer:
	var idle: AudioStreamPlayer = null
	var same := 0
	var oldest_same: AudioStreamPlayer = null
	var oldest: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _flat:
		if not p.playing:
			if not idle: idle = p
			continue
		if p.get_meta(&"id") == d.id:
			same += 1
			if not oldest_same or p.get_meta(&"t0") < oldest_same.get_meta(&"t0"): oldest_same = p
		if not oldest or p.get_meta(&"t0") < oldest.get_meta(&"t0"): oldest = p
	if same >= d.max_voices: return oldest_same
	return idle if idle else oldest


func _listener_distance(pos: Vector3) -> float:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position.distance_to(pos) if cam else 0.0


## How many world voices are sounding now (for checks and the performance HUD).
func active_world_voices() -> int:
	var n := 0
	for p: AudioStreamPlayer3D in _world: if p.playing: n += 1
	return n

#endregion


#region loops

## A looping player for the owner to start (play()) and stop. 3D: it follows `parent`. Set its volume_db
## yourself on top of the sound's own (def.volume_db is already on it).
func loop_3d(id: StringName, parent: Node3D) -> AudioStreamPlayer3D:
	var d := _lookup(id)
	if not d: return null
	var p := AudioStreamPlayer3D.new()
	p.stream = d.streams[0]
	p.bus = d.bus
	p.volume_db = d.volume_db
	p.unit_size = d.unit_size
	p.max_distance = d.max_distance
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(p)
	return p


## A flat looping player (the owner frees it).
func loop_2d(id: StringName, parent: Node) -> AudioStreamPlayer:
	var d := _lookup(id)
	if not d: return null
	var p := AudioStreamPlayer.new()
	p.stream = d.streams[0]
	p.bus = d.bus
	p.volume_db = d.volume_db
	parent.add_child(p)
	return p


## An owner that wants this loop sounding says so every frame, with its distance from the listener.
## There are only max_voices of each loop: loop_granted() tells the owner whether it is one of the nearest.
func loop_wanted(id: StringName, source: Object, dist: float) -> void:
	var d: SfxDef = _defs.get(id)
	if not d or dist > d.max_distance: return
	if not _loop_requests.has(id): _loop_requests[id] = []
	_loop_requests[id].append([dist, source])


func loop_granted(id: StringName, source: Object) -> bool:
	return _loop_winners.has(id) and _loop_winners[id].has(source)


## An owner started its loop (for the counts: checks read them).
func note_loop(id: StringName) -> void:
	loops_started[id] = loops_started.get(id, 0) + 1


func listener_distance(pos: Vector3) -> float:
	return _listener_distance(pos)


func _decide_loops() -> void:
	_loop_winners.clear()
	for id: StringName in _loop_requests:
		var reqs: Array = _loop_requests[id]
		reqs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var winners := {}
		for i: int in mini(reqs.size(), _defs[id].max_voices): winners[reqs[i][1]] = true
		_loop_winners[id] = winners
	_loop_requests.clear()

#endregion


#region ambience and music

## The map has been loaded: its ground sound and ambience loops (the last map's fade out).
func set_map(map_name: StringName) -> void:
	_map_name = map_name
	var m: MapAudio = _maps.get(map_name)
	surface = m.surface if m else &"concrete"
	var wanted: Dictionary[StringName, float] = {}
	if m: for i: int in m.ambience.size(): wanted[m.ambience[i]] = m.ambience_db[i]
	for id: StringName in _ambience.keys():
		if wanted.has(id): continue
		_fade_out_and_free(_ambience[id], _AMBIENCE_FADE)
		_ambience.erase(id)
	for id: StringName in wanted:
		var d := _lookup(id)
		if not d: continue
		var p: AudioStreamPlayer = _ambience.get(id)
		if not p:
			p = AudioStreamPlayer.new()
			p.stream = d.streams[0]
			p.bus = d.bus
			p.volume_db = -60.0
			add_child(p)
			_ambience[id] = p
			p.play(randf() * p.stream.get_length()) # not every visit starts at the same bar
			played[id] = played.get(id, 0) + 1
		_amb_db[id] = wanted[id]
		create_tween().tween_property(p, "volume_db", d.volume_db + wanted[id] + _duck_db, _AMBIENCE_FADE)


## Lowers every ambience loop by `db` (negative), fading: the menus ask for it (a quiet bed behind the title
## and the match setup), a match asks for 0.
func duck_ambience(db: float, fade: float = 0.6) -> void:
	_duck_db = db
	for id: StringName in _ambience:
		create_tween().tween_property(_ambience[id], "volume_db", _defs[id].volume_db + _amb_db.get(id, 0.0) + db, fade)


func get_map_name() -> StringName:
	return _map_name


## The ids of the ambience loops running now.
func ambience_ids() -> Array[StringName]:
	return _ambience.keys()


func _fade_out_and_free(p: AudioStreamPlayer, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, time)
	tw.tween_callback(p.queue_free)


## The music hook: nothing plays music yet. Plays `stream` on the Music bus (looping if it can), fading
## the last track out over `fade` seconds.
func play_music(stream: AudioStream, fade: float = 1.0, volume_db: float = 0.0) -> void:
	if _music.playing and fade > 0.0:
		var old := _music
		_music = AudioStreamPlayer.new()
		_music.bus = BUS_MUSIC
		add_child(_music)
		_fade_out_and_free(old, fade)
	_music.stream = stream
	_music.volume_db = -40.0 if fade > 0.0 else volume_db
	_music.play()
	if fade > 0.0: create_tween().tween_property(_music, "volume_db", volume_db, fade)


func stop_music(fade: float = 1.0) -> void:
	if not _music.playing: return
	if fade <= 0.0:
		_music.stop()
		return
	var old := _music
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	add_child(_music)
	_fade_out_and_free(old, fade)

#endregion
