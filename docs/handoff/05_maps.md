# 5. Maps and the map generator

Full design pages live in [`docs/maps/`](../maps/README.md), one per map (layout, intent, bots,
known issues, art direction). This page is the summary plus how the pipeline works.

## The four maps (menu order: `Main._MAPS`)

| Map | Scene | Built by | Size | Identity |
|---|---|---|---|---|
| **Gym** | `scn/map/test_gym.tscn` | `src/map/test_gym.gd` at **runtime** (`@tool`; generated nodes aren't saved) | 420 m square, arena r 190 | A labelled tuning and regression course: stairs, ramps (to the 62° limit), vault walls 0.9/1.2/1.5 m, slide tunnel, wall-jump shaft, pillar field, pads, speed track, 90 m slide hill. Nav links are added by hand in `_build_nav_links()`. The game starts here: it's the default `start_map` and the title screen's first map. |
| **Overworld** | `scn/map/overworld.tscn` | `tools/mapgen/overworld_gen.gd` | playable circle r 260; Terrain3D 1024 m; mountains from r 310 | The fast map: open rolling country. SLIDE HILL (45 m dome + tower), THE RIDGE, THE CRATER (skate bowl), THE MESA (24 m plateau, one ramp), CANYON (16 m deep, wall-jump slot), AQUEDUCT (13 m deck with gaps). 26 Poisson clusters from 8 kits, launchers, hop pads, speed strips. Spawn meadow at the centre. |
| **Jungle** | `scn/map/jungle.tscn` | `tools/mapgen/jungle_gen.gd` (seed 2718) | r 230; mountains from r 280 | Dense forest on two levels. THE TEMPLE: 8 tiers × 3.5 m on a plaza, a grand ramp, a hollow pillared hall, a ledge-spiral shaft up to a shrine (whose roof you can climb). THE FALLS: a 20 m cliff, two waterfall ribbons, slide chutes. THE RIVER with log bridges. Treehouse groves with canopy rope bridges. "Twins" (two trunks 3.4 m apart to wall-jump between). ~890 trunks with walk-through canopy. |
| **Inferno** | `scn/map/inferno.tscn` | `tools/mapgen/inferno_gen.gd` (seed 666) | ~500 m across, arena r 245 | No terrain: box geometry over a lava sea (visual y −14, rule `lava_height` −8). See below. |

### Inferno in brief (the newest map, most recently changed)

- **THE MAW** (centre pit):
  - an octagonal shaft with a rim walkway at y 0 (r 32–44) and a low inner parapet;
  - 30 m walls with a door toward each hall;
  - four floating platforms at 8 m, and a **spire** at 20 m (18 × 18, now square to the halls);
  - pads: rim → platform → spire. The spire's four pads lob you over the walls deep into each hall.
- **Four roofless halls**, 100 × 140 m, from r 90 to 230. They have 30 m walls with invisible
  blockers up to 100 m (no wall-walking), doors 12 × 12 with sills flush with the floor, and a narthex
  with braziers and spawns at the inner end. Each round starts in a random hall (spawn markers have
  a `room` meta).
  - **N, OSSUARY OF EMBERS** (`_nave_of_ash` in code: the functions keep the old names): a sunken
    crypt of tombs round a plinth, catwalks at 7 m, an ash mound.
  - **E, THE SCALDING MERE** (`_brimstone_nave`): a lava lake with 20 islands at 3 heights, chained
    bridges, vents, a 10 m tower, a balcony at 12 m.
  - **S, BASILICA OF SMOULDER** (`_cathedral_of_cinders`): pews, column pairs to wall-jump onto
    capitals at 9 m, galleries, a choir loft at 18 m.
  - **W, THE IRON GALLOWS** (`_hall_of_chains`): 14 platforms hung on chains (the chains run up to
    y 220, out of sight) at 2–13 m over lava, climbing to a **cage** at 16 m (6 m bars, a crown ring,
    hung on 4 chains). In its far dark corner is **the Ashen Vault**: a secret but real room inside a
    buttress (12 × 14 m, a 4 × 5 m doorway, a gold prize). A solid twin buttress stands on the other
    corner so the pair reads as architecture. **No portals or illusions:** the owner insisted.
- **Spokes:** 12 m causeways from each hall's inner door to the pit rim.
- **Ring (rebuilt on 2026-11-17):** from each side door, an 8 m causeway leads to a **railed octagonal
  landing** (each face exactly one causeway wide, 10 m). A long diagonal causeway then runs to a
  **railed 16 m island** with a brazier, and the same continues into the neighbouring hall. Rails
  cover every edge except where a causeway joins, and the parapets stop exactly at platform edges.
  This was the third attempt; the owner complained twice about open corners and overrunning rails.
- **Checkpoints** (lava respawns): every narthex plus 3–4 spots per hall, the rim, spokes, ring
  landings and islands.
- All 29 pads land. Lava falls run ~15–23 per 2-minute 9-bot match, mostly in the pit and the Gallows.

## The generator pipeline (`tools/mapgen/`)

Each `<map>_gen.gd` `extends SceneTree` and runs **headless, deterministically** (a fixed seed). It
overwrites **every** output: the scene, merged meshes (`assets/meshes/<map>/`), navmesh chunks and
`jump_links.res` (`assets/navmesh/<map>/`), Terrain3D data (`assets/terrain/<map>/`), and materials
(`assets/tres/materials/greybox/<map>/`).

```bash
timeout 900 godot --headless --script res://tools/mapgen/inferno_gen.gd
```

**Timing:** Inferno ~2 s, Jungle ~13 s, Overworld ~12 s. A "Terrain3D … Cannot find clipmap target or
active camera" error and "border_size is ceiled" warnings are normal during generation.

### Library (`tools/mapgen/lib/`, preloaded, no `class_name`, because `tools/` is `.gdignore`d)

- **`map_kit.gd` (MapKit):** one cluster's geometry in local space.
  - `box(pos, size, mat, yaw, grounded, tilt)` (long axis = local Z);
  - `visual()` (look only, no collision) and `blocker()` (collision only, no mesh);
  - `slab(from, to, width, thick, mat, overlap)` for ramps and bridges. It sinks the slab along its
    own up, and **overlaps only past the low end**, so a ramp's top edge never pokes through the
    deck it meets;
  - `post()`, `pad(at, to, peak)`, and `link(from, to, kind)` for routes the auto links miss;
  - `square_edge()`.
- **`map_kits.gd` (MapKits):** the 8 standard kits (`ruins, pillars, stilts, kickers, tower,
  blocks, vaults, hub`). FLAT kits go only on flat ground; SLOPED kits cope with slopes.
- **`map_gen.gd` (MapGen, ~1,000 lines):** the builder.
  - **Terrain:** heights (`bake_heights`, `h`, `bumpiness`), Terrain3D data and node.
  - **Materials:** per-map `mat_dir`.
  - **Clusters:** Poisson placement (`place_clusters`); `emit_kit` / `emit_world_kit` merge each kit
    into one body + one mesh, saved binary.
  - **Pads:** `pad()` aims a lob by simulating the character's own flight (`lob_speed`,
    `flight_distance`) and checks the arc is clear (`arc_clear`). Also `add_launchers` and
    `add_open_pads_and_strips` (open pads/strips ≥ 14 m apart; `strip_lane` points strips down
    clear lanes).
  - **Nav:** `bake_navmesh` builds 128 m chunks. `weld_navmesh` merges the chunk edges.
    `drop_buried` removes polygons inside solid geometry: Recast sees a buried box top as a floor,
    and bots used to target it.
  - **Links:** `add_drop_links` (pad landings), then `_add_jump_links`. That one samples every open
    navmesh edge every 1.5 m and adds CLIMB / WALLJUMP / JUMP / jump-down / DROP links with ray
    clearance checks. It keeps one per start cell (3.5 m; climbs 2.5 m; tall 8 m) to keep link
    counts down: Jungle ~6.2k, Overworld ~2.6k, Inferno ~4.9k. Every link slows the navigation
    map's rebuild.
  - **Scene:** `add_environment` (sun: shadows, now overridden at runtime by STG), `add_spawns`,
    `add_labels` (floating names, per-label lifts), `save_scene`.
