# Overworld

**Identity:** open rolling country under a warm sky: big terrain features you can read from
anywhere, obstacle clusters with open running ground between them. The "fast" map: long slides,
long launches, long chases you can see coming.

**Built by** `tools/mapgen/overworld_gen.gd` (seed fixed; Terrain3D heightmap, 1 m per vertex,
1024 m square). Playable circle r 260 (arena radius), dry edge from r 262 (past the outermost
cluster at 238 + footprint), bound r 312. Mountains rise from r 310 to 480 (not navigable).
Spawn: the flat meadow in the middle (r ≤ 55, no clusters).

## Areas

| Area | Where | Shape | For |
|---|---|---|---|
| Spawn meadow | centre, r ≤ 55 | flat | a clear start; see the whole map |
| SLIDE HILL | west, (-165, 25), r 105, 45 m tall | smooth dome, climbing tower on top | long downhill slides in every direction; the tower is a vantage + launch point |
| THE RIDGE | north-west, (-255,-40) → (-95,-225), 14 m | long spine, 22 m half-width | slide down either side; a fast lane across the north-west |
| THE CRATER | south-west, (-135, 165), r 38 | ring ridge 13 m, bowl 6 m deep | skate-bowl circuits; a place to loop a chaser |
| THE MESA | north, (20, -195), 110 × 68 m, 24 m tall | sheer cliffs, one ramp (62 m run), pillars on top | a hard-to-reach high ground; ramp is the only walk-up (pads and wall-jumps otherwise) |
| CANYON | east, runs north-south, 16 m deep | cut with a wall-jump slot; ramp exits at z -165 (E), -35 (W), 85 (E), 195 (W) | a sheltered fast lane; drop in to break line of sight |
| AQUEDUCT | z -55, from the hill east to x 195, deck 13 m | ruined deck in 12 m segments with broken gaps | a high route over the canyon; gap jumps |
| Clusters | everywhere else, Poisson 52 m apart, r ≤ 238 | 8 kits (ruins, pillars, stilts, kickers, tower, blocks, vaults, hub) | the moment-to-moment obstacles; open ground between |
| Launchers | from hubs (3) and towers (1), 70–170 m | long-range aimed pads | cross the map fast |
| Open pads / strips | 14 hop pads, 10 speed strips, outside the meadow | | momentum between clusters |

## Bots

Auto links everywhere (climbs, wall-jumps, gap jumps, drops, pads). Known: bots reach 3 of 4
tower tops from the centre in a minute (one tower, near (177, -158), takes a route they rarely
finish). Navigation comes up in ~0.6 s after load.

## Known rough edges

- The dry edge band (262–312 m) is empty open ground: fine, but plain.
- Some open speed strips point at rising ground (gentle, 7–11°): not a wall, just a slower run.

## Art pass (M6)

Warm gold grade, long shadows. Terrain: grass on the low ground, rock on the steep (the
lightweight terrain shader already splits by slope). Aqueduct and ruins in sandstone; the mesa
as layered rock; the canyon walls banded. MultiMesh grass and rocks with visibility ranges (PLAN
§5). Keep silhouettes of the big features clean: they're how you navigate.
