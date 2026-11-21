# Inferno

**Identity:** four roofless cathedral halls and a central pit, all floating over a sea of lava,
under a red-black sky. Vertical and dangerous: lava everywhere you might fall, so every gap is a
decision. Each hall plays differently.

**Built by** `tools/mapgen/inferno_gen.gd` (seed 666). No terrain: box geometry over a lava plane
(y -14, `lava.gdshader`). Arena radius 245, bound 294, dry edge at 290 (never in play).

**Lava:** fall below y -8 (`lava_height`) and you're put back at the nearest checkpoint, slowed
to half speed for 2 s, and can't dash while slowed. Not a death. Checkpoints: each hall's narthex
and 3–4 spots inside, the pit rim (between doors and pads), spokes, ring islands.

**Hot Potato storm:** rises out of the lava (y −16, 90 m tall) and closes in on the pit, stopping
at r 48, just outside the pit's walls (it never cuts through the middle room).

**Spawns:** 8 markers in each hall's narthex, tagged by hall: every round starts in a random hall
(every mode, Spread included). Spread spreads everyone across that hall instead of the
narthex: ~40–100 `spawn_spread` markers per hall on its low floors (y −6.5..3.5, away from pads),
picked as far apart as they go.

## Shared structure

- **The Pit / THE MAW** (centre): an octagonal shaft, rim walkway at y 0 (r 32–44) with a low
  parapet on the inner edge, walls 30 m with a door toward each hall. Inside: four floating
  platforms at 8 m (r 22, 12 × 12) and a spire at 20 m (18 × 18, square to the halls: turned, it
  read as a pinwheel from above). Pads: rim → platform →
  spire; the spire's four pads lob you over the walls deep into the hall that way.
- **Halls:** 100 × 140 m, r 90 → 230, walls 30 m (invisible walls above to 100 m: no standing
  on them), doors 12 × 12 in the inner end and both sides (sills level with the floor). Narthex: solid floor across the inner 20 m with two braziers.
- **Spokes:** 12 m causeways from each hall's inner door to the pit rim (low iron parapets).
  Speed strips on two of them.
- **Ring:** out of each side door, an 8 m causeway to an octagonal landing (24 m across; one
  face per causeway, so each meets a face whole), then a long diagonal causeway to a 16 m island
  halfway to the neighbouring hall (brazier), and the same into that hall. Every platform edge is
  railed except where a causeway joins; causeway parapets stop exactly at the platform edges.
  A speed strip on one diagonal of each pair.

## The halls

Hall-local coordinates: z runs outward from the pit (inner door at -70, apse at +70), x across.

### N: OSSUARY OF EMBERS (the crypt)
- Aisles at y 0 along both walls (x ±38..50), apse floor at y 0.
- **The crypt:** the middle sunk to y -6 (above the lava line), rows of tombs (1.4 m, vault
  them), a dais with an 8 m-wide plinth (top 4 m: wall-jump it, or vents), ramps down from the
  narthex, the apse and both aisles.
- **Catwalks** at 7 m along both walls, pillars under them (wall-jump links); vents up from the
  plinth and the crypt.
- **Ash mound** in the apse: three 3 m steps up to 9 m.

### E: THE SCALDING MERE (the lava lake)
- Walkways along both walls (x ±40..50), apse floor at the far end.
- **The lake:** 20 islands at 0 / 1.5 / 3 m, gaps a run-up jump clears; five chained bridges;
  vents from the walkways onto the middle island and the high islands.
- **The tower:** on the middle island, 9 × 9, 10 m tall; a vent up to it, a vent from it to the
  balcony.
- **Apse:** an altar in two steps, a balcony at 12 m across it (vents up from the floor).

### S: BASILICA OF SMOULDER (the cathedral)
- A full floor, pews down the nave (1 m, vault them), a centre aisle.
- **Column pairs** at x ±24 (4 per side): wall-jump the gap onto the capitals at 9 m (a kit link
  each); chained bridges from two of them to the galleries.
- **Galleries** at 9 m along both walls on arcades; vents from their outer ends to the choir loft.
- **Apse:** altar steps (1 / 2 / 3 m) with a gold altar; **choir loft** at 18 m across it.

