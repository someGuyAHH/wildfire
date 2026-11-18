# 7. Bug history

Every notable bug so far, grouped by area: what it looked like, why it happened, how it was fixed.
Most fixes have a commit with a longer write-up (`git log --grep=<word>`). Read the
**Lessons** at the end even if you skip the rest.

## Engine and GDScript traps

| Symptom | Cause | Fix |
|---|---|---|
| Every character's physics body at **NaN** on the Inferno; pads and contacts dead | `spawn_rooms` appended into a `PackedVector3Array` pulled out of a Dictionary, but packed arrays are **values**, so it appended to a copy. Every room came back empty, and the spawn maths divided by zero. | Plain `Array`s inside the dictionary, plus a guard against empty rooms in `_pick_spawn_room`. |
| A check hung until its timeout | `var run := not (_cheats[...] …)` can't infer a type from an untyped Dictionary, so `main.gd` failed to parse and Main never loaded. | Explicit `var run: bool`. Read the stderr when a check hangs. |
| A `.tres` broke after a hand edit | A `#` comment. `.tres`/`.tscn` comments use `;`. | Use `;` (or no comments). |
| A new `class_name` wasn't found by headless scripts | The global class cache hadn't been updated. | `godot --headless --import` once. |
| Camera boom misbehaved | A member named `scale` shadowed `Node3D.scale`. | Renamed to `_scale`. Watch for shadowed built-ins (`show`, `snapped`, `scale`: all were hit). |
| GDScript warnings | `show` param shadowing `Node3D.show()`; a nested duplicate `old` variable; an unused parameter; `snapped` shadowing a built-in. | Renamed / removed. Keep the project warning-free. |
| Settings Reset re-centred the toggle text | `MenuStepper.setup()` forced centred text. On first build `FireButton._ready()` ran afterwards and reset it to left; Reset calls `setup()` on rows that are already ready. | Fixed the ordering in `setup()`. |
| Effects kept animating while paused | Shaders used `TIME`, which never stops. | A global shader uniform `game_time` advanced by Main (which pauses). All shaders use it, lava and waterfalls included. |

## Movement

| Symptom | Cause | Fix |
|---|---|---|
| Dashing into stairs stopped you dead and bonked you | Auto-step didn't run during dashes. | `_try_step_up` also runs in `ST_DASHING`. |
| Dash-jump slowed you down at high speed | It set speed to 85% of dash speed (23.8) regardless. | It keeps the faster of the two, then adds +4 m/s when you're already faster. |
| Pads/slopes made the camera jitter | The camera eased every height change. | It only eases step-ups the character announces (`stepped_up`). |
| Running onto an aimed pad at 25 m/s dropped you to ~6 | The lob replaced your horizontal velocity. | If you're faster than the lob you keep your speed. Bots ease off before pads so they still get the exact lob. |
| Momentum pads killed a fast climb or fall | They reset vertical speed. | They keep the higher of launch and climb, and a fall bounces back at 0.7×. |
| Landing back on a pad left you on a dead pad | Pads fired only on `body_entered`. | They also fire for anyone standing on them (on floor, not frozen). |
| Dashing out of lava cancelled the slow | The dash ignored `_slow_mult`. | No dashing while slowed. |
| **Fly cheat off → no collision with anything** (blocked all testing) | `debug_fly` saved the collision mask on every set to true; `_apply_cheats` re-set it, so the second save stored the zeroed mask. | The setter returns early when the value doesn't change. The check confirms the mask is restored. |
| Wall-slide camera tilted from just touching a wall | The tilt was on whenever wall-sliding. | It fades in from 4 to 10 m/s of along-wall speed. |
| Wall bonks from point-blank dashes | Impact speed used velocity. | It uses real closing speed over the last 0.1 s of positions (a ring buffer). |

## Tagging and match

