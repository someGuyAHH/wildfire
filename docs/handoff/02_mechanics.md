# 2. Mechanics: movement, controls, contact, hazards

All movement numbers live in **`MovementConfig`** (`src/character/movement_config.gd`, ~50 knobs).
The project uses one shared preset, `assets/tres/movement/default_movement.tres`. That file
currently overrides nothing, so **the script defaults are the live values**. Players and bots share
it. The F2 tuning panel edits it live, and the F1 help sheet reads its numbers live.

## Movement kit (live values)

| Move | How | Behaviour / numbers |
|---|---|---|
| **Run** | WASD / arrows / left stick | 14 m/s top speed (`max_speed`), accel 90, decel 70 m/s², so full speed in ~0.15 s. Analogue input scales speed. Overspeed on the ground drags at 10 m/s². |
| **Jump** | Space / A | 9.5 m/s (apex ≈ 2.5 m). Variable: releasing early multiplies upward speed by 0.5. Coyote time 0.12 s, jump buffer 0.12 s. Gravity 18 m/s², ×1.35 when falling, terminal 65 m/s. |
| **Bhop** | jump right after landing | Within `landing_grace` 0.15 s of landing, ground friction never touches your extra speed. |
| **Air control** | | Air accel 45, air decel 2, air turn rate 2.8. Above top speed you bend your momentum without losing it. |
| **Slide** | Ctrl or C / B, on the ground | +5 m/s boost on entry (once per 0.6 s). Never under 11 m/s on flat ground while held. Friction 1.0, speeds up downhill. The body drops to 1.0 m (eyes at 0.8) and fits under low gaps. When it runs out you crouch-walk at 7 m/s. |
| **Slide-jump** | jump during a slide | Keeps all of the slide speed: the main way to build speed. |
| **Dash** | Shift or right mouse / RB | 28 m/s for 0.14 s in the input direction (or the look direction), ignores gravity, works in the air. 3 charges, one back every 1.2 s. Exit speed 16 m/s. You can't dash while slowed (lava). |
| **Dash-jump** | jump during a ground dash | Keeps 85% of the dash speed (23.8 m/s). If you're already faster, it adds +4 m/s (`dash_jump_boost`) and never slows you. Chained, this levels off around 38–41 m/s. |
| **Wall-jump** | jump in the air next to a wall | Any surface steeper than 62° (`floor_max_angle_deg`) is a wall. 3 per airtime, refilled on landing. Up 10.5, push 9, keeps 90% of along-the-wall speed, wall coyote 0.15 s. Jump + 3 wall-jumps reaches ~11.6 m. |
| **Wall-slide** | hold toward a wall while falling | Fall capped at 3 m/s. The camera leans, but only fades in from 4 to 10 m/s of along-the-wall speed. |
| **Slam** | Ctrl in the air | Drops at 48 m/s, keeping 15% of horizontal speed. |
| **Slam-bounce** | jump within 0.25 s of a slam landing | Apex = 4 m + 60% of the fall height, max 20 m. Chained bounces on flat ground level off. |
| **Slam-slide** | keep Ctrl held through a slam landing | You land straight into a slide. |
| **Brake slam** | Q in the air | Drops you at slam speed while horizontal speed eases off (75 m/s²), keeping 30% steering to hit a small landing. |
| **Skid stop** | Q on the ground | 160 m/s² decel for 0.2 s. Spamming it (dizzy meter ≥ 4, drains 1.2/s) stuns you for 2 s. From overdrive (≥ 30 m/s) it's a **crash stop**: stunned 0.5 s, then disoriented 1.8 s. |
| **Auto-step** | automatic | Steps up to 0.42 × height ≈ 0.76 m need no jump, even mid-dash (dashes into stairs used to stop you dead). |
| **Vault** | jump at a ledge, keep jump held, push forward | Ledges up to 1.5 m: you get popped on top. 0.3 s cooldown. |
| **Steep ground** | | Slopes over 62° are walls. Floor snap 0.55 m. |
| **Soft speed cap** | | No hard cap. Drag (0.015) applies above 32 m/s, so momentum tech is rewarded but bounded. |
| **Wall bonk** | hit a wall head-on | Disoriented if your *real* closing speed into the wall exceeds 20 m/s, measured over the last 0.1 s of positions, so point-blank dashes (wall-jump setups) don't count. Lasts 2.5 s, +0.1 s per m/s above 20, max 4.5 s. Steering drifts (up to 0.55 rad), you stumble on your own, and the camera sways. 0.4 s cooldown. |
| **Overdrive** | ≥ 30 m/s horizontal | Violet speed flames and sparks off your body; braking to a stop crash-stops you. |

**Body:** a capsule 1.8 m tall with radius 0.4 and eyes at 1.62.

**Movement states** (in `character.gd`): `grounded, airborne, sliding, dashing, slamming, frozen`.
Wall-sliding is a flag on `airborne`, not a state. A frozen character (a fresh Torch, stunned,
burned out) brakes to a stop.

## Props

