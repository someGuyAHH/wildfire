# 3. Architecture: how the code fits together

~7,000 lines of typed GDScript in `src/` and ~3,300 more in `tools/` (map generators and checks).
There are no C# or GDExtension modules of our own; Terrain3D is a prebuilt addon.

## Folder rules

- **Root** is grouped by kind of file: `src/` (code only), `scn/` (scenes), `assets/` (resources),
  `docs/`, `tools/` (offline scripts the editor doesn't import: `tools/.gdignore`), `addons/terrain_3d`.
- **`src/` and `scn/`** are grouped by game context, with matching names: `main, globals, character, player, bot,
  match, props, map, hud, menu, debug` (`vfx` only in `scn/`).
- **`assets/`** is grouped by file type: `gdshaders/ (+include/noise.gdshaderinc)`, `tres/{bot, environments,
  match, materials (+greybox/<map>/), movement, terrain, ui}`, `meshes/<map>/`, `navmesh/<map>/`,
  `terrain/<map>/`, `images/terrain/`. The `models/ sfx/ music/ fonts/` folders are empty.
- **Rules:** scripts never live in `assets/`. Downloaded assets would go in their type folder plus
  `assets/CREDITS.md` (nothing downloaded yet). A new part of the game gets a new `src/` folder.
- **Code style:** typed GDScript. Tuning numbers live in `Resource` files so they can be edited live.
  Class doc comments are `"""` blocks or `##`. Handlers are named `on_<signal>`. Private members
  start with `_`. Script consts that preload another script are named `_I<NAME>`
  (e.g. `_IBRAIN`) when there's no `class_name`. Comments are plain English, lower-case style in places.

## Project settings worth knowing (`project.godot`)

- `run/main_scene = res://scn/main/main.tscn`. Window 1920×1080 (mode 2 = maximized), stretch
  `canvas_items`/`expand`. Project name "Wildfire".
- **Physics:** 120 ticks/s, `max_physics_steps_per_frame` 12, Jolt, physics interpolation on.
- **Autoload:** `STG` → `src/globals/settings.gd` (the only autoload).
- **Theme:** `assets/tres/ui/wildfire_theme.tres` (type variations FireButton, ModeCard, MenuLabel,
  HudLabel, FireTitle, MenuSlider, DarkPanel, TorchFrame).
- **Physics layers:** 1 world, 2 characters, 3 tag_zones, 4 triggers, 5 hazards.
  **Render layers:** 1 world, 2 first_person_hidden (your own body and embers are hidden in first person).
- **Shader global:** `game_time` (float). Main advances it in `_process`, so every effect (flames,
  speed lines, lava, waterfalls, vignettes) **freezes when the game pauses**. Shaders must use
  `game_time`, not `TIME`.
- MSAA and FXAA project defaults are overridden at runtime by `STG`. On Windows the renderer uses D3D12.

## Scene tree at runtime

```
Main (Node, src/main/main.gd)                 the only persistent scene; also the scene manager
├─ TagManager (src/match/tag_manager.gd)      rules = the active MatchRules
├─ <maps>                                     every visited map stays here, "parked" unless active
├─ PerfHud (CanvasLayer)                      Settings > Performance HUD, any build
├─ menu Camera3D                              title-screen orbit camera
├─ MainMenu (scn/menu/main_menu.tscn)         title / modes / settings / how to play
├─ burn transition (scn/vfx/burn_transition)  the fire wipe between title and match
├─ Player (scn/player/player.tscn)            Character + Input + CameraRig/Camera + Hud
├─ Bot × N (scn/bot/bot.tscn)                 Character + Brain
├─ MatchHud, PauseMenu                        built per match
└─ BotDebug (F5, made on first use)
```

`scn/character/character.tscn` is the shared body: CharacterBody3D (`character.gd`) with Collision
(capsule), Visual/Body + Visor (placeholder meshes); the RoleMarker is added in code. `player.tscn` and
`bot.tscn` inherit it and add a controller node.

## The core idea: intent-driven characters

```
PlayerInput (src/player/player_input.gd) ─┐
                                          ├─► CharacterIntent ─► Character (movement state machine)
BotBrain    (src/bot/bot_brain.gd) ───────┘
```

- `Character` never reads `Input`. Every physics tick it consumes `intent` (`CharacterIntent`:
  `wish_dir` (world, horizontal, length 0..1), `look_dir`, and held/pressed flags for jump, slide,
  dash, brake). Controllers overwrite it every tick; "pressed" flags are one-tick edges
  (`clear_edges()`).
- Both controllers set `process_physics_priority = character.priority - 10`, so they write the intent
  before the character reads it in the same tick.
- `character.gd` (1,123 lines) is one deliberate hot loop. `_physics_process`:
  1. ticks the timers and handles jump-buffer, dash and brake edges;
  2. bends `wish_dir` if disoriented;
  3. runs the state's `_move_*`;
  4. applies the soft cap and tries to step up;
  5. calls `move_and_slide()`;
  6. runs `_after_move` (landing, wall bonk, leaving the floor), turns the visual and updates the sparks.
- Signals: `state_changed, jumped(kind), landed, dashed, frozen_changed, stepped_up, braked,
  dizzy_changed, wall_bonked, disoriented_changed`. The camera and HUD listen to these.
- `speed_mult` is set by the match (Torch bonus). `_slow_mult` comes from lava. `debug_fly` is a setter
  that saves and restores the collision mask **only on a real change** (see bug history).
- Launch memory: `launch(vel, keep_horizontal, target)` sets `_launched` and `_launch_target`
  until landing. Bots steer toward `get_launch_target()` mid-flight.

## Main (`src/main/main.gd`, 554 lines)

- **Title mode (attract):** a live match of 8 bots on the selected map, with an orbiting camera (r 95,
  h 34) and the menu over it. The MAP choice on the mode screen swaps the background map
  (`on_menu_map_changed`). A throwaway SubViewport renders one frame through the menu camera
  (`_background_picture`), it's laid under the menu, the map switches behind it, and the picture
  fades out over 0.7 s. Picks made during the fade chain on afterwards. A "live cross-fade" was
  tried and reverted at the owner's request (see bug history).
- **Match mode:** `_start_match(mode, bots, difficulty, map)` does the following:
  1. loads the map (`_use_map` / `load_map`);
  2. sets `tag_manager.rules` and spawns the player and bots (tints, skills: Easy/Normal/Hard/Mixed);
  3. builds the MatchHud and PauseMenu;
  4. sets the Hunted focus, gathers the spawn points and starts the round;
  5. captures the mouse.

  `return_to_title()` reverses it. Burn transitions go in and out.
- **Map cache / parking:** `load_map(path)` keeps every visited map in `_map_cache`. The old map is
  parked with `GameMap.set_active(false)`: hidden, not processing, collision zeroed, navigation taken
  off the navigation map (`set_navigation_map(RID())`), WorldEnvironment out. Re-adding a Terrain3D
  map cost ~0.8 s; a parked swap is 5–18 ms. After a load: `STG.apply_graphics()` (a new
  WorldEnvironment and sun).
- **Each physics tick:** `_keep_in_bounds()` (the bound wall), then lava (`_into_lava`: teleport to
  `nearest_checkpoint`, then `slow`) and the kill height (`tag_manager.respawn`).
- **Debug cheats:** `_CHEAT_KEYS` maps actions to the `_cheats` dict; `toggle_cheat` / `_apply_cheats`.
  A label sits bottom left. Debug builds only, and only in a match.
- **Spawns:** `_spawn_points()` reads the map's `spawn`-group markers (plus a ring of radius 7 around
  them if there are too few).

