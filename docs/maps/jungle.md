# Jungle

**Identity:** a dense forest around a stepped temple, with a highland cliff and waterfalls to
the north and a canopy level of treehouses and rope bridges. Two layers: the floor (tight, lots
of cover, trunks to wall-jump) and the canopy (fast, exposed, connected by bridges).

**Built by** `tools/mapgen/jungle_gen.gd` (seed 2718; Terrain3D). Playable circle r 230, dry
edge from r 236 (past the outermost cluster at 212 + footprint), bound r 276, mountains from 280.
Spawn: clearing at (0, 105), south of the temple.

**Hot Potato storm:** drifts from the map's centre onto THE TEMPLE (0, −30) as it closes in, and
stops at r 75: the temple and its open plaza, right where the trees start (r 76).

## Areas

| Area | Where | Shape | For |
|---|---|---|---|
| THE TEMPLE | centre, (0, -30) | 8 tiers × 3.5 m (half 44 → 20), plaza flat to r 76 | the landmark; every tier is a jump + vault |
| — grand ramp | south face, foot 22 m out | solid causeway to the top (~31°) | the walk-up; bots use it |
| — the hall | inside, half 20, 10.5 m tall | 4 pillars, braziers, doorways E/W/N (6 × 4.5 m) | cover from the chase; a dark interior |
| — the shaft | hall ceiling → summit, half 5 | ledge spiral every 2.5 m (corners open) | a secret way up: bots climb it in ~10–14 s |
| — the shrine | summit, 28 m | 4 pillars, roof flush with them at 36.5 m | the roof is reachable by wall-jumping a pillar (bots too) |
| THE FALLS | north, highland 20 m up past the cliff z ≈ -150 | cliff (wall-jumpable), two streams over the lip into pools at x -55 and 65 | the waterfalls are draped ribbons (`waterfall.gdshader`) |
| — slide chutes | x -10 and 125, from the cliff top | walled ramps at 30°, speed strip at each head | fast way down |
| THE RIVER | from the east pool (65, -122) to the rim | a meandering channel (width 0.8-1.3x) over a bed that never rises downstream, 1.2 m of water all along (`water.gdshader`), 3 log bridges | a line across the east side |
| Groves | (-130, 30) r 62; (55, 150) r 52; (-95, -100) r 40 | treehouses ~28 m apart: a thick ridged trunk (3 m radius, buttress roots, thinning to 80%), spiral ledges hugging it, deck ring at 12–16 m, a crown, pad up | the canopy level |
| — canopy bridges | between decks ≤ 40 m apart | rope bridges | the canopy network |
| Twins | among the clusters | two trunks 3.4 m apart, platforms at 8 m either side of the gap | wall-jump up the gap; a kit link lets bots do it |
| Forest | everywhere free | trunks 9 m apart (16–30 m tall), canopy leaves (walk-through) | cover, wall-jumps; kept clear of pads, landings and speed-strip lanes |
| Clusters | Poisson 46 m, r ≤ 212 | the standard kits + twins | |

## Bots

Auto links (incl. wall-jumps up to 9 m, jump-downs) plus the twins' kit links. Bots reach every
tested high spot (decks, temple summit, shrine roof, twins platforms). Navigation comes up in
~2.5 s after the first load (the most links of any map: ~6k).

## Known rough edges

- Speed strips sometimes point at a gentle rise (not a wall).
- The temple hall is dark by design; the braziers are the only light.
- Menu orbit camera is the same height on every map: on the Jungle it mostly sees canopy.

## Art pass (M6)

Teal/green grade, volumetric fog with light shafts through the canopy (PLAN §5). MultiMesh foliage
with visibility ranges; collision stays on trunks and walkways only. The temple in weathered
limestone with moss on the upper tiers; the hall lit warm by the braziers against the green
outside. Waterfalls: keep the ribbon shader, add spray particles at the pools. Treehouses in
dark wood with rope bridges that sag a little.
