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
| M6 | Art pass (generated humanoid + anims, vector textures, shaders, per-map grading, VFX) | done, signed off 2026-11-20: `docs/M6.md` |
| M7 | Polish (audio, menus, settings, more modes) | mostly done (2026-11-22): audio, menus, settings, HUD; not built: more modes, a release build |

## Still to confirm in the game

Verified headless, not all confirmed by the owner (who has been playing and finds it mostly good):

- Shadow quality presets and VSync "On".
- The Inferno's fill lighting (`docs/maps/inferno.md`: not measured on the GPU).
- The HUD, pause menu and the F1 / F2 panels after the menu rework (never screenshotted).

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
- **Settings:** most are global; a map can set its own defaults (`GameMap.graphics_defaults`, the Jungle does) and a choice made on a map sticks to that map.

## Next

1. Decide on more modes (Freeze tag, the hunter's sense: both in the plan, never built).
2. A release build: `export_presets.cfg` exists, but no build is recorded; version number, icon, quitting without the debug build.
3. Whatever the owner finds playing.

## Decisions (PLAN.md §10)

- Camera: first person by default, third-person toggle.
- Art direction: the §6 interpretation is confirmed.
- Blender: portable install in `tools/.blender/` (git-ignored), run headless, exports `.glb`.
- Downloads: free assets are fine without asking, each logged in `assets/CREDITS.md`, with game-safe licences only.
- Collectibles: cut. Multiplayer: out of scope, but the architecture leaves room for it.
