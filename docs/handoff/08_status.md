# 8. Status, known issues, what's next

## Milestones (from `docs/PLAN.md` §8)

| # | Milestone | State |
|---|---|---|
| M0 | Setup (project settings, folders, git) | done |
| M1 | Movement (controller, camera, gym, debug HUD) | done |
| M2 | Tag core (TagManager, Classic, HUD) | done |
| M3 | Bots v1 (navmesh, perception, chase/flee, jukes, skills, shove/stun, hunted vignette) | done |
| M4 | Bots v2 (nav links, Spread + Hunted + Hot Potato, team chasing, perf) | done |
| M5 | Maps greybox (Overworld, Jungle, Inferno) | **maps done; collectibles not started** |
| M6 | Art pass (generated humanoid + anims, SVG textures, shaders, per-map grading, VFX) | not started |
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
  - The far corners of halls are very dark (sun over the walls plus braziers only); the vault corner is meant to be dark.
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
- **Hunter's sense, Freeze tag, collectibles:** in the plan, never built.
- **Third-person camera:** exists (V), but the player model is a placeholder capsule with a visor.
- **Audio:** none at all.
- **Settings:** shadow quality, render scale and the rest are global. There's no per-map quality.

## Plausible next steps (none started; confirm with the owner first)

1. The owner checks the last batch in-game and reports. Fix what they find (they usually send a
   numbered list with screenshots).
2. M5 leftover: **collectibles** on movement-tech spots (pillar tops, towers, launcher arcs) filling
   a meter for a small payoff (dash refill / speed burst).
3. M6 art pass. PLAN.md §6 has the direction ("vector-art Ultrakill, ultra-realistic"): SVG-authored
   textures, triplanar world shader, per-map grading. `docs/maps/*.md` each have an "Art pass"
   section. Open questions: Blender isn't installed (bpy venv?), and CC0 downloads need the owner's OK.
4. Occlusion culling between Inferno halls (`OccluderInstance3D`) and per-hall GI.
5. Audio (M7).

## Open decisions from PLAN.md §10 (still open unless noted)

- The camera defaults to first person, with a third-person toggle (implemented that way).
- The art direction interpretation (§6) isn't confirmed.
- Blender: install it or use a project-local `bpy` venv.
- OK to download CC0 packs into `assets/` (logged in `assets/CREDITS.md`)? Each download needs confirmation.
- Multiplayer is out of scope, but the intent architecture leaves room for it.
