# 8. Status, known issues, what's next

## Milestones (from `docs/PLAN.md` §8)

| # | Milestone | State |
|---|---|---|
| M0 | Setup (project settings, folders, git) | done |
| M1 | Movement (controller, camera, gym, debug HUD) | done |
| M2 | Tag core (TagManager, Classic, HUD) | done |
| M3 | Bots v1 (navmesh, perception, chase/flee, jukes, skills, shove/stun, hunted vignette) | done |
| M4 | Bots v2 (nav links, Spread + Hunted + Hot Potato, team chasing, perf) | done |
| M5 | Maps greybox (Overworld, Jungle, Inferno) | done (collectibles cut) |
| M6 | Art pass (generated humanoid + anims, SVG textures, shaders, per-map grading, VFX) | **started 2026-11-18**: plan in `docs/M6.md` |
| M7 | Polish (audio, menus, settings, more modes) | partly: menus and settings exist; no audio |

## Last batch (commit `5098ce8`, 2026-11-17): needs the owner's eyes in-game

These were all verified headless, but **nothing visual has been confirmed by the owner yet**:

- Shadow quality presets (jaggies, cut-off shadows): ask whether Medium/High look right and what they cost on the iGPU.
- VSync "On" (tearing).
- Flush ramp tops on every map.
- The new Inferno ring (octagonal landings, rails), the squared spire, the chains, the cage crown.
- The cheats on 7 8 9 0 inside the editor.

## Known rough edges

- **Inferno:**
  - Shade lighting (2026-11-21): the shaded bands along the halls' walls were near black (1 % of the sun). Two shadowless fill directionals and a warm ambient lift them to ~2.2 stops under the sun (`light_probe.gd`: 0 % of floor under the bar, from 35 %). Needs the owner's eye in-game, and a GPU measurement of the fills' cost.
  - Floating labels at 40 m overlap from the spire at some angles.
  - Lava falls run ~15–23 per 2 min with 9 bots, mostly in the pit and the Gallows. Bots could judge long jumps better.
  - The generator's hall functions keep their old names (`_nave_of_ash` etc.); the display names changed.
- **Jungle:**
  - Some speed strips point at a gentle rise.
  - The menu orbit camera mostly sees canopy.
- **Overworld:**
  - The dry edge band (262–312 m) is empty ground.
  - Bots rarely finish the route to one tower near (177, −158).
- **Bots** are good at chasing and fleeing but don't use slides/dashes for pure speed as well as a
  skilled player, and pick escape points without a pre-baked "escape value" map (the plan's idea).
- **Hunter's sense, Freeze tag:** in the plan, never built. Collectibles: cut.
- **Third-person camera:** exists (V), but the player model is a placeholder capsule with a visor.
- **Audio:** none at all.
- **Settings:** shadow quality, render scale and the rest are global. There's no per-map quality.

## Next

M6, step by step, in [`docs/M6.md`](../M6.md): first the art test room (the Inferno's Basilica),
which the owner has to approve in the editor before anything is mass-produced.

## Decisions (PLAN.md §10)

- Camera: first person by default, third-person toggle.
- Art direction: the §6 interpretation is confirmed.
- Blender: portable install in `tools/.blender/` (git-ignored), run headless, exports `.glb`.
- Downloads: free assets are fine without asking, each logged in `assets/CREDITS.md`, with game-safe licences only.
- Collectibles: cut. Multiplayer: out of scope, but the architecture leaves room for it.
