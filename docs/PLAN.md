# WILDFIRE — Game Plan

Status: draft v0.1 (2026-11-15) · Engine: Godot 4.7.2, Forward+, Jolt Physics (already set in `project.godot`)

---

## 1. Pitch

A fast 3D game of tag against bots, set on huge maps built for movement. Everyone, bots included, can sprint, slide, dash and wall-jump, so a chase plays out as a contest of routes, not a footrace you lose from the start. Players should feel close to the speed of Ultrakill. The look is crisp vector-style shapes under realistic lighting.

**Design pillars**
1. **Movement never holds you back.** Momentum is kept, not punished. You don't snag on geometry, there's no stamina wall and no fall damage. Low obstacles get stepped over or vaulted automatically.
2. **Bots play by the player's rules.** Bots drive the same character controller through the same input interface. No speed cheats; difficulty comes from decisions, reaction time and how well they use the movement kit.
3. **Maps are playgrounds.** They're big and open, with loops, verticality and traversal props. Every area should have more than one way out.
4. **Readable chaos.** The Torch is always obvious, tags are loud, and silhouettes stay clean even in a burning cathedral.


## Theme: WILDFIRE

Tag, but the tag is **fire**. One player is **the Torch**: on fire, glowing, and visible through walls. Touch someone and you **set them alight**; the fire (and the Torch speed bonus) jumps to them. Everyone else is **kindling**. **Least total time burning wins.**

| Concept | WILDFIRE name |
|---|---|
| Tagged player | the Torch |
| Tagging | setting someone alight |
| Runners | kindling |
| Score | time burning |
| Body slam (20+ m/s) | shove |
| Just-tagged immunity | fireproof for a moment |

**How it reads on screen:** the Torch carries real fire (embers trailing behind), the HUD shouts "YOU'RE ON FIRE!", and the feed reads "Bot 3 set You alight". In the art pass (M6) fire becomes the visual thread through every map: embers, ash trails, scorched ground where the Torch has run, the Inferno map as the fire's home turf, dry jungle that looks like it could go up any second. The blue speed flames are the contrast: cold fire for kindling that's moving fast enough to stay ahead.

**Anti-stalling (fire and smoke):**
- **Dry edge:** the outer 15% of the arena (amber band on the ground) heats kindling up. At full heat you **smolder**, gaining time burning at half rate without being the Torch, until you cool off inside.
- **Smoke:** kindling that stays within 8 m of one spot for 6 s starts **smoking** (a column of smoke, a 4 s warning). Still there when it runs out? You **catch fire and become the Torch**. Moving away puts it out.
- **Snuffs:** shoving the Torch takes 3 s off your score (1 s for shoving kindling). Aggressive bots sneak up on a Torch that's busy with someone else and try it, but only when their dash would land hard enough.
- Bots know all of this: heat sends them back inside, stillness makes them relocate.
- Numbers live in `MatchRules` (Dry edge / Smoke groups).

In code, `tag`/`tagged` stay as the generic verbs; anything about the role uses `torch` (`get_torch()`, `torch_added` / `torch_removed`, `MatchRules.torch_*`).

---

## 2. Core loop & modes

| Mode | Rules | Win condition | Priority |
|---|---|---|---|
| **Classic** | One Torch. Touching someone passes it on. The new Torch is frozen for 1.5 s, and the previous Torch can't be tagged back for 3 s. | Least total time as It when the round timer (e.g. 5 min) ends | MVP |
| **Infection** | Tagged players join the chasers | Last runner standing, or runners win if any survive the timer | MVP+1 |
| **Freeze tag** | Tagged runners freeze; other runners unfreeze them by touch | Chasers freeze everyone, or the runners survive the timer | Later |
| **Hot Potato** | Holding the fire when the fuse ends knocks you out; new round | Last one standing | Later |
| **One vs all (Hunted)** | Every bot hunts you. Tag-back is on: tagging a chaser freezes it for a while | Survive as long as you can (time survived is the score) | M4, with team chasing |

**Tagging:** contact-based. An `Area3D` tag sphere (about 1.3 m) on the Torch overlaps a runner's hurtbox. It's automatic, so player and bots are judged the same way. An optional "lunge" (a short forward burst on a cooldown) gives the Torch a finishing tool.