- **Inferno extras** (in `inferno_gen.gd`):
  - `_try_pad` with `_supported` (5 down-rays: the pad's whole disc must stand on something);
  - `_arc_hits_something`;
  - `_chain_bridge`, `_causeway`, `_octagon`, `_rail`, `_wall` (doors + blockers), `_floor`, `_pillar`, `_vault`.

### Layout rules the generators follow (learned the hard way)

- Anything a player can reach should be reachable by the link kinds. A 7 m gap between islands at
  different heights has no link. Check with `nav_reach.gd`.
- Pads must stand on solid ground (the whole disc). Landings must be ≥ 5 m from another pad (a
  landing on a pad relaunches you) and away from speed strips. A strip once sat on a pad and
  boosted the launch 28 m past the landing.
- **No coplanar overlapping top faces (z-fighting).** Offset overlapping boxes by 1–3 cm: bridges sit
  3 cm under what they rest on, rim and octagon halves alternate 1.5 cm, and crossing rails
  alternate 1.5 cm in height.
- Keep rotated geometry squared to its neighbours where it reads from above. The spire's 22.5° turn
  plus its pads drew a pinwheel that the owner read as a swastika.
- Open walk edges near lava need rails. Rails stop where walkways start: no overrun.
- Visual-only (non-solid) things are fine anywhere, but chains and rods must look anchored or run out of sight.

## After changing a generator

1. Regenerate the map (and any other map if you touched `lib/`).
2. Run `pads.gd` (every pad lands), `nav_reach.gd` on the spots you changed, and `stuck.gd` (2-minute
   match); on the Inferno also `lava.gd`.
3. Update `docs/maps/<map>.md`.
4. Commit the generator **and** all regenerated outputs together.
