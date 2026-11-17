# WILDFIRE maps

Design notes for every map: what each place is *for*, where it is, how bots get around it, what's
known to be rough, and where the art pass (M6) should take it. The greybox scenes are generated
and look ambiguous at first sight; read the map's page before changing it.

| Map | Page | Scene | Built by | Size (playable) |
|---|---|---|---|---|
| Test Gym | [test_gym.md](test_gym.md) | `scn/map/test_gym.tscn` | `src/map/test_gym.gd` (at runtime) | 420 m square |
| Overworld | [overworld.md](overworld.md) | `scn/map/overworld.tscn` | `tools/mapgen/overworld_gen.gd` | circle r 260 m |
| Jungle | [jungle.md](jungle.md) | `scn/map/jungle.tscn` | `tools/mapgen/jungle_gen.gd` | circle r 230 m |
| Inferno | [inferno.md](inferno.md) | `scn/map/inferno.tscn` | `tools/mapgen/inferno_gen.gd` | ~500 m across |

## How the maps are made

- **Generated, deterministic.** Each `*_gen.gd` builds its map headless from a fixed seed and
  overwrites every output (scene, meshes, navmesh, materials):
  `godot --headless --script res://tools/mapgen/<map>_gen.gd`. Change the generator, not the scene.
- **Shared library** `tools/mapgen/lib/`:
  - `map_kit.gd` (MapKit): a cluster's geometry in local space: boxes (solid, `visual` = look
    only, `blocker` = collision only), `slab` (ramps/bridges), `post`, pads, strips, explicit nav
    `link`s for routes the auto links miss.
  - `map_kits.gd` (MapKits): the standard obstacle kits (ruins, pillars, stilts, kickers, tower,
    blocks, vaults, hub).
  - `map_gen.gd` (MapGen): heights, Terrain3D data, per-map greybox materials (`mat_dir`),
    Poisson cluster placement, emitting kits (merged meshes saved binary), aimed jump pads (flight
    simulated, arcs checked), launchers, open pads and speed strips, chunked navmesh bake (128 m
    chunks, buried floors dropped), auto nav links, spawns, labels, the sun.
- **Coordinates:** x = east, z = south, y = up, metres. The arena centre is the origin.
- **Rules every map gets from GameMap:** `arena_radius` (the Hot Potato storm starts there),
  `dry_edge_radius` (where the dry edge starts; generators put it just past the outermost
  content), a bound (`arena_radius` × 1.2) nobody can pass, optional `lava_height` + checkpoints,
  spawn markers (optionally tagged with a `room`: each round starts in one).

## How bots get around (and what that asks of a layout)

Bots only walk the navmesh; everything else is a nav link:

| Link | Made by | Bot does |
|---|---|---|
| PAD | every pad (`MapGen.pad`) | walks on, then steers for the pad's landing spot in the air |
| CLIMB | auto: ledges ≤ 3.6 m up within 2 m | runs in with jump held, vaults |
| WALL-JUMP | auto: ledges 3.6–9 m up within 2.5 m with a wall under them; or a kit's `link` (twins) | jumps, leans into the wall, wall-jumps up |
| JUMP | auto: gaps 1–6 m (rising ≤ 2.2 m within 4.5 m); jumps down across ≤ 9 m and ≤ 12 m down (one-way) | runs to the edge, jumps |
| DROP | auto: edges ≤ 4 m above something; pad landings get one too | walks off |

Layout rules this implies:
- Anything a player can reach should be reachable by these: a gap of 7 m between two islands at
  different heights has no link. `tools/checks/nav_reach.gd` finds those.
- Pads must stand on solid ground (their whole disc) and land somewhere at least ~5 m from
  another pad (a landing on a pad relaunches you). Inferno's generator checks the first.
- Don't stack two boxes with coplanar top faces where they overlap (z-fighting): offset by a few cm.
- A wall or column top a player can stand on but bots can't reach is fine, as long as it's
  not where bots would snap a chase target (galleries next to tall walls, etc).

## Checks (`tools/checks/`)

Run with `godot --headless --fixed-fps 120 -s res://tools/checks/<check>.gd` and the env vars at
the top of each file. Never press Reset / save settings from a check.

| Check | What |
|---|---|
| `pads.gd` | every pad lands where its link says |
| `nav_reach.gd` | a nav path to each of a list of spots |
| `reach.gd` | a Torch bot actually gets to each spot (frozen player there) |
| `stuck.gd` | 2-minute match: bots that stop moving, lava respawns |
| `spread.gd` | Spread: how many Torches over time |
| `lava.gd`, `cheats.gd` | lava respawn + slow, the debug cheats (keys 7 8 9 0) |
| `nav_time.gd` | how long a map's navigation takes to come up |

## Art pass (M6) across all maps

Per PLAN.md §6: flat vector-style shapes, realistic lighting. Each map gets its own grade: warm
gold Overworld, teal/green Jungle, red/black/orange Inferno. Greybox materials live in
`assets/tres/materials/greybox/<map>/` and are named by role (stone, wood, ...), so swapping
in real materials can happen per role per map.