**Keeping the chase fair (no rubber-banding):**
- The Torch gets **+6% max speed** and its dash recharges faster.
- **Hunter's sense:** if the Torch hasn't tagged anyone for 20 s, the nearest runner gets a brief outline through walls.
- Runners have the map. Loops, jump pads and wall-jump routes are how you escape.

---

## 3. Movement design (the "fun physics")

Built on `CharacterBody3D` + `move_and_slide()` (Jolt). The game uses hand-written kinematic movement, not rigid bodies, so it stays precise and predictable.

### 3.1 Movement kit
| Move | Behaviour |
|---|---|
| Run | Fast and responsive. No separate walk; analogue input scales speed |
| Jump | Variable height (release early to cut it). 0.12 s coyote time and 0.12 s jump buffer |
| Slide | Crouch while moving: +speed burst on entry, very low friction, faster downhill, fits under low gaps |
| Slide-jump | Jumping out of a slide keeps all horizontal speed (the main way to build speed) |
| Dash | Burst in the input direction, works in the air. 3 charges, regenerating |
| Wall-jump | Kick off any steep surface. Up to 3 before touching the ground (refreshed on landing) |
| Wall-slide | Falls slowly while held against a wall, so you can set up a wall-jump |
| Ground slam | Drop fast from the air. Its landing bounce turns into a high jump |
| Auto-step & vault | Steps ≤ 0.5 m are free. Ledges ≤ 1.4 m with a jump held get a quick mantle |
| Air control | High. You can steer mid-air and redirect momentum |

### 3.2 Starting tuning values (all in a `MovementConfig` resource for live tuning)
| Param | Value | Note |
|---|---|---|
| Max run speed | 14 m/s | Around 2× a real sprint |
| Ground accel / decel | 90 / 70 m/s² | Snappy. You reach full speed in about 0.15 s |
| Air accel | 45 m/s² | Lets you steer in the air |
| Gravity | 32 m/s² (×1.6 when falling) | Heavier than real for snappy arcs |
| Jump velocity | 11.5 m/s | Apex about 2 m |
| Slide entry boost | +5 m/s, friction 1.5 m/s² | |
| Dash | 28 m/s for 0.14 s, 3 charges, 1.2 s regen each | |
| Speed cap | none hard; drag above 30 m/s | Momentum tech is rewarded, not clamped |
| Floor max angle | 50° | Steeper surfaces count as walls for wall-jumps |
| Capsule | 1.8 m tall, 0.4 m radius | |

### 3.3 Feel-critical engine settings
- **Physics tick 120 Hz** with **physics interpolation on** (`physics/common/physics_interpolation`), for smooth high-speed movement.
- `floor_snap_length` around 0.4 m (turned off while jumping), `floor_constant_speed = true`, `floor_block_on_wall = false`.
- Collision shapes on level geometry are **rounded/chamfered or simplified** so corners don't snag. Decorative clutter gets no collision.
- Camera: FOV kick with speed (90→105), small landing dip, view tilt while wall-sliding, speed-line overlay above 20 m/s.

### 3.4 Architecture: intent-driven controller
```
PlayerInput ─┐
			 ├─► CharacterIntent {move_dir, look, jump, slide, dash, slam} ─► Character (movement FSM)
BotBrain ────┘
```
- `Character` never reads `Input` directly. It consumes a `CharacterIntent` each physics tick.
- Movement is a small state machine kept in `character.gd` itself: `grounded`, `airborne`, `sliding`, `dashing`, `slamming`, `frozen`. Wall-sliding is a flag on `airborne`, not its own state.
- Bots get the exact same physics. This also keeps the door open for local or online multiplayer later.

---

## 4. Bot AI

### 4.1 Layers
1. **Perception** (10 Hz, staggered across bots): line-of-sight raycasts, a hearing radius (footsteps/dashes), and a memory of last-seen positions that fades over about 5 s.
2. **Decision** (utility scoring, 4–5 Hz): picks a goal (`Chase`, `Intercept`, `Search`, `Flee`, `Hide`, `Juke`, `Wander`).
3. **Navigation**: `NavigationAgent3D` paths on baked navmeshes. Path queries go through `NavigationServer3D` so they don't block.
4. **Locomotion**: follows the path and decides when to use the movement kit. It slides on long straights and downhill, dashes to close the last few metres or break away, and jumps or wall-jumps over `NavigationLink3D` links.
5. **Output**: writes a `CharacterIntent`, the same one the player produces.