| Symptom | Cause | Fix |
|---|---|---|
| Shoves felt arbitrary | A flat distance plus a height band. | The real capsule gap (crouch/slide shrink it); the reach never drops below the tag reach. |
| Spread: 10+ Torches within 30–40 s, bots helpless | Everyone spawned in a 6 m ring, so the first Torch walked into half the field. A fresh Torch got frozen (pointless). The Torch speed/dash bonus stacked across a pack. Runners only avoided the nearest Torch. | Scattered spawns, no freeze in Spread, no Torch bonus in Spread, runners penalise every nearby Torch. Now 2–4 Torches at 30 s, and rounds run 80–120 s. |
| Tag-back freezing in Spread | Same freeze rule as Classic. | Removed for Spread. |
| Dry edge ran through playable content | The edge was at 0.85 × arena radius. | Maps set `dry_edge_radius` just past their outermost content. Smoldering 5 s now ignites you, and a bound wall at 1.2 × arena radius stops wandering into the mountains. |

## Bots

| Symptom | Cause | Fix |
|---|---|---|
| The Torch cycled through every target every ~0.4 s | The "unreachable" check compared the target's position with the end of a path planned to the **intercept** point, which is always > 2.5 m off for a moving target. | Unreachable only if the path stops short of its own goal or the target is off the navmesh (airborne doesn't count). Switches dropped from 47 in 20 s to 13 in 60 s. |
| Bots dodged every dash shove | The dodge fired on the first tick a dash came within 6 m, from any direction, at up to 85% odds. | It must be seen, waits for the reaction time, and uses `juke_skill × 0.55`. |
| Bots stuck at pad landings / planning to ride pads backwards | `NavigationLink3D` defaults to **two-way**. | Pad and drop links are one-way. |
| Overworld path queries ignored links | `included_regions` was set, and the pathfinder then ignores links. | Don't set it; narrow only the closest-point snaps (chunk grid). |
| Jungle hitches (20 ms ticks) | Every bot repathing in the same tick, and escape picks snapping 8–16 candidates. | A cap of 2 path queries per tick; snap only the best 3 escape candidates. Worst tick 20 → 7 ms. |
| Bots fell short on long pad lobs (31 lava falls / 2 min) | Mid-flight they steered toward their path, fighting the lob. | Pads know their landing, and launched bots steer to it (8–9 falls, later ~15–23 on the bigger redesign). |
| Bots overshot lobs | Brake-steering on long flights. | Steer toward the launch target; brake only on JUMP/VAULT links. |
| Bots bonked a floating ledge's underside forever | They jumped from right under the lip. | Back out from under the lip before a vault. |
| Bots couldn't wall-jump where the player could ("unfair") | No links for 3.6–9 m ledges. | Auto WALLJUMP links (wall needed halfway, lip clear) plus lean-into-the-wall steering; kit links for the twins. |
| Bots never jumped *down* across gaps | No link kind for it. | Jump-down links (≤ 9 m across, ≤ 12 m down, one-way). |
| Bots targeted spots they could never reach | Recast baked buried box tops / ground under boxes as floor. | `drop_buried` removes navmesh polygons inside solid geometry. |
| Maps visited after the Gym had broken links | A *disabled* nav region still counts when links pick a floor to attach to, so links grabbed the Gym's invisible floor at y 0. | Parked maps leave the navigation map entirely (`set_navigation_map(RID())`). |
| Jungle navigation took 4–8 s to come up | 21k links (each costs the map rebuild). | One link per start cell: Jungle 6.2k, ~2.5 s. |
| Twins platform unreachable | It was at 11 m, out of jump + 3 wall-jumps. | Two platforms at 8 m and a kit WALLJUMP link. |

## Maps and generation