### W: THE IRON GALLOWS (hanging platforms)
- Walkways round the edge at y 0 (sides and apse); the rest is a lava pit.
- **14 platforms** hung on chains (running up out of sight, not to the wall tops) at 2–13 m, linked by sloped chained bridges and vents, climbing
  to **the cage** at 16 m (6 m bars with gaps under a crown ring, hung on four chains). A vent from the cage down to the apse.
- Every platform has a way out (bridge, vent, or a jump-down).
- **The Ashen Vault (secret):** in the dark far corner of the apse walkway (hall-local x +44,
  the apse wall), a 4 × 5 m doorway into a real room inside a buttress against the hall's outer
  corner: 12 × 14 m, 7 m tall, a gold prize between two braziers, a sign. A solid twin buttress
  stands on the other corner so the pair reads as architecture from outside. No illusion: bots
  walk in like anywhere else.

## Lighting

The sun (50° up, from the south-west) shadows a band ~25 m deep along each hall's south and west
walls, under the galleries, lofts and bridges. The sky's top is near black, so before 2026-11-21
those places got ~1 % of the sun's light at the default settings (Lighting Low: no GI, no SSAO):
35 % of all floor was black. Now (`inferno_gen.gd` `_add_fill_lights`, the environment's ambient):

- **EmberSky:** a shadowless directional from the opposite side of the sky (38° up, warm red),
  the glowing haze the sun doesn't cover. Lights the floors and faces the sun misses.
- **LavaGlow:** a shadowless directional from below (32° up from under, lava orange): the
  undersides of bridges, platforms and galleries, the lower walls, and the players from beneath.
- **Ambient:** 60 % a warm ember colour (0.55, 0.32, 0.25), 40 % the sky, energy 1.0 (was the
  sky alone at 0.8).

Both fills skip the sky (no second sun drawn) and the baked GI (they stand in for bounce). Cost:
two shadowless directionals, no shadow maps; not yet measured on the GPU.

**The bar** (`tools/checks/light_probe.gd`, a CPU model of the renderer's direct light): the light on
any standable floor must be at least 1/6 of the sun's direct light on an open floor, ~2.6 stops
under it, and the same for a standing character. Why 1/6: the basalt is a dark tone (25 % grey), and
under that much light it already displays at only ~0.06 (~15 / 255) after AgX; any darker and the
floor, the walls and the brick joints fall within a couple of code values of each other and of
black, so edges and routes vanish. Any brighter as a rule and the shade stops reading as shade:
the halls should keep deep contrast. Results:

| | before | after |
|---|---|---|
| floor spots under the bar | 35.4 % | 0 % |
| character spots under the bar | 31.1 % | 0 % |
| darkest floor (share of the sun-lit floor) | 0.01 (6.8 stops under) | 0.23 (2.2 stops under) |
| basalt floor in the darkest shade, display value | 0.00 | 0.08 (sun-lit: 0.24) |
| sun-lit floor, all light | 0.93 | 1.13 (+0.3 stops) |

Shade is still clearly shade (the bands show on the heat map), and the braziers still pool warm
light. The probe can't see glow, specular, the shaders' brick tones and rim highlights, look-only
geometry, depth fog or the lava's own glow, so the numbers are a floor, not the final picture.

## Bots

All 29 pads land; every island and platform has a nav path (`nav_reach.gd`); bots reach the high
spots in every hall (catwalks, plinth, tower, balcony, capitals, galleries, choir loft, the cage)
and walk into the vault. Lava respawns: ~15–23 per 2 minutes with 9 bots, mostly in the
pit and the Gallows: the lava is doing its job, but bots could judge long jumps better.

## Known rough edges / next

- Labels float at 40 m; from the spire they overlap at some angles.
- Ramps across all maps end flush with what they climb onto (`MapKit.slab` only overlaps past
  the low end); earlier versions poked their top edge through the deck.

## Art pass (M6)

Red/black/orange grade, heavy glow from the lava, volumetric fog. Oversized brutalist-gothic
architecture (PLAN §6): ribbed vaults on the hall walls even without roofs, rose-window shapes
in the apse walls, iron in the chains and bridges, obsidian-black basalt floors with glowing
cracks near the lava. Occlusion culling between halls (`OccluderInstance3D`); per-hall GI.
Each hall's own accent: ash grey (Ossuary), sulphur yellow (Mere), ember gold (Basilica), rust
(Gallows).