## TagManager (`src/match/tag_manager.gd`, 731 lines)

- **Phases:** IDLE → COUNTDOWN → PLAYING → RESULTS → (auto) COUNTDOWN.
  `set_participants(list, spawns)`, `start_round()`.
- **Spawning per round:**
  - Maps with `room`-tagged spawn markers (Inferno: one room per hall) start each round in a random room (`_pick_spawn_room`), in every mode.
  - Spread on a map with `spawn_spread` markers (the Inferno) picks a random room from those and
    the `people` spots farthest apart (`_far_apart`). Before 2026-11-18 it scattered everyone over
    the whole map; the owner wanted one hall like the other modes.
- **Per tick while playing:** scores, fuse, storm, bump immunity, edge and hiding, then `_check_bumps()`
  (first, so a stunned Torch can't tag this tick), then `_check_tags()`. Then the round end checks:
  timer, Spread with nobody left unlit, Hot Potato with ≤ 1 alive.
- **State per character:** dictionaries keyed by `Character` (torch time, tags, snuffs, shoves,
  streaks, heat, smolder, stillness anchor, smoke, out).
- **Signals:** `phase_changed, torch_added, torch_removed, tagged, round_ended(standings), bumped,
  smoking_started, combusted, smolder_changed, burned_out(c, reason)`.
- **Queries used by the HUD and bots:** `get_torch(es)`, `is_torch`, `nearest_torch`, `get_score`,
  `lower_score_wins`, `get_heat`, `is_smoldering`, `get_ignite_left`, `get_stillness`,
  `is_smoking`, `get_smoke_left`, `get_fuse_left`, `get_storm_radius`, `alive_count`, …
- **Shoves:** use the real capsule segments (`Character.get_capsule_segment`) and the closing speed.
- **Debug:** `untaggable` (the no-tag cheat).

## GameMap (`src/map/game_map.gd`) and TerrainMap (`src/map/terrain_map.gd`)

- `GameMap` (a `@tool` Node3D) is the base for every map. It holds:
  - the arena (`arena_center`, `arena_radius`, `dry_edge_radius`) and lava (`lava_height`,
    `lava_slow_time`, `lava_slow_mult`);
  - navigation: `bake_navigation()` at runtime for the Gym, or `use_baked_navigation()`;
    `is_nav_ready()` / `navigation_ready`; `nav_snap()`; `add_nav_link()`; `add_link_set(NavLinkSet)`;
  - parking: `set_active`, `set_nav_active`, `park_environment`;
  - the dry edge ring (`mark_dry_edge`, draped in 3 m cells over the terrain via `ground_height()`)
    and the Hot Potato storm wall (`set_storm`);
  - `spawn_rooms()`, `nearest_checkpoint()` and `get_bound_radius()`;
  - the Hot Potato storm per map: `storm_bottom` (where its wall starts: under the lowest floor),
    `storm_height_scale`, `storm_center` (where it closes in on; it drifts there from the arena
    centre) and `storm_end_radius` (its last circle; 0 = the mode's 25 m).
- **Nav link kinds:** `LINK_PAD 1, LINK_VAULT 2, LINK_DROP 3, LINK_WALLJUMP 4, LINK_JUMP 5`
  (stored on links as `link_kind`). `NAV_CELL` 0.4 / `NAV_CELL_HEIGHT` 0.25 must match the baked
  navmesh, or nothing connects.
- `TerrainMap extends GameMap`: the script for every generated map (Overworld, Jungle and Inferno,
  the Inferno with no terrain node). It loads the pre-baked navmesh chunks (128 m) and the
  `jump_links` `NavLinkSet` (thousands of links as packed arrays, registered straight with the
  server, so the scene stays small). It snaps through the chunk grid, because closest-point
  queries over the whole map are ~20× slower. Path queries can't use `included_regions`, because
  the pathfinder then ignores links.
- Groups: `spawn` (markers, optional meta `room`), `checkpoint` (lava respawn markers),
  `map_labels` (floating area names; hidden on the title screen).

## Settings (`STG` autoload, `src/globals/settings.gd`)

- Stored in `user://settings.cfg` (section `player`) as one `Dictionary[StringName, float]`; toggles
  are 0/1 and choices are indexes. Use `get_value`, `set_value(key, v, save=true)`,
  `reset_to_defaults`, `is_on`, and the `settings_changed` signal.
- **Keys and defaults:**
  - mouse sensitivity 5.6 (× 0.001 rad/px), FOV 112, third person off;
  - render scale 0.6 (FSR below 1.0), SSAO off, glow on, MSAA off, FXAA on;
  - **VSync 1 = Adaptive** (0 Off / 1 Adaptive / 2 On), **Shadows 1 = Medium** (0 Low / 1 Medium / 2 High);
  - perf HUD 0 (Off / FPS / Full).
- The defaults were chosen for the owner's Iris Xe iGPU. Measured: SSAO ~10 ms, MSAA 2× ~9 ms,
  glow ~5 ms; FSR at 0.6 is the big win.
- `apply_graphics()` pushes onto the root viewport, window, environment and **every DirectionalLight3D**
  (`_apply_shadows`: splits 2/4, max distance 120/180/240 m, atlas 4096/4096/8192, soft filter
  quality, pancake 40, bias 0.08, normal bias 1.5, blur 1.0). Main calls it after every map load.
- UI: `SettingsList` (`src/menu/settings_list.gd`) is shared by the title screen and the pause menu.
  The F2 tuning panel also writes to STG and to the MovementConfig.

## UI (all built in code)

- `main_menu.gd`: title, mode select (`ModeCard` with animated banner shader; `MenuStepper`s for MAP,
  bots, difficulty), settings, how to play. Mouse, keyboard and pad all work; focus = hover.
- `pause_menu.gd`: Esc / Start pauses the tree (`get_tree().paused`), and it auto-pauses on focus
  loss. Buttons: resume, restart, settings, tuning, help, back to title (QUIT was removed on purpose).
- `match_hud.gd`: the timer/countdown, who's the Torch, the Torch frame, the feed, the Tab scoreboard
  and results, the threat vignette and arrow, and hazard status lines (heat, smoke, ignite countdown, fuse, storm).
- `player_hud.gd`: speed and dizzy screen effects, crosshair, debug label, hints. It owns the
  `help_overlay` (F1) and `tuning_panel` (F2).
- `perf_hud.gd`: FPS, or Full (frame time avg/worst, GPU / render-CPU ms, draw calls, render res).
- `fire_button.gd` / `menu_stepper.gd` / `mode_card.gd`: the custom widgets.

## Shaders (`assets/gdshaders/`)

`burn_transition, chevrons (speed strips), dizzy, fire_text, greybox_grid (greybox material grid),
lava (flowing, Inferno), menu_backdrop, mode_banner, momentum (speed flames), speed_lines,
storm_wall, threat_vignette, waterfall (Jungle ribbons)`. `include/noise.gdshaderinc` holds the
shared hash and value noise. All of them run on `game_time`.

## Resources

- `assets/tres/match/*.tres` (MatchRules per mode), `bot/{easy,normal,hard}.tres` (BotSkill),
  `movement/default_movement.tres`.
- `environments/{gym,inferno,jungle}_environment.tres`. The Overworld reuses the gym's.
- `materials/`: character body, dry edge, fire text variants, vignettes, menu backdrop, mode banner,
  `greybox.tres`, and `greybox/<map>/<role>.tres` (per-map role colours: stone, wood, basalt, iron…).
  Anything recoloured per instance duplicates its base `.tres`.
- `vfx/slam_fx.tres` (SlamFxConfig): the slam-jump impact (`src/vfx/slam_fx.gd`, one node under Main):
  crack decal + embers, dust ring, lingering dust, rock chunks, shockwave decal and camera shake, all
  sized by the launch intensity (`MovementConfig.slam_jump_intensity`, the one the sound uses). A fixed
  pool made once (no particle amounts change at runtime), oldest taken over, culled past 60 m, prewarmed
  at match start. Textures: `tools/texgen/slam_fx.py` -> `assets/images/vfx/`.
- `scn/vfx/`: fire (+ light), smoke, sparks, storm wall, burn transition, menu embers, background fade.