| Symptom | Cause | Fix |
|---|---|---|
| Thick ramps stopped ~4 m short of the top | `slab` sank straight down, sliding the top face downhill by thick/2 × tan(tilt). | Sink along the slab's own up. |
| **Every ramp poked through the platform at its top** | `slab` extended `overlap` past *both* ends; past the high end a tilted slab keeps climbing. | Overlap only past the low end (2026-11-17). All maps regenerated. |
| Overworld Pad27 overshot by 28 m | A speed strip had been placed on the pad. | Open pads and strips keep ≥ 14 m apart. |
| Materials repainted across maps | Every map wrote `stone`, `wood`… into one folder. | `mat_dir` per map. |
| Pads hanging off edges | Pad placed with no support check. | `_supported`: 5 down-rays across the disc. Plinth and tower widened. |
| Pads relaunching you on landing | Landing within reach of another pad. | Landings ≥ 5 m from pads. |
| Out-of-bounds pads in two Inferno halls (reported against the old hall names: the Ossuary and the Mere) | Pads placed where the layout had no floor under them. | Fixed with the support check above and moved pads (`8b22337`). |
| Gaps at every Inferno doorway | No sill. | Sills flush with the floor. |
| Players standing on 30 m hall walls | Walls had walkable tops. | Invisible `blocker`s up to 100 m. |
| **Z-fighting** (spire; Mere islands; bridges; rim corners) | Coplanar overlapping top faces. | Offsets: bridges/causeways 3 cm under, overlapping pieces 1.5 cm apart, alternating rail heights. |
| **"Swastika" of black lines on the spire top** | The spire was turned 22.5° while everything else was square; its edges plus 4 pads formed a pinwheel. | Spire squared to the halls. |
| Ring bridges: open corners at side doors, then rails overrunning and missing the connector | Diagonal bridges met square landings at corners; parapets ran to the landing centre. | Octagonal railed landings, each face a causeway's width; parapets exactly end-to-end. It took three tries. |
| Gallows chains ended in mid-air; cage bars looked like "short cut rods" | Chains stopped at the wall-top height, and bars had no top. | Chains run to y 220 (out of sight); the cage has a crown ring and hangs on chains. |
| Secret room: the projection/portal trick was buggy (X-ray floor, room visible in 3rd person or mid-jump) | A camera-projection portal. | The owner said: "Real room, no illusion whatsoever." A buttress room in the Gallows' dark corner; the portal code was deleted entirely. |
| Parked maps spamming errors | Pads (and the portal) called `get_overlapping_bodies()` with monitoring off. | `if not monitoring: return`. |

## Rendering and settings

| Symptom | Cause | Fix |
|---|---|---|
| Saw-tooth shadow acne on big flat faces | Grazing-angle faces in the far split. | Biases first went up (0.12 / 2.5) and then blur was added. Replaced by the Shadow quality presets. |
| **Jagged shadows everywhere, sharp only up close; shadows cutting off when the camera lowers** | One 4096 map over 160 m in 2 splits: past the ~16 m near split each texel is ~15 cm, made worse by the 0.6 render scale. Plus distance/pancake limits. | The **Shadow quality** setting (Low/Medium/High: 2–4 blended splits, 120–240 m, 4096/8192 atlas, soft filter, pancake 40, lower biases), applied to every sun after each map load. **Not visually confirmed by the owner yet.** |
| A horizontal tear across one shader band with VSync "on" | VSync used `VSYNC_ADAPTIVE`, which tears late frames by design. | VSync is now Off / Adaptive / On. The owner's saved value maps to Adaptive; they should pick On. |
| F8 closed the game | When run embedded in the editor, F7/F8 are the editor's pause/stop. | Cheats moved to 7 8 9 0. |

## Menu background map switch (a cautionary tale)

1. A burn transition → a fade through black → a cross-fade using a one-frame SubViewport screenshot.
2. The screenshot was sometimes black: the viewport hadn't rendered before it was read.
3. A **live** cross-fade (the old map on render layer 20 with its own camera for 0.7 s) was built,
   and the owner said "rewind, it's worse now. It'd been better". **It was reverted** (`04131ad`).
   So the screenshot cross-fade (step 1) is what's live again, black-frame risk included. The owner
   accepted it as better. Don't redo this without asking.

## Lessons

- Verify with a headless check, then commit. "It parses" isn't verification.
- Generated content is checked by the scripts in `tools/checks/`. Run pads, nav_reach and stuck after every
  generator change.
- Watch for value-type containers, shadowed built-ins, two-way default nav links, and
  coplanar faces.
- When the owner reports a visual bug from a screenshot, fix the generator rule behind it, not just
  that one spot. They said "same mistake with roughly every single ramp".
