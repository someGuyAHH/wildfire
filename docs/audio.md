# Audio

All sound effects, ambience and the menu sounds are in; **there is no music** (only a Music bus and a hook,
`SFX.play_music(stream, fade)`, for whoever makes it; tracks would go in `assets/music/`).
Headless can't play sound, so how it *sounds* (levels, which clip suits which event) is the owner's ear to judge.

## Layout

| Where | What |
|---|---|
| `assets/sfx/one_shots/` | short sounds, mono 44.1 kHz WAV, `name_N` = variants of one sound |
| `assets/sfx/loops/` | looping sounds (slide, wall-slide, torch, kindling, fuse, storm, the player's wind), OGG |
| `assets/sfx/ambience/` | one stereo OGG loop per map layer (wind, plains, jungle, lava, hall) |
| `assets/tres/audio/sfx_bank.tres` | **the tuning**: one `SfxDef` per sound (bus, volume, jitter, pitch range, max voices, min interval, 3D unit size / max distance) and one `MapAudio` per map (footstep surface, ambience layers and their dB) |
| `assets/tres/audio/bus_layout.tres` | Master (with a hard limiter), Music, SFX, UI, Ambience |
| `src/audio/sfx.gd` | autoload `SFX`: `play_at(id, pos)`, `play(id)`, `ui(id)`, loops, `set_map`, music hook, voice limits |
| `src/audio/character_audio.gd` | per runner (player and bots alike, positional): footsteps, jump, land, dash, slide, wall kick, slam, vault, skid, bonk, and the loops |
| `src/audio/match_audio.gd` | per match: ignite / extinguish, shove, smoke warning, fuse tick, explosion, storm, countdown, win / lose |
| `tools/audio/build_sfx.py` | recipes: raw packs in `tools/audio/sources/` (git-ignored) to `assets/sfx/` (trim, layer, normalise, loop) |
| `tools/audio/make_bank.py` | writes the first `sfx_bank.tres`; refuses to overwrite a tuned one without `--force` |
| `tools/checks/audio.gd` | headless check, see below |

Every file is logged in `assets/CREDITS.md` (all CC0).

## Rules of the system

- Files are normalised alike (RMS about -17 dB for one-shots, -22 loops, -26 ambience), so `volume_db` in the bank is only balance.
- Repeats: a random variant (never the same twice), pitch range and volume jitter per sound.
- Voices: each sound has `max_voices`; the world has a pool of 32 3D players. A new sound steals the
  furthest one only if it is nearer, else it is dropped. Loops are shared the same way: every owner asks
  each frame (`loop_wanted`) and the nearest `max_voices` get them (`loop_granted`).
- Sounds past `max_distance` are not played at all. The title screen's bots are silent.
- Footsteps follow the map's surface (`MapAudio.surface`); a floor collider with a `surface` meta overrides it.
- Volume sliders (Settings > Audio) are percent per bus, stored in `STG` (`vol_master`, `vol_music`, `vol_sfx`, `vol_ui`, `vol_ambience`).

## The slam-jump launch

`JUMP_SLAM_BOUNCE` plays the layer group `slam_jump` (`SFX.play_layers`) at an intensity 0..1 from the launch height
(`MovementConfig.slam_jump_intensity`: base bounce 4 m = 0, max 20 m = 1). Each layer is a `SfxDef` with `gate_from` / `gate_full`
(it fades in between them), `intensity_db` (louder at the top) and `intensity_pitch` (deeper at the top), all tuned in `sfx_bank.tres`:
thud + light crack from 0, rock crunch from 0.2 (full 0.55), gravel and debris from 0.4 (full 0.85), a deep boom from 0.55 (full 0.9).
The ground slam's own landing (`slam_land`) is separate and plays when you hit the ground.

## The ear ring

After a hard stop (and a wall bonk) the local player hears a soft ringing (`tinnitus`, a synthesised 3.2 kHz sine pair that
beats at 2.5 Hz, built by `ear_ring()` in `build_sfx.py`: no source file) for as long as they are dizzy or disoriented: `EarRing`
(`src/audio/ear_ring.gd`). It starts at its peak and falls with the share of the dizziness left (`SfxBank.ring_curve`), rising over
`ring_attack` (no click); while it rings the SFX and Ambience buses are low-passed down to `ring_muffle_hz` by the same amount
(`SFX.set_muffle`). It plays on its own bus, `Ringing` (so the muffle doesn't touch it), which follows the SFX volume. Peak level
= the `tinnitus` sound's `volume_db`. It stops at once on a pause, burning out, the round ending or leaving the match, and the muffle
is always restored. The old one-shot for a ground brake (`skid`) is gone.

## Adding a sound

1. Put the raw file in `tools/audio/sources/`, add a recipe to `build_sfx.py`, run `python3 tools/audio/build_sfx.py name`.
2. Add a `SfxDef` for it to `sfx_bank.tres` (or run `make_bank.py --force` if nothing was hand-tuned), `godot --headless --import` (twice if the first run complains).
3. Call it: `SFX.play_at(&"id", pos)`. Credit the source in `assets/CREDITS.md`.

## Check

```bash
XDG_DATA_HOME=<a dir with "scratch" in its name> MAPI=3 timeout 400 godot --headless --fixed-fps 120 -s res://tools/checks/audio.gd
```

Loads the bank (every stream, bus, loop flag, orphan files, each map's ambience), pokes the menus, then plays a Hot
Potato match on Inferno with the player driven through run / jump / dash / slide / brake / slam, the fire, fuse, storm and
round end pushed along, and requires every sound id to have been asked for. Prints `audio: ok`. (`XDG_DATA_HOME` keeps
the settings rows it presses from saving to the real `user://settings.cfg`. MAPI=3 because it needs lava.)