### 4.2 Chaser behaviour
- **Target choice:** score = path distance + angle-to-target penalty + "recently escaped me" penalty + bonus for low-mobility targets (no dash charges, mid-air).
- **Intercept:** aims at a predicted position (`target_pos + velocity × t_lead`) snapped to the navmesh, not where the target is right now.
- **Team play (Infection):** chasers share a blackboard. The second chaser on the same target picks a flanking intercept on another route.
- **Search:** with no line of sight, goes to the last known position, then checks nearby nav polygons weighted by how recently they were seen.

### 4.3 Runner behaviour
- **Flee goal sampling:** about 16 candidate points on a ring (radius 25–60 m), projected onto the navmesh. Each point is scored by:
  - path distance from the nearest chaser minus my own distance (a positive margin is good)
  - its **escape value**, pre-baked per map region: how many exits it has, with dead ends penalised
  - whether it's moving *away* from threats and not straight past one
- **Juke:** when the Torch is within about 4 m and closing, the runner makes a sharp lateral dash or slide-cut with some randomness. Skill decides how well it's timed.
- **Use of terrain:** runners prefer routes with jump pads and loops. Navmesh links are tagged with traversal cost, and skilled bots treat a wall-jump link as cheap.

### 4.4 Difficulty knobs (per bot, so a lobby can mix skills)
Reaction delay (80–400 ms), prediction accuracy, how often it uses the movement kit, juke timing, how far it plans its route, and how long it remembers things.

### 4.5 Scale & performance
- Target **12–16 bots** at 60+ fps on a mid-range GPU.
- AI ticks are staggered, so not every bot thinks on the same frame.
- Bots far from the player and off-screen drop to a cheaper "coarse" tick.
- Huge maps use **chunked navmeshes**: one `NavigationRegion3D` per map chunk, baked in the editor and merged at the edges by the navigation server.

---

## 5. Maps

All maps share a kit of traversal props: **jump pads, speed strips, ziplines, launch ramps, slide chutes, wall-jump shafts, vault walls**. Every map gets a greybox version first, with gameplay validated by bots before any art goes in.

| Map | Size (target) | Identity | Movement features | Tech notes |
|---|---|---|---|---|
| **Test Gym** | 200 × 200 m | Greybox with measured obstacles | Every prop, slopes at every angle, wall-jump tests | Used for tuning and as a bot regression arena |
| **Overworld** | about 1.5 × 1.5 km | Rolling hills, cliffs, rock arches, ruined aqueducts, a river canyon | Long downhill slides, canyon wall-jumps, ziplines between peaks | Chunked heightmap terrain + `HeightMapShape3D`; SDFGI; visibility ranges for LOD; MultiMesh grass/rocks |
| **Inferno** | about 600 m of linked halls, very tall | Enormous cathedral halls, lava rivers, chained bridges, fire-jet columns, a vertical pit level | Jump pads over lava (lava = respawn at the nearest checkpoint + 2 s slow, no death), flame-vent updrafts, pillar wall-jumps | `OccluderInstance3D` occlusion culling between halls; volumetric fog; emissive lava + glow; LightmapGI or VoxelGI per hall |
| **Jungle** | about 800 × 800 m | Dense canopy, temple ruins, waterfalls, two-level layout (floor + canopy walkways) | Vine swings (later), canopy ziplines, slick waterfall slide chutes, tree-trunk wall-jumps | MultiMesh foliage with visibility ranges; collision only on trunks and walkways; volumetric fog with light shafts |
| *Backlog* | | Rooftop city, frozen glacier (ice = less friction), floating sky islands | | |

**Terrain approach (decided at M5):** Terrain3D 1.1.0 (works on 4.7.2). Maps are generated headless by `tools/mapgen/*_gen.gd` on a shared library (`tools/mapgen/lib`: kits, aimed pads, chunked navmesh, auto jump/climb/drop links); scenes use `src/map/terrain_map.gd`. Full collision mode, lightweight terrain shader (measured ~4.5 ms/frame cheaper on Iris Xe). Built playable areas are smaller than the table above: the Overworld is 520 m across, the Jungle 460 m.

---

## 6. Art direction — "vector-art Ultrakill, ultra-realistic"