| Prop | Scene / script | Behaviour |
|---|---|---|
| **Jump pad** (orange) | `scn/props/jump_pad.tscn`, `src/props/jump_pad.gd` (Area3D) | Two kinds. A **momentum pad** (`keep_horizontal` true) adds its push and never slows your climb; a fast fall comes back as upward speed (`fall_bounce` 0.7). An **aimed pad** (`keep_horizontal` false) is a lob that lands you on a spot (`landing`, set by the generator). If you arrive faster than the lob, you keep your own horizontal speed and steer the landing yourself. Pads also fire for anyone **standing** on them, not just entering (a skip guard applies while their map is parked). |
| **Speed strip** (cyan) | `scn/props/speed_strip.tscn`, `src/props/speed_strip.gd` | Pushes riders to `boost_speed` (30–34 m/s) along the strip's −Z. |
| **Launcher** | an aimed pad with a long range (70–170 m) | Generated on the Overworld between clusters. |
| **Brazier** | generated geometry + an OmniLight | Just light (Jungle temple, Inferno). |

## Controls (keyboard / mouse / gamepad)

| Action | Keys | Pad |
|---|---|---|
| Move | WASD, arrow keys | left stick |
| Look | mouse | right stick |
| Jump | Space | A |
| Slide / slam | Ctrl, C | B, L3 |
| Dash | Shift, right mouse | RB |
| Brake | Q | LB |
| Respawn | R | Back |
| Pause | Esc | Start |
| 1st / 3rd person | V | R3 |
| Scoreboard | hold Tab | |
| Cruise + free look | hold middle mouse | |
| Fullscreen | F11 | |
| Help sheet | F1 (scrolls with the wheel / PgUp/PgDn) | |

**Cruise / free look:** holding middle mouse latches everything you were holding (move keys,
slide, jump) in the world direction it had, and the mouse only turns the camera. On release the
view snaps straight back.

**Debug-only keys** (debug builds: `OS.is_debug_build()`; they are off in exports):

| Key | Does |
|---|---|
| F2 | live tuning panel (MovementConfig + graphics sliders) |
| F3 | readout (speed, state) |
| F4 | slow-mo ×0.25 |
| F5 | bot debug overlay: each bot's goal, state, link and path drawn in the world |
| F6 | the Torch hunts only you |
| **7** | **no-tag**: you can't be lit (tags, smoke, edge, storm) but are still chased (`TagManager.untaggable`) |
| **8** | **alone**: bots are lifted 500 m up, out of play, and put back where they were when toggled off |
| **9** | **fly**: noclip along the view direction; E up, Q down, dash = fast |
| **0** | **freeze**: bots and the match clock stop; you don't |

The cheats were on F7–F10 until 2026-11-17. They moved because the Godot editor keeps F7/F8
(pause/stop) when the game runs embedded in it, so F8 closed the game. The active cheats are listed
bottom left. The cheats work only in a match.

## Contact and status effects (Character API)

- `freeze(t)` stops a character (a fresh Torch, a stun). `slow(t, mult)` / `is_slowed()` is the lava slow.
- `disorient(t)` adds steering drift and stumbling (wall bonk, shove attacker, crash stop).
- `knockback(vel)`, `launch(vel, keep_horizontal, target)` (pads), `boost(dir, speed)` (strips).
- `set_burning`, `set_smoke(level)`, `set_out` (burned out), `emote(text)` (shouts over the head),
  `set_role_marker(color, torch)` (the 3D marker over the head, see below).

## Screen feedback

- **Blue edge flames + motion blur + cyan crosshair** at ≥ 20 m/s (`momentum.gdshader`): you can shove.
- **Violet** past overdrive, and **speed lines** from 15 to 34 m/s.
- A **dizzy** screen warp while stunned or bonked (`dizzy.gdshader`).
- A **red frame** while you're the Torch. A red **threat vignette** + arrow when hunted. A **heat** vignette on the dry edge.
- The **FOV kicks** with speed (+16° over 13–34 m/s) and on a dash (+7). There's a landing dip, a strafe tilt and a wall-slide tilt.

## Role markers (replaced the floating name tags)
Every character has a `RoleMarker` (`src/character/role_marker.gd`, tuned in
`assets/tres/match/marker_config.tres`): a small flat-shaded inverted pyramid spinning and bobbing
over the head. Colour is the role: the Torch is fire orange, glowing and drawn through walls (xray
shader, render priority 10); everyone else wears their `base_tint` and is depth tested. One shared
mesh and two shared materials (colour and glow are per-instance shader parameters, so no material
per character); the node scales itself with camera distance (clamped) to stay a constant size on
screen. Opaque on purpose: TAA smeared the old see-through labels. A role change pops the scale.
The player's own marker is hidden in first person and shown in third person (V). Names are no
longer shown permanently: `MatchHud` shows the name of whoever your view ray passes (within
`aim_radius`, not behind a wall) for `name_show_time` seconds; the scoreboard and feed keep names.
Title-screen bots (`show_labels = false`) get no marker. Check: `tools/checks/markers.gd`.