**Working interpretation (to confirm):** shapes and textures are drawn like vector art, with flat colour regions, crisp edges, bold graphic patterns and no photographic noise. They're lit like a realistic modern game: physically based lighting, GI, volumetric fog, reflections and heavy glow. From Ultrakill we take the scale, the oversized brutalist and gothic architecture, the saturated hellish palettes and the sense of speed. We don't take its low-res PS1 filtering.

**Pipeline**
- **Textures are written as SVG** (by hand or with Python). Godot imports SVG directly and rasterises it at whatever resolution we choose, so every texture can be regenerated at any size.
- Roughness and normal maps come from the same SVG shapes (embossed edges, panel lines), so lighting picks up the vector detail.
- Optional **CC0 PBR textures** (ambientCG, Poly Haven) for realistic surfaces such as rock and lava crust, to mix with the vector layers.
- **Shaders:** a triplanar world material for terrain and architecture, emissive lava with flow, and an optional thin edge-detect outline as a post-process to sharpen the vector look.
- **Environment:** AgX tonemapping, SDFGI (outdoor) / VoxelGI or LightmapGI (indoor), volumetric fog, SSAO, SSR, glow. Each map gets its own colour grade (warm gold Overworld, red/black/orange Inferno, teal/green Jungle).

**Characters**
1. Now: capsule + head placeholder, with colour showing the role (Torch = glowing red/orange).
2. Next: a simple low-poly humanoid **generated with Blender's Python API** (`tools/blender/`), rigged, with basic animations: run, slide, jump, wall-slide, frozen.
3. Alternative: CC0 animated humanoids (e.g. Quaternius or Kenney packs, license checked at download time) retargeted to one skeleton.

**Blender status:** `blender` isn't on PATH in this environment. Options: install Blender and tell me its path, or I set up `pip install bpy` in a venv inside the project (`tools/.venv`). That runs Blender headless, but needs the matching Python version.

---

## 7. Project structure

There are three levels of grouping:
- **Root** is grouped by *kind of file*: code, scenes, assets, docs, tools.
- **`src/`** is grouped by *game context*: which part of the game the code belongs to.
- **`assets/`** is grouped by *file type*. Subfolders inside a type folder group by use once there are enough files to need it.

`scn/` uses the same context folders as `src/`, so a scene sits next to its script's name.

```
res://
  src/                    GDScript only, grouped by game context
    main/                 main.gd: the persistent root scene (loads maps, spawns, respawns; grows into the scene manager)
    globals/              autoloads, only for API-style services when they're needed
    character/            shared body used by player AND bots:
                            character.gd (movement FSM), character_intent.gd, movement_config.gd
    player/               player_input.gd, player_camera.gd, camera_fx.gd
    bot/                  bot_brain.gd, perception.gd, blackboard.gd, behaviours/ (chase, intercept, search, flee, juke)
    match/                tag_manager.gd, round_timer.gd, scoreboard.gd, modes/ (classic, infection, …)
    props/                jump_pad.gd, speed_strip.gd, zipline.gd, launch_ramp.gd, lava_volume.gd, checkpoint.gd
    map/                  map.gd (spawns, metadata), chunked_terrain.gd (@tool), escape_value_baker.gd (@tool)
    hud/                  match HUD, speedometer, tag indicator
    menu/                 main menu, map/mode select, settings screen
    vfx/                  speed lines, tag flash, dash trail controllers

  scn/                    .tscn scenes, same context folders as src/
    character/  player/  bot/  props/  hud/  menu/  vfx/
    map/                  test_gym.tscn, overworld.tscn, inferno.tscn, jungle.tscn (+ per-map sub-scenes)

  assets/                 non-code resources, grouped by file type
    gdshaders/            world_triplanar.gdshader, lava.gdshader, outline_post.gdshader, …
    tres/                 Godot resource files: materials/, environments/, movement/ (MovementConfig presets), navmesh/
    images/               textures and UI images (SVG sources + PNG/EXR), heightmaps/
    models/               .glb / .blend exports (characters, props, architecture)
    sfx/
    music/
    fonts/
	CREDITS.md            source + license for every third-party file, wherever it's stored

  docs/                   PLAN.md (this file), later design notes
  tools/                  offline scripts Godot shouldn't import (has a .gdignore)
    blender/              bpy generation scripts → write .glb into assets/models/
    texgen/               Python/SVG texture generators → write into assets/images/
  addons/                 only if a Godot plugin is ever needed (Godot requires this path)
```

**Rules**
- Downloaded assets don't get their own folder. They go in the folder for their file type, and each one gets an entry in `assets/CREDITS.md`.
- Scripts never live in `assets/`, and assets never live in `src/`.
- When a new part of the game shows up, it gets a new folder in `src/`, plus a matching one in `scn/` if it has scenes. Don't stretch an existing folder to cover it.

Code style: typed GDScript, with tuning values kept in `Resource` files so they can be adjusted live in the inspector.

---

## 8. Milestones

| # | Milestone | Deliverable | Done when… |
|---|---|---|---|
| **M0** | Setup | Project settings (120 Hz, interpolation, input map, layers), folder skeleton, git init | Project opens clean, empty gym loads |
| **M1** | Movement | Character + intent system, full movement kit, camera feel, Test Gym greybox, debug HUD (speed/state) | Running around the gym alone is fun for 5 minutes |
| **M2** | Tag core | TagManager, Classic mode, timer, freeze/no-tag-back rules, HUD (who's the Torch, scoreboard) | A full round plays start to finish |
| **M3** | Bots v1 | Navmesh, perception, Chase/Flee/Search, intercept, juke, 8 bots in gym, difficulty presets. Plus: **bump stun** (20+ m/s real closing speed into another player stuns them; attacker gets knocked back; the Torch touching you is still just a tag) and a **targeting vignette** (red screen edges + off-screen arrow when a chaser is actually hunting you) | Bots tag each other and the player; runners escape sometimes |
| **M4** | Bots v2 | Nav links for traversal, Spread (infection) + Hunted modes, team chasing (flanking), perf check | 16 bots at 60 fps, and bots use jump pads/wall-jumps |
| **M5** | Maps (greybox) | Overworld (chunked terrain), Inferno, Jungle, all greyboxed with props + navmesh. **Collectibles** placed on movement-tech spots (pillar tops, towers, launcher arcs) that fill a meter for a small payoff (dash refill / speed burst) | Each map plays well with bots before art goes in |
| **M6** | Art pass | Generated humanoid + anims, SVG texture sets, shaders, per-map environment, VFX (tag flash, speed lines, dash trails) | Screenshots read as the target style |
| **M7** | Polish | Audio, main menu, map/mode select, settings (FOV, sens, bot count/difficulty), more modes | Shippable vertical slice |

**Status (2026-11-16):** M5 in progress: Overworld and Jungle playable (greybox, bots climb/jump/drop via generated links), Inferno next. Collectibles not started.

**Status (2026-11-15):** M0–M4 done. M4: Classic / Spread / Hunted modes (pause menu), several Torches at once with team chasing (spread over targets, flank when a teammate is closer), nav links for pads, vault walls, drops and the wall-jump shaft (`GameMap.add_nav_link`), and a perf check: 16 characters cost ~2.5 ms per 120 Hz physics tick (bot AI ~0.2 of that), so no think-LOD was needed. Next: M5 maps.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Bots can't use advanced movement on navmesh paths | `NavigationLink3D` for jumps/pads, locomotion layer plans slides/dashes, test bots in the gym first |
| Huge maps hurt navmesh bake time and memory | Chunked regions, coarser cell size outdoors, bake offline in the editor |
| Fast movement + thin colliders = tunnelling | 120 Hz physics, thick/simplified level collision, Jolt's CCD where needed |
| "Vector" and "ultra-realistic" pull in opposite directions | Lock the look early with one art-test room (M6 starts with it) before mass-producing assets |
| Chases feel unwinnable or never-ending | Tunable Torch bonuses, hunter's sense, round timer. Playtest numbers in M2/M3 |

---

## 10. Open decisions

1. **Camera:** first-person (Ultrakill-like, best sense of speed) or third-person (see your character and the bots around you)? *Suggestion: first-person default with a third-person toggle. The controller doesn't care which.*
2. **Art direction:** is the interpretation in §6 right?
3. **Blender:** install Blender (give the path) or use a project-local `bpy` venv?
4. **Asset downloads:** OK to fetch CC0 packs (humanoids, PBR textures) into `assets/` (logged in `assets/CREDITS.md`) when we reach M6? Each download gets confirmed first.
5. **Multiplayer:** out of scope for now, but the intent architecture leaves room for it. Keep it that way?
